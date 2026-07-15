from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db
from app.dependencies.auth import get_current_user_optional
from app.models.users import User
from app.routers.pages import NAV_ITEMS
from app.services.clients import get_client, get_client_detail_data, get_clients_page_data, normalize_filters

router = APIRouter(prefix="/clients", tags=["clients"])
templates = Jinja2Templates(directory="app/templates")

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


def render(request: Request, template_name: str, current_user: User, context: dict) -> HTMLResponse:
    base_context = {
        "app_name": settings.app_name,
        "nav_items": NAV_ITEMS,
        "current_path": "/clients",
        "user": current_user,
    }
    base_context.update(context)
    return templates.TemplateResponse(request=request, name=template_name, context=base_context)


@router.get("", response_class=HTMLResponse)
def clients_page(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    search: Annotated[str | None, Query()] = None,
    provider: Annotated[str | None, Query()] = None,
    page: Annotated[int, Query(ge=1)] = 1,
) -> Response:
    if current_user is None:
        return redirect_to_login()
    filters = normalize_filters(search, provider)
    data = get_clients_page_data(db, filters=filters, page=page, user=current_user)
    return render(request, "clients/index.html", current_user, {"data": data})


@router.get("/{client_id}", response_class=HTMLResponse)
def client_detail(request: Request, db: DbSession, current_user: CurrentUser, client_id: int) -> Response:
    if current_user is None:
        return redirect_to_login()
    client = get_client(db, client_id, current_user)
    if client is None:
        return render(request, "errors/404.html", current_user, {"missing_path": request.url.path})
    return render(request, "clients/detail.html", current_user, {"data": get_client_detail_data(client)})
