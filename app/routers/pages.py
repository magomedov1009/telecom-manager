from datetime import UTC, date, datetime, time, timedelta
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Depends, Form, Query, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import SESSION_COOKIE_NAME, create_session_token, verify_password
from app.db.session import get_db
from app.dependencies.auth import can_open_finance, can_open_reports, get_current_user_optional, require_admin_user
from app.models.clients import Client, Connection, ExtraWork, Provider
from app.models.enums import ConnectionType, ExpenseCategory, FinanceTransactionType, InventoryItemType, InventoryTransactionType, PaidBy
from app.models.finance import Expense, FinanceTransaction
from app.models.inventory import InventoryTransaction, Material
from app.models.users import User
from app.services.finance import get_finance_stats
from app.services.inventory import format_quantity

router = APIRouter()
templates = Jinja2Templates(directory="app/templates")
templates.env.globals["format_quantity"] = format_quantity

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]


NAV_ITEMS = [
    {"label": "Dashboard", "endpoint": "/dashboard", "icon": "bi-speedometer2", "roles": ["admin", "manager", "installer"]},
    {"label": "Подключения", "endpoint": "/connections", "icon": "bi-router"},
    {"label": "Клиенты", "endpoint": "/clients", "icon": "bi-people"},
    {"label": "Склад", "endpoint": "/materials", "icon": "bi-box-seam"},
    {"label": "Финансы", "endpoint": "/finance", "icon": "bi-cash-coin"},
    {"label": "Допработы", "endpoint": "/additional-works", "icon": "bi-tools"},
    {"label": "Отчеты", "endpoint": "/reports", "icon": "bi-bar-chart"},
    {"label": "Настройки", "endpoint": "/settings", "icon": "bi-gear"},
]


def render(request: Request, template_name: str, context: dict) -> HTMLResponse:
    base_context = {
        "app_name": settings.app_name,
        "nav_items": NAV_ITEMS,
        "current_path": request.url.path,
    }
    base_context.update(context)
    return templates.TemplateResponse(request=request, name=template_name, context=base_context)


def parse_query_date(value: str | None) -> date | None:
    if not value:
        return None
    return date.fromisoformat(value)


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


@router.get("/", response_class=HTMLResponse)
def home(current_user: CurrentUser) -> RedirectResponse:
    if current_user is None:
        return redirect_to_login()
    return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)


@router.get("/login", response_class=HTMLResponse)
def login_page(request: Request, current_user: CurrentUser) -> Response:
    if current_user is not None:
        return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)
    return render(request, "auth/login.html", {"error": None})


@router.post("/login")
def login(
    request: Request,
    db: DbSession,
    username: Annotated[str, Form()],
    password: Annotated[str, Form()],
) -> Response:
    user = db.scalar(select(User).where(User.username == username, User.is_active.is_(True)))
    if user is None or not verify_password(password, user.hashed_password):
        return render(
            request,
            "auth/login.html",
            {"error": "Неверный логин или пароль", "username": username},
        )

    user.last_login_at = datetime.now(UTC)
    db.commit()
    response = RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)
    response.set_cookie(
        key=SESSION_COOKIE_NAME,
        value=create_session_token(user.id),
        httponly=True,
        samesite="lax",
        secure=False,
        max_age=60 * 60 * 12,
    )
    return response


@router.post("/logout")
def logout() -> RedirectResponse:
    response = RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)
    response.delete_cookie(SESSION_COOKIE_NAME)
    return response



PERIOD_LABELS = {
    "all": "За всё время",
    "today": "\u0421\u0435\u0433\u043e\u0434\u043d\u044f",
    "yesterday": "\u0412\u0447\u0435\u0440\u0430",
    "week": "\u042d\u0442\u0430 \u043d\u0435\u0434\u0435\u043b\u044f",
    "month": "\u042d\u0442\u043e\u0442 \u043c\u0435\u0441\u044f\u0446",
    "custom": "\u041f\u0440\u043e\u0438\u0437\u0432\u043e\u043b\u044c\u043d\u044b\u0439 \u043f\u0435\u0440\u0438\u043e\u0434",
}

