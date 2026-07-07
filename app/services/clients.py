from dataclasses import dataclass
from math import ceil
from urllib.parse import urlencode

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.models.clients import Client
from app.models.enums import Provider
from app.services.connections import PROVIDER_LABELS


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


def make_client_item(client: Client) -> ClientListItem:
    latest_connection = max(client.connections, key=lambda item: (item.connection_date, item.id), default=None)
    identifier = client.contract_number if client.provider == Provider.ELLKO else (client.phone or client.contract_number)
    return ClientListItem(
        client=client,
        identifier=identifier,
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
