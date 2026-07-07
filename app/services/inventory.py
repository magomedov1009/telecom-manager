from dataclasses import dataclass
from datetime import date, datetime, time
from decimal import Decimal
from math import ceil
from urllib.parse import urlencode

from sqlalchemy import Select, func, or_, select
from sqlalchemy.orm import Session, joinedload

from app.models.enums import InventoryTransactionType, MaterialUnit
from app.models.inventory import InventoryTransaction, Material, Warehouse
from app.models.users import User

NEGATIVE_OPERATION_TYPES = {
    InventoryTransactionType.CONNECTION,
    InventoryTransactionType.TRANSFER_OUT,
    InventoryTransactionType.ISSUE_TO_THIRD_PARTY,
    InventoryTransactionType.WRITE_OFF,
}

POSITIVE_OPERATION_TYPES = {
    InventoryTransactionType.RECEIPT,
    InventoryTransactionType.TRANSFER_IN,
    InventoryTransactionType.RETURN,
}

OPERATION_LABELS = {
    InventoryTransactionType.RECEIPT: "Приход",
    InventoryTransactionType.CONNECTION: "Подключение",
    InventoryTransactionType.TRANSFER_IN: "Перемещение: приход",
    InventoryTransactionType.TRANSFER_OUT: "Перемещение: расход",
    InventoryTransactionType.RETURN: "Возврат",
    InventoryTransactionType.ISSUE_TO_THIRD_PARTY: "Выдача третьему лицу",
    InventoryTransactionType.WRITE_OFF: "Списание",
    InventoryTransactionType.ADJUSTMENT: "Корректировка",
}

MATERIAL_UNIT_LABELS = {
    MaterialUnit.PIECE: "шт.",
    MaterialUnit.METER: "м",
}


class InventoryError(ValueError):
    pass


@dataclass(frozen=True)
class StockCell:
    warehouse: Warehouse
    material: Material
    quantity: Decimal


@dataclass(frozen=True)
class OperationHistoryPage:
    items: list[InventoryTransaction]
    page: int
    per_page: int
    total: int
    pages: int


@dataclass(frozen=True)
class MaterialsPageData:
    warehouses: list[Warehouse]
    materials: list[Material]
    stock_rows: list[dict]
    history: OperationHistoryPage
    filters: dict
    operation_types: list[InventoryTransactionType]
    operation_labels: dict[InventoryTransactionType, str]
    unit_labels: dict[MaterialUnit, str]
    error: str | None = None
    success: str | None = None
    filter_query: str = ""


def get_active_warehouses(db: Session) -> list[Warehouse]:
    return list(db.scalars(select(Warehouse).where(Warehouse.active.is_(True)).order_by(Warehouse.name)))


def get_active_materials(db: Session) -> list[Material]:
    return list(db.scalars(select(Material).where(Material.active.is_(True)).order_by(Material.name)))


def get_stock_quantity(db: Session, warehouse_id: int, material_id: int) -> Decimal:
    quantity = db.scalar(
        select(func.coalesce(func.sum(InventoryTransaction.quantity), 0)).where(
            InventoryTransaction.warehouse_id == warehouse_id,
            InventoryTransaction.material_id == material_id,
        )
    )
    return Decimal(quantity or 0)


def build_stock_rows(db: Session, warehouses: list[Warehouse], materials: list[Material]) -> list[dict]:
    totals = db.execute(
        select(
            InventoryTransaction.warehouse_id,
            InventoryTransaction.material_id,
            func.coalesce(func.sum(InventoryTransaction.quantity), 0),
        ).group_by(InventoryTransaction.warehouse_id, InventoryTransaction.material_id)
    ).all()
    quantity_map = {(warehouse_id, material_id): Decimal(quantity) for warehouse_id, material_id, quantity in totals}

    rows = []
    for material in materials:
        warehouse_quantities = []
        total_quantity = Decimal("0")
        for warehouse in warehouses:
            quantity = quantity_map.get((warehouse.id, material.id), Decimal("0"))
            total_quantity += quantity
            warehouse_quantities.append(StockCell(warehouse=warehouse, material=material, quantity=quantity))
        rows.append(
            {
                "material": material,
                "unit_label": MATERIAL_UNIT_LABELS.get(material.unit, material.unit.value),
                "warehouse_quantities": warehouse_quantities,
                "total": total_quantity,
            }
        )
    return rows


