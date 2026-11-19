from datetime import date

from sqlalchemy import BigInteger, Date, ForeignKey, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import BaseModel


class FiberWorkLog(BaseModel):
    """Installer's private cable and fiber-splicing ledger.

    This table is intentionally independent from connections, inventory and
    financial transactions. The mobile sync record is the canonical identity;
    the JSON arrays retain the detailed field notes used for hand-off.
    """

    __tablename__ = "fiber_work_logs"

    owner_user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.id", ondelete="CASCADE"), index=True,
        nullable=False,
    )
    object_name: Mapped[str] = mapped_column(String(255), nullable=False)
    work_date: Mapped[date] = mapped_column(Date, index=True, nullable=False)
    cable_spans: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    splices: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    map_data: Mapped[dict | None] = mapped_column(JSON)
    notes: Mapped[str | None] = mapped_column(Text)
