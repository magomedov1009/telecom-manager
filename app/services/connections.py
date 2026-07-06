from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from math import ceil
from urllib.parse import urlencode

from sqlalchemy import Select, delete, func, or_, select
from sqlalchemy.orm import Session, joinedload, selectinload

from app.models.clients import Client, Connection, ConnectionMaterial
from app.models.enums import ConnectionType, FinanceTransactionType, InventoryTransactionType, MaterialUnit, Provider, UserRole
from app.models.finance import FinanceTransaction
from app.models.inventory import InventoryTransaction, Material, Warehouse
from app.models.users import User
from app.services.inventory import ensure_sufficient_stock, get_stock_quantity

CONNECTION_TYPE_LABELS = {
    ConnectionType.NEW: "Новое подключение",
    ConnectionType.RECONNECT: "Повторное подключение",
    ConnectionType.ONU_REPLACE: "Замена ONU",
    ConnectionType.CABLE_REPLACE: "Замена кабеля",
    ConnectionType.WITHOUT_MATERIALS: "Без материалов",
    ConnectionType.CUSTOM: "Нестандартное подключение",
}

PROVIDER_LABELS = {
    Provider.ELLKO: "ELLKO",
    Provider.OPTIMASET: "OPTIMASET",
}

MATERIAL_UNIT_LABELS = {
    MaterialUnit.PIECE: "шт.",
    MaterialUnit.METER: "м",
}


class ConnectionError(ValueError):
    pass


@dataclass(frozen=True)
class ConnectionListPage:
    items: list[Connection]
    page: int
    per_page: int
    total: int
    pages: int


@dataclass(frozen=True)
class ConnectionsPageData:
    connections: ConnectionListPage
    warehouses: list[Warehouse]
    materials: list[Material]
    providers: list[Provider]
    connection_types: list[ConnectionType]
    provider_labels: dict[Provider, str]
    connection_type_labels: dict[ConnectionType, str]
    unit_labels: dict[MaterialUnit, str]
    filters: dict
    filter_query: str
    error: str | None = None
    success: str | None = None


@dataclass(frozen=True)
class ConnectionFormData:
    warehouses: list[Warehouse]
    materials: list[Material]
    providers: list[Provider]
    connection_types: list[ConnectionType]
    provider_labels: dict[Provider, str]
    connection_type_labels: dict[ConnectionType, str]
    unit_labels: dict[MaterialUnit, str]
    connection: Connection | None = None
    error: str | None = None


def parse_decimal(value: str, field_name: str, allow_zero: bool = True) -> Decimal:
    normalized = (value or "0").replace(",", ".").strip()
    try:
        amount = Decimal(normalized)
    except Exception as exc:
        raise ConnectionError(f"{field_name}: введите число") from exc
    if amount < 0 or (amount == 0 and not allow_zero):
        raise ConnectionError(f"{field_name}: значение должно быть больше нуля")
    return amount


def parse_material_rows(material_ids: list[int], quantities: list[str]) -> list[tuple[int, Decimal]]:
    rows: list[tuple[int, Decimal]] = []
    for material_id, quantity_value in zip(material_ids, quantities, strict=False):
        if not material_id or not quantity_value.strip():
            continue
        quantity = parse_decimal(quantity_value, "Количество материала", allow_zero=False)
        rows.append((material_id, quantity))
    return rows


def calculate_finance(price: Decimal, installer_amount: str | None, office_amount: str | None) -> tuple[Decimal, Decimal]:
    if price == Decimal("1000"):
        return Decimal("1000"), Decimal("0")
    if price == Decimal("3000"):
        return Decimal("1000"), Decimal("2000")
    installer = parse_decimal(installer_amount or "0", "Доля монтажника")
    office = parse_decimal(office_amount or "0", "Доля офиса")
    if installer + office != price:
        raise ConnectionError("Для произвольной суммы доля монтажника и офиса должны равняться цене подключения")
    return installer, office


def get_reference_data(db: Session) -> tuple[list[Warehouse], list[Material]]:
    warehouses = list(db.scalars(select(Warehouse).where(Warehouse.active.is_(True)).order_by(Warehouse.name)))
    materials = list(db.scalars(select(Material).where(Material.active.is_(True)).order_by(Material.name)))
    return warehouses, materials


