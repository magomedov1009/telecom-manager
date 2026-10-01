from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import BaseModel


class CloudSubscription(BaseModel):
    """Commercial access record for one cloud organization.

    The record is deliberately separate from operational data.  Expiring a
    subscription must never delete a customer's data or local application.
    """

    __tablename__ = "cloud_subscriptions"

    organization_id: Mapped[int] = mapped_column(
        ForeignKey("mobile_organizations.id", ondelete="CASCADE"),
        unique=True,
        index=True,
    )
    plan_code: Mapped[str] = mapped_column(String(32), nullable=False, default="trial")
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="trial")
    starts_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    payment_provider: Mapped[str | None] = mapped_column(String(32))
    payment_reference: Mapped[str | None] = mapped_column(String(255), unique=True)
