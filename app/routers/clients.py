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
from app.services.clients import get_clients_page_data, normalize_filters

router = APIRouter(prefix="/clients", tags=["clients"])
templates = Jinja2Templates(directory="app/templates")

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


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
    data = get_clients_page_data(db, filters=filters, page=page)
    return templates.TemplateResponse(
        request=request,
        name="clients/index.html",
        context={
            "app_name": settings.app_name,
            "nav_items": NAV_ITEMS,
            "current_path": "/clients",
            "user": current_user,
            "data": data,
        },
    )
