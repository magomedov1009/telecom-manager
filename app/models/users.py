from datetime import datetime

from sqlalchemy import Boolean, DateTime, Enum, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import BaseModel
from app.models.enums import UserRole


class User(BaseModel):
    __tablename__ = "users"

    username: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[UserRole] = mapped_column(
        Enum(UserRole, name="user_role"),
        nullable=False,
    )
    phone: Mapped[str | None] = mapped_column(String(32), unique=True)
    email: Mapped[str | None] = mapped_column(String(255), unique=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    comment: Mapped[str | None] = mapped_column(String(500))

    connections: Mapped[list["Connection"]] = relationship(
        back_populates="installer",
        foreign_keys="Connection.installer_id",
    )
    inventory_transactions: Mapped[list["InventoryTransaction"]] = relationship(
        back_populates="user",
        foreign_keys="InventoryTransaction.user_id",
    )
    expenses: Mapped[list["Expense"]] = relationship(
        back_populates="user",
        foreign_keys="Expense.user_id",
    )
    finance_transactions: Mapped[list["FinanceTransaction"]] = relationship(
        back_populates="user",
        foreign_keys="FinanceTransaction.user_id",
    )
    extra_works: Mapped[list["ExtraWork"]] = relationship(
        back_populates="installer",
        foreign_keys="ExtraWork.installer_id",
    )
    event_logs: Mapped[list["EventLog"]] = relationship(
        back_populates="actor",
        foreign_keys="EventLog.actor_id",
    )