EXPENSE_CATEGORY_LABELS = {
    ExpenseCategory.FUEL: "\u0411\u0435\u043d\u0437\u0438\u043d",
    ExpenseCategory.TOOLS: "\u0418\u043d\u0441\u0442\u0440\u0443\u043c\u0435\u043d\u0442",
    ExpenseCategory.TRANSPORT: "\u0422\u0440\u0430\u043d\u0441\u043f\u043e\u0440\u0442",
    ExpenseCategory.COMMUNICATION: "\u0421\u0432\u044f\u0437\u044c",
    ExpenseCategory.OTHER: "\u041f\u0440\u043e\u0447\u0435\u0435",
}

FINANCE_EVENT_LABELS = {
    FinanceTransactionType.CONNECTION: "\u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u0435",
    FinanceTransactionType.EXTRA_WORK: "\u0414\u043e\u043f\u0440\u0430\u0431\u043e\u0442\u0430",
    FinanceTransactionType.EXPENSE: "\u0420\u0430\u0441\u0445\u043e\u0434",
    FinanceTransactionType.PAYMENT_TO_OFFICE: "\u041f\u0435\u0440\u0435\u0434\u0430\u0447\u0430 \u0434\u0435\u043d\u0435\u0433 \u043e\u0444\u0438\u0441\u0443",
    FinanceTransactionType.PAYMENT_FROM_OFFICE: "\u0412\u044b\u043f\u043b\u0430\u0442\u0430 \u043e\u0444\u0438\u0441\u043e\u043c",
    FinanceTransactionType.ADJUSTMENT: "\u041a\u043e\u0440\u0440\u0435\u043a\u0442\u0438\u0440\u043e\u0432\u043a\u0430",
}

INVENTORY_EVENT_LABELS = {
    InventoryTransactionType.RECEIPT: "\u041f\u0440\u0438\u0445\u043e\u0434 \u043c\u0430\u0442\u0435\u0440\u0438\u0430\u043b\u043e\u0432",
    InventoryTransactionType.CONNECTION: "\u0421\u043f\u0438\u0441\u0430\u043d\u0438\u0435 \u043d\u0430 \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u0435",
    InventoryTransactionType.TRANSFER_IN: "\u041f\u0435\u0440\u0435\u043c\u0435\u0449\u0435\u043d\u0438\u0435: \u043f\u0440\u0438\u0445\u043e\u0434",
    InventoryTransactionType.TRANSFER_OUT: "\u041f\u0435\u0440\u0435\u043c\u0435\u0449\u0435\u043d\u0438\u0435: \u0440\u0430\u0441\u0445\u043e\u0434",
    InventoryTransactionType.RETURN: "\u0412\u043e\u0437\u0432\u0440\u0430\u0442",
    InventoryTransactionType.ISSUE_TO_THIRD_PARTY: "\u0412\u044b\u0434\u0430\u0447\u0430",
    InventoryTransactionType.WRITE_OFF: "\u0421\u043f\u0438\u0441\u0430\u043d\u0438\u0435",
    InventoryTransactionType.ADJUSTMENT: "\u041a\u043e\u0440\u0440\u0435\u043a\u0442\u0438\u0440\u043e\u0432\u043a\u0430",
}


def resolve_dashboard_period(period: str, date_from: date | None, date_to: date | None) -> dict:
    today = date.today()
    if period == "all":
        start_date = None
        end_date = None
    elif period == "yesterday":
        start_date = end_date = today - timedelta(days=1)
    elif period == "week":
        start_date = today - timedelta(days=today.weekday())
        end_date = today
    elif period == "month":
        start_date = today.replace(day=1)
        end_date = today
    elif period == "custom":
        start_date = date_from or today
        end_date = date_to or start_date
    else:
        period = "today"
        start_date = end_date = today
    if start_date is not None and end_date is not None and end_date < start_date:
        start_date, end_date = end_date, start_date
    return {
        "period": period,
        "label": PERIOD_LABELS[period],
        "date_from": start_date,
        "date_to": end_date,
        "start": datetime.combine(start_date, time.min) if start_date is not None else None,
        "end": datetime.combine(end_date, time.max) if end_date is not None else None,
    }


