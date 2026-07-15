from dataclasses import dataclass
from datetime import date, datetime, time
from decimal import Decimal
from math import ceil
from urllib.parse import urlencode

from sqlalchemy import Select, func, or_, select
from sqlalchemy.orm import Session, joinedload

from app.models.clients import Provider
from app.models.enums import InventoryItemType, InventoryTransactionType, MaterialUnit
from app.models.inventory import InventoryTransaction, Material, Warehouse
from app.models.users import User
from app.services.access import AccessScope, apply_user_scope, get_access_scope

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

ITEM_TYPE_LABELS = {
    InventoryItemType.MATERIAL: "Материалы",
    InventoryItemType.EQUIPMENT: "Оборудование",
}

MATERIAL_UNIT_LABELS = {
    MaterialUnit.PIECE: "??.",
    MaterialUnit.METER: "?",
}

DEFAULT_UNIT_OPTIONS = ["м", "кг", "л", "рулон", "упаковка", "шт.", "ед."]


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
    equipment: list[Material]
    stock_rows: list[dict]
    material_stock_rows: list[dict]
    equipment_stock_rows: list[dict]
    history: OperationHistoryPage
    filters: dict
    operation_types: list[InventoryTransactionType]
    operation_labels: dict[InventoryTransactionType, str]
    item_type_labels: dict[InventoryItemType, str]
    unit_options: list[str]
    providers: list[Provider]
    error: str | None = None
    success: str | None = None
    filter_query: str = ""


def get_unit_label(material: Material) -> str:
    return material.unit_name or MATERIAL_UNIT_LABELS.get(material.unit, material.unit.value)


def get_active_warehouses(db: Session) -> list[Warehouse]:
    return list(db.scalars(select(Warehouse).where(Warehouse.active.is_(True)).order_by(Warehouse.name)))


def get_active_materials(db: Session) -> list[Material]:
    return list(db.scalars(select(Material).where(Material.active.is_(True)).order_by(Material.item_type, Material.name)))


def get_stock_quantity(db: Session, warehouse_id: int, material_id: int) -> Decimal:
    quantity = db.scalar(
        select(func.coalesce(func.sum(InventoryTransaction.quantity), 0)).where(
            InventoryTransaction.warehouse_id == warehouse_id,
            InventoryTransaction.material_id == material_id,
        )
    )
    return Decimal(quantity or 0)


def build_stock_rows(db: Session, warehouses: list[Warehouse], materials: list[Material], providers: list[Provider], scope: AccessScope | None = None) -> list[dict]:
    totals_query = select(
        InventoryTransaction.warehouse_id,
        InventoryTransaction.material_id,
        func.coalesce(func.sum(InventoryTransaction.quantity), 0),
    ).group_by(InventoryTransaction.warehouse_id, InventoryTransaction.material_id)
    totals = db.execute(apply_user_scope(totals_query, InventoryTransaction.user_id, scope)).all()
    quantity_map = {(warehouse_id, material_id): Decimal(quantity) for warehouse_id, material_id, quantity in totals}

    provider_totals_query = (
        select(
            InventoryTransaction.provider_id,
            InventoryTransaction.material_id,
            func.coalesce(func.sum(InventoryTransaction.quantity), 0),
        )
        .where(InventoryTransaction.provider_id.is_not(None))
        .group_by(InventoryTransaction.provider_id, InventoryTransaction.material_id)
    )
    provider_totals = db.execute(apply_user_scope(provider_totals_query, InventoryTransaction.user_id, scope)).all()
    provider_quantity_map = {(provider_id, material_id): Decimal(quantity) for provider_id, material_id, quantity in provider_totals}

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
                "unit_label": get_unit_label(material),
                "warehouse_quantities": warehouse_quantities,
                "total": total_quantity,
                "provider_quantities": [(provider, provider_quantity_map.get((provider.id, material.id), Decimal("0"))) for provider in providers],
            }
        )
    return rows

