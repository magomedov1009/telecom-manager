from datetime import datetime

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, Integer, JSON, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base
from app.models.base import BaseModel


class MobileOrganization(BaseModel):
    __tablename__ = "mobile_organizations"
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    hosting_mode: Mapped[str] = mapped_column(String(32), nullable=False, default="cloud")
    is_legacy_workspace: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    owner_user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"),
        index=True,
    )


class MobileMembership(BaseModel):
    __tablename__ = "mobile_memberships"
    __table_args__ = (UniqueConstraint("organization_id", "user_id"),)
    organization_id: Mapped[int] = mapped_column(ForeignKey("mobile_organizations.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    role: Mapped[str] = mapped_column(String(32), nullable=False)


class MobileDeviceToken(BaseModel):
    __tablename__ = "mobile_device_tokens"
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    organization_id: Mapped[int] = mapped_column(ForeignKey("mobile_organizations.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class MobileSyncRecord(BaseModel):
    __tablename__ = "mobile_sync_records"
    __table_args__ = (UniqueConstraint("organization_id", "entity_type", "entity_id"),)
    organization_id: Mapped[int] = mapped_column(ForeignKey("mobile_organizations.id", ondelete="CASCADE"), index=True)
    entity_type: Mapped[str] = mapped_column(String(64), index=True)
    entity_id: Mapped[str] = mapped_column(String(36), index=True)
    site_id: Mapped[int | None] = mapped_column(BigInteger, index=True)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False)
    version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class MobileSyncChange(BaseModel):
    __tablename__ = "mobile_sync_changes"
    organization_id: Mapped[int] = mapped_column(ForeignKey("mobile_organizations.id", ondelete="CASCADE"), index=True)
    record_id: Mapped[int] = mapped_column(BigInteger, ForeignKey("mobile_sync_records.id", ondelete="CASCADE"), index=True)
    entity_type: Mapped[str] = mapped_column(String(64), index=True)
    entity_id: Mapped[str] = mapped_column(String(36), index=True)
    operation: Mapped[str] = mapped_column(String(16), nullable=False)
    version: Mapped[int] = mapped_column(Integer, nullable=False)


class MobileAuthRateLimit(Base):
    """Shared fixed-window counters for public mobile authentication routes."""

    __tablename__ = "mobile_auth_rate_limits"
    __table_args__ = (
        UniqueConstraint(
            "key_hash",
            "action",
            name="uq_mobile_auth_rate_limits_key_action",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    key_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    action: Mapped[str] = mapped_column(String(32), nullable=False)
    window_started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
