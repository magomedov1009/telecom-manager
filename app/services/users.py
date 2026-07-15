from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.enums import UserRole
from app.models.users import User


def get_assignable_users(db: Session) -> list[User]:
    return list(
        db.scalars(
            select(User)
            .where(User.is_active.is_(True), User.role == UserRole.INSTALLER)
            .order_by(User.full_name, User.username)
        )
    )


def resolve_actor_user(db: Session, current_user: User, actor_user_id: int | None) -> User:
    if current_user.role != UserRole.ADMIN or not actor_user_id:
        return current_user
    actor = db.get(User, actor_user_id)
    if actor is None or not actor.is_active or actor.role != UserRole.INSTALLER:
        return current_user
    return actor
