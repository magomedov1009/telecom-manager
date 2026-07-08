from dataclasses import dataclass
from datetime import date, datetime, time
from decimal import Decimal
from math import ceil
from urllib.parse import urlencode

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, joinedload, selectinload

from app.models.clients import ExtraWork, ExtraWorkMaterial, ExtraWorkType, Provider
from app.models.enums import FinanceTransactionType, InventoryTransactionType, PaidBy
from app.models.finance import FinanceTransaction
from app.models.inventory import InventoryTransaction, Material, Warehouse
from app.models.users import User
from app.services.inventory import ensure_sufficient_stock


class AdditionalWorkError(ValueError):
    pass


@dataclass(frozen=True)
class AdditionalWorksPage:
    items: list[ExtraWork]
    page: int
    per_page: int
    total: int
    pages: int


@dataclass(frozen=True)
class AdditionalWorksData:
    works: AdditionalWorksPage
    providers: list[Provider]
    work_types: list[ExtraWorkType]
    materials: list[Material]
    filters: dict
    filter_query: str
    error: str | None = None
    success: str | None = None


def parse_decimal(value: str | None, field: str, allow_zero: bool = True) -> Decimal:
    normalized = (value or "0").replace(",", ".").strip()
    try:
        amount = Decimal(normalized)
    except Exception as exc:
        raise AdditionalWorkError(f"{field}: введите число") from exc
    if amount < 0 or (amount == 0 and not allow_zero):
        raise AdditionalWorkError(f"{field}: значение должно быть больше нуля")
    return amount


def normalize_filters(search: str | None, provider_id: int | None, date_from: date | None, date_to: date | None) -> dict:
    return {"search": search.strip() if search else None, "provider_id": provider_id, "date_from": date_from, "date_to": date_to}


def build_filter_query(filters: dict) -> str:
    params = {}
    for key, value in filters.items():
        if value:
            params[key] = value.isoformat() if hasattr(value, "isoformat") else value
    return urlencode(params)


def build_query(filters: dict):
    query = select(ExtraWork).options(joinedload(ExtraWork.provider), joinedload(ExtraWork.work_type), joinedload(ExtraWork.installer), selectinload(ExtraWork.materials).joinedload(ExtraWorkMaterial.material))
    if filters.get("provider_id"):
        query = query.where(ExtraWork.provider_id == int(filters["provider_id"]))
    if filters.get("date_from"):
        query = query.where(ExtraWork.work_date >= filters["date_from"])
    if filters.get("date_to"):
        query = query.where(ExtraWork.work_date <= filters["date_to"])
    if filters.get("search"):
        pattern = f"%{filters['search']}%"
        query = query.outerjoin(ExtraWork.work_type).where(or_(ExtraWorkType.name.ilike(pattern), ExtraWork.comment.ilike(pattern)))
    return query.order_by(ExtraWork.work_date.desc(), ExtraWork.id.desc())


def get_page(db: Session, filters: dict, page: int, per_page: int = 15) -> AdditionalWorksPage:
    page = max(page, 1)
    query = build_query(filters)
    total = db.scalar(select(func.count()).select_from(query.order_by(None).subquery())) or 0
    items = list(db.scalars(query.offset((page - 1) * per_page).limit(per_page)))
    return AdditionalWorksPage(items=items, page=page, per_page=per_page, total=total, pages=max(ceil(total / per_page), 1))


def get_data(db: Session, filters: dict, page: int, error: str | None = None, success: str | None = None) -> AdditionalWorksData:
    return AdditionalWorksData(
        works=get_page(db, filters, page),
        providers=list(db.scalars(select(Provider).where(Provider.is_active.is_(True)).order_by(Provider.name))),
        work_types=list(db.scalars(select(ExtraWorkType).where(ExtraWorkType.is_active.is_(True)).order_by(ExtraWorkType.name))),
        materials=list(db.scalars(select(Material).where(Material.active.is_(True)).order_by(Material.item_type, Material.name))),
        filters=filters,
        filter_query=build_filter_query(filters),
        error=error,
        success=success,
    )


def parse_material_rows(material_ids: list[int], quantities: list[str]) -> list[tuple[int, Decimal]]:
    rows = []
    for material_id, quantity in zip(material_ids, quantities, strict=False):
        if not material_id or not quantity.strip():
            continue
        rows.append((material_id, parse_decimal(quantity, "Количество", allow_zero=False)))
    return rows


def create_additional_work(db: Session, *, user: User, provider_id: int, work_date: date, work_type_id: int, amount: str, office_amount: str, use_materials: bool, material_ids: list[int], material_quantities: list[str], comment: str | None) -> ExtraWork:
    provider = db.get(Provider, provider_id)
    if provider is None or not provider.is_active:
        raise AdditionalWorkError("Выберите активного провайдера")
    work_type = db.get(ExtraWorkType, work_type_id)
    if work_type is None or not work_type.is_active:
        raise AdditionalWorkError("Выберите вид дополнительной работы")
    total = parse_decimal(amount, "Получено от провайдера")
    office = parse_decimal(office_amount, "Офис получает")
    if office > total:
        raise AdditionalWorkError("Офис не может получить больше стоимости работы")
    installer = total - office
    rows = parse_material_rows(material_ids, material_quantities) if use_materials else []
    warehouse = None
    if rows:
        warehouse = db.scalar(select(Warehouse).where(Warehouse.active.is_(True)).order_by(Warehouse.name).limit(1))
        if warehouse is None:
            raise AdditionalWorkError("Нет активного склада для списания материалов")
        for material_id, quantity in rows:
            ensure_sufficient_stock(db, warehouse.id, material_id, quantity)

    work = ExtraWork(
        provider_id=provider.id,
        work_type_id=work_type.id,
        installer_id=user.id,
        work_date=work_date,
        amount=total,
        office_amount=office,
        installer_amount=installer,
        status="completed",
        comment=comment.strip() if comment else None,
    )
    db.add(work)
    db.flush()
    for material_id, quantity in rows:
        db.add(ExtraWorkMaterial(extra_work_id=work.id, material_id=material_id, quantity=quantity, comment=comment))
        db.add(InventoryTransaction(warehouse_id=warehouse.id, material_id=material_id, user_id=user.id, provider_id=provider.id, operation_type=InventoryTransactionType.WRITE_OFF, quantity=-quantity, comment=f"Допработа #{work.id}"))
    if installer:
        db.add(FinanceTransaction(extra_work_id=work.id, provider_id=provider.id, user_id=user.id, amount=installer, transaction_type=FinanceTransactionType.EXTRA_WORK, accrual_to=PaidBy.INSTALLER, comment="Допработа: монтажнику"))
    if office:
        db.add(FinanceTransaction(extra_work_id=work.id, provider_id=provider.id, user_id=user.id, amount=office, transaction_type=FinanceTransactionType.EXTRA_WORK, accrual_to=PaidBy.OFFICE, comment="Допработа: офису"))
    db.commit()
    return work
