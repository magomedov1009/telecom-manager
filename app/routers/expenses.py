from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Form, Query, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db
from app.dependencies.auth import get_current_user_optional
from app.models.users import User
from app.routers.pages import NAV_ITEMS
from app.services.expenses import ExpenseError, create_expense, get_expenses_page_data, normalize_filters

router = APIRouter(prefix="/expenses", tags=["expenses"])
templates = Jinja2Templates(directory="app/templates")

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]


def parse_query_date(value: str | None) -> date | None:
    if not value:
        return None
    return date.fromisoformat(value)


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


def render_expenses(request: Request, current_user: User, data) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request,
        name="expenses/index.html",
        context={
            "app_name": settings.app_name,
            "nav_items": NAV_ITEMS,
            "current_path": "/expenses",
            "user": current_user,
            "data": data,
        },
    )


@router.get("", response_class=HTMLResponse)
def expenses_page(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    search: Annotated[str | None, Query()] = None,
    category: Annotated[str | None, Query()] = None,
    date_from: Annotated[str | None, Query()] = None,
    date_to: Annotated[str | None, Query()] = None,
    page: Annotated[int, Query(ge=1)] = 1,
) -> Response:
    if current_user is None:
        return redirect_to_login()
    filters = normalize_filters(search, category, parse_query_date(date_from), parse_query_date(date_to))
    data = get_expenses_page_data(db, filters=filters, page=page)
    return render_expenses(request, current_user, data)


@router.post("", response_class=HTMLResponse)
def create_expense_action(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    expense_date: Annotated[date, Form()],
    category: Annotated[str, Form()],
    description: Annotated[str, Form()],
    amount: Annotated[str, Form()],
    paid_by: Annotated[str, Form()],
    comment: Annotated[str | None, Form()] = None,
) -> Response:
    if current_user is None:
        return redirect_to_login()

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
        )
        success = "Расход добавлен"
    except ExpenseError as exc:
        db.rollback()
        error = str(exc)

    filters = normalize_filters(None, None, None, None)
    data = get_expenses_page_data(db, filters=filters, page=1, error=error, success=success)
    return render_expenses(request, current_user, data)
