from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.orm import Session

from app.core.security import SESSION_COOKIE_NAME, verify_session_token
from app.db.session import get_db
from app.models.users import User


def get_current_user_optional(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
) -> User | None:
    user_id = verify_session_token(request.cookies.get(SESSION_COOKIE_NAME))
    if user_id is None:
        return None
    return db.get(User, user_id)
