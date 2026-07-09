from dataclasses import dataclass
from datetime import date, datetime, time
from decimal import Decimal
from math import ceil
from urllib.parse import urlencode

from sqlalchemy import Select, func, or_, select
from sqlalchemy.orm import Session, joinedload

from app.models.clients import Connection, ExtraWork
from app.models.enums import FinanceTransactionType, PaidBy
from app.models.clients import Provider
from app.models.finance import Expense, FinanceTransaction
from app.services.expenses import ExpensesPageData
from app.models.users import User

FINANCE_TYPE_LABELS = {
    FinanceTransactionType.CONNECTION: "Начисление за подключение",
    FinanceTransactionType.EXTRA_WORK: "Допработа",
    FinanceTransactionType.EXPENSE: "Расход",
    FinanceTransactionType.PAYMENT_TO_OFFICE: "Передача денег в офис",
    FinanceTransactionType.PAYMENT_FROM_OFFICE: "Выплата офисом монтажнику",
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
    expenses_total: Decimal
    profit: Decimal
    office_owes_me: Decimal
    i_owe_office: Decimal
    balance: Decimal
    customer_received: Decimal
    paid_to_office: Decimal
    installer_expenses: Decimal
    available_installer_cash: Decimal


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
    providers: list[Provider]
    expenses_data: ExpensesPageData | None = None
    income_items: list[FinanceTransaction] | None = None
    settlement_items: list[FinanceTransaction] | None = None
    cash_flow_items: list[FinanceTransaction] | None = None
    expense_summary: dict | None = None
    income_summary: dict | None = None
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
    provider_id: int | None = None,
) -> dict:
    return {
        "date_from": date_from,
        "date_to": date_to,
        "transaction_type": transaction_type or None,
        "user_id": user_id,
        "search": search.strip() if search else None,
        "provider_id": provider_id,
    }


def build_filter_query(filters: dict) -> str:
    params = {}
    for key in ("date_from", "date_to", "transaction_type", "user_id", "search", "provider_id"):
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


def apply_period(query, start: datetime | None = None, end: datetime | None = None, column=None):
    date_column = column or FinanceTransaction.created_at
    if start is not None:
        query = query.where(date_column >= start)
    if end is not None:
        query = query.where(date_column <= end)
    return query


def get_money_received_query(start: datetime | None = None, end: datetime | None = None):
    query = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(
        FinanceTransaction.transaction_type.in_([
            FinanceTransactionType.CONNECTION,
            FinanceTransactionType.PAYMENT_FROM_OFFICE,
        ]),
        FinanceTransaction.amount > 0,
    )
    return apply_period(query, start, end)


def get_income_query(start: datetime | None = None, end: datetime | None = None):
    query = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(
        FinanceTransaction.transaction_type.in_([
            FinanceTransactionType.CONNECTION,
            FinanceTransactionType.EXTRA_WORK,
        ]),
        FinanceTransaction.amount > 0,
    )
    return apply_period(query, start, end)


def get_expense_query(start: datetime | None = None, end: datetime | None = None):
    query = select(func.coalesce(func.sum(func.abs(FinanceTransaction.amount)), 0)).where(
        FinanceTransaction.transaction_type == FinanceTransactionType.EXPENSE
    )
    return apply_period(query, start, end)


def period_from_filters(filters: dict | None) -> tuple[datetime | None, datetime | None]:
    if not filters:
        return None, None
    start = datetime.combine(filters["date_from"], time.min) if filters.get("date_from") else None
    end = datetime.combine(filters["date_to"], time.max) if filters.get("date_to") else None
    return start, end


