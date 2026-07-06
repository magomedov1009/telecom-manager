from typing import Annotated

from fastapi import APIRouter, Depends, Form, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import SESSION_COOKIE_NAME, create_session_token, verify_password
from app.db.session import get_db
from app.dependencies.auth import get_current_user_optional
from app.models.clients import Client, Connection, ExtraWork
from app.models.finance import Expense, FinanceTransaction
from app.models.inventory import InventoryTransaction, Material
from app.models.users import User
from app.services.finance import get_finance_stats

router = APIRouter()
templates = Jinja2Templates(directory="app/templates")

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]


NAV_ITEMS = [
    {"label": "Dashboard", "endpoint": "/dashboard", "icon": "bi-speedometer2"},
    {"label": "Подключения", "endpoint": "/connections", "icon": "bi-router"},
    {"label": "Клиенты", "endpoint": "/clients", "icon": "bi-people"},
    {"label": "Материалы", "endpoint": "/materials", "icon": "bi-box-seam"},
    {"label": "Финансы", "endpoint": "/finance", "icon": "bi-cash-coin"},
    {"label": "Расходы", "endpoint": "/expenses", "icon": "bi-receipt"},
    {"label": "Допработы", "endpoint": "/extra-works", "icon": "bi-tools"},
    {"label": "Отчеты", "endpoint": "/reports", "icon": "bi-bar-chart"},
    {"label": "Настройки", "endpoint": "/settings", "icon": "bi-gear"},
]


def render(request: Request, template_name: str, context: dict) -> HTMLResponse:
    base_context = {
        "app_name": settings.app_name,
        "nav_items": NAV_ITEMS,
        "current_path": request.url.path,
    }
    base_context.update(context)
    return templates.TemplateResponse(request=request, name=template_name, context=base_context)


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


@router.get("/", response_class=HTMLResponse)
def home(current_user: CurrentUser) -> RedirectResponse:
    if current_user is None:
        return redirect_to_login()
    return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)


@router.get("/login", response_class=HTMLResponse)
def login_page(request: Request, current_user: CurrentUser) -> Response:
    if current_user is not None:
        return RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)
    return render(request, "auth/login.html", {"error": None})


@router.post("/login")
def login(
    request: Request,
    db: DbSession,
    username: Annotated[str, Form()],
    password: Annotated[str, Form()],
) -> Response:
    user = db.scalar(select(User).where(User.username == username, User.is_active.is_(True)))
    if user is None or not verify_password(password, user.hashed_password):
        return render(
            request,
            "auth/login.html",
            {"error": "Неверный логин или пароль", "username": username},
        )

    response = RedirectResponse(url="/dashboard", status_code=status.HTTP_303_SEE_OTHER)
    response.set_cookie(
        key=SESSION_COOKIE_NAME,
        value=create_session_token(user.id),
        httponly=True,
        samesite="lax",
        secure=False,
        max_age=60 * 60 * 12,
    )
    return response


@router.post("/logout")
def logout() -> RedirectResponse:
    response = RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)
    response.delete_cookie(SESSION_COOKIE_NAME)
    return response


@router.get("/dashboard", response_class=HTMLResponse)
def dashboard(request: Request, db: DbSession, current_user: CurrentUser) -> Response:
    if current_user is None:
        return redirect_to_login()

    stats = {
        "clients": db.scalar(select(func.count(Client.id))) or 0,
        "connections": db.scalar(select(func.count(Connection.id))) or 0,
        "materials": db.scalar(select(func.count(Material.id))) or 0,
        "inventory_transactions": db.scalar(select(func.count(InventoryTransaction.id))) or 0,
        "finance_transactions": db.scalar(select(func.count(FinanceTransaction.id))) or 0,
        "expenses": db.scalar(select(func.count(Expense.id))) or 0,
        "extra_works": db.scalar(select(func.count(ExtraWork.id))) or 0,
    }
    finance_stats = get_finance_stats(db)
    return render(request, "pages/dashboard.html", {"user": current_user, "stats": stats, "finance_stats": finance_stats})


@router.get("/{section}", response_class=HTMLResponse)
def section_page(
    request: Request,
    section: str,
    current_user: CurrentUser,
) -> Response:
    if current_user is None:
        return redirect_to_login()

    section_titles = {
        "connections": "Подключения",
        "clients": "Клиенты",
        "materials": "Материалы",
        "finance": "Финансы",
        "expenses": "Расходы",
        "extra-works": "Допработы",
        "reports": "Отчеты",
        "settings": "Настройки",
    }
    title = section_titles.get(section)
    if title is None:
        return render(request, "errors/404.html", {"user": current_user, "missing_path": request.url.path})
    return render(request, "pages/section.html", {"user": current_user, "title": title})