def get_form_data(db: Session, connection: Connection | None = None, error: str | None = None) -> ConnectionFormData:
    warehouses, materials = get_reference_data(db)
    return ConnectionFormData(
        warehouses=warehouses,
        materials=materials,
        providers=list(Provider),
        connection_types=list(ConnectionType),
        provider_labels=PROVIDER_LABELS,
        connection_type_labels=CONNECTION_TYPE_LABELS,
        unit_labels=MATERIAL_UNIT_LABELS,
        connection=connection,
        error=error,
    )


def normalize_filters(
    search: str | None,
    provider: str | None,
    connection_type: str | None,
    warehouse_id: int | None,
    date_from: date | None,
    date_to: date | None,
) -> dict:
    return {
        "search": search.strip() if search else None,
        "provider": provider or None,
        "connection_type": connection_type or None,
        "warehouse_id": warehouse_id,
        "date_from": date_from,
        "date_to": date_to,
    }


def build_filter_query(filters: dict) -> str:
    params = {}
    for key in ("search", "provider", "connection_type", "warehouse_id", "date_from", "date_to"):
        value = filters.get(key)
        if value:
            params[key] = value.isoformat() if hasattr(value, "isoformat") else value
    return urlencode(params)


def build_connections_query(filters: dict) -> Select[tuple[Connection]]:
    query = select(Connection).options(
        joinedload(Connection.client),
        joinedload(Connection.warehouse),
        joinedload(Connection.installer),
        selectinload(Connection.connection_materials).joinedload(ConnectionMaterial.material),
    ).join(Connection.client)

    if filters.get("search"):
        pattern = f"%{filters['search']}%"
        query = query.where(
            or_(
                Client.contract_number.ilike(pattern),
                Client.login.ilike(pattern),
                Client.address.ilike(pattern),
                Client.phone.ilike(pattern),
                Connection.comment.ilike(pattern),
            )
        )
    if filters.get("provider"):
        try:
            query = query.where(Client.provider == Provider(filters["provider"]))
        except ValueError:
            pass
    if filters.get("connection_type"):
        try:
            query = query.where(Connection.connection_type == ConnectionType(filters["connection_type"]))
        except ValueError:
            pass
    if filters.get("warehouse_id"):
        query = query.where(Connection.warehouse_id == int(filters["warehouse_id"]))
    if filters.get("date_from"):
        query = query.where(Connection.connection_date >= filters["date_from"])
    if filters.get("date_to"):
        query = query.where(Connection.connection_date <= filters["date_to"])

    return query.order_by(Connection.connection_date.desc(), Connection.id.desc())


def get_connections_page(db: Session, filters: dict, page: int, per_page: int = 15) -> ConnectionListPage:
    page = max(page, 1)
    query = build_connections_query(filters)
    total = db.scalar(select(func.count()).select_from(query.order_by(None).subquery())) or 0
    items = list(db.scalars(query.offset((page - 1) * per_page).limit(per_page)))
    return ConnectionListPage(items=items, page=page, per_page=per_page, total=total, pages=max(ceil(total / per_page), 1))


def get_connections_page_data(
    db: Session,
    *,
    filters: dict,
    page: int,
    error: str | None = None,
    success: str | None = None,
) -> ConnectionsPageData:
    warehouses, materials = get_reference_data(db)
    return ConnectionsPageData(
        connections=get_connections_page(db, filters, page),
        warehouses=warehouses,
        materials=materials,
        providers=list(Provider),
        connection_types=list(ConnectionType),
        provider_labels=PROVIDER_LABELS,
        connection_type_labels=CONNECTION_TYPE_LABELS,
        unit_labels=MATERIAL_UNIT_LABELS,
        filters=filters,
        filter_query=build_filter_query(filters),
        error=error,
        success=success,
    )


def get_connection(db: Session, connection_id: int) -> Connection | None:
    return db.scalar(
        select(Connection)
        .where(Connection.id == connection_id)
        .options(
            joinedload(Connection.client),
            joinedload(Connection.warehouse),
            joinedload(Connection.installer),
            selectinload(Connection.connection_materials).joinedload(ConnectionMaterial.material),
            selectinload(Connection.finance_transactions),
            selectinload(Connection.inventory_transactions).joinedload(InventoryTransaction.material),
        )
    )