def get_finance_stats(db: Session, filters: dict | None = None) -> FinanceStats:
    now = datetime.now()
    today_start = datetime.combine(now.date(), time.min)
    today_end = datetime.combine(now.date(), time.max)
    month_start = datetime(now.year, now.month, 1)
    period_start, period_end = period_from_filters(filters)
    provider_id = filters.get("provider_id") if filters else None

    today_received = Decimal(db.scalar(get_money_received_query(today_start, today_end)) or 0)
    month_received = Decimal(db.scalar(get_money_received_query(month_start, None)) or 0)

    installer_accrued_query = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(
        FinanceTransaction.transaction_type.in_([FinanceTransactionType.CONNECTION, FinanceTransactionType.EXTRA_WORK]),
        FinanceTransaction.accrual_to == PaidBy.INSTALLER,
        FinanceTransaction.amount > 0,
    )
    if provider_id:
        installer_accrued_query = installer_accrued_query.where(FinanceTransaction.provider_id == int(provider_id))
    installer_accrued = Decimal(db.scalar(apply_period(installer_accrued_query, period_start, period_end)) or 0)

    office_accrued_query = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(
        FinanceTransaction.transaction_type == FinanceTransactionType.CONNECTION,
        FinanceTransaction.accrual_to == PaidBy.OFFICE,
        FinanceTransaction.amount > 0,
    )
    if provider_id:
        office_accrued_query = office_accrued_query.where(FinanceTransaction.provider_id == int(provider_id))
    office_accrued = Decimal(db.scalar(apply_period(office_accrued_query, period_start, period_end)) or 0)

    expenses_total_query = get_expense_query(period_start, period_end)
    income_total_query = get_income_query(period_start, period_end)
    if provider_id:
        expenses_total_query = expenses_total_query.where(FinanceTransaction.provider_id == int(provider_id))
        income_total_query = income_total_query.where(FinanceTransaction.provider_id == int(provider_id))
    expenses_total = Decimal(db.scalar(expenses_total_query) or 0)
    income_total = Decimal(db.scalar(income_total_query) or 0)
    profit = income_total - expenses_total

    installer_expenses_query = select(func.coalesce(func.sum(Expense.amount), 0)).where(
        Expense.paid_by == PaidBy.INSTALLER,
    )
    if provider_id:
        installer_expenses_query = installer_expenses_query.where(Expense.provider_id == int(provider_id))
    installer_expenses = Decimal(db.scalar(apply_period(installer_expenses_query, period_start, period_end, Expense.created_at)) or 0)

    paid_from_office_query = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(
        FinanceTransaction.transaction_type == FinanceTransactionType.PAYMENT_FROM_OFFICE,
    )
    if provider_id:
        paid_from_office_query = paid_from_office_query.where(FinanceTransaction.provider_id == int(provider_id))
    paid_from_office = Decimal(db.scalar(apply_period(paid_from_office_query, period_start, period_end)) or 0)

    paid_to_office_query = select(func.coalesce(func.sum(func.abs(FinanceTransaction.amount)), 0)).where(
        FinanceTransaction.transaction_type == FinanceTransactionType.PAYMENT_TO_OFFICE,
    )
    if provider_id:
        paid_to_office_query = paid_to_office_query.where(FinanceTransaction.provider_id == int(provider_id))
    paid_to_office = Decimal(db.scalar(apply_period(paid_to_office_query, period_start, period_end)) or 0)

    office_money_query = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(
        FinanceTransaction.transaction_type == FinanceTransactionType.CONNECTION,
        FinanceTransaction.accrual_to == PaidBy.OFFICE,
        FinanceTransaction.amount > 0,
    )
    if provider_id:
        office_money_query = office_money_query.where(FinanceTransaction.provider_id == int(provider_id))
    office_money = Decimal(db.scalar(apply_period(office_money_query, period_start, period_end)) or 0)

    adjustments_query = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(
        FinanceTransaction.transaction_type == FinanceTransactionType.ADJUSTMENT,
    )
    if provider_id:
        adjustments_query = adjustments_query.where(FinanceTransaction.provider_id == int(provider_id))
    adjustments = Decimal(db.scalar(apply_period(adjustments_query, period_start, period_end)) or 0)

    extra_work_installer_accrued_query = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(
        FinanceTransaction.transaction_type == FinanceTransactionType.EXTRA_WORK,
        FinanceTransaction.accrual_to == PaidBy.INSTALLER,
        FinanceTransaction.amount > 0,
    )
    if provider_id:
        extra_work_installer_accrued_query = extra_work_installer_accrued_query.where(FinanceTransaction.provider_id == int(provider_id))
    extra_work_installer_accrued = Decimal(db.scalar(apply_period(extra_work_installer_accrued_query, period_start, period_end)) or 0)

    office_owes_me_raw = extra_work_installer_accrued + installer_expenses - paid_from_office + adjustments
    office_owes_me = office_owes_me_raw if office_owes_me_raw > 0 else Decimal("0")

    i_owe_office_raw = office_money - paid_to_office
    i_owe_office = i_owe_office_raw if i_owe_office_raw > 0 else Decimal("0")

    balance = office_owes_me - i_owe_office

    customer_received_query = get_money_received_query(period_start, period_end)
    if provider_id:
        customer_received_query = customer_received_query.where(FinanceTransaction.provider_id == int(provider_id))
    customer_received = Decimal(db.scalar(customer_received_query) or 0)
    available_installer_cash = customer_received - paid_to_office - installer_expenses

    return FinanceStats(
        today_received=today_received,
        month_received=month_received,
        installer_accrued=installer_accrued,
        office_accrued=office_accrued,
        expenses_total=expenses_total,
        profit=profit,
        office_owes_me=office_owes_me,
        i_owe_office=i_owe_office,
        balance=balance,
        customer_received=customer_received,
        paid_to_office=paid_to_office,
        installer_expenses=installer_expenses,
        available_installer_cash=available_installer_cash,
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
    if filters.get("provider_id"):
        query = query.where(FinanceTransaction.provider_id == int(filters["provider_id"]))
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


def finance_items_query(filters: dict, transaction_types: list[FinanceTransactionType] | None = None):
    query = select(FinanceTransaction).options(
        joinedload(FinanceTransaction.user),
        joinedload(FinanceTransaction.connection).joinedload(Connection.client),
        joinedload(FinanceTransaction.expense),
        joinedload(FinanceTransaction.extra_work),
    )
    if transaction_types is not None:
        query = query.where(FinanceTransaction.transaction_type.in_(transaction_types))
    if filters.get("date_from"):
        query = query.where(FinanceTransaction.created_at >= datetime.combine(filters["date_from"], time.min))
    if filters.get("date_to"):
        query = query.where(FinanceTransaction.created_at <= datetime.combine(filters["date_to"], time.max))
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


def get_finance_items(db: Session, filters: dict, transaction_types: list[FinanceTransactionType] | None = None, limit: int = 100) -> list[FinanceTransaction]:
    return list(db.scalars(finance_items_query(filters, transaction_types).limit(limit)))


def finance_client_label(transaction: FinanceTransaction) -> str:
    if transaction.connection is not None and transaction.connection.client is not None:
        client = transaction.connection.client
        return client.contract_number or client.login or client.phone or "—"
    return "—"


def money_direction(transaction: FinanceTransaction) -> str:
    return "Приход" if transaction.amount > 0 else "Расход"


def get_expense_summary(db: Session, filters: dict) -> dict:
    start, end = period_from_filters(filters)
    total_query = select(func.coalesce(func.sum(Expense.amount), 0))
    installer_query = select(func.coalesce(func.sum(Expense.amount), 0)).where(Expense.paid_by == PaidBy.INSTALLER)
    office_query = select(func.coalesce(func.sum(Expense.amount), 0)).where(Expense.paid_by == PaidBy.OFFICE)
    count_query = select(func.count(Expense.id))
    top_query = select(Expense.category, func.coalesce(func.sum(Expense.amount), 0).label("total")).group_by(Expense.category).order_by(func.coalesce(func.sum(Expense.amount), 0).desc())
    total = Decimal(db.scalar(apply_period(total_query, start, end, Expense.created_at)) or 0)
    installer = Decimal(db.scalar(apply_period(installer_query, start, end, Expense.created_at)) or 0)
    office = Decimal(db.scalar(apply_period(office_query, start, end, Expense.created_at)) or 0)
    operations = db.scalar(apply_period(count_query, start, end, Expense.created_at)) or 0
    top_row = db.execute(apply_period(top_query, start, end, Expense.created_at).limit(1)).first()
    top = {"label": "—", "amount": Decimal("0")}
    if top_row is not None:
        top = {"label": top_row[0].value, "amount": Decimal(top_row[1] or 0)}
    return {"total": total, "installer": installer, "office": office, "operations": operations, "top": top}


def get_income_summary(db: Session, filters: dict) -> dict:
    start, end = period_from_filters(filters)
    provider_id = filters.get("provider_id") if filters else None
    connection_query = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(FinanceTransaction.transaction_type == FinanceTransactionType.CONNECTION, FinanceTransaction.amount > 0)
    extra_query = select(func.coalesce(func.sum(FinanceTransaction.amount), 0)).where(FinanceTransaction.transaction_type == FinanceTransactionType.EXTRA_WORK, FinanceTransaction.amount > 0)
    if provider_id:
        connection_query = connection_query.where(FinanceTransaction.provider_id == int(provider_id))
        extra_query = extra_query.where(FinanceTransaction.provider_id == int(provider_id))
    connection_income = Decimal(db.scalar(apply_period(connection_query, start, end)) or 0)
    extra_income = Decimal(db.scalar(apply_period(extra_query, start, end)) or 0)
    return {"connections": connection_income, "extra_works": extra_income, "total": connection_income + extra_income}


def get_finance_page_data(
    db: Session,
    *,
    filters: dict,
    page: int,
    error: str | None = None,
    success: str | None = None,
) -> FinancePageData:
    return FinancePageData(
        stats=get_finance_stats(db, filters),
        journal=get_journal_page(db, filters, page),
        filters=filters,
        filter_query=build_filter_query(filters),
        users=list(db.scalars(select(User).order_by(User.full_name))),
        transaction_types=list(FinanceTransactionType),
        type_labels=FINANCE_TYPE_LABELS,
        manual_types=MANUAL_TYPES,
        providers=list(db.scalars(select(Provider).where(Provider.is_active.is_(True)).order_by(Provider.name))),
        income_items=get_finance_items(db, filters, [FinanceTransactionType.CONNECTION, FinanceTransactionType.EXTRA_WORK]),
        settlement_items=get_finance_items(db, filters, [FinanceTransactionType.PAYMENT_FROM_OFFICE, FinanceTransactionType.PAYMENT_TO_OFFICE]),
        cash_flow_items=get_finance_items(db, filters),
        expense_summary=get_expense_summary(db, filters),
        income_summary=get_income_summary(db, filters),
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
