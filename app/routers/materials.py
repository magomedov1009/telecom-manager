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
from app.services.inventory import (
    InventoryError,
    create_inventory_item,
    create_operation,
    format_quantity,
    get_materials_page_data,
    normalize_filters,
)

router = APIRouter(prefix="/materials", tags=["materials"])
templates = Jinja2Templates(directory="app/templates")
templates.env.globals["format_quantity"] = format_quantity

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


def render_materials(
    request: Request,
    template_name: str,
    current_user: User,
    data,
) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request,
        name=template_name,
        context={
            "app_name": settings.app_name,
            "nav_items": NAV_ITEMS,
            "current_path": "/materials",
            "user": current_user,
            "data": data,
        },
    )


@router.get("", response_class=HTMLResponse)
def materials_page(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    search: Annotated[str | None, Query()] = None,
    warehouse_id: Annotated[int | None, Query()] = None,
    material_id: Annotated[int | None, Query()] = None,
    operation_type: Annotated[str | None, Query()] = None,
    date_from: Annotated[date | None, Query()] = None,
    date_to: Annotated[date | None, Query()] = None,
    page: Annotated[int, Query(ge=1)] = 1,
    item_type: Annotated[str | None, Query()] = None,
) -> Response:
    if current_user is None:
        return redirect_to_login()

    filters = normalize_filters(search, warehouse_id, material_id, operation_type, date_from, date_to, item_type)
    data = get_materials_page_data(db, filters=filters, page=page)
    template_name = "materials/_module.html" if request.headers.get("HX-Request") else "materials/index.html"
    return render_materials(request, template_name, current_user, data)


@router.post("/items", response_class=HTMLResponse)
def create_inventory_item_action(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    name: Annotated[str, Form()],
    item_type: Annotated[str, Form()],
    unit_name: Annotated[str, Form()],
    category: Annotated[str | None, Form()] = None,
) -> Response:
    if current_user is None:
        return redirect_to_login()

    error = None
    success = None
    try:
        create_inventory_item(db, name=name, item_type=item_type, category=category, unit_name=unit_name)
        success = "Позиция успешно создана"
    except InventoryError as exc:
        db.rollback()
        error = str(exc)

    if not request.headers.get("HX-Request"):
        return RedirectResponse(url="/materials", status_code=status.HTTP_303_SEE_OTHER)

    filters = normalize_filters(None, None, None, None, None, None)
    data = get_materials_page_data(db, filters=filters, page=1, error=error, success=success)
    return render_materials(request, "materials/_module.html", current_user, data)


@router.post("/operations", response_class=HTMLResponse)
def create_material_operation(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    operation: Annotated[str, Form()],
    warehouse_id: Annotated[int, Form()],
    material_id: Annotated[int, Form()],
    quantity: Annotated[str, Form()],
    comment: Annotated[str | None, Form()] = None,
    destination_warehouse_id: Annotated[int | None, Form()] = None,
    adjustment_direction: Annotated[str, Form()] = "plus",
) -> Response:
    if current_user is None:
        return redirect_to_login()


    error = None
    success = None
    try:
        create_operation(
            db,
            user=current_user,
            operation=operation,
            warehouse_id=warehouse_id,
            material_id=material_id,
            quantity=quantity,
            comment=comment,
            destination_warehouse_id=destination_warehouse_id,
            adjustment_direction=adjustment_direction,
        )
        success = "Операция успешно создана"
    except InventoryError as exc:
        db.rollback()
        error = str(exc)

    if not request.headers.get("HX-Request"):
        return RedirectResponse(url="/materials", status_code=status.HTTP_303_SEE_OTHER)

    filters = normalize_filters(None, None, None, None, None, None)
    data = get_materials_page_data(db, filters=filters, page=1, error=error, success=success)
    return render_materials(request, "materials/_module.html", current_user, data)
