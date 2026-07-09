
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from io import BytesIO
from math import ceil
from urllib.parse import urlencode
from xml.sax.saxutils import escape
from zipfile import ZIP_DEFLATED, ZipFile

from sqlalchemy import Select, func, or_, select
from sqlalchemy.orm import Session, joinedload

from app.models.clients import Client, Connection, ExtraWork, ExtraWorkType, Provider
from app.models.enums import ConnectionType, ExpenseCategory, FinanceTransactionType, InventoryItemType, PaidBy
from app.models.finance import Expense, FinanceTransaction
from app.models.inventory import InventoryTransaction, Material
from app.services.expenses import make_expense_row
from app.services.finance import get_finance_stats
from app.services.inventory import get_unit_label

PERIOD_LABELS = {
    "all": "\u0417\u0430 \u0432\u0441\u0451 \u0432\u0440\u0435\u043c\u044f",
    "today": "\u0421\u0435\u0433\u043e\u0434\u043d\u044f",
    "yesterday": "\u0412\u0447\u0435\u0440\u0430",
    "week": "\u041d\u0435\u0434\u0435\u043b\u044f",
    "month": "\u041c\u0435\u0441\u044f\u0446",
    "custom": "\u041f\u0440\u043e\u0438\u0437\u0432\u043e\u043b\u044c\u043d\u044b\u0439 \u043f\u0435\u0440\u0438\u043e\u0434",
}

CONNECTION_TYPE_LABELS = {
    ConnectionType.NEW: "\u041d\u043e\u0432\u043e\u0435",
    ConnectionType.RECONNECT: "\u041f\u043e\u0432\u0442\u043e\u0440\u043d\u043e\u0435",
    ConnectionType.ONU_REPLACE: "\u0417\u0430\u043c\u0435\u043d\u0430 ONU",
    ConnectionType.CABLE_REPLACE: "\u0417\u0430\u043c\u0435\u043d\u0430 \u043a\u0430\u0431\u0435\u043b\u044f",
    ConnectionType.WITHOUT_MATERIALS: "\u0411\u0435\u0437 \u043c\u0430\u0442\u0435\u0440\u0438\u0430\u043b\u043e\u0432",
    ConnectionType.CUSTOM: "\u041d\u0435\u0441\u0442\u0430\u043d\u0434\u0430\u0440\u0442\u043d\u043e\u0435",
}

EXPENSE_CATEGORY_LABELS = {
    ExpenseCategory.FUEL: "\u0411\u0435\u043d\u0437\u0438\u043d",
    ExpenseCategory.TOOLS: "\u0418\u043d\u0441\u0442\u0440\u0443\u043c\u0435\u043d\u0442",
    ExpenseCategory.TRANSPORT: "\u0422\u0440\u0430\u043d\u0441\u043f\u043e\u0440\u0442",
    ExpenseCategory.COMMUNICATION: "\u0421\u0432\u044f\u0437\u044c",
    ExpenseCategory.OTHER: "\u041f\u0440\u043e\u0447\u0435\u0435",
}

PAID_BY_LABELS = {PaidBy.INSTALLER: "\u041c\u043e\u043d\u0442\u0430\u0436\u043d\u0438\u043a", PaidBy.OFFICE: "\u041e\u0444\u0438\u0441"}
FINANCE_TYPE_LABELS = {
    FinanceTransactionType.CONNECTION: "\u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u0435",
    FinanceTransactionType.EXTRA_WORK: "\u0414\u043e\u043f\u0440\u0430\u0431\u043e\u0442\u0430",
    FinanceTransactionType.EXPENSE: "\u0420\u0430\u0441\u0445\u043e\u0434",
    FinanceTransactionType.PAYMENT_TO_OFFICE: "\u041f\u0435\u0440\u0435\u0434\u0430\u0447\u0430 \u0432 \u043e\u0444\u0438\u0441",
    FinanceTransactionType.PAYMENT_FROM_OFFICE: "\u0412\u044b\u043f\u043b\u0430\u0442\u0430 \u043e\u0444\u0438\u0441\u043e\u043c",
    FinanceTransactionType.ADJUSTMENT: "\u041a\u043e\u0440\u0440\u0435\u043a\u0442\u0438\u0440\u043e\u0432\u043a\u0430",
}
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


def paginate_rows(rows: list, page: int, sort: str, direction: str, per_page: int = 15) -> ReportPage:
    page = max(page, 1)
    total = len(rows)
    start = (page - 1) * per_page
    return ReportPage(rows[start : start + per_page], page, per_page, total, max(ceil(total / per_page), 1), sort, direction)


