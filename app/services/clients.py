from dataclasses import dataclass
from math import ceil
from urllib.parse import urlencode

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.models.clients import Client, Connection, ConnectionMaterial, Provider
from app.models.users import User
from app.services.access import AccessScope, apply_user_scope, get_access_scope
from app.services.inventory import format_quantity


@dataclass(frozen=True)
class ClientListItem:
    client: Client
    identifier: str
    full_name: str
    status: str
    connection_date: object | None
    connection_id: int | None


@dataclass(frozen=True)
class ClientListPage:
    items: list[ClientListItem]
    page: int
    per_page: int
    total: int
    pages: int


@dataclass(frozen=True)
class ClientsPageData:
    clients: ClientListPage
    filters: dict
    filter_query: str
    providers: list[Provider]


@dataclass(frozen=True)
class ClientDetailData:
    client: Client
    identifier: str
    full_name: str
    phone: str
    onu: str
    status: str
    connection_date: object | None
    note: str


def normalize_filters(search: str | None, provider: str | None) -> dict:
    return {
        "search": search.strip() if search else None,
        "provider": provider or None,
    }


def build_filter_query(filters: dict) -> str:
    params = {key: value for key, value in filters.items() if value}
    return urlencode(params)


def build_clients_query(filters: dict, scope: AccessScope | None = None):
    query = select(Client).options(selectinload(Client.connections)).join(Client.connections)
    query = apply_user_scope(query, Connection.installer_id, scope)
    if filters.get("search"):
        pattern = f"%{filters['search']}%"
        query = query.where(
            or_(
                Client.contract_number.ilike(pattern),
                Client.login.ilike(pattern),
                Client.address.ilike(pattern),
                Client.phone.ilike(pattern),
                Client.comment.ilike(pattern),
            )
        )
    if filters.get("provider"):
        query = query.where(Client.provider_id == int(filters["provider"]))
    return query.distinct().order_by(Client.id.desc())


def get_latest_connection(client: Client) -> Connection | None:
    return max(client.connections, key=lambda item: (item.connection_date, item.id), default=None)


def get_client_identifier(client: Client) -> str:
    return client.contract_number or client.login or client.phone or "—"


def make_client_item(client: Client) -> ClientListItem:
    latest_connection = get_latest_connection(client)
    return ClientListItem(
        client=client,
        identifier=get_client_identifier(client),
        full_name=client.comment or "—",
        status="Активен" if latest_connection else "Без подключений",
        connection_date=latest_connection.connection_date if latest_connection else None,
        connection_id=latest_connection.id if latest_connection else None,
    )


def get_clients_page(db: Session, filters: dict, page: int, per_page: int = 15, user: User | None = None) -> ClientListPage:
    page = max(page, 1)
    scope = get_access_scope(db, user) if user is not None else None
    query = build_clients_query(filters, scope)
    total = db.scalar(select(func.count()).select_from(query.order_by(None).subquery())) or 0
    clients = list(db.scalars(query.offset((page - 1) * per_page).limit(per_page)))
    return ClientListPage(
        items=[make_client_item(client) for client in clients],
        page=page,
        per_page=per_page,
        total=total,
        pages=max(ceil(total / per_page), 1),
    )


def get_clients_page_data(db: Session, filters: dict, page: int, user: User | None = None) -> ClientsPageData:
    return ClientsPageData(
        clients=get_clients_page(db, filters, page, user=user),
        filters=filters,
        filter_query=build_filter_query(filters),
        providers=list(db.scalars(select(Provider).where(Provider.is_active.is_(True)).order_by(Provider.name))),
    )


def get_client(db: Session, client_id: int, user: User | None = None) -> Client | None:
    query = select(Client).where(Client.id == client_id)
    if user is not None:
        query = query.join(Client.connections)
        query = apply_user_scope(query, Connection.installer_id, get_access_scope(db, user))
    return db.scalar(
        query
        .options(
            selectinload(Client.connections)
            .selectinload(Connection.connection_materials)
            .joinedload(ConnectionMaterial.material)
        )
    )


def get_client_detail_data(client: Client) -> ClientDetailData:
    latest_connection = get_latest_connection(client)
    onu = "—"
    if latest_connection is not None:
        for item in latest_connection.connection_materials:
            if item.material.name.upper() == "ONU":
                onu = format_quantity(item.quantity)
                break
    return ClientDetailData(
        client=client,
        identifier=get_client_identifier(client),
        full_name=client.comment or "—",
        phone=client.phone or "—",
        onu=onu,
        status="Активен" if latest_connection else "Без подключений",
        connection_date=latest_connection.connection_date if latest_connection else None,
        note=client.comment or "—",
    )
