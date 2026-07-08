from typing import Annotated

from fastapi import APIRouter, Depends, Form, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db
from app.dependencies.auth import get_current_user_optional
from app.models.clients import ExtraWorkType
from app.models.users import User
from app.routers.pages import NAV_ITEMS
from app.services.additional_works import parse_decimal

router = APIRouter(prefix="/settings/additional-work-types", tags=["additional-work-types"])
templates = Jinja2Templates(directory="app/templates")
DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


def load_types(db: Session) -> list[ExtraWorkType]:
    return list(db.scalars(select(ExtraWorkType).order_by(ExtraWorkType.name)))


def render_page(request: Request, current_user: User, types: list[ExtraWorkType], error: str | None = None, success: str | None = None) -> HTMLResponse:
    return templates.TemplateResponse(request=request, name="settings/additional_work_types.html", context={"app_name": settings.app_name, "nav_items": NAV_ITEMS, "current_path": "/settings", "user": current_user, "types": types, "error": error, "success": success})


@router.get("", response_class=HTMLResponse)
def page(request: Request, db: DbSession, current_user: CurrentUser) -> Response:
    if current_user is None:
        return redirect_to_login()
    return render_page(request, current_user, load_types(db))


@router.post("", response_class=HTMLResponse)
def create_type(request: Request, db: DbSession, current_user: CurrentUser, name: Annotated[str, Form()], description: Annotated[str | None, Form()] = None, default_price: Annotated[str | None, Form()] = None, default_office_amount: Annotated[str | None, Form()] = None, requires_materials: Annotated[bool, Form()] = False, requires_equipment: Annotated[bool, Form()] = False) -> Response:
    if current_user is None:
        return redirect_to_login()
    clean_name = name.strip()
    error = None
    success = None
    if not clean_name:
        error = "Название обязательно"
    else:
        db.add(ExtraWorkType(name=clean_name, description=description.strip() if description else None, default_price=parse_decimal(default_price, "Стоимость") if default_price else None, default_office_amount=parse_decimal(default_office_amount, "Доля офиса") if default_office_amount else None, requires_materials=requires_materials, requires_equipment=requires_equipment, is_active=True))
        db.commit()
        success = "Вид работы создан"
    return render_page(request, current_user, load_types(db), error, success)


@router.post("/{type_id}/toggle", response_class=HTMLResponse)
def toggle_type(request: Request, type_id: int, db: DbSession, current_user: CurrentUser) -> Response:
    if current_user is None:
        return redirect_to_login()
    item = db.get(ExtraWorkType, type_id)
    if item is not None:
        item.is_active = not item.is_active
        db.commit()
    return render_page(request, current_user, load_types(db), success="Статус обновлен")