def order_query(query, sort_map: dict, sort: str, direction: str):
    column = sort_map.get(sort, sort_map["date"])
    return query.order_by(column.asc() if direction == "asc" else column.desc())


def connection_query(period: dict, provider_id: int | None):
    query = select(Connection).join(Connection.client).options(joinedload(Connection.client).joinedload(Client.provider))
    query = apply_date_period(query, Connection.connection_date, period)
    if provider_id:
        query = query.where(Client.provider_id == provider_id)
    return query


def apply_connection_search(query, search: str | None):
    if not search:
        return query
    pattern = f"%{search}%"
    return query.where(or_(Client.contract_number.ilike(pattern), Client.login.ilike(pattern), Client.address.ilike(pattern), Client.phone.ilike(pattern), Client.comment.ilike(pattern), Connection.comment.ilike(pattern)))


def extra_work_query(period: dict, provider_id: int | None):
    query = select(ExtraWork).join(ExtraWork.work_type).options(joinedload(ExtraWork.provider), joinedload(ExtraWork.work_type))
    query = apply_date_period(query, ExtraWork.work_date, period)
    if provider_id:
        query = query.where(ExtraWork.provider_id == provider_id)
    return query


def apply_extra_work_search(query, search: str | None):
    if not search:
        return query
    pattern = f"%{search}%"
    return query.where(or_(ExtraWork.comment.ilike(pattern), ExtraWorkType.name.ilike(pattern), ExtraWorkType.description.ilike(pattern)))


def expense_query(period: dict, provider_id: int | None):
    query = select(Expense).options(joinedload(Expense.provider))
    query = apply_datetime_period(query, Expense.created_at, period)
    if provider_id:
        query = query.where(Expense.provider_id == provider_id)
    return query


def apply_expense_search(query, search: str | None):
    if not search:
        return query
    return query.where(Expense.comment.ilike(f"%{search}%"))


def finance_query(period: dict, provider_id: int | None):
    query = select(FinanceTransaction).options(joinedload(FinanceTransaction.provider), joinedload(FinanceTransaction.user))
    query = apply_datetime_period(query, FinanceTransaction.created_at, period)
    if provider_id:
        query = query.where(FinanceTransaction.provider_id == provider_id)
    return query


def apply_finance_search(query, search: str | None):
    if not search:
        return query
    return query.where(FinanceTransaction.comment.ilike(f"%{search}%"))


def income_summary(db: Session, period: dict, provider_id: int | None) -> dict:
    connection_income = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(FinanceTransaction.transaction_type == FinanceTransactionType.CONNECTION, FinanceTransaction.amount > 0)
    extra_income = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(FinanceTransaction.transaction_type == FinanceTransactionType.EXTRA_WORK, FinanceTransaction.amount > 0)
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
        receipt = apply_datetime_period(select(func.coalesce(func.sum(InventoryTransaction.quantity), 0)).where(InventoryTransaction.material_id == material.id, InventoryTransaction.quantity > 0), InventoryTransaction.created_at, period)
        spent = apply_datetime_period(select(func.coalesce(func.sum(func.abs(InventoryTransaction.quantity)), 0)).where(InventoryTransaction.material_id == material.id, InventoryTransaction.quantity < 0), InventoryTransaction.created_at, period)
        if provider_id:
            balance = balance.where(InventoryTransaction.provider_id == provider_id)
            receipt = receipt.where(InventoryTransaction.provider_id == provider_id)
            spent = spent.where(InventoryTransaction.provider_id == provider_id)
        result[material.item_type].append({"material": material, "unit": get_unit_label(material), "receipt": decimal_scalar(db, receipt), "expense": decimal_scalar(db, spent), "balance": decimal_scalar(db, balance)})
    return {"materials": result[InventoryItemType.MATERIAL], "equipment": result[InventoryItemType.EQUIPMENT]}


def inventory_page(inventory: dict, search: str | None, page: int, sort: str, direction: str, per_page: int = 15) -> ReportPage:
    rows = inventory["materials"] + inventory["equipment"]
    if search:
        needle = search.lower()
        rows = [row for row in rows if needle in row["material"].name.lower() or (row["material"].category and needle in row["material"].category.lower())]
    sort_key = sort if sort in {"name", "receipt", "expense", "balance"} else "name"
    rows = sorted(rows, key=(lambda row: row["material"].name.lower()) if sort_key == "name" else (lambda row: row[sort_key]), reverse=direction != "asc")
    return paginate_rows(rows, page, sort_key, direction, per_page)


