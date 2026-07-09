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
from app.services.inventory import format_quantity
from app.services.connections import (
    ConnectionError,
    create_connection,
    delete_connection,
    get_connection,
    get_connections_page_data,
    get_form_data,
    normalize_filters,
    update_connection,
)

router = APIRouter(prefix="/connections", tags=["connections"])
templates = Jinja2Templates(directory="app/templates")
templates.env.globals["format_quantity"] = format_quantity

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]


def parse_query_int(value: str | None) -> int | None:
    if not value:
        return None
    return int(value)


def parse_query_date(value: str | None) -> date | None:
    if not value:
        return None
    return date.fromisoformat(value)


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


def render(request: Request, template_name: str, current_user: User, context: dict) -> HTMLResponse:
    base_context = {
        "app_name": settings.app_name,
        "nav_items": NAV_ITEMS,
        "current_path": "/connections",
        "user": current_user,
    }
    base_context.update(context)
    return templates.TemplateResponse(request=request, name=template_name, context=base_context)


@router.get("", response_class=HTMLResponse)
def connections_page(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    search: Annotated[str | None, Query()] = None,
    provider: Annotated[str | None, Query()] = None,
    connection_type: Annotated[str | None, Query()] = None,
    warehouse_id: Annotated[str | None, Query()] = None,
    date_from: Annotated[str | None, Query()] = None,
    date_to: Annotated[str | None, Query()] = None,
    page: Annotated[int, Query(ge=1)] = 1,
) -> Response:
    if current_user is None:
        return redirect_to_login()
    filters = normalize_filters(search, provider, connection_type, parse_query_int(warehouse_id), parse_query_date(date_from), parse_query_date(date_to))
    data = get_connections_page_data(db, filters=filters, page=page)
    template = "connections/_module.html" if request.headers.get("HX-Request") else "connections/index.html"
    return render(request, template, current_user, {"data": data})


@router.get("/new", response_class=HTMLResponse)
def new_connection_page(request: Request, db: DbSession, current_user: CurrentUser) -> Response:
    if current_user is None:
        return redirect_to_login()
    return render(request, "connections/form.html", current_user, {"form": get_form_data(db), "mode": "create"})


@router.post("", response_class=HTMLResponse)
def create_connection_action(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    connection_date: Annotated[date, Form()],
    provider: Annotated[str, Form()],
    address: Annotated[str, Form()],
    connection_type: Annotated[str, Form()],
    warehouse_id: Annotated[int, Form()],
    price: Annotated[str, Form()],
    login: Annotated[str, Form()] = "",
    contract_number: Annotated[str, Form()] = "",
    phone: Annotated[str | None, Form()] = None,
    installer_amount: Annotated[str | None, Form()] = None,
    office_amount: Annotated[str | None, Form()] = None,
    client_comment: Annotated[str | None, Form()] = None,
    connection_comment: Annotated[str | None, Form()] = None,
    material_id: Annotated[list[int], Form()] = [],
    material_quantity: Annotated[list[str], Form()] = [],
) -> Response:
    if current_user is None:
        return redirect_to_login()
    try:
        connection = create_connection(
            db,
            user=current_user,
            connection_date=connection_date,
            provider=provider,
            contract_number=contract_number,
            login=login,
            address=address,
            phone=phone,
            client_comment=client_comment,
            connection_comment=connection_comment,
            connection_type=connection_type,
            warehouse_id=warehouse_id,
            price=price,
            installer_amount=installer_amount,
            office_amount=office_amount,
            material_ids=material_id,
            material_quantities=material_quantity,
        )
    except (ConnectionError, ValueError) as exc:
        db.rollback()
        return render(request, "connections/form.html", current_user, {"form": get_form_data(db, error=str(exc)), "mode": "create"})
    return RedirectResponse(url=f"/connections/{connection.id}", status_code=status.HTTP_303_SEE_OTHER)


@router.get("/{connection_id}", response_class=HTMLResponse)
def connection_detail(request: Request, db: DbSession, current_user: CurrentUser, connection_id: int) -> Response:
    if current_user is None:
        return redirect_to_login()
    connection = get_connection(db, connection_id)
    if connection is None:
        return render(request, "errors/404.html", current_user, {"missing_path": request.url.path})
    return render(request, "connections/detail.html", current_user, {"connection": connection})


@router.get("/{connection_id}/edit", response_class=HTMLResponse)
def edit_connection_page(request: Request, db: DbSession, current_user: CurrentUser, connection_id: int) -> Response:
    if current_user is None:
        return redirect_to_login()
    connection = get_connection(db, connection_id)
    if connection is None:
        return render(request, "errors/404.html", current_user, {"missing_path": request.url.path})
    return render(request, "connections/form.html", current_user, {"form": get_form_data(db, connection=connection), "mode": "edit"})


@router.post("/{connection_id}/edit", response_class=HTMLResponse)
def update_connection_action(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    connection_id: int,
    connection_date: Annotated[date, Form()],
    provider: Annotated[str, Form()],
    address: Annotated[str, Form()],
    connection_type: Annotated[str, Form()],
    warehouse_id: Annotated[int, Form()],
    price: Annotated[str, Form()],
    login: Annotated[str, Form()] = "",
    contract_number: Annotated[str, Form()] = "",
    phone: Annotated[str | None, Form()] = None,
    installer_amount: Annotated[str | None, Form()] = None,
    office_amount: Annotated[str | None, Form()] = None,
    client_comment: Annotated[str | None, Form()] = None,
    connection_comment: Annotated[str | None, Form()] = None,
    material_id: Annotated[list[int], Form()] = [],
    material_quantity: Annotated[list[str], Form()] = [],
) -> Response:
    if current_user is None:
        return redirect_to_login()
    connection = get_connection(db, connection_id)
    if connection is None:
        return render(request, "errors/404.html", current_user, {"missing_path": request.url.path})
    try:
        update_connection(
            db,
            connection=connection,
            user=current_user,
            connection_date=connection_date,
            provider=provider,
            contract_number=contract_number,
            login=login,
            address=address,
            phone=phone,
            client_comment=client_comment,
            connection_comment=connection_comment,
            connection_type=connection_type,
            warehouse_id=warehouse_id,
            price=price,
            installer_amount=installer_amount,
            office_amount=office_amount,
            material_ids=material_id,
            material_quantities=material_quantity,
        )
    except (ConnectionError, ValueError) as exc:
        db.rollback()
        return render(request, "connections/form.html", current_user, {"form": get_form_data(db, connection=connection, error=str(exc)), "mode": "edit"})
    return RedirectResponse(url=f"/connections/{connection.id}", status_code=status.HTTP_303_SEE_OTHER)


@router.post("/{connection_id}/delete", response_class=HTMLResponse)
def delete_connection_action(request: Request, db: DbSession, current_user: CurrentUser, connection_id: int) -> Response:
    if current_user is None:
        return redirect_to_login()
    connection = get_connection(db, connection_id)
    if connection is None:
        return render(request, "errors/404.html", current_user, {"missing_path": request.url.path})
    try:
        delete_connection(db, connection=connection, user=current_user)
    except ConnectionError as exc:
        db.rollback()
        return render(request, "connections/detail.html", current_user, {"connection": connection, "error": str(exc)})
    return RedirectResponse(url="/connections", status_code=status.HTTP_303_SEE_OTHER)
