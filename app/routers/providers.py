from typing import Annotated

from fastapi import APIRouter, Depends, Form, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db
from app.dependencies.auth import require_admin_user, get_current_user_optional
from app.models.clients import Provider
from app.models.users import User
from app.routers.pages import NAV_ITEMS

router = APIRouter(prefix="/settings/providers", tags=["providers"])
templates = Jinja2Templates(directory="app/templates")

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


def render_providers(request: Request, current_user: User, error: str | None = None, success: str | None = None) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request,
        name="settings/providers.html",
        context={
            "app_name": settings.app_name,
            "nav_items": NAV_ITEMS,
            "current_path": "/settings",
            "user": current_user,
            "providers": request.state.providers,
            "error": error,
            "success": success,
        },
    )


def load_providers(db: Session) -> list[Provider]:
    return list(db.scalars(select(Provider).order_by(Provider.name)))


@router.get("", response_class=HTMLResponse)
def providers_page(request: Request, db: DbSession, current_user: CurrentUser) -> Response:
    if current_user is None:
        return redirect_to_login()
    if not require_admin_user(current_user):
        return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)
    request.state.providers = load_providers(db)
    return render_providers(request, current_user)


@router.post("", response_class=HTMLResponse)
def create_provider(request: Request, db: DbSession, current_user: CurrentUser, name: Annotated[str, Form()], description: Annotated[str | None, Form()] = None) -> Response:
    if current_user is None:
        return redirect_to_login()
    if not require_admin_user(current_user):
        return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)
    clean_name = name.strip()
    error = None
    success = None
    if not clean_name:
        error = "Название провайдера обязательно"
    elif db.scalar(select(Provider).where(Provider.name == clean_name)) is not None:
        error = "Провайдер с таким названием уже существует"
    else:
        db.add(Provider(name=clean_name, description=description.strip() if description else None, is_active=True))
        db.commit()
        success = "Провайдер создан"
    request.state.providers = load_providers(db)
    return render_providers(request, current_user, error, success)


@router.post("/{provider_id}/toggle", response_class=HTMLResponse)
def toggle_provider(request: Request, provider_id: int, db: DbSession, current_user: CurrentUser) -> Response:
    if current_user is None:
        return redirect_to_login()
    if not require_admin_user(current_user):
        return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)
    provider = db.get(Provider, provider_id)
    if provider is not None:
        provider.is_active = not provider.is_active
        db.commit()
    request.state.providers = load_providers(db)
    return render_providers(request, current_user, success="Статус провайдера обновлен")


@router.post("/{provider_id}", response_class=HTMLResponse)
def update_provider(request: Request, provider_id: int, db: DbSession, current_user: CurrentUser, name: Annotated[str, Form()], description: Annotated[str | None, Form()] = None) -> Response:
    if current_user is None:
        return redirect_to_login()
    if not require_admin_user(current_user):
        return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)
    provider = db.get(Provider, provider_id)
    if provider is not None:
        provider.name = name.strip()
        provider.description = description.strip() if description else None
        db.commit()
    request.state.providers = load_providers(db)
    return render_providers(request, current_user, success="Провайдер обновлен")
