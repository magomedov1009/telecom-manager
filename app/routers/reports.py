from datetime import date
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
from app.services.inventory import format_quantity
from app.services.reports import get_reports_data

router = APIRouter(prefix="/reports", tags=["reports"])
templates = Jinja2Templates(directory="app/templates")
templates.env.globals["format_quantity"] = format_quantity

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


@router.get("", response_class=HTMLResponse)
def reports_page(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    period: Annotated[str, Query()] = "all",
    date_from: Annotated[date | None, Query()] = None,
    date_to: Annotated[date | None, Query()] = None,
    provider_id: Annotated[int | None, Query()] = None,
    search: Annotated[str | None, Query()] = None,
    tab: Annotated[str, Query()] = "providers",
    page: Annotated[int, Query(ge=1)] = 1,
    sort: Annotated[str, Query()] = "date",
    direction: Annotated[str, Query()] = "desc",
) -> Response:
    if current_user is None:
        return redirect_to_login()

    data = get_reports_data(
        db,
        period_key=period,
        date_from=date_from,
        date_to=date_to,
        provider_id=provider_id,
        search=search,
        active_tab=tab,
        page=page,
        sort=sort,
        direction=direction,
    )
    return templates.TemplateResponse(
        request=request,
        name="reports/index.html",
        context={
            "app_name": settings.app_name,
            "nav_items": NAV_ITEMS,
            "current_path": "/reports",
            "user": current_user,
            "data": data,
        },
    )
