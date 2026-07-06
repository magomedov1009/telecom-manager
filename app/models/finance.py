from decimal import Decimal

from sqlalchemy import CheckConstraint, Enum, ForeignKey, Numeric, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import BaseModel
from app.models.enums import ExpenseCategory, FinanceTransactionType


class Expense(BaseModel):
    __tablename__ = "expenses"
    __table_args__ = (
        CheckConstraint("amount > 0", name="ck_expenses_amount_positive"),
    )

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    category: Mapped[ExpenseCategory] = mapped_column(
        Enum(ExpenseCategory, name="expense_category"),
        index=True,
        nullable=False,
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    comment: Mapped[str | None] = mapped_column(Text)

    user: Mapped["User"] = relationship(
        back_populates="expenses",
        foreign_keys=[user_id],
    )
    finance_transactions: Mapped[list["FinanceTransaction"]] = relationship(
        back_populates="expense",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )


class FinanceTransaction(BaseModel):
    __tablename__ = "finance_transactions"
    __table_args__ = (
        CheckConstraint("amount <> 0", name="ck_finance_transactions_amount_non_zero"),
        CheckConstraint(
            "num_nonnulls(connection_id, expense_id, extra_work_id) <= 1",
            name="ck_finance_transactions_single_source",
        ),
    )

    connection_id: Mapped[int | None] = mapped_column(
        ForeignKey("connections.id", ondelete="CASCADE"),
        index=True,
    )
    expense_id: Mapped[int | None] = mapped_column(
        ForeignKey("expenses.id", ondelete="CASCADE"),
        index=True,
    )
    extra_work_id: Mapped[int | None] = mapped_column(
        ForeignKey("extra_works.id", ondelete="CASCADE"),
        index=True,
    )
    user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"),
        index=True,
    )
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), nullable=False)
    transaction_type: Mapped[FinanceTransactionType] = mapped_column(
        Enum(FinanceTransactionType, name="finance_transaction_type"),
        index=True,
        nullable=False,
    )
    comment: Mapped[str | None] = mapped_column(Text)

    connection: Mapped["Connection | None"] = relationship(back_populates="finance_transactions")
    expense: Mapped["Expense | None"] = relationship(back_populates="finance_transactions")
    extra_work: Mapped["ExtraWork | None"] = relationship(back_populates="finance_transactions")
    user: Mapped["User | None"] = relationship(
        back_populates="finance_transactions",
        foreign_keys=[user_id],
    )