def provider_cards(db: Session, period: dict, provider_id: int | None, search: str | None) -> list[dict]:
    providers = select(Provider).where(Provider.is_active.is_(True)).order_by(Provider.name)
    if provider_id:
        providers = providers.where(Provider.id == provider_id)
    cards = []
    for provider in db.scalars(providers):
        finance = get_finance_stats(db, {"date_from": period["date_from"], "date_to": period["date_to"], "provider_id": provider.id})
        income = income_summary(db, period, provider.id)
        inventory = inventory_summary(db, period, provider.id)
        cards.append({
            "provider": provider,
            "connections": db.scalar(select(func.count()).select_from(apply_connection_search(connection_query(period, provider.id), search).order_by(None).subquery())) or 0,
            "extra_works": db.scalar(select(func.count()).select_from(apply_extra_work_search(extra_work_query(period, provider.id), search).order_by(None).subquery())) or 0,
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
        })
    return cards


def filtered_connections(db: Session, period: dict, provider_id: int | None, search: str | None, page: int, sort: str, direction: str, per_page: int = 15) -> ReportPage:
    query = apply_connection_search(connection_query(period, provider_id), search)
    return paginate(db, order_query(query, {"date": Connection.connection_date, "provider": Client.provider_id, "amount": Connection.price, "type": Connection.connection_type}, sort, direction), page, per_page, sort, direction)


def filtered_extra_works(db: Session, period: dict, provider_id: int | None, search: str | None, page: int, sort: str, direction: str, per_page: int = 15) -> ReportPage:
    query = apply_extra_work_search(extra_work_query(period, provider_id), search)
    return paginate(db, order_query(query, {"date": ExtraWork.work_date, "provider": ExtraWork.provider_id, "amount": ExtraWork.amount, "type": ExtraWork.work_type_id}, sort, direction), page, per_page, sort, direction)


def filtered_expenses(db: Session, period: dict, provider_id: int | None, search: str | None, page: int, sort: str, direction: str, per_page: int = 15) -> ReportPage:
    query = apply_expense_search(expense_query(period, provider_id), search)
    page_data = paginate(db, order_query(query, {"date": Expense.created_at, "provider": Expense.provider_id, "amount": Expense.amount, "category": Expense.category}, sort, direction), page, per_page, sort, direction)
    return ReportPage([make_expense_row(item) for item in page_data.items], page_data.page, page_data.per_page, page_data.total, page_data.pages, page_data.sort, page_data.direction)


def filtered_finance(db: Session, period: dict, provider_id: int | None, search: str | None, page: int, sort: str, direction: str, per_page: int = 15) -> ReportPage:
    query = apply_finance_search(finance_query(period, provider_id), search)
    return paginate(db, order_query(query, {"date": FinanceTransaction.created_at, "provider": FinanceTransaction.provider_id, "amount": FinanceTransaction.amount, "type": FinanceTransaction.transaction_type}, sort, direction), page, per_page, sort, direction)


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


def get_reports_data(db: Session, *, period_key: str, date_from: date | None, date_to: date | None, provider_id: int | None, search: str | None, active_tab: str, page: int, sort: str, direction: str, per_page: int = 15) -> dict:
    period = resolve_period(period_key, date_from, date_to)
    active_tab = active_tab if active_tab in REPORT_TABS else "providers"
    direction = "asc" if direction == "asc" else "desc"
    clean_search = search.strip() if search else None
    filters = {"period": period["period"], "date_from": period["date_from"], "date_to": period["date_to"], "provider_id": provider_id, "search": clean_search}
    inventory = inventory_summary(db, period, provider_id)
    finance = get_finance_stats(db, {"date_from": period["date_from"], "date_to": period["date_to"], "provider_id": provider_id})
    income = income_summary(db, period, provider_id)
    selected_provider = db.get(Provider, provider_id) if provider_id else None
    connections_query = apply_connection_search(connection_query(period, provider_id), clean_search)
    extra_query = apply_extra_work_search(extra_work_query(period, provider_id), clean_search)
    expense_q = apply_expense_search(expense_query(period, provider_id), clean_search)
    connections = filtered_connections(db, period, provider_id, clean_search, page, sort, direction, per_page)
    extra_works = filtered_extra_works(db, period, provider_id, clean_search, page, sort, direction, per_page)
    expenses = filtered_expenses(db, period, provider_id, clean_search, page, sort, direction, per_page)
    finance_page = filtered_finance(db, period, provider_id, clean_search, page, sort, direction, per_page)
    inv_page = inventory_page(inventory, clean_search, page, sort, direction, per_page)
    page_map = {"connections": connections, "extra_works": extra_works, "expenses": expenses, "finance": finance_page, "inventory": inv_page}
    page_data = page_map.get(active_tab)
    export_query = report_query(filters, active_tab, None, page_data.sort if page_data else None, page_data.direction if page_data else None)
    return {
        "period": period,
        "period_labels": PERIOD_LABELS,
        "providers": list(db.scalars(select(Provider).where(Provider.is_active.is_(True)).order_by(Provider.name))),
        "selected_provider": selected_provider.name if selected_provider else "\u0412\u0441\u0435 \u043f\u0440\u043e\u0432\u0430\u0439\u0434\u0435\u0440\u044b",
        "filters": filters,
        "active_tab": active_tab,
        "provider_cards": provider_cards(db, period, provider_id, clean_search),
        "connections": connections,
        "extra_works": extra_works,
        "expenses": expenses,
        "finance_page": finance_page,
        "inventory": inventory,
        "inventory_page": inv_page,
        "finance": finance,
        "income": income,
        "connection_total": total_for(db, connections_query, Connection.price),
        "extra_work_total": total_for(db, extra_query, ExtraWork.amount),
        "expense_total": total_for(db, expense_q, Expense.amount),
        "expense_labels": EXPENSE_CATEGORY_LABELS,
        "paid_by_labels": PAID_BY_LABELS,
        "finance_type_labels": FINANCE_TYPE_LABELS,
        "connection_type_labels": CONNECTION_TYPE_LABELS,
        "query": report_query,
        "export_query": export_query,
    }