def period_filter(query, column, period_data: dict):
    if period_data.get("start") is not None:
        query = query.where(column >= period_data["start"])
    if period_data.get("end") is not None:
        query = query.where(column <= period_data["end"])
    return query


def scalar_decimal(db: Session, query) -> Decimal:
    return Decimal(db.scalar(query) or 0)


def build_dashboard_data(db: Session, period_data: dict, provider_id: int | None = None) -> dict:
    connection_period = period_filter(
        select(Connection),
        Connection.connection_date,
        {
            **period_data,
            "start": period_data["date_from"],
            "end": period_data["date_to"],
        },
    )
    if provider_id:
        connection_period = connection_period.join(Connection.client).where(Client.provider_id == provider_id)
    connection_ids_subquery = connection_period.with_only_columns(Connection.id).subquery()

    connections = {
        "total": db.scalar(select(func.count()).select_from(connection_ids_subquery)) or 0,
        "new_clients": db.scalar(select(func.count()).select_from((period_filter(select(Client), Client.created_at, period_data).where(Client.provider_id == provider_id) if provider_id else period_filter(select(Client), Client.created_at, period_data)).subquery())) or 0,
        "reconnects": db.scalar(select(func.count(Connection.id)).where(Connection.id.in_(select(connection_ids_subquery.c.id)), Connection.connection_type == ConnectionType.RECONNECT)) or 0,
        "onu_replacements": db.scalar(select(func.count(Connection.id)).where(Connection.id.in_(select(connection_ids_subquery.c.id)), Connection.connection_type == ConnectionType.ONU_REPLACE)) or 0,
    }
    connections["equipment_replacements"] = connections["onu_replacements"]

    finance_filters = {"date_from": period_data["date_from"], "date_to": period_data["date_to"], "provider_id": provider_id}
    finance_stats = get_finance_stats(db, finance_filters)
    customer_received_query = period_filter(
        select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(
            FinanceTransaction.transaction_type == FinanceTransactionType.CONNECTION,
            FinanceTransaction.amount > 0,
        ),
        FinanceTransaction.created_at,
        period_data,
    )
    if provider_id:
        customer_received_query = customer_received_query.where(FinanceTransaction.provider_id == provider_id)
    customer_received = scalar_decimal(db, customer_received_query)

    def stock_summary(item_type: InventoryItemType) -> list[dict]:
        rows = []
        items = list(db.scalars(select(Material).where(Material.active.is_(True), Material.item_type == item_type).order_by(Material.name)))
        for item in items:
            balance_query = select(func.coalesce(func.sum(InventoryTransaction.quantity), 0)).where(InventoryTransaction.material_id == item.id)
            if provider_id:
                balance_query = balance_query.where(InventoryTransaction.provider_id == provider_id)
            balance = scalar_decimal(db, balance_query)
            spent_query = period_filter(
                    select(func.coalesce(func.sum(func.abs(InventoryTransaction.quantity)), 0)).where(InventoryTransaction.material_id == item.id, InventoryTransaction.quantity < 0),
                    InventoryTransaction.created_at,
                    period_data,
                )
            if provider_id:
                spent_query = spent_query.where(InventoryTransaction.provider_id == provider_id)
            spent = scalar_decimal(db, spent_query)
            rows.append({"label": item.name, "balance": balance, "spent": spent, "unit": item.unit_name or item.unit.value})
        return rows

    materials = stock_summary(InventoryItemType.MATERIAL)
    equipment = stock_summary(InventoryItemType.EQUIPMENT)

    expenses_total = scalar_decimal(
        db,
        (period_filter(select(func.coalesce(func.sum(Expense.amount), 0)), Expense.created_at, period_data).where(Expense.provider_id == provider_id) if provider_id else period_filter(select(func.coalesce(func.sum(Expense.amount), 0)), Expense.created_at, period_data)),
    )
    installer_expenses = scalar_decimal(
        db,
        (period_filter(select(func.coalesce(func.sum(Expense.amount), 0)).where(Expense.paid_by == PaidBy.INSTALLER), Expense.created_at, period_data).where(Expense.provider_id == provider_id) if provider_id else period_filter(select(func.coalesce(func.sum(Expense.amount), 0)).where(Expense.paid_by == PaidBy.INSTALLER), Expense.created_at, period_data)),
    )
    office_expenses = scalar_decimal(
        db,
        (period_filter(select(func.coalesce(func.sum(Expense.amount), 0)).where(Expense.paid_by == PaidBy.OFFICE), Expense.created_at, period_data).where(Expense.provider_id == provider_id) if provider_id else period_filter(select(func.coalesce(func.sum(Expense.amount), 0)).where(Expense.paid_by == PaidBy.OFFICE), Expense.created_at, period_data)),
    )
    top_expense_query = period_filter(
        select(Expense.category, func.coalesce(func.sum(Expense.amount), 0).label("total")).group_by(Expense.category).order_by(func.coalesce(func.sum(Expense.amount), 0).desc()),
        Expense.created_at,
        period_data,
    )
    if provider_id:
        top_expense_query = top_expense_query.where(Expense.provider_id == provider_id)
    top_expense_row = db.execute(top_expense_query.limit(1)).first()
    top_expense = {"label": "—", "amount": Decimal("0")}
    if top_expense_row is not None:
        top_expense = {"label": EXPENSE_CATEGORY_LABELS.get(top_expense_row[0], top_expense_row[0].value), "amount": Decimal(top_expense_row[1] or 0)}
    expense_count_query = period_filter(select(Expense), Expense.created_at, period_data)
    if provider_id:
        expense_count_query = expense_count_query.where(Expense.provider_id == provider_id)
    expense_operations = db.scalar(select(func.count()).select_from(expense_count_query.subquery())) or 0

    extra_query = period_filter(select(ExtraWork), ExtraWork.work_date, {**period_data, "start": period_data["date_from"], "end": period_data["date_to"]})
    if provider_id:
        extra_query = extra_query.where(ExtraWork.provider_id == provider_id)
    extra_subquery = extra_query.subquery()
    extra_total = scalar_decimal(db, select(func.coalesce(func.sum(extra_subquery.c.amount), 0)))
    extra_works = {
        "count": db.scalar(select(func.count()).select_from(extra_subquery)) or 0,
        "total": extra_total,
        "office_owes": extra_total,
    }

    finance_events = [
        {
            "date": item.created_at,
            "type": FINANCE_EVENT_LABELS.get(item.transaction_type, item.transaction_type.value),
            "title": item.comment or FINANCE_EVENT_LABELS.get(item.transaction_type, item.transaction_type.value),
            "amount": item.amount,
            "icon": "bi-cash-coin",
            "tone": "primary",
        }
        for item in db.scalars((select(FinanceTransaction).where(FinanceTransaction.provider_id == provider_id) if provider_id else select(FinanceTransaction)).order_by(FinanceTransaction.created_at.desc(), FinanceTransaction.id.desc()).limit(10))
    ]
    inventory_events = [
        {
            "date": item.created_at,
            "type": INVENTORY_EVENT_LABELS.get(item.operation_type, item.operation_type.value),
            "title": item.material.name if item.material else "Склад",
            "amount": format_quantity(item.quantity),
            "icon": "bi-box-seam",
            "tone": "secondary",
        }
        for item in db.scalars((select(InventoryTransaction).where(InventoryTransaction.provider_id == provider_id) if provider_id else select(InventoryTransaction)).order_by(InventoryTransaction.created_at.desc(), InventoryTransaction.id.desc()).limit(10))
    ]
    events = sorted(finance_events + inventory_events, key=lambda item: item["date"], reverse=True)[:10]

    return {
        "connections": connections,
        "finance": finance_stats,
        "customer_received": customer_received,
        "materials": materials,
        "equipment": equipment,
        "extra_works": extra_works,
        "expenses": {
            "total": expenses_total,
            "installer": installer_expenses,
            "office": office_expenses,
            "top": top_expense,
            "operations": expense_operations,
        },
        "kpi": {
            "average_check": customer_received / connections["total"] if connections["total"] else None,
            "average_profit": finance_stats.profit / connections["total"] if connections["total"] else None,
            "average_expense": expenses_total / connections["total"] if connections["total"] else None,
            "average_material_spent": sum((item["spent"] for item in materials), Decimal("0")) / connections["total"] if connections["total"] else None,
        },
        "attention": build_dashboard_attention(finance_stats, materials, equipment),
        "events": events,
    }


