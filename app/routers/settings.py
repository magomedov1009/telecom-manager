from typing import Annotated

from fastapi import APIRouter, Depends, Form, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import hash_password
from app.db.session import get_db
from app.dependencies.auth import get_current_user_optional, require_admin_user
from app.models.enums import UserRole
from app.models.users import User
from app.routers.pages import NAV_ITEMS

router = APIRouter(prefix="/settings", tags=["settings"])
templates = Jinja2Templates(directory="app/templates")

DbSession = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User | None, Depends(get_current_user_optional)]

ROLE_LABELS = {
    UserRole.ADMIN: "ADMIN",
    UserRole.MANAGER: "MANAGER",
    UserRole.INSTALLER: "INSTALLER",
}


def redirect_to_login() -> RedirectResponse:
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)


def forbidden(request: Request, current_user: User | None) -> HTMLResponse | RedirectResponse:
    if current_user is None:
        return redirect_to_login()
    return templates.TemplateResponse(
        request=request,
        name="errors/404.html",
        context={"app_name": settings.app_name, "nav_items": NAV_ITEMS, "current_path": request.url.path, "user": current_user, "missing_path": request.url.path},
        status_code=404,
    )


def render_settings(request: Request, template_name: str, current_user: User, context: dict | None = None) -> HTMLResponse:
    data = {"app_name": settings.app_name, "nav_items": NAV_ITEMS, "current_path": "/settings", "user": current_user}
    if context:
        data.update(context)
    return templates.TemplateResponse(request=request, name=template_name, context=data)


def load_users(db: Session) -> list[User]:
    return list(db.scalars(select(User).order_by(User.created_at.desc(), User.id.desc())))


def load_managers(db: Session) -> list[User]:
    return list(db.scalars(select(User).where(User.role == UserRole.MANAGER, User.is_active.is_(True)).order_by(User.full_name)))


def users_context(db: Session, **extra) -> dict:
    context = {"users": load_users(db), "managers": load_managers(db), "roles": list(UserRole), "role_labels": ROLE_LABELS}
    context.update(extra)
    return context


def normalize_manager_id(db: Session, manager_id: int | None) -> int | None:
    if not manager_id:
        return None
    manager = db.get(User, manager_id)
    if manager is None or manager.role != UserRole.MANAGER or not manager.is_active:
        return None
    return manager.id


@router.get("", response_class=HTMLResponse)
def settings_page(request: Request, current_user: CurrentUser) -> Response:
    if current_user is None or not require_admin_user(current_user):
        return forbidden(request, current_user)
    return render_settings(request, "settings/index.html", current_user)


@router.get("/users", response_class=HTMLResponse)
def users_page(request: Request, db: DbSession, current_user: CurrentUser) -> Response:
    if current_user is None or not require_admin_user(current_user):
        return forbidden(request, current_user)
    return render_settings(request, "settings/users.html", current_user, users_context(db))


@router.post("/users", response_class=HTMLResponse)
def create_user(
    request: Request,
    db: DbSession,
    current_user: CurrentUser,
    full_name: Annotated[str, Form()],
    username: Annotated[str, Form()],
    password: Annotated[str, Form()],
    role: Annotated[UserRole, Form()],
    is_active: Annotated[bool, Form()] = True,
    comment: Annotated[str | None, Form()] = None,
    manager_id: Annotated[int | None, Form()] = None,
) -> Response:
    if current_user is None or not require_admin_user(current_user):
        return forbidden(request, current_user)
    error = None
    success = None
    clean_username = username.strip()
    if not full_name.strip() or not clean_username or not password:
        error = "Заполните имя, логин и пароль"
    elif db.scalar(select(User).where(User.username == clean_username)) is not None:
        error = "Пользователь с таким логином уже существует"
    else:
        db.add(User(full_name=full_name.strip(), username=clean_username, hashed_password=hash_password(password), role=role, is_active=is_active, comment=comment.strip() if comment else None, manager_id=normalize_manager_id(db, manager_id)))
        db.commit()
        success = "Пользователь создан"
    return render_settings(request, "settings/users.html", current_user, users_context(db, error=error, success=success))


@router.post("/users/{user_id}", response_class=HTMLResponse)
def update_user(
    request: Request,
    user_id: int,
    db: DbSession,
    current_user: CurrentUser,
    full_name: Annotated[str, Form()],
    role: Annotated[UserRole, Form()],
    is_active: Annotated[bool, Form()] = True,
    comment: Annotated[str | None, Form()] = None,
    manager_id: Annotated[int | None, Form()] = None,
) -> Response:
    if current_user is None or not require_admin_user(current_user):
        return forbidden(request, current_user)
    item = db.get(User, user_id)
    if item is not None:
        item.full_name = full_name.strip()
        item.role = role
        item.is_active = is_active
        item.comment = comment.strip() if comment else None
        item.manager_id = normalize_manager_id(db, manager_id)
        db.commit()
    return render_settings(request, "settings/users.html", current_user, {"users": load_users(db), "roles": list(UserRole), "role_labels": ROLE_LABELS, "success": "Пользователь обновлен"})


@router.post("/users/{user_id}/password", response_class=HTMLResponse)
def change_password(request: Request, user_id: int, db: DbSession, current_user: CurrentUser, password: Annotated[str, Form()]) -> Response:
    if current_user is None or not require_admin_user(current_user):
        return forbidden(request, current_user)
    item = db.get(User, user_id)
    if item is not None and password:
        item.hashed_password = hash_password(password)
        db.commit()
    return render_settings(request, "settings/users.html", current_user, {"users": load_users(db), "roles": list(UserRole), "role_labels": ROLE_LABELS, "success": "Пароль обновлен"})


@router.post("/users/{user_id}/toggle", response_class=HTMLResponse)
def toggle_user(request: Request, user_id: int, db: DbSession, current_user: CurrentUser) -> Response:
    if current_user is None or not require_admin_user(current_user):
        return forbidden(request, current_user)
    item = db.get(User, user_id)
    if item is not None and item.id != current_user.id:
        item.is_active = not item.is_active
        db.commit()
    return render_settings(request, "settings/users.html", current_user, {"users": load_users(db), "roles": list(UserRole), "role_labels": ROLE_LABELS, "success": "Статус пользователя обновлен"})
