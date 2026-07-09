
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db
from app.dependencies.auth import can_export_reports, can_open_reports, get_current_user_optional
from app.models.users import User
from app.routers.pages import NAV_ITEMS
from app.services.inventory import format_quantity
from app.services.reports import build_pdf, build_xlsx, get_reports_data, rows_for_export

router = APIRouter(prefix="/reports", tags=["reports"])
templates = Jinja2Templates(directory="app/templates")
templates.env.globals["format_quantity"] = format_quantity

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]


def parse_query_date(value: str | None) -> date | None:
    if not value:
        return None
    return date.fromisoformat(value)


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


def build_data(db: Session, period: str, date_from: date | None, date_to: date | None, provider_id: str | None, search: str | None, tab: str, page: int, sort: str, direction: str, per_page: int = 15):
    return get_reports_data(
        db,
        period_key=period,
        date_from=parse_query_date(date_from),
        date_to=parse_query_date(date_to),
        provider_id=int(provider_id) if provider_id else None,
        search=search,
        active_tab=tab,
        page=page,
        sort=sort,
        direction=direction,
        per_page=per_page,
    )


@router.get("", response_class=HTMLResponse)
def reports_page(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    period: Annotated[str, Query()] = "all",
    date_from: Annotated[str | None, Query()] = None,
    date_to: Annotated[str | None, Query()] = None,
    provider_id: Annotated[str | None, Query()] = None,
    search: Annotated[str | None, Query()] = None,
    tab: Annotated[str, Query()] = "providers",
    page: Annotated[int, Query(ge=1)] = 1,
    sort: Annotated[str, Query()] = "date",
    direction: Annotated[str, Query()] = "desc",
) -> Response:
    if current_user is None:
        return redirect_to_login()
    if not can_open_reports(current_user):
        return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)
    data = build_data(db, period, date_from, date_to, provider_id, search, tab, page, sort, direction)
    return templates.TemplateResponse(
        request=request,
        name="reports/index.html",
        context={"app_name": settings.app_name, "nav_items": NAV_ITEMS, "current_path": "/reports", "user": current_user, "data": data},
    )


@router.get("/export.xlsx")
def export_xlsx(
    db: DbSession,
    current_user: CurrentUser,
    period: Annotated[str, Query()] = "all",
    date_from: Annotated[str | None, Query()] = None,
    date_to: Annotated[str | None, Query()] = None,
    provider_id: Annotated[str | None, Query()] = None,
    search: Annotated[str | None, Query()] = None,
    tab: Annotated[str, Query()] = "providers",
    sort: Annotated[str, Query()] = "date",
    direction: Annotated[str, Query()] = "desc",
) -> Response:
    if current_user is None:
        return redirect_to_login()
    if not can_export_reports(current_user):
        return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)
    data = build_data(db, period, date_from, date_to, provider_id, search, tab, 1, sort, direction, per_page=100000)
    filename, headers, rows = rows_for_export(db, data, data["active_tab"])
    return Response(
        build_xlsx(headers, rows),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="telecom-manager-{filename}.xlsx"'},
    )


@router.get("/export.pdf")
def export_pdf(
    db: DbSession,
    current_user: CurrentUser,
    period: Annotated[str, Query()] = "all",
    date_from: Annotated[str | None, Query()] = None,
    date_to: Annotated[str | None, Query()] = None,
    provider_id: Annotated[str | None, Query()] = None,
    search: Annotated[str | None, Query()] = None,
    tab: Annotated[str, Query()] = "providers",
    sort: Annotated[str, Query()] = "date",
    direction: Annotated[str, Query()] = "desc",
) -> Response:
    if current_user is None:
        return redirect_to_login()
    if not can_export_reports(current_user):
        return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)
    data = build_data(db, period, date_from, date_to, provider_id, search, tab, 1, sort, direction, per_page=100000)
    filename, headers, rows = rows_for_export(db, data, data["active_tab"])
    return Response(
        build_pdf("Telecom Manager", headers, rows),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="telecom-manager-{filename}.pdf"'},
    )