def rows_for_export(db: Session, data: dict, tab: str) -> tuple[str, list[str], list[list[str]]]:
    if tab == "providers":
        rows = []
        for item in data["provider_cards"]:
            rows.append([item["provider"].name, item["connections"], item["extra_works"], item["connection_income"], item["extra_work_income"], item["total_income"], item["expenses"], item["profit"], item["office_owes_me"], item["i_owe_office"]])
        return "providers", ["\u041f\u0440\u043e\u0432\u0430\u0439\u0434\u0435\u0440", "\u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u044f", "\u0414\u043e\u043f\u0440\u0430\u0431\u043e\u0442\u044b", "\u0414\u043e\u0445\u043e\u0434 \u043f\u043e\u0434\u043a\u043b.", "\u0414\u043e\u0445\u043e\u0434 \u0434\u043e\u043f\u0440.", "\u041e\u0431\u0449\u0438\u0439 \u0434\u043e\u0445\u043e\u0434", "\u0420\u0430\u0441\u0445\u043e\u0434\u044b", "\u041f\u0440\u0438\u0431\u044b\u043b\u044c", "\u041e\u0444\u0438\u0441 \u0434\u043e\u043b\u0436\u0435\u043d", "\u042f \u0434\u043e\u043b\u0436\u0435\u043d"], rows
    if tab == "connections":
        rows = [[i.connection_date, i.client.provider.name, i.client.login or i.client.contract_number, i.client.address, CONNECTION_TYPE_LABELS.get(i.connection_type, i.connection_type.value), i.price, i.office_amount, i.installer_amount] for i in data["connections"].items]
        return "connections", ["\u0414\u0430\u0442\u0430", "\u041f\u0440\u043e\u0432\u0430\u0439\u0434\u0435\u0440", "\u041b\u043e\u0433\u0438\u043d / \u0434\u043e\u0433\u043e\u0432\u043e\u0440", "\u0410\u0434\u0440\u0435\u0441", "\u0422\u0438\u043f", "\u0421\u0442\u043e\u0438\u043c\u043e\u0441\u0442\u044c", "\u041e\u0444\u0438\u0441", "\u041c\u043e\u043d\u0442\u0430\u0436\u043d\u0438\u043a"], rows
    if tab == "extra_works":
        rows = [[i.work_date, i.provider.name, i.work_type.name, i.amount, i.comment or ""] for i in data["extra_works"].items]
        return "extra_works", ["\u0414\u0430\u0442\u0430", "\u041f\u0440\u043e\u0432\u0430\u0439\u0434\u0435\u0440", "\u0412\u0438\u0434 \u0440\u0430\u0431\u043e\u0442\u044b", "\u0421\u0442\u043e\u0438\u043c\u043e\u0441\u0442\u044c", "\u041a\u043e\u043c\u043c\u0435\u043d\u0442\u0430\u0440\u0438\u0439"], rows
    if tab == "expenses":
        rows = [[r.expense.created_at.date(), r.expense.provider.name, r.category_label, r.description, r.expense.amount, PAID_BY_LABELS.get(r.expense.paid_by, r.expense.paid_by.value)] for r in data["expenses"].items]
        return "expenses", ["\u0414\u0430\u0442\u0430", "\u041f\u0440\u043e\u0432\u0430\u0439\u0434\u0435\u0440", "\u041a\u0430\u0442\u0435\u0433\u043e\u0440\u0438\u044f", "\u041e\u043f\u0438\u0441\u0430\u043d\u0438\u0435", "\u0421\u0443\u043c\u043c\u0430", "\u041a\u0442\u043e \u043e\u043f\u043b\u0430\u0442\u0438\u043b"], rows
    if tab == "inventory":
        rows = [[r["material"].name, r["material"].item_type.value, r["receipt"], r["expense"], r["balance"], r["unit"]] for r in data["inventory_page"].items]
        return "inventory", ["\u041d\u0430\u0437\u0432\u0430\u043d\u0438\u0435", "\u0422\u0438\u043f", "\u041f\u0440\u0438\u0445\u043e\u0434", "\u0420\u0430\u0441\u0445\u043e\u0434", "\u041e\u0441\u0442\u0430\u0442\u043e\u043a", "\u0415\u0434. \u0438\u0437\u043c."], rows
    rows = [[i.created_at, FINANCE_TYPE_LABELS.get(i.transaction_type, i.transaction_type.value), i.provider.name if i.provider else "", i.amount, i.comment or "", i.user.full_name if i.user else ""] for i in data["finance_page"].items]
    return "finance", ["\u0414\u0430\u0442\u0430", "\u0422\u0438\u043f", "\u041f\u0440\u043e\u0432\u0430\u0439\u0434\u0435\u0440", "\u0421\u0443\u043c\u043c\u0430", "\u041a\u043e\u043c\u043c\u0435\u043d\u0442\u0430\u0440\u0438\u0439", "\u041f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044c"], rows