def build_dashboard_attention(finance_stats, materials: list[dict], equipment: list[dict]) -> list[dict]:
    warnings = []
    for item in materials:
        if item["balance"] <= 10:
            warnings.append({"label": f"Заканчивается материал: {item['label']}", "level": "warning", "icon": "bi-exclamation-triangle"})
    for item in equipment:
        if item["balance"] <= 2:
            warnings.append({"label": f"Заканчивается оборудование: {item['label']}", "level": "warning", "icon": "bi-hdd-network"})
    if finance_stats.office_owes_me >= Decimal("10000"):
        warnings.append({"label": "Большой долг офиса", "level": "warning", "icon": "bi-building-exclamation"})
    if finance_stats.i_owe_office >= Decimal("10000"):
        warnings.append({"label": "Большой долг монтажника", "level": "warning", "icon": "bi-person-exclamation"})
    if finance_stats.profit < 0:
        warnings.append({"label": "Отрицательная прибыль", "level": "danger", "icon": "bi-graph-down-arrow"})
    return warnings


@router.get("/dashboard", response_class=HTMLResponse)
def dashboard(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    period: Annotated[str, Query()] = "all",
    date_from: Annotated[str | None, Query()] = None,
    date_to: Annotated[str | None, Query()] = None,
    provider_id: Annotated[str | None, Query()] = None,
) -> Response:
    if current_user is None:
        return redirect_to_login()

    period_data = resolve_dashboard_period(period, parse_query_date(date_from), parse_query_date(date_to))
    selected_provider_id = int(provider_id) if provider_id else None
    providers = list(db.scalars(select(Provider).where(Provider.is_active.is_(True)).order_by(Provider.name)))
    dashboard_data = build_dashboard_data(db, period_data, selected_provider_id)
    return render(
        request,
        "pages/dashboard.html",
        {"user": current_user, "period": period_data, "dashboard": dashboard_data, "period_labels": PERIOD_LABELS, "providers": providers, "selected_provider_id": selected_provider_id},
    )


@router.get("/{section}", response_class=HTMLResponse)
def section_page(
    request: Request,
    section: str,
    current_user: CurrentUser,
) -> Response:
    if current_user is None:
        return redirect_to_login()

    section_titles = {
        "connections": "Подключения",
        "clients": "Клиенты",
        "materials": "Склад",
        "finance": "Финансы",
        "expenses": "Расходы",
        "additional-works": "Допработы",
        "reports": "Отчеты",
        "settings": "Настройки",
    }
    if section == "settings" and not require_admin_user(current_user):
        return render(request, "errors/404.html", {"user": current_user, "missing_path": request.url.path})
    if section == "reports" and not can_open_reports(current_user):
        return render(request, "errors/404.html", {"user": current_user, "missing_path": request.url.path})
    if section == "finance" and not can_open_finance(current_user):
        return render(request, "errors/404.html", {"user": current_user, "missing_path": request.url.path})
    title = section_titles.get(section)
    if title is None:
        return render(request, "errors/404.html", {"user": current_user, "missing_path": request.url.path})
    return render(request, "pages/section.html", {"user": current_user, "title": title})
