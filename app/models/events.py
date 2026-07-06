from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, Enum, ForeignKey, JSON, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import BaseModel
from app.models.enums import EventAction


class EventLog(BaseModel):
    __tablename__ = "event_logs"

    actor_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"),
        index=True,
    )
    action: Mapped[EventAction] = mapped_column(
        Enum(EventAction, name="event_action"),
        index=True,
        nullable=False,
    )
    entity_type: Mapped[str] = mapped_column(String(128), index=True, nullable=False)
    entity_id: Mapped[int | None] = mapped_column(index=True)
    payload: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    ip_address: Mapped[str | None] = mapped_column(String(45))
    user_agent: Mapped[str | None] = mapped_column(String(512))
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    actor: Mapped["User | None"] = relationship(
        back_populates="event_logs",
        foreign_keys=[actor_id],
    )