def normalize_client_identity(
    provider: Provider,
    contract_number: str | None,
    login: str | None,
    phone: str | None,
) -> tuple[str, str, str | None]:
    normalized_contract = contract_number.strip() if contract_number else ""
    normalized_login = login.strip() if login else ""

    if provider == Provider.ELLKO:
        if not normalized_login:
            raise ConnectionError("Для Эллко обязателен номер договора")
        return normalized_login, normalized_login, normalized_contract or None

    if provider == Provider.OPTIMASET:
        if not normalized_login:
            raise ConnectionError("Для Оптимасеть обязателен номер телефона")
        phone_value = normalized_login
        phone_contract = phone_value[1:] if phone_value.startswith("8") and len(phone_value) > 1 else phone_value
        return normalized_contract or phone_contract, phone_contract, phone_value

    raise ConnectionError("Неизвестный провайдер")


def find_or_create_client(
    db: Session,
    *,
    provider: Provider,
    contract_number: str,
    login: str | None,
    address: str,
    phone: str | None,
    comment: str | None,
) -> Client:
    client = db.scalar(select(Client).where(or_(Client.contract_number == contract_number, Client.login == login)))
    if client is None:
        client = Client(provider=provider, contract_number=contract_number, login=login, address=address, phone=phone, comment=comment)
        db.add(client)
        db.flush()
        return client

    if client.contract_number != contract_number and client.login != login:
        raise ConnectionError("Номер договора или логин уже используются другим клиентом")
    client.provider = provider
    client.contract_number = contract_number
    client.login = login
    client.address = address
    client.phone = phone
    client.comment = comment
    return client


def validate_materials(db: Session, warehouse_id: int, material_rows: list[tuple[int, Decimal]]) -> None:
    for material_id, quantity in material_rows:
        material = db.get(Material, material_id)
        if material is None or not material.active:
            raise ConnectionError("Выбранный материал не найден или отключён")
        ensure_sufficient_stock(db, warehouse_id, material_id, quantity)


def add_connection_materials_and_transactions(
    db: Session,
    *,
    connection: Connection,
    user: User,
    material_rows: list[tuple[int, Decimal]],
    comment: str | None,
) -> None:
    for material_id, quantity in material_rows:
        db.add(ConnectionMaterial(connection_id=connection.id, material_id=material_id, quantity=quantity, comment=comment))
        db.add(
            InventoryTransaction(
                warehouse_id=connection.warehouse_id,
                material_id=material_id,
                connection_id=connection.id,
                user_id=user.id,
                operation_type=InventoryTransactionType.CONNECTION,
                quantity=-quantity,
                comment=comment,
            )
        )


def reverse_connection_materials(db: Session, *, connection: Connection, user: User) -> None:
    transactions = list(
        db.scalars(
            select(InventoryTransaction).where(
                InventoryTransaction.connection_id == connection.id,
                InventoryTransaction.operation_type == InventoryTransactionType.CONNECTION,
                InventoryTransaction.quantity < 0,
            )
        )
    )
    for transaction in transactions:
        db.add(
            InventoryTransaction(
                warehouse_id=transaction.warehouse_id,
                material_id=transaction.material_id,
                connection_id=connection.id,
                user_id=user.id,
                operation_type=InventoryTransactionType.ADJUSTMENT,
                quantity=abs(transaction.quantity),
                comment="Возврат списания при редактировании подключения",
            )
        )
    db.execute(delete(ConnectionMaterial).where(ConnectionMaterial.connection_id == connection.id))


def replace_finance_transaction(db: Session, *, connection: Connection, user: User, amount: Decimal) -> None:
    db.execute(delete(FinanceTransaction).where(FinanceTransaction.connection_id == connection.id))
    if amount != 0:
        db.add(
            FinanceTransaction(
                connection_id=connection.id,
                amount=amount,
                user_id=user.id,
                transaction_type=FinanceTransactionType.CONNECTION,
                comment="Оплата подключения",
            )
        )