def parse_decimal(value: str) -> Decimal:
    normalized = value.replace(",", ".").strip()
    try:
        amount = Decimal(normalized)
    except Exception as exc:
        raise InventoryError("Количество должно быть числом") from exc
    if amount <= 0:
        raise InventoryError("Количество должно быть больше нуля")
    if amount != amount.to_integral_value():
        raise InventoryError("Количество материала должно быть целым числом")
    return amount


def create_operation(
    db: Session,
    *,
    user: User,
    operation: str,
    warehouse_id: int,
    material_id: int,
    quantity: str,
    comment: str | None,
    destination_warehouse_id: int | None = None,
    adjustment_direction: str = "plus",
) -> None:
    amount = parse_decimal(quantity)

    warehouse = db.get(Warehouse, warehouse_id)
    material = db.get(Material, material_id)
    if warehouse is None or not warehouse.active:
        raise InventoryError("Склад не найден или отключён")
    if material is None or not material.active:
        raise InventoryError("Материал не найден или отключён")

    if operation == "receipt":
        add_transaction(db, user, warehouse_id, material_id, InventoryTransactionType.RECEIPT, amount, comment)
    elif operation == "transfer":
        if destination_warehouse_id is None:
            raise InventoryError("Выберите склад назначения")
        if destination_warehouse_id == warehouse_id:
            raise InventoryError("Склады отправления и назначения должны отличаться")
        destination = db.get(Warehouse, destination_warehouse_id)
        if destination is None or not destination.active:
            raise InventoryError("Склад назначения не найден или отключён")
        ensure_sufficient_stock(db, warehouse_id, material_id, amount)
        add_transaction(db, user, warehouse_id, material_id, InventoryTransactionType.TRANSFER_OUT, -amount, comment)
        add_transaction(db, user, destination_warehouse_id, material_id, InventoryTransactionType.TRANSFER_IN, amount, comment)
    elif operation == "issue":
        ensure_sufficient_stock(db, warehouse_id, material_id, amount)
        add_transaction(db, user, warehouse_id, material_id, InventoryTransactionType.ISSUE_TO_THIRD_PARTY, -amount, comment)
    elif operation == "return":
        add_transaction(db, user, warehouse_id, material_id, InventoryTransactionType.RETURN, amount, comment)
    elif operation == "write_off":
        ensure_sufficient_stock(db, warehouse_id, material_id, amount)
        add_transaction(db, user, warehouse_id, material_id, InventoryTransactionType.WRITE_OFF, -amount, comment)
    elif operation == "adjustment":
        signed_amount = -amount if adjustment_direction == "minus" else amount
        if signed_amount < 0:
            ensure_sufficient_stock(db, warehouse_id, material_id, abs(signed_amount))
        add_transaction(db, user, warehouse_id, material_id, InventoryTransactionType.ADJUSTMENT, signed_amount, comment)
    else:
        raise InventoryError("Неизвестный тип операции")

    db.commit()


def ensure_sufficient_stock(db: Session, warehouse_id: int, material_id: int, quantity: Decimal) -> None:
    current_quantity = get_stock_quantity(db, warehouse_id, material_id)
    if current_quantity < quantity:
        raise InventoryError(
            f"Недостаточно материала на складе. Доступно: {format_quantity(current_quantity)}, требуется: {format_quantity(quantity)}"
        )


def add_transaction(
    db: Session,
    user: User,
    warehouse_id: int,
    material_id: int,
    operation_type: InventoryTransactionType,
    quantity: Decimal,
    comment: str | None,
) -> None:
    db.add(
        InventoryTransaction(
            warehouse_id=warehouse_id,
            material_id=material_id,
            user_id=user.id,
            operation_type=operation_type,
            quantity=quantity,
            comment=comment.strip() if comment else None,
        )
    )


