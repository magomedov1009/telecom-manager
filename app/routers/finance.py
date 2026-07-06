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
from app.services.finance import (
    FinanceError,
    create_manual_transaction,
    get_finance_page_data,
    normalize_filters,
    source_label,
)

router = APIRouter(prefix="/finance", tags=["finance"])
templates = Jinja2Templates(directory="app/templates")
templates.env.globals["finance_source_label"] = source_label

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]


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
        },
    )


@router.get("", response_class=HTMLResponse)
def finance_page(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    date_from: Annotated[date | None, Query()] = None,
    date_to: Annotated[date | None, Query()] = None,
    transaction_type: Annotated[str | None, Query()] = None,
    user_id: Annotated[int | None, Query()] = None,
    search: Annotated[str | None, Query()] = None,
    page: Annotated[int, Query(ge=1)] = 1,
) -> Response:
    if current_user is None:
        return redirect_to_login()
    filters = normalize_filters(date_from, date_to, transaction_type, user_id, search)
    data = get_finance_page_data(db, filters=filters, page=page)
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
    data = get_finance_page_data(db, filters=filters, page=1, error=error, success=success)
    return render_finance(request, "finance/_module.html", current_user, data)
