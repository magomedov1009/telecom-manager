from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from math import ceil
from urllib.parse import urlencode

from sqlalchemy import Select, func, or_, select
from sqlalchemy.orm import Session, joinedload

from app.models.clients import Client, Connection, ExtraWork, Provider
from app.models.enums import ConnectionType, ExpenseCategory, FinanceTransactionType, InventoryItemType, PaidBy
from app.models.finance import Expense, FinanceTransaction
from app.models.inventory import InventoryTransaction, Material
from app.services.expenses import make_expense_row
from app.services.finance import get_finance_stats
from app.services.inventory import get_unit_label

PERIOD_LABELS = {
    "all": "За всё время",
    "today": "Сегодня",
    "yesterday": "Вчера",
    "week": "Неделя",
    "month": "Месяц",
    "custom": "Произвольный период",
}

CONNECTION_TYPE_LABELS = {
    ConnectionType.NEW: "Новое",
    ConnectionType.RECONNECT: "Повторное",
    ConnectionType.ONU_REPLACE: "Замена ONU",
    ConnectionType.CABLE_REPLACE: "Замена кабеля",
    ConnectionType.WITHOUT_MATERIALS: "Без материалов",
    ConnectionType.CUSTOM: "Нестандартное",
}

EXPENSE_CATEGORY_LABELS = {
    ExpenseCategory.FUEL: "Бензин",
    ExpenseCategory.TOOLS: "Инструмент",
    ExpenseCategory.TRANSPORT: "Транспорт",
    ExpenseCategory.COMMUNICATION: "Связь",
    ExpenseCategory.OTHER: "Прочее",
}

PAID_BY_LABELS = {PaidBy.INSTALLER: "Монтажник", PaidBy.OFFICE: "Офис"}
REPORT_TABS = ("providers", "connections", "extra_works", "expenses", "inventory", "finance")


@dataclass(frozen=True)
class ReportPage:
    items: list
    page: int
    per_page: int
    total: int
    pages: int
    sort: str
    direction: str


def resolve_period(period: str, date_from: date | None, date_to: date | None) -> dict:
    today = date.today()
    if period == "all":
        start_date = end_date = None
    elif period == "yesterday":
        start_date = end_date = today - timedelta(days=1)
    elif period == "week":
        start_date, end_date = today - timedelta(days=today.weekday()), today
    elif period == "month":
        start_date, end_date = today.replace(day=1), today
    elif period == "custom":
        start_date, end_date = date_from or today, date_to or date_from or today
    else:
        period, start_date, end_date = "today", today, today
    if start_date and end_date and end_date < start_date:
        start_date, end_date = end_date, start_date
    return {
        "period": period,
        "label": PERIOD_LABELS[period],
        "date_from": start_date,
        "date_to": end_date,
        "start": datetime.combine(start_date, time.min) if start_date else None,
        "end": datetime.combine(end_date, time.max) if end_date else None,
    }


def apply_datetime_period(query, column, period: dict):
    if period["start"]:
        query = query.where(column >= period["start"])
    if period["end"]:
        query = query.where(column <= period["end"])
    return query


def apply_date_period(query, column, period: dict):
    if period["date_from"]:
        query = query.where(column >= period["date_from"])
    if period["date_to"]:
        query = query.where(column <= period["date_to"])
    return query


def decimal_scalar(db: Session, query) -> Decimal:
    return Decimal(db.scalar(query) or 0)


def paginate(db: Session, query: Select, page: int, per_page: int, sort: str, direction: str) -> ReportPage:
    page = max(page, 1)
    total = db.scalar(select(func.count()).select_from(query.order_by(None).subquery())) or 0
    items = list(db.scalars(query.offset((page - 1) * per_page).limit(per_page)))
    return ReportPage(items, page, per_page, total, max(ceil(total / per_page), 1), sort, direction)


def order_query(query, sort_map: dict, sort: str, direction: str):
    column = sort_map.get(sort, sort_map["date"])
    return query.order_by(column.asc() if direction == "asc" else column.desc())


def connection_query(period: dict, provider_id: int | None):
    query = select(Connection).join(Connection.client).options(joinedload(Connection.client).joinedload(Client.provider))
    query = apply_date_period(query, Connection.connection_date, period)
    if provider_id:
        query = query.where(Client.provider_id == provider_id)
    return query


def extra_work_query(period: dict, provider_id: int | None):
    query = select(ExtraWork).options(joinedload(ExtraWork.provider), joinedload(ExtraWork.work_type))
    query = apply_date_period(query, ExtraWork.work_date, period)
    if provider_id:
        query = query.where(ExtraWork.provider_id == provider_id)
    return query


def expense_query(period: dict, provider_id: int | None):
    query = select(Expense).options(joinedload(Expense.provider))
    query = apply_datetime_period(query, Expense.created_at, period)
    if provider_id:
        query = query.where(Expense.provider_id == provider_id)
    return query