def build_history_query(filters: dict) -> Select[tuple[InventoryTransaction]]:
    query = select(InventoryTransaction).options(
        joinedload(InventoryTransaction.user),
        joinedload(InventoryTransaction.warehouse),
        joinedload(InventoryTransaction.material),
    )

    if filters.get("warehouse_id"):
        query = query.where(InventoryTransaction.warehouse_id == int(filters["warehouse_id"]))
    if filters.get("material_id"):
        query = query.where(InventoryTransaction.material_id == int(filters["material_id"]))
    if filters.get("operation_type"):
        try:
            operation_type = InventoryTransactionType(filters["operation_type"])
        except ValueError:
            operation_type = None
        if operation_type is not None:
            query = query.where(InventoryTransaction.operation_type == operation_type)
    if filters.get("date_from"):
        query = query.where(InventoryTransaction.created_at >= datetime.combine(filters["date_from"], time.min))
    if filters.get("date_to"):
        query = query.where(InventoryTransaction.created_at <= datetime.combine(filters["date_to"], time.max))
    if filters.get("search"):
        pattern = f"%{filters['search']}%"
        query = query.join(InventoryTransaction.material).join(InventoryTransaction.warehouse).join(InventoryTransaction.user)
        query = query.where(
            or_(
                InventoryTransaction.comment.ilike(pattern),
                Material.name.ilike(pattern),
                Warehouse.name.ilike(pattern),
                User.username.ilike(pattern),
                User.full_name.ilike(pattern),
            )
        )

    return query.order_by(InventoryTransaction.created_at.desc(), InventoryTransaction.id.desc())


def get_history(db: Session, filters: dict, page: int, per_page: int = 15) -> OperationHistoryPage:
    page = max(page, 1)
    query = build_history_query(filters)
    count_query = select(func.count()).select_from(query.order_by(None).subquery())
    total = db.scalar(count_query) or 0
    items = list(db.scalars(query.offset((page - 1) * per_page).limit(per_page)))
    pages = max(ceil(total / per_page), 1)
    return OperationHistoryPage(items=items, page=page, per_page=per_page, total=total, pages=pages)


def normalize_filters(
    search: str | None,
    warehouse_id: int | None,
    material_id: int | None,
    operation_type: str | None,
    date_from: date | None,
    date_to: date | None,
) -> dict:
    return {
        "search": search.strip() if search else None,
        "warehouse_id": warehouse_id,
        "material_id": material_id,
        "operation_type": operation_type or None,
        "date_from": date_from,
        "date_to": date_to,
    }


def get_materials_page_data(
    db: Session,
    *,
    filters: dict,
    page: int,
    error: str | None = None,
    success: str | None = None,
    filter_query: str = "",
) -> MaterialsPageData:
    warehouses = get_active_warehouses(db)
    materials = get_active_materials(db)
    return MaterialsPageData(
        warehouses=warehouses,
        materials=materials,
        stock_rows=build_stock_rows(db, warehouses, materials),
        history=get_history(db, filters, page),
        filters=filters,
        operation_types=[
            InventoryTransactionType.RECEIPT,
            InventoryTransactionType.TRANSFER_OUT,
            InventoryTransactionType.TRANSFER_IN,
            InventoryTransactionType.RETURN,
            InventoryTransactionType.ISSUE_TO_THIRD_PARTY,
            InventoryTransactionType.WRITE_OFF,
            InventoryTransactionType.ADJUSTMENT,
        ],
        operation_labels=OPERATION_LABELS,
        unit_labels=MATERIAL_UNIT_LABELS,
        error=error,
        success=success,
    )


def format_quantity(quantity: Decimal) -> str:
    if quantity == quantity.to_integral_value():
        return str(int(quantity))
    normalized = quantity.normalize()
    return format(normalized, "f")





def build_filter_query(filters: dict) -> str:
    params = {}
    for key in ("search", "warehouse_id", "material_id", "operation_type", "date_from", "date_to"):
        value = filters.get(key)
        if value:
            params[key] = value.isoformat() if hasattr(value, "isoformat") else value
    return urlencode(params)