def parse_decimal(value: str, *, integer_only: bool = False) -> Decimal:
    normalized = value.replace(",", ".").strip()
    try:
        amount = Decimal(normalized)
    except Exception as exc:
        raise InventoryError("Количество должно быть числом") from exc
    if amount <= 0:
        raise InventoryError("Количество должно быть больше нуля")
    if integer_only and amount != amount.to_integral_value():
        raise InventoryError("Количество оборудования должно быть целым числом")
    return amount


def create_inventory_item(db: Session, *, name: str, item_type: str, category: str | None, unit_name: str) -> None:
    clean_name = name.strip()
    clean_unit = unit_name.strip()
    if not clean_name:
        raise InventoryError("Название обязательно")
    if not clean_unit:
        raise InventoryError("Единица измерения обязательна")
    try:
        item_type_enum = InventoryItemType(item_type)
    except ValueError as exc:
        raise InventoryError("Некорректный тип складской позиции") from exc
    if db.scalar(select(Material).where(func.lower(Material.name) == clean_name.lower())) is not None:
        raise InventoryError("Такая складская позиция уже существует")
    unit = MaterialUnit.PIECE if item_type_enum == InventoryItemType.EQUIPMENT else MaterialUnit.METER
    db.add(Material(name=clean_name, item_type=item_type_enum, category=category.strip() if category else None, unit_name=clean_unit, unit=unit, active=True))
    db.commit()


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
    warehouse = db.get(Warehouse, warehouse_id)
    material = db.get(Material, material_id)
    if warehouse is None or not warehouse.active:
        raise InventoryError("Склад не найден или отключен")
    if material is None or not material.active:
        raise InventoryError("Складская позиция не найдена или отключена")

    amount = parse_decimal(quantity, integer_only=material.item_type == InventoryItemType.EQUIPMENT)

    if operation == "receipt":
        add_transaction(db, user, warehouse_id, material_id, InventoryTransactionType.RECEIPT, amount, comment)
    elif operation == "transfer":
        if destination_warehouse_id is None:
            raise InventoryError("Выберите склад назначения")
        if destination_warehouse_id == warehouse_id:
            raise InventoryError("Склад отправления и назначения должны отличаться")
        destination = db.get(Warehouse, destination_warehouse_id)
        if destination is None or not destination.active:
            raise InventoryError("Склад назначения не найден или отключен")
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
        raise InventoryError("Некорректный тип операции")

    db.commit()


def ensure_sufficient_stock(db: Session, warehouse_id: int, material_id: int, quantity: Decimal) -> None:
    current_quantity = get_stock_quantity(db, warehouse_id, material_id)
    if current_quantity < quantity:
        raise InventoryError(
            f"Недостаточно на складе. Остаток: {format_quantity(current_quantity)}, требуется: {format_quantity(quantity)}"
        )


def add_transaction(db: Session, user: User, warehouse_id: int, material_id: int, operation_type: InventoryTransactionType, quantity: Decimal, comment: str | None) -> None:
    db.add(InventoryTransaction(warehouse_id=warehouse_id, material_id=material_id, user_id=user.id, operation_type=operation_type, quantity=quantity, comment=comment.strip() if comment else None))


def build_history_query(filters: dict, scope: AccessScope | None = None) -> Select[tuple[InventoryTransaction]]:
    query = select(InventoryTransaction).options(joinedload(InventoryTransaction.user), joinedload(InventoryTransaction.warehouse), joinedload(InventoryTransaction.material))
    query = apply_user_scope(query, InventoryTransaction.user_id, scope)
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
    if filters.get("item_type"):
        try:
            item_type = InventoryItemType(filters["item_type"])
        except ValueError:
            item_type = None
        if item_type is not None:
            query = query.join(InventoryTransaction.material).where(Material.item_type == item_type)
    if filters.get("date_from"):
        query = query.where(InventoryTransaction.created_at >= datetime.combine(filters["date_from"], time.min))
    if filters.get("date_to"):
        query = query.where(InventoryTransaction.created_at <= datetime.combine(filters["date_to"], time.max))
    if filters.get("search"):
        pattern = f"%{filters['search']}%"
        query = query.join(InventoryTransaction.material).join(InventoryTransaction.warehouse).join(InventoryTransaction.user)
        query = query.where(or_(InventoryTransaction.comment.ilike(pattern), Material.name.ilike(pattern), Material.category.ilike(pattern), Warehouse.name.ilike(pattern), User.username.ilike(pattern), User.full_name.ilike(pattern)))
    return query.order_by(InventoryTransaction.created_at.desc(), InventoryTransaction.id.desc())