def income_summary(db: Session, period: dict, provider_id: int | None) -> dict:
    connection_income = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(
        FinanceTransaction.transaction_type == FinanceTransactionType.CONNECTION,
        FinanceTransaction.amount > 0,
    )
    extra_income = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(
        FinanceTransaction.transaction_type == FinanceTransactionType.EXTRA_WORK,
        FinanceTransaction.amount > 0,
    )
    connection_income = apply_datetime_period(connection_income, FinanceTransaction.created_at, period)
    extra_income = apply_datetime_period(extra_income, FinanceTransaction.created_at, period)
    if provider_id:
        connection_income = connection_income.where(FinanceTransaction.provider_id == provider_id)
        extra_income = extra_income.where(FinanceTransaction.provider_id == provider_id)
    connections = decimal_scalar(db, connection_income)
    extra_works = decimal_scalar(db, extra_income)
    return {"connections": connections, "extra_works": extra_works, "total": connections + extra_works}


def inventory_summary(db: Session, period: dict, provider_id: int | None) -> dict:
    result = {InventoryItemType.MATERIAL: [], InventoryItemType.EQUIPMENT: []}
    for material in db.scalars(select(Material).where(Material.active.is_(True)).order_by(Material.item_type, Material.name)):
        balance = select(func.coalesce(func.sum(InventoryTransaction.quantity), 0)).where(InventoryTransaction.material_id == material.id)
        receipt = apply_datetime_period(
            select(func.coalesce(func.sum(InventoryTransaction.quantity), 0)).where(InventoryTransaction.material_id == material.id, InventoryTransaction.quantity > 0),
            InventoryTransaction.created_at,
            period,
        )
        spent = apply_datetime_period(
            select(func.coalesce(func.sum(func.abs(InventoryTransaction.quantity)), 0)).where(InventoryTransaction.material_id == material.id, InventoryTransaction.quantity < 0),
            InventoryTransaction.created_at,
            period,
        )
        if provider_id:
            balance = balance.where(InventoryTransaction.provider_id == provider_id)
            receipt = receipt.where(InventoryTransaction.provider_id == provider_id)
            spent = spent.where(InventoryTransaction.provider_id == provider_id)
        result[material.item_type].append(
            {
                "material": material,
                "unit": get_unit_label(material),
                "receipt": decimal_scalar(db, receipt),
                "expense": decimal_scalar(db, spent),
                "balance": decimal_scalar(db, balance),
            }
        )
    return {"materials": result[InventoryItemType.MATERIAL], "equipment": result[InventoryItemType.EQUIPMENT]}


def inventory_page(inventory: dict, search: str | None, page: int, sort: str, direction: str) -> ReportPage:
    rows = inventory["materials"] + inventory["equipment"]
    if search:
        needle = search.lower()
        rows = [row for row in rows if needle in row["material"].name.lower() or (row["material"].category and needle in row["material"].category.lower())]
    sort_key = sort if sort in {"name", "receipt", "expense", "balance"} else "name"
    rows = sorted(rows, key=(lambda row: row["material"].name.lower()) if sort_key == "name" else (lambda row: row[sort_key]), reverse=direction != "asc")
    page = max(page, 1)
    total = len(rows)
    per_page = 15
    start = (page - 1) * per_page
    return ReportPage(rows[start : start + per_page], page, per_page, total, max(ceil(total / per_page), 1), sort_key, direction)


def provider_cards(db: Session, period: dict, provider_id: int | None) -> list[dict]:
    providers = select(Provider).where(Provider.is_active.is_(True)).order_by(Provider.name)
    if provider_id:
        providers = providers.where(Provider.id == provider_id)
    cards = []
    for provider in db.scalars(providers):
        finance = get_finance_stats(db, {"date_from": period["date_from"], "date_to": period["date_to"], "provider_id": provider.id})
        income = income_summary(db, period, provider.id)
        inventory = inventory_summary(db, period, provider.id)
        cards.append(
            {
                "provider": provider,
                "connections": db.scalar(select(func.count()).select_from(connection_query(period, provider.id).order_by(None).subquery())) or 0,
                "extra_works": db.scalar(select(func.count()).select_from(extra_work_query(period, provider.id).order_by(None).subquery())) or 0,
                "connection_income": income["connections"],
                "extra_work_income": income["extra_works"],
                "total_income": income["total"],
                "expenses": finance.expenses_total,
                "profit": finance.profit,
                "materials": inventory["materials"],
                "equipment": inventory["equipment"],
                "office_owes_me": finance.office_owes_me,
                "i_owe_office": finance.i_owe_office,
                "settlement_closed": finance.office_owes_me == 0 and finance.i_owe_office == 0,
            }
        )
    return cards


def filtered_connections(db: Session, period: dict, provider_id: int | None, search: str | None, page: int, sort: str, direction: str) -> ReportPage:
    query = connection_query(period, provider_id)
    if search:
        pattern = f"%{search}%"
        query = query.where(or_(Client.contract_number.ilike(pattern), Client.login.ilike(pattern), Client.address.ilike(pattern)))
    return paginate(db, order_query(query, {"date": Connection.connection_date, "provider": Client.provider_id, "amount": Connection.price, "type": Connection.connection_type}, sort, direction), page, 15, sort, direction)