def cell_value(value) -> str:
    if isinstance(value, Decimal):
        return f"{value:.2f}"
    if isinstance(value, datetime):
        return value.strftime("%d.%m.%Y %H:%M")
    if isinstance(value, date):
        return value.strftime("%d.%m.%Y")
    return str(value)


def build_xlsx(headers: list[str], rows: list[list]) -> bytes:
    def cell(ref: str, value) -> str:
        return f'<c r="{ref}" t="inlineStr"><is><t>{escape(cell_value(value))}</t></is></c>'
    sheet_rows = []
    all_rows = [headers] + rows
    for row_index, row in enumerate(all_rows, 1):
        cells = []
        for col_index, value in enumerate(row, 1):
            col = ""
            n = col_index
            while n:
                n, rem = divmod(n - 1, 26)
                col = chr(65 + rem) + col
            cells.append(cell(f"{col}{row_index}", value))
        sheet_rows.append(f'<row r="{row_index}">{"".join(cells)}</row>')
    sheet = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>' + ''.join(sheet_rows) + '</sheetData></worksheet>'
    output = BytesIO()
    with ZipFile(output, "w", ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>')
        zf.writestr("_rels/.rels", '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        zf.writestr("xl/workbook.xml", '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Report" sheetId="1" r:id="rId1"/></sheets></workbook>')
        zf.writestr("xl/_rels/workbook.xml.rels", '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>')
        zf.writestr("xl/worksheets/sheet1.xml", sheet)
    return output.getvalue()


def build_pdf(title: str, headers: list[str], rows: list[list]) -> bytes:
    lines = [title, ""] + [" | ".join(headers)] + [" | ".join(cell_value(value) for value in row) for row in rows]
    text_commands = []
    y = 800
    for line in lines[:42]:
        safe = cell_value(line).replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
        text_commands.append(f"BT /F1 9 Tf 40 {y} Td ({safe}) Tj ET")
        y -= 18
    stream = "\n".join(text_commands).encode("cp1251", errors="replace")
    objects = [
        b"1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n",
        b"2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n",
        b"3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj\n",
        b"4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >> endobj\n",
        b"5 0 obj << /Length " + str(len(stream)).encode() + b" >> stream\n" + stream + b"\nendstream endobj\n",
    ]
    output = BytesIO()
    output.write(b"%PDF-1.4\n")
    offsets = [0]
    for obj in objects:
        offsets.append(output.tell())
        output.write(obj)
    xref = output.tell()
    output.write(f"xref\n0 {len(objects)+1}\n0000000000 65535 f \n".encode())
    for offset in offsets[1:]:
        output.write(f"{offset:010d} 00000 n \n".encode())
    output.write(f"trailer << /Size {len(objects)+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF".encode())
    return output.getvalue()
