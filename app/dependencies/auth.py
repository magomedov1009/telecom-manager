from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import SESSION_COOKIE_NAME, verify_session_token
from app.db.session import get_db
from app.models.enums import UserRole
from app.models.mobile_sync import MobileMembership, MobileOrganization
from app.models.users import User


def can_access_web_application(db: Session, user_id: int) -> bool:
    """Only legacy workspaces use the non-tenant-aware website tables."""
    if settings.hosting_mode != "cloud":
        return True
    legacy_membership = db.scalar(
        select(MobileMembership.id)
        .join(
            MobileOrganization,
            MobileOrganization.id == MobileMembership.organization_id,
        )
        .where(
            MobileMembership.user_id == user_id,
            MobileOrganization.is_legacy_workspace.is_(True),
        )
        .limit(1)
    )
    return legacy_membership is not None


def get_current_user_optional(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> User | None:
    user_id = verify_session_token(request.cookies.get(SESSION_COOKIE_NAME))
    if user_id is None:
        return None
    user = db.get(User, user_id)
    if user is None or not user.is_active:
        return None
    if not can_access_web_application(db, user.id):
        return None
    return user


def require_admin_user(user: User | None) -> bool:
    return user is not None and user.role == UserRole.ADMIN


def can_open_reports(user: User | None) -> bool:
    return user is not None and user.role in {UserRole.ADMIN, UserRole.MANAGER}


def can_open_finance(user: User | None) -> bool:
    return user is not None and user.role in {UserRole.ADMIN, UserRole.MANAGER, UserRole.INSTALLER}


def can_export_reports(user: User | None) -> bool:
    return user is not None and user.role in {UserRole.ADMIN, UserRole.MANAGER}