def filtered_extra_works(db: Session, period: dict, provider_id: int | None, search: str | None, page: int, sort: str, direction: str) -> ReportPage:
    query = extra_work_query(period, provider_id)
    if search:
        query = query.where(ExtraWork.comment.ilike(f"%{search}%"))
    return paginate(db, order_query(query, {"date": ExtraWork.work_date, "provider": ExtraWork.provider_id, "amount": ExtraWork.amount, "type": ExtraWork.work_type_id}, sort, direction), page, 15, sort, direction)


def filtered_expenses(db: Session, period: dict, provider_id: int | None, search: str | None, page: int, sort: str, direction: str) -> ReportPage:
    query = expense_query(period, provider_id)
    if search:
        query = query.where(Expense.comment.ilike(f"%{search}%"))
    page_data = paginate(db, order_query(query, {"date": Expense.created_at, "provider": Expense.provider_id, "amount": Expense.amount, "category": Expense.category}, sort, direction), page, 15, sort, direction)
    return ReportPage([make_expense_row(item) for item in page_data.items], page_data.page, page_data.per_page, page_data.total, page_data.pages, page_data.sort, page_data.direction)


def filtered_finance(db: Session, period: dict, provider_id: int | None, search: str | None, page: int, sort: str, direction: str) -> ReportPage:
    query = select(FinanceTransaction).options(joinedload(FinanceTransaction.provider), joinedload(FinanceTransaction.user))
    query = apply_datetime_period(query, FinanceTransaction.created_at, period)
    if provider_id:
        query = query.where(FinanceTransaction.provider_id == provider_id)
    if search:
        query = query.where(FinanceTransaction.comment.ilike(f"%{search}%"))
    return paginate(db, order_query(query, {"date": FinanceTransaction.created_at, "provider": FinanceTransaction.provider_id, "amount": FinanceTransaction.amount, "type": FinanceTransaction.transaction_type}, sort, direction), page, 15, sort, direction)


def total_for(db: Session, query: Select, column) -> Decimal:
    subquery = query.with_only_columns(column).order_by(None).subquery()
    return decimal_scalar(db, select(func.coalesce(func.sum(subquery.c[0]), 0)))


def report_query(filters: dict, tab: str | None = None, page: int | None = None, sort: str | None = None, direction: str | None = None) -> str:
    params = {}
    for key in ("period", "date_from", "date_to", "provider_id", "search"):
        value = filters.get(key)
        if value:
            params[key] = value.isoformat() if hasattr(value, "isoformat") else value
    if tab:
        params["tab"] = tab
    if page and page > 1:
        params["page"] = page
    if sort:
        params["sort"] = sort
    if direction:
        params["direction"] = direction
    return urlencode(params)


def get_reports_data(db: Session, *, period_key: str, date_from: date | None, date_to: date | None, provider_id: int | None, search: str | None, active_tab: str, page: int, sort: str, direction: str) -> dict:
    period = resolve_period(period_key, date_from, date_to)
    active_tab = active_tab if active_tab in REPORT_TABS else "providers"
    direction = "asc" if direction == "asc" else "desc"
    clean_search = search.strip() if search else None
    filters = {"period": period["period"], "date_from": period["date_from"], "date_to": period["date_to"], "provider_id": provider_id, "search": clean_search}
    inventory = inventory_summary(db, period, provider_id)
    finance = get_finance_stats(db, {"date_from": period["date_from"], "date_to": period["date_to"], "provider_id": provider_id})
    income = income_summary(db, period, provider_id)
    selected_provider = db.get(Provider, provider_id) if provider_id else None
    connections = filtered_connections(db, period, provider_id, clean_search, page, sort, direction)
    extra_works = filtered_extra_works(db, period, provider_id, clean_search, page, sort, direction)
    expenses = filtered_expenses(db, period, provider_id, clean_search, page, sort, direction)
    return {
        "period": period,
        "period_labels": PERIOD_LABELS,
        "providers": list(db.scalars(select(Provider).where(Provider.is_active.is_(True)).order_by(Provider.name))),
        "selected_provider": selected_provider.name if selected_provider else "Все провайдеры",
        "filters": filters,
        "active_tab": active_tab,
        "provider_cards": provider_cards(db, period, provider_id),
        "connections": connections,
        "extra_works": extra_works,
        "expenses": expenses,
        "finance_page": filtered_finance(db, period, provider_id, clean_search, page, sort, direction),
        "inventory": inventory,
        "inventory_page": inventory_page(inventory, clean_search, page, sort, direction),
        "finance": finance,
        "income": income,
        "connection_total": total_for(db, connection_query(period, provider_id), Connection.price),
        "extra_work_total": total_for(db, extra_work_query(period, provider_id), ExtraWork.amount),
        "expense_total": total_for(db, expense_query(period, provider_id), Expense.amount),
        "expense_labels": EXPENSE_CATEGORY_LABELS,
        "paid_by_labels": PAID_BY_LABELS,
        "connection_type_labels": CONNECTION_TYPE_LABELS,
        "query": report_query,
    }
