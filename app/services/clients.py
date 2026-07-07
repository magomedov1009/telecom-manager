from dataclasses import dataclass
from math import ceil
from urllib.parse import urlencode

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.models.clients import Client, Connection, ConnectionMaterial
from app.models.enums import Provider
from app.services.connections import PROVIDER_LABELS
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
    provider_labels: dict[Provider, str]


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
    provider_labels: dict[Provider, str]


def normalize_filters(search: str | None, provider: str | None) -> dict:
    return {
        "search": search.strip() if search else None,
        "provider": provider or None,
    }


def build_filter_query(filters: dict) -> str:
    params = {key: value for key, value in filters.items() if value}
    return urlencode(params)


def build_clients_query(filters: dict):
    query = select(Client).options(selectinload(Client.connections))
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
        try:
            query = query.where(Client.provider == Provider(filters["provider"]))
        except ValueError:
            pass
    return query.order_by(Client.id.desc())


def get_latest_connection(client: Client) -> Connection | None:
    return max(client.connections, key=lambda item: (item.connection_date, item.id), default=None)


def get_client_identifier(client: Client) -> str:
    if client.provider == Provider.ELLKO:
        return client.contract_number
    return client.phone or client.contract_number


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


def get_clients_page(db: Session, filters: dict, page: int, per_page: int = 15) -> ClientListPage:
    page = max(page, 1)
    query = build_clients_query(filters)
    total = db.scalar(select(func.count()).select_from(query.order_by(None).subquery())) or 0
    clients = list(db.scalars(query.offset((page - 1) * per_page).limit(per_page)))
    return ClientListPage(
        items=[make_client_item(client) for client in clients],
        page=page,
        per_page=per_page,
        total=total,
        pages=max(ceil(total / per_page), 1),
    )


def get_clients_page_data(db: Session, filters: dict, page: int) -> ClientsPageData:
    return ClientsPageData(
        clients=get_clients_page(db, filters, page),
        filters=filters,
        filter_query=build_filter_query(filters),
        providers=list(Provider),
        provider_labels=PROVIDER_LABELS,
    )


def get_client(db: Session, client_id: int) -> Client | None:
    return db.scalar(
        select(Client)
        .where(Client.id == client_id)
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
        provider_labels=PROVIDER_LABELS,
    )
