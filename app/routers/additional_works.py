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
from app.services.additional_works import AdditionalWorkError, create_additional_work, get_data, normalize_filters
from app.services.inventory import format_quantity

router = APIRouter(prefix="/additional-works", tags=["additional-works"])
templates = Jinja2Templates(directory="app/templates")
templates.env.globals["format_quantity"] = format_quantity

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


def render_page(request: Request, current_user: User, data) -> HTMLResponse:
    return templates.TemplateResponse(request=request, name="additional_works/index.html", context={"app_name": settings.app_name, "nav_items": NAV_ITEMS, "current_path": "/additional-works", "user": current_user, "data": data})


@router.get("", response_class=HTMLResponse)
def page(request: Request, db: DbSession, current_user: CurrentUser, search: Annotated[str | None, Query()] = None, provider_id: Annotated[int | None, Query()] = None, date_from: Annotated[date | None, Query()] = None, date_to: Annotated[date | None, Query()] = None, page: Annotated[int, Query(ge=1)] = 1) -> Response:
    if current_user is None:
        return redirect_to_login()
    filters = normalize_filters(search, provider_id, date_from, date_to)
    return render_page(request, current_user, get_data(db, filters, page))


@router.post("", response_class=HTMLResponse)
def create_action(request: Request, db: DbSession, current_user: CurrentUser, provider_id: Annotated[int, Form()], work_date: Annotated[date, Form()], work_type_id: Annotated[int, Form()], amount: Annotated[str, Form()], use_materials: Annotated[str, Form()] = "", material_id: Annotated[list[int], Form()] = [], material_quantity: Annotated[list[str], Form()] = [], comment: Annotated[str | None, Form()] = None) -> Response:
    if current_user is None:
        return redirect_to_login()
    error = None
    success = None
    try:
        create_additional_work(db, user=current_user, provider_id=provider_id, work_date=work_date, work_type_id=work_type_id, amount=amount, use_materials=(use_materials == "on"), material_ids=material_id, material_quantities=material_quantity, comment=comment)
        success = "Дополнительная работа создана"
    except AdditionalWorkError as exc:
        db.rollback()
        error = str(exc)
    data = get_data(db, normalize_filters(None, None, None, None), 1, error=error, success=success)
    return render_page(request, current_user, data)
