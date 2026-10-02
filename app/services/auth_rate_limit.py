"""Database-backed limits for public authentication endpoints."""

from datetime import UTC, datetime, timedelta
import hashlib
import hmac

from fastapi import HTTPException, status
from sqlalchemy import case, delete, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.mobile_sync import MobileAuthRateLimit


def enforce_auth_rate_limit(
    db: Session,
    *,
    action: str,
    identity: str,
    limit: int,
    window: timedelta,
    now: datetime | None = None,
) -> None:
    """Atomically count requests across workers and reject excess attempts."""
    current_time = now or datetime.now(UTC)
    key_hash = hmac.new(
        settings.app_secret_key.encode("utf-8"),
        f"{action}\0{identity}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    table = MobileAuthRateLimit.__table__
    values = {
        "key_hash": key_hash,
        "action": action,
        "window_started_at": current_time,
        "attempts": 1,
    }
    dialect = db.get_bind().dialect.name
    insert = pg_insert if dialect == "postgresql" else sqlite_insert
    statement = insert(table).values(**values)
    expired = table.c.window_started_at <= current_time - window
    statement = statement.on_conflict_do_update(
        index_elements=[table.c.key_hash, table.c.action],
        set_={
            "window_started_at": case(
                (expired, current_time),
                else_=table.c.window_started_at,
            ),
            "attempts": case(
                (expired, 1),
                else_=table.c.attempts + 1,
            ),
        },
    )
    db.execute(statement)
    attempts = db.scalar(
        select(MobileAuthRateLimit.attempts).where(
            MobileAuthRateLimit.key_hash == key_hash,
            MobileAuthRateLimit.action == action,
        )
    )
    # Keep the table bounded while retaining counters for at least the full
    # configured window. Otherwise a long registration window could be pruned
    # early by the historical two-day cleanup threshold.
    configured_window = timedelta(
        seconds=max(
            settings.mobile_login_rate_window_seconds,
            settings.cloud_registration_rate_window_seconds,
        )
    )
    retention = max(window, configured_window) + timedelta(days=1)
    db.execute(
        delete(MobileAuthRateLimit).where(
            MobileAuthRateLimit.window_started_at < current_time - retention
        )
    )
    db.commit()
    if attempts is not None and attempts > limit:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Слишком много попыток. Повторите позже.",
            headers={"Retry-After": str(max(1, int(window.total_seconds())))},
        )
