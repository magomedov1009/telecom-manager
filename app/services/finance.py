from dataclasses import dataclass
from datetime import date, datetime, time
from decimal import Decimal
from math import ceil
from urllib.parse import urlencode

from sqlalchemy import Select, func, or_, select
from sqlalchemy.orm import Session, joinedload

from app.models.clients import Connection, ExtraWork
from app.models.enums import FinanceTransactionType
from app.models.finance import Expense, FinanceTransaction
from app.models.users import User

FINANCE_TYPE_LABELS = {
    FinanceTransactionType.CONNECTION: "Подключение",
    FinanceTransactionType.EXTRA_WORK: "Допработа",
    FinanceTransactionType.EXPENSE: "Расход",
    FinanceTransactionType.PAYMENT_TO_OFFICE: "Передал деньги в офис",
    FinanceTransactionType.PAYMENT_FROM_OFFICE: "Получил деньги от офиса",
    FinanceTransactionType.ADJUSTMENT: "Корректировка",
}

MANUAL_TYPES = [
    FinanceTransactionType.PAYMENT_FROM_OFFICE,
    FinanceTransactionType.PAYMENT_TO_OFFICE,
    FinanceTransactionType.ADJUSTMENT,
]


class FinanceError(ValueError):
    pass


@dataclass(frozen=True)
class FinanceStats:
    today_received: Decimal
    month_received: Decimal
    installer_accrued: Decimal
    office_accrued: Decimal
    office_owes_me: Decimal
    i_owe_office: Decimal
    balance: Decimal


@dataclass(frozen=True)
class FinanceJournalPage:
    items: list[FinanceTransaction]
    page: int
    per_page: int
    total: int
    pages: int


@dataclass(frozen=True)
class FinancePageData:
    stats: FinanceStats
    journal: FinanceJournalPage
    filters: dict
    filter_query: str
    users: list[User]
    transaction_types: list[FinanceTransactionType]
    type_labels: dict[FinanceTransactionType, str]
    manual_types: list[FinanceTransactionType]
    error: str | None = None
    success: str | None = None


def parse_amount(value: str) -> Decimal:
    normalized = (value or "").replace(",", ".").strip()
    try:
        amount = Decimal(normalized)
    except Exception as exc:
        raise FinanceError("Сумма должна быть числом") from exc
    if amount <= 0:
        raise FinanceError("Сумма должна быть больше нуля")
    return amount


def normalize_filters(
    date_from: date | None,
    date_to: date | None,
    transaction_type: str | None,
    user_id: int | None,
    search: str | None,
) -> dict:
    return {
        "date_from": date_from,
        "date_to": date_to,
        "transaction_type": transaction_type or None,
        "user_id": user_id,
        "search": search.strip() if search else None,
    }


def build_filter_query(filters: dict) -> str:
    params = {}
    for key in ("date_from", "date_to", "transaction_type", "user_id", "search"):
        value = filters.get(key)
        if value:
            params[key] = value.isoformat() if hasattr(value, "isoformat") else value
    return urlencode(params)


def signed_amount_for_manual(transaction_type: FinanceTransactionType, amount: Decimal) -> Decimal:
    if transaction_type == FinanceTransactionType.PAYMENT_TO_OFFICE:
        return -amount
    return amount


def create_manual_transaction(
    db: Session,
    *,
    user: User,
    transaction_type: str,
    amount: str,
    comment: str | None,
) -> None:
    try:
        type_enum = FinanceTransactionType(transaction_type)
    except ValueError as exc:
        raise FinanceError("Неизвестный тип финансовой операции") from exc
    if type_enum not in MANUAL_TYPES:
        raise FinanceError("Этот тип операции нельзя создать вручную")

    parsed_amount = signed_amount_for_manual(type_enum, parse_amount(amount))
    db.add(
        FinanceTransaction(
            user_id=user.id,
            amount=parsed_amount,
            transaction_type=type_enum,
            comment=comment.strip() if comment else None,
        )
    )
    db.commit()


def get_money_received_query(start: datetime | None = None, end: datetime | None = None):
    query = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(
        FinanceTransaction.transaction_type.in_([
            FinanceTransactionType.CONNECTION,
            FinanceTransactionType.EXTRA_WORK,
            FinanceTransactionType.PAYMENT_FROM_OFFICE,
        ]),
        FinanceTransaction.amount > 0,
    )
    if start is not None:
        query = query.where(FinanceTransaction.created_at >= start)
    if end is not None:
        query = query.where(FinanceTransaction.created_at <= end)
    return query


