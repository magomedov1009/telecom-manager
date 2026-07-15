from dataclasses import dataclass

from sqlalchemy import Select, select
from sqlalchemy.orm import Session

from app.models.enums import UserRole
from app.models.users import User


@dataclass(frozen=True)
class AccessScope:
    user: User
    user_ids: list[int] | None

    @property
    def is_admin(self) -> bool:
        return self.user.role == UserRole.ADMIN


def get_accessible_user_ids(db: Session, user: User) -> list[int] | None:
    if user.role == UserRole.ADMIN:
        return None
    if user.role == UserRole.MANAGER:
        subordinate_ids = list(db.scalars(select(User.id).where(User.manager_id == user.id, User.is_active.is_(True))))
        return sorted(set([user.id, *subordinate_ids]))
    return [user.id]


def get_access_scope(db: Session, user: User) -> AccessScope:
    return AccessScope(user=user, user_ids=get_accessible_user_ids(db, user))


def apply_user_scope(query: Select, column, scope: AccessScope | None) -> Select:
    if scope is not None and scope.user_ids is not None:
        return query.where(column.in_(scope.user_ids))
    return query


def can_access_user_id(scope: AccessScope | None, user_id: int | None) -> bool:
    if scope is None or scope.user_ids is None:
        return True
    return user_id in scope.user_ids
