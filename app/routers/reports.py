
from datetime import date, datetime, time
from typing import Annotated
from urllib.parse import urlencode

from fastapi import APIRouter, Depends, Form, Query, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db
from app.dependencies.auth import can_export_reports, can_open_reports, get_current_user_optional
from app.models.inventory import MaterialDebtSettlement
from app.models.users import User
from app.routers.pages import NAV_ITEMS
from app.services.access import get_access_scope
from app.services.inventory import format_quantity
from app.services.reports import build_pdf, build_xlsx, get_reports_data, material_settlements, rows_for_export

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


def build_data(db: Session, current_user: User, period: str, date_from: date | None, date_to: date | None, provider_id: str | None, search: str | None, tab: str, page: int, sort: str, direction: str, per_page: int = 15):
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
        current_user=current_user,
    )


@router.get("", response_class=HTMLResponse)
def reports_page(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    period: Annotated[str, Query()] = "month",
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
    data = build_data(db, current_user, period, date_from, date_to, provider_id, search, tab, page, sort, direction)
    return templates.TemplateResponse(
        request=request,
        name="reports/index.html",
        context={"app_name": settings.app_name, "nav_items": NAV_ITEMS, "current_path": "/reports", "user": current_user, "data": data},
    )


@router.post("/material-settlements/close")
def close_material_debt(
    db: DbSession,
    current_user: CurrentUser,
    debtor_id: Annotated[int, Form()],
    creditor_id: Annotated[int, Form()],
    material_id: Annotated[int, Form()],
    settlement_date: Annotated[date, Form()],
    confirm: Annotated[str, Form()],
    period: Annotated[str, Form()] = "month",
    date_from: Annotated[str, Form()] = "",
    date_to: Annotated[str, Form()] = "",
    provider_id: Annotated[str, Form()] = "",
    search: Annotated[str, Form()] = "",
) -> Response:
    if current_user is None:
        return redirect_to_login()
    if current_user.role.value != "admin" or confirm != "yes":
        return RedirectResponse(url="/reports?tab=material_settlements", status_code=status.HTTP_303_SEE_OTHER)

    balance_period = {
        "date_from": None,
        "date_to": settlement_date,
        "start": None,
        "end": datetime.combine(settlement_date, time.max),
    }
    current_balances = material_settlements(
        db,
        balance_period,
        None,
        None,
        get_access_scope(db, current_user),
    )
    balance = next(
        (
            row
            for row in current_balances
            if row["debtor"].id == debtor_id
            and row["creditor"].id == creditor_id
            and row["material"].id == material_id
        ),
        None,
    )
    # Recalculate at the chosen date so a stale page or duplicate click cannot
    # close more than the actual remaining debt.
    if balance is not None and balance["quantity"] > 0:
        db.add(
            MaterialDebtSettlement(
                debtor_provider_id=debtor_id,
                creditor_provider_id=creditor_id,
                material_id=material_id,
                user_id=current_user.id,
                quantity=balance["quantity"],
                comment="Долг закрыт из отчёта",
                created_at=datetime.combine(settlement_date, time(hour=12)),
            )
        )
        db.commit()

    params = {
        "tab": "material_settlements",
        "period": period,
        "date_from": date_from,
        "date_to": date_to,
        "provider_id": provider_id,
        "search": search,
    }
    return RedirectResponse(
        url=f"/reports?{urlencode({key: value for key, value in params.items() if value})}",
        status_code=status.HTTP_303_SEE_OTHER,
    )


@router.get("/export.xlsx")
def export_xlsx(
    db: DbSession,
    current_user: CurrentUser,
    period: Annotated[str, Query()] = "month",
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
    data = build_data(db, current_user, period, date_from, date_to, provider_id, search, tab, 1, sort, direction, per_page=100000)
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
    period: Annotated[str, Query()] = "month",
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
    data = build_data(db, current_user, period, date_from, date_to, provider_id, search, tab, 1, sort, direction, per_page=100000)
    filename, headers, rows = rows_for_export(db, data, data["active_tab"])
    return Response(
        build_pdf("Telecom Manager", headers, rows),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="telecom-manager-{filename}.pdf"'},
    )
