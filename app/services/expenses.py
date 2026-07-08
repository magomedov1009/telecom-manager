from dataclasses import dataclass
from datetime import date, datetime, time
from decimal import Decimal
from json import dumps, loads
from math import ceil
from urllib.parse import urlencode

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, joinedload

from app.models.enums import ExpenseCategory, FinanceTransactionType, PaidBy
from app.models.clients import Provider
from app.models.finance import Expense, FinanceTransaction
from app.models.users import User

EXPENSE_CATEGORY_OPTIONS = [
    ("fuel", "Бензин", ExpenseCategory.FUEL),
    ("tools", "Инструмент", ExpenseCategory.TOOLS),
    ("materials", "Материалы", ExpenseCategory.OTHER),
    ("transport", "Транспорт", ExpenseCategory.TRANSPORT),
    ("rent", "Аренда", ExpenseCategory.OTHER),
    ("other", "Прочее", ExpenseCategory.OTHER),
]

CATEGORY_LABELS = {key: label for key, label, _ in EXPENSE_CATEGORY_OPTIONS}
DB_CATEGORY_LABELS = {
    ExpenseCategory.FUEL: "Бензин",
    ExpenseCategory.TOOLS: "Инструмент",
    ExpenseCategory.TRANSPORT: "Транспорт",
    ExpenseCategory.COMMUNICATION: "Прочее",
    ExpenseCategory.OTHER: "Прочее",
}


class ExpenseError(ValueError):
    pass


@dataclass(frozen=True)
class ExpenseRow:
    expense: Expense
    category_label: str
    description: str
    comment: str


@dataclass(frozen=True)
class ExpenseListPage:
    items: list[ExpenseRow]
    page: int
    per_page: int
    total: int
    pages: int


@dataclass(frozen=True)
class ExpensesPageData:
    expenses: ExpenseListPage
    filters: dict
    filter_query: str
    categories: list[tuple[str, str]]
    users: list[User]
    error: str | None = None
    success: str | None = None


def normalize_filters(search: str | None, category: str | None, date_from: date | None, date_to: date | None) -> dict:
    return {
        "search": search.strip() if search else None,
        "category": category or None,
        "date_from": date_from,
        "date_to": date_to,
    }


def build_filter_query(filters: dict) -> str:
    params = {}
    for key, value in filters.items():
        if value:
            params[key] = value.isoformat() if hasattr(value, "isoformat") else value
    return urlencode(params)


def get_category_option(category_key: str) -> tuple[str, str, ExpenseCategory]:
    for option in EXPENSE_CATEGORY_OPTIONS:
        if option[0] == category_key:
            return option
    raise ExpenseError("Выберите категорию расхода")


def parse_amount(value: str) -> Decimal:
    try:
        amount = Decimal((value or "").replace(",", ".").strip())
    except Exception as exc:
        raise ExpenseError("Сумма должна быть числом") from exc
    if amount <= 0:
        raise ExpenseError("Сумма должна быть больше нуля")
    return amount


def pack_comment(category_key: str, description: str, comment: str | None) -> str:
    return dumps(
        {
            "category": category_key,
            "description": description.strip(),
            "comment": comment.strip() if comment else "",
        },
        ensure_ascii=False,
    )


def unpack_comment(expense: Expense) -> dict:
    if not expense.comment:
        return {"category": None, "description": "—", "comment": ""}
    try:
        data = loads(expense.comment)
    except ValueError:
        return {"category": None, "description": expense.comment, "comment": ""}
    return {
        "category": data.get("category"),
        "description": data.get("description") or "—",
        "comment": data.get("comment") or "",
    }


def make_expense_row(expense: Expense) -> ExpenseRow:
    data = unpack_comment(expense)
    category_key = data.get("category")
    return ExpenseRow(
        expense=expense,
        category_label=CATEGORY_LABELS.get(category_key) or DB_CATEGORY_LABELS.get(expense.category, expense.category.value),
        description=data["description"],
        comment=data["comment"],
    )


def build_expenses_query(filters: dict):
    query = select(Expense).options(joinedload(Expense.user))
    if filters.get("search"):
        pattern = f"%{filters['search']}%"
        query = query.join(Expense.user).where(
            or_(
                Expense.comment.ilike(pattern),
                User.username.ilike(pattern),
                User.full_name.ilike(pattern),
            )
        )
    if filters.get("category"):
        _, _, db_category = get_category_option(filters["category"])
        query = query.where(Expense.category == db_category)
        if filters["category"] in {"materials", "rent", "other"}:
            query = query.where(Expense.comment.ilike(f'%"category": "{filters["category"]}"%'))
    if filters.get("date_from"):
        query = query.where(Expense.created_at >= datetime.combine(filters["date_from"], time.min))
    if filters.get("date_to"):
        query = query.where(Expense.created_at <= datetime.combine(filters["date_to"], time.max))
    return query.order_by(Expense.created_at.desc(), Expense.id.desc())


def get_expenses_page(db: Session, filters: dict, page: int, per_page: int = 15) -> ExpenseListPage:
    page = max(page, 1)
    query = build_expenses_query(filters)
    total = db.scalar(select(func.count()).select_from(query.order_by(None).subquery())) or 0
    items = list(db.scalars(query.offset((page - 1) * per_page).limit(per_page)))
    return ExpenseListPage(
        items=[make_expense_row(item) for item in items],
        page=page,
        per_page=per_page,
        total=total,
        pages=max(ceil(total / per_page), 1),
    )


def get_expenses_page_data(
    db: Session,
    *,
    filters: dict,
    page: int,
    error: str | None = None,
    success: str | None = None,
) -> ExpensesPageData:
    return ExpensesPageData(
        expenses=get_expenses_page(db, filters, page),
        filters=filters,
        filter_query=build_filter_query(filters),
        categories=[(key, label) for key, label, _ in EXPENSE_CATEGORY_OPTIONS],
        users=list(db.scalars(select(User).order_by(User.full_name))),
        error=error,
        success=success,
    )


def create_expense(
    db: Session,
    *,
    expense_date: date,
    category: str,
    description: str,
    amount: str,
    paid_by_user_id: int,
    paid_by: str,
    comment: str | None,
    provider_id: int | None = None,
) -> None:
    category_key, _, db_category = get_category_option(category)
    if not description.strip():
        raise ExpenseError("Описание обязательно")
    parsed_amount = parse_amount(amount)
    try:
        paid_by_enum = PaidBy(paid_by)
    except ValueError as exc:
        raise ExpenseError("Укажите, кто оплатил расход") from exc
    user = db.get(User, paid_by_user_id)
    if user is None or not user.is_active:
        raise ExpenseError("Выберите пользователя, который оплатил расход")
    provider = db.get(Provider, provider_id) if provider_id else db.scalar(select(Provider).where(Provider.is_active.is_(True)).order_by(Provider.id))
    if provider is None or not provider.is_active:
        raise ExpenseError("Выберите активного провайдера")

    created_at = datetime.combine(expense_date, time.min)
    expense = Expense(
        user_id=user.id,
        provider_id=provider.id,
        category=db_category,
        amount=parsed_amount,
        paid_by=paid_by_enum,
        comment=pack_comment(category_key, description, comment),
        created_at=created_at,
    )
    db.add(expense)
    db.flush()
    db.add(
        FinanceTransaction(
            expense_id=expense.id,
            user_id=user.id,
            provider_id=provider.id,
            amount=-parsed_amount,
            transaction_type=FinanceTransactionType.EXPENSE,
            comment=description.strip(),
            created_at=created_at,
        )
    )
    db.commit()
