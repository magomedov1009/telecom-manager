from datetime import date, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, Form, Query, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db
from app.dependencies.auth import can_open_finance, get_current_user_optional
from app.models.users import User
from app.routers.pages import NAV_ITEMS
from app.services.expenses import ExpenseError, create_expense, get_expenses_page_data, normalize_filters as normalize_expense_filters
from app.services.finance import (
    FinanceError,
    create_manual_transaction,
    get_finance_page_data,
    normalize_filters,
    finance_client_label,
    money_direction,
    source_label,
)

router = APIRouter(prefix="/finance", tags=["finance"])
templates = Jinja2Templates(directory="app/templates")
templates.env.globals["finance_source_label"] = source_label
templates.env.globals["finance_client_label"] = finance_client_label
templates.env.globals["money_direction"] = money_direction

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]

PERIOD_LABELS = {
    "all": "За всё время",
    "today": "Сегодня",
    "yesterday": "Вчера",
    "week": "Неделя",
    "month": "Месяц",
    "custom": "Произвольный период",
}


def resolve_period(period: str, date_from: date | None, date_to: date | None) -> tuple[str, date | None, date | None]:
    today = date.today()
    if period == "all":
        return period, None, None
    if period == "yesterday":
        day = today - timedelta(days=1)
        return period, day, day
    if period == "week":
        return period, today - timedelta(days=today.weekday()), today
    if period == "month":
        return period, today.replace(day=1), today
    if period == "custom":
        start = date_from or today
        end = date_to or start
        if end < start:
            start, end = end, start
        return period, start, end
    return "today", today, today


def parse_query_int(value: str | None) -> int | None:
    if not value:
        return None
    return int(value)


def parse_query_date(value: str | None) -> date | None:
    if not value:
        return None
    return date.fromisoformat(value)


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


def render_finance(request: Request, template_name: str, current_user: User, data) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request,
        name=template_name,
        context={
            "app_name": settings.app_name,
            "nav_items": NAV_ITEMS,
            "current_path": "/finance",
            "user": current_user,
            "data": data,
            "period_labels": PERIOD_LABELS,
        },
    )


@router.get("", response_class=HTMLResponse)
def finance_page(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    period: Annotated[str, Query()] = "all",
    date_from: Annotated[str | None, Query()] = None,
    date_to: Annotated[str | None, Query()] = None,
    transaction_type: Annotated[str | None, Query()] = None,
    user_id: Annotated[str | None, Query()] = None,
    provider_id: Annotated[str | None, Query()] = None,
    search: Annotated[str | None, Query()] = None,
    page: Annotated[int, Query(ge=1)] = 1,
) -> Response:
    if current_user is None:
        return redirect_to_login()
    if not can_open_finance(current_user):
        return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)
    active_period, period_from, period_to = resolve_period(period, parse_query_date(date_from), parse_query_date(date_to))
    filters = normalize_filters(period_from, period_to, transaction_type, parse_query_int(user_id), search, parse_query_int(provider_id))
    data = get_finance_page_data(db, filters=filters, page=page, current_user=current_user)
    expense_filters = normalize_expense_filters(search, None, period_from, period_to)
    object.__setattr__(data, "expenses_data", get_expenses_page_data(db, filters=expense_filters, page=page, current_user=current_user))
    data.filters["period"] = active_period
    template = "finance/_module.html" if request.headers.get("HX-Request") else "finance/index.html"
    return render_finance(request, template, current_user, data)


@router.post("/operations", response_class=HTMLResponse)
def create_finance_operation(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    transaction_type: Annotated[str, Form()],
    amount: Annotated[str, Form()],
    comment: Annotated[str | None, Form()] = None,
) -> Response:
    if current_user is None:
        return redirect_to_login()
    if not can_open_finance(current_user):
        return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)

    error = None
    success = None
    try:
        create_manual_transaction(
            db,
            user=current_user,
            transaction_type=transaction_type,
            amount=amount,
            comment=comment,
        )
        success = "Финансовая операция создана"
    except FinanceError as exc:
        db.rollback()
        error = str(exc)

    if not request.headers.get("HX-Request"):
        return RedirectResponse(url="/finance", status_code=status.HTTP_303_SEE_OTHER)

    filters = normalize_filters(None, None, None, None, None)
    data = get_finance_page_data(db, filters=filters, page=1, error=error, success=success, current_user=current_user)
    expense_filters = normalize_expense_filters(None, None, None, None)
    object.__setattr__(data, "expenses_data", get_expenses_page_data(db, filters=expense_filters, page=1, current_user=current_user))
    data.filters["period"] = "all"
    return render_finance(request, "finance/_module.html", current_user, data)


@router.post("/expenses", response_class=HTMLResponse)
def create_finance_expense(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    expense_date: Annotated[date, Form()],
    category: Annotated[str, Form()],
    description: Annotated[str, Form()],
    amount: Annotated[str, Form()],
    paid_by: Annotated[str, Form()],
    provider_id: Annotated[int, Form()],
    comment: Annotated[str | None, Form()] = None,
) -> Response:
    if current_user is None:
        return redirect_to_login()
    if not can_open_finance(current_user):
        return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)

    error = None
    success = None
    try:
        create_expense(
            db,
            expense_date=expense_date,
            category=category,
            description=description,
            amount=amount,
            paid_by_user_id=current_user.id,
            paid_by=paid_by,
            comment=comment,
            provider_id=provider_id,
        )
        success = "Расход добавлен"
    except ExpenseError as exc:
        db.rollback()
        error = str(exc)

    filters = normalize_filters(None, None, None, None, None)
    data = get_finance_page_data(db, filters=filters, page=1, error=error, success=success, current_user=current_user)
    expense_filters = normalize_expense_filters(None, None, None, None)
    object.__setattr__(data, "expenses_data", get_expenses_page_data(db, filters=expense_filters, page=1, current_user=current_user))
    data.filters["period"] = "all"
    if not request.headers.get("HX-Request"):
        return RedirectResponse(url="/finance", status_code=status.HTTP_303_SEE_OTHER)
    return render_finance(request, "finance/_module.html", current_user, data)