def get_finance_stats(db: Session) -> FinanceStats:
    now = datetime.now()
    today_start = datetime.combine(now.date(), time.min)
    today_end = datetime.combine(now.date(), time.max)
    month_start = datetime(now.year, now.month, 1)

    today_received = Decimal(db.scalar(get_money_received_query(today_start, today_end)) or 0)
    month_received = Decimal(db.scalar(get_money_received_query(month_start, None)) or 0)

    installer_accrued = Decimal(db.scalar(select(func.coalesce(func.sum(Connection.installer_amount), 0))) or 0)
    office_accrued = Decimal(db.scalar(select(func.coalesce(func.sum(Connection.office_amount), 0))) or 0)
    paid_to_office = abs(Decimal(db.scalar(select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(FinanceTransaction.transaction_type == FinanceTransactionType.PAYMENT_TO_OFFICE)) or 0))
    paid_from_office = Decimal(db.scalar(select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(FinanceTransaction.transaction_type == FinanceTransactionType.PAYMENT_FROM_OFFICE)) or 0)
    adjustments = Decimal(db.scalar(select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(FinanceTransaction.transaction_type == FinanceTransactionType.ADJUSTMENT)) or 0)

    raw_balance = office_accrued - paid_to_office - paid_from_office + adjustments
    i_owe_office = raw_balance if raw_balance > 0 else Decimal("0")
    office_owes_me = abs(raw_balance) if raw_balance < 0 else Decimal("0")

    return FinanceStats(
        today_received=today_received,
        month_received=month_received,
        installer_accrued=installer_accrued,
        office_accrued=office_accrued,
        office_owes_me=office_owes_me,
        i_owe_office=i_owe_office,
        balance=raw_balance,
    )


def build_journal_query(filters: dict) -> Select[tuple[FinanceTransaction]]:
    query = select(FinanceTransaction).options(
        joinedload(FinanceTransaction.user),
        joinedload(FinanceTransaction.connection).joinedload(Connection.client),
        joinedload(FinanceTransaction.expense),
        joinedload(FinanceTransaction.extra_work),
    )

    if filters.get("date_from"):
        query = query.where(FinanceTransaction.created_at >= datetime.combine(filters["date_from"], time.min))
    if filters.get("date_to"):
        query = query.where(FinanceTransaction.created_at <= datetime.combine(filters["date_to"], time.max))
    if filters.get("transaction_type"):
        try:
            query = query.where(FinanceTransaction.transaction_type == FinanceTransactionType(filters["transaction_type"]))
        except ValueError:
            pass
    if filters.get("user_id"):
        query = query.where(FinanceTransaction.user_id == int(filters["user_id"]))
    if filters.get("search"):
        pattern = f"%{filters['search']}%"
        query = query.outerjoin(FinanceTransaction.user).where(
            or_(
                FinanceTransaction.comment.ilike(pattern),
                User.username.ilike(pattern),
                User.full_name.ilike(pattern),
            )
        )
    return query.order_by(FinanceTransaction.created_at.desc(), FinanceTransaction.id.desc())


def get_journal_page(db: Session, filters: dict, page: int, per_page: int = 15) -> FinanceJournalPage:
    page = max(page, 1)
    query = build_journal_query(filters)
    total = db.scalar(select(func.count()).select_from(query.order_by(None).subquery())) or 0
    items = list(db.scalars(query.offset((page - 1) * per_page).limit(per_page)))
    return FinanceJournalPage(items=items, page=page, per_page=per_page, total=total, pages=max(ceil(total / per_page), 1))


def get_finance_page_data(
    db: Session,
    *,
    filters: dict,
    page: int,
    error: str | None = None,
    success: str | None = None,
) -> FinancePageData:
    return FinancePageData(
        stats=get_finance_stats(db),
        journal=get_journal_page(db, filters, page),
        filters=filters,
        filter_query=build_filter_query(filters),
        users=list(db.scalars(select(User).order_by(User.full_name))),
        transaction_types=list(FinanceTransactionType),
        type_labels=FINANCE_TYPE_LABELS,
        manual_types=MANUAL_TYPES,
        error=error,
        success=success,
    )


def source_label(transaction: FinanceTransaction) -> str:
    if transaction.connection is not None:
        return f"Подключение #{transaction.connection.id}"
    if transaction.expense is not None:
        return f"Расход #{transaction.expense.id}"
    if transaction.extra_work is not None:
        return f"Допработа #{transaction.extra_work.id}"
    return "Ручная операция"
