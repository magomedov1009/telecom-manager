from datetime import datetime

from decimal import Decimal

from sqlalchemy import DateTime, ForeignKey, Numeric, String
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


class CloudPayment(BaseModel):
    """One immutable checkout attempt, reconciled by its provider notification."""

    __tablename__ = "cloud_payments"

    organization_id: Mapped[int] = mapped_column(
        ForeignKey("mobile_organizations.id", ondelete="CASCADE"),
        index=True,
    )
    public_token: Mapped[str] = mapped_column(String(96), unique=True, index=True)
    label: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    plan_code: Mapped[str] = mapped_column(String(32), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    provider: Mapped[str] = mapped_column(String(32), nullable=False, default="yoomoney")
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="pending")
    provider_operation_id: Mapped[str | None] = mapped_column(String(255), unique=True)
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class CloudPaymentReceipt(BaseModel):
    """An individual successful YooMoney charge for a checkout order."""

    __tablename__ = "cloud_payment_receipts"

    payment_id: Mapped[int] = mapped_column(
        ForeignKey("cloud_payments.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    provider_operation_id: Mapped[str] = mapped_column(
        String(255),
        unique=True,
        nullable=False,
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    paid_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