def get_history(db: Session, filters: dict, page: int, per_page: int = 15, user: User | None = None) -> OperationHistoryPage:
    page = max(page, 1)
    scope = get_access_scope(db, user) if user is not None else None
    query = build_history_query(filters, scope)
    total = db.scalar(select(func.count()).select_from(query.order_by(None).subquery())) or 0
    items = list(db.scalars(query.offset((page - 1) * per_page).limit(per_page)))
    return OperationHistoryPage(items=items, page=page, per_page=per_page, total=total, pages=max(ceil(total / per_page), 1))


def normalize_filters(search: str | None, warehouse_id: int | None, material_id: int | None, operation_type: str | None, date_from: date | None, date_to: date | None, item_type: str | None = None) -> dict:
    return {"search": search.strip() if search else None, "warehouse_id": warehouse_id, "material_id": material_id, "operation_type": operation_type or None, "date_from": date_from, "date_to": date_to, "item_type": item_type or None}


def get_materials_page_data(db: Session, *, filters: dict, page: int, error: str | None = None, success: str | None = None, filter_query: str = "", current_user: User | None = None) -> MaterialsPageData:
    warehouses = get_active_warehouses(db)
    providers = list(db.scalars(select(Provider).where(Provider.is_active.is_(True)).order_by(Provider.name)))
    all_items = get_active_materials(db)
    material_items = [item for item in all_items if item.item_type == InventoryItemType.MATERIAL]
    equipment_items = [item for item in all_items if item.item_type == InventoryItemType.EQUIPMENT]
    scope = get_access_scope(db, current_user) if current_user is not None else None
    stock_rows = build_stock_rows(db, warehouses, all_items, providers, scope)
    return MaterialsPageData(
        warehouses=warehouses,
        materials=material_items,
        equipment=equipment_items,
        stock_rows=stock_rows,
        material_stock_rows=[row for row in stock_rows if row["material"].item_type == InventoryItemType.MATERIAL],
        equipment_stock_rows=[row for row in stock_rows if row["material"].item_type == InventoryItemType.EQUIPMENT],
        history=get_history(db, filters, page, user=current_user),
        filters=filters,
        operation_types=[InventoryTransactionType.RECEIPT, InventoryTransactionType.TRANSFER_OUT, InventoryTransactionType.TRANSFER_IN, InventoryTransactionType.RETURN, InventoryTransactionType.ISSUE_TO_THIRD_PARTY, InventoryTransactionType.WRITE_OFF, InventoryTransactionType.ADJUSTMENT],
        operation_labels=OPERATION_LABELS,
        item_type_labels=ITEM_TYPE_LABELS,
        unit_options=DEFAULT_UNIT_OPTIONS,
        providers=providers,
        error=error,
        success=success,
        filter_query=filter_query,
    )


def format_quantity(quantity: Decimal) -> str:
    if quantity == quantity.to_integral_value():
        return str(int(quantity))
    return format(quantity.normalize(), "f")


def build_filter_query(filters: dict) -> str:
    params = {}
    for key in ("search", "warehouse_id", "material_id", "operation_type", "date_from", "date_to", "item_type"):
        value = filters.get(key)
        if value:
            params[key] = value.isoformat() if hasattr(value, "isoformat") else value
    return urlencode(params)