def create_connection(
    db: Session,
    *,
    user: User,
    connection_date: date,
    provider: str,
    contract_number: str,
    login: str | None,
    address: str,
    phone: str | None,
    client_comment: str | None,
    connection_comment: str | None,
    connection_type: str,
    warehouse_id: int,
    price: str,
    installer_amount: str | None,
    office_amount: str | None,
    material_ids: list[int],
    material_quantities: list[str],
) -> Connection:
    provider_enum = Provider(provider)
    normalized_contract_number, normalized_login, normalized_phone = normalize_client_identity(provider_enum, contract_number, login, phone)
    connection_type_enum = ConnectionType(connection_type)
    parsed_price = parse_decimal(price, "Цена подключения")
    parsed_installer_amount, parsed_office_amount = calculate_finance(parsed_price, installer_amount, office_amount)
    material_rows = [] if connection_type_enum == ConnectionType.WITHOUT_MATERIALS else parse_material_rows(material_ids, material_quantities)

    warehouse = db.get(Warehouse, warehouse_id)
    if warehouse is None or not warehouse.active:
        raise ConnectionError("Склад не найден или отключён")
    validate_materials(db, warehouse_id, material_rows)

    client = find_or_create_client(
        db,
        provider=provider_enum,
        contract_number=normalized_contract_number,
        login=normalized_login,
        address=address.strip(),
        phone=normalized_phone,
        comment=client_comment.strip() if client_comment else None,
    )
    connection = Connection(
        client_id=client.id,
        warehouse_id=warehouse_id,
        connection_type=connection_type_enum,
        connection_date=connection_date,
        installer_id=user.id,
        price=parsed_price,
        office_amount=parsed_office_amount,
        installer_amount=parsed_installer_amount,
        comment=connection_comment.strip() if connection_comment else None,
    )
    db.add(connection)
    db.flush()

    add_connection_materials_and_transactions(db, connection=connection, user=user, material_rows=material_rows, comment=connection_comment)
    replace_finance_transaction(db, connection=connection, user=user, amount=parsed_price)
    db.commit()
    return connection


def update_connection(
    db: Session,
    *,
    connection: Connection,
    user: User,
    connection_date: date,
    provider: str,
    contract_number: str,
    login: str | None,
    address: str,
    phone: str | None,
    client_comment: str | None,
    connection_comment: str | None,
    connection_type: str,
    warehouse_id: int,
    price: str,
    installer_amount: str | None,
    office_amount: str | None,
    material_ids: list[int],
    material_quantities: list[str],
) -> Connection:
    provider_enum = Provider(provider)
    normalized_contract_number, normalized_login, normalized_phone = normalize_client_identity(provider_enum, contract_number, login, phone)
    connection_type_enum = ConnectionType(connection_type)
    parsed_price = parse_decimal(price, "Цена подключения")
    parsed_installer_amount, parsed_office_amount = calculate_finance(parsed_price, installer_amount, office_amount)
    material_rows = [] if connection_type_enum == ConnectionType.WITHOUT_MATERIALS else parse_material_rows(material_ids, material_quantities)

    warehouse = db.get(Warehouse, warehouse_id)
    if warehouse is None or not warehouse.active:
        raise ConnectionError("Склад не найден или отключён")

    reverse_connection_materials(db, connection=connection, user=user)
    validate_materials(db, warehouse_id, material_rows)

    client = connection.client
    client.provider = provider_enum
    client.contract_number = normalized_contract_number
    client.login = normalized_login
    client.address = address.strip()
    client.phone = normalized_phone
    client.comment = client_comment.strip() if client_comment else None

    connection.warehouse_id = warehouse_id
    connection.connection_type = connection_type_enum
    connection.connection_date = connection_date
    connection.price = parsed_price
    connection.office_amount = parsed_office_amount
    connection.installer_amount = parsed_installer_amount
    connection.comment = connection_comment.strip() if connection_comment else None

    add_connection_materials_and_transactions(db, connection=connection, user=user, material_rows=material_rows, comment=connection_comment)
    replace_finance_transaction(db, connection=connection, user=user, amount=parsed_price)
    db.commit()
    return connection


def delete_connection(db: Session, *, connection: Connection, user: User) -> None:
    if user.role != UserRole.ADMIN:
        raise ConnectionError("Удалять подключения может только администратор")
    reverse_connection_materials(db, connection=connection, user=user)
    db.delete(connection)
    db.commit()


def get_stock_hint(db: Session, warehouse_id: int | None, material_id: int | None) -> Decimal | None:
    if not warehouse_id or not material_id:
        return None
    return get_stock_quantity(db, warehouse_id, material_id)



