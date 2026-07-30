from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
import hashlib
import secrets
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, or_, select
from sqlalchemy.orm import Session

from app.core.security import verify_password
from app.db.session import get_db
from app.models.mobile_sync import (
    MobileDeviceToken,
    MobileMembership,
    MobileOrganization,
    MobileSyncChange,
    MobileSyncRecord,
)
from app.models.clients import (
    Client, Connection, ConnectionMaterial, ExtraWork, ExtraWorkMaterial,
    ExtraWorkType, Provider,
)
from app.models.finance import Expense, FinanceTransaction
from app.models.inventory import InventoryTransaction, Material, Warehouse
from app.models.enums import (
    ConnectionType,
    ExpenseCategory,
    FinanceTransactionType,
    InventoryItemType,
    InventoryTransactionType,
    MaterialUnit,
    PaidBy,
)
from app.models.users import User
from app.services.expenses import pack_comment, unpack_comment

router = APIRouter(prefix="/api/mobile", tags=["mobile-sync"])
DbSession = Annotated[Session, Depends(get_db)]


class LoginRequest(BaseModel):
    username: str
    password: str
    device_name: str = Field(min_length=1, max_length=120)
    organization_id: int | None = None


class OrganizationOption(BaseModel):
    id: int
    name: str
    role: str


class LoginResponse(BaseModel):
    token: str
    organization_id: int
    organization_name: str
    user_id: int
    username: str
    full_name: str
    role: str
    organizations: list[OrganizationOption]


class CreateOrganizationRequest(BaseModel):
    name: str = Field(min_length=1, max_length=255)


class AddMemberRequest(BaseModel):
    username: str = Field(min_length=1, max_length=100)
    role: Literal["admin", "manager", "installer"]


class MemberResponse(BaseModel):
    user_id: int
    username: str
    full_name: str
    role: str


class PushItem(BaseModel):
    entity_type: str = Field(min_length=1, max_length=64)
    entity_id: str = Field(min_length=1, max_length=36)
    operation: Literal["upsert", "delete"]
    version: int = Field(ge=1)
    payload: dict


class PushRequest(BaseModel):
    changes: list[PushItem] = Field(max_length=500)


class ReplaceSnapshotRequest(BaseModel):
    confirmation: Literal["REPLACE_ALL_FROM_PHONE"]
    changes: list[PushItem] = Field(max_length=20000)


class PushResult(BaseModel):
    entity_type: str
    entity_id: str
    status: Literal["accepted", "duplicate", "conflict"]
    server_version: int


class PullItem(BaseModel):
    cursor: int
    entity_type: str
    entity_id: str
    operation: str
    version: int
    payload: dict


class PullResponse(BaseModel):
    cursor: int
    has_more: bool
    changes: list[PullItem]


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _value(value):
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if hasattr(value, "value"):
        return value.value
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return float(value)


def _mobile_payload(item, fields: tuple[str, ...]) -> dict:
    payload = {field: _value(getattr(item, field)) for field in fields}
    payload.update({
        "id": str(item.id),
        "organization_id": "",
        "created_at": item.created_at.isoformat(),
        "updated_at": item.updated_at.isoformat(),
        "deleted_at": None,
        "version": 1,
        "sync_state": "synced",
    })
    for key, value in tuple(payload.items()):
        if key.endswith("_id") and value is not None:
            payload[key] = str(value)
    return payload


def _mobile_entity_id(
    db: Session,
    organization_id: int,
    entity_type: str,
    site_id: int | None,
) -> str | None:
    if site_id is None:
        return None
    record = db.scalar(
        select(MobileSyncRecord).where(
            MobileSyncRecord.organization_id == organization_id,
            MobileSyncRecord.entity_type == entity_type,
            MobileSyncRecord.site_id == site_id,
        )
    )
    return record.entity_id if record is not None else str(site_id)


def _translate_site_foreign_keys(
    db: Session,
    organization_id: int,
    entity_type: str,
    payload: dict,
) -> None:
    references = {
        "warehouse": {"provider_id": "provider"},
        "client": {"provider_id": "provider"},
        "connection": {"client_id": "client", "warehouse_id": "warehouse"},
        "extra_work": {"provider_id": "provider", "work_type_id": "extra_work_type"},
        "expense": {"provider_id": "provider"},
        "connection_material": {
            "connection_id": "connection",
            "material_id": "material",
        },
        "extra_work_material": {
            "extra_work_id": "extra_work",
            "material_id": "material",
        },
        "inventory_transaction": {
            "warehouse_id": "warehouse",
            "counterpart_warehouse_id": "warehouse",
            "provider_id": "provider",
            "material_id": "material",
            "connection_id": "connection",
        },
        "finance_transaction": {
            "provider_id": "provider",
            "connection_id": "connection",
            "expense_id": "expense",
            "extra_work_id": "extra_work",
        },
    }
    for field, target_type in references.get(entity_type, {}).items():
        value = payload.get(field)
        payload[field] = _mobile_entity_id(
            db,
            organization_id,
            target_type,
            int(value) if value is not None else None,
        )


def _bootstrap_site_data(db: Session, organization_id: int) -> None:
    """Seed the primary mobile workspace from the existing website database."""
    primary_id = db.scalar(select(MobileOrganization.id).order_by(MobileOrganization.id))
    if primary_id != organization_id:
        return
    if not db.scalar(select(func.count()).select_from(Provider)):
        return
    specs = (
        ("provider", Provider, ("name", "description", "is_active")),
        ("material", Material, ("name", "item_type", "unit_name", "category", "active")),
        ("extra_work_type", ExtraWorkType, (
            "name", "description", "default_price", "default_office_amount",
            "requires_materials", "requires_equipment", "is_active",
        )),
        ("user", User, (
            "username", "full_name", "role", "manager_id", "comment",
            "last_login_at", "is_active",
        )),
        ("warehouse", Warehouse, ("provider_id", "name", "active")),
        ("client", Client, (
            "provider_id", "contract_number", "login", "address", "phone", "comment",
        )),
        ("connection", Connection, (
            "client_id", "warehouse_id", "connection_type", "connection_date",
            "price", "office_amount", "installer_amount", "comment",
        )),
        ("extra_work", ExtraWork, (
            "provider_id", "work_type_id", "work_date", "amount",
            "office_amount", "installer_amount", "status", "comment",
        )),
        ("expense", Expense, ("provider_id", "category", "amount", "paid_by", "comment")),
        ("connection_material", ConnectionMaterial, (
            "connection_id", "material_id", "quantity", "comment",
        )),
        ("extra_work_material", ExtraWorkMaterial, (
            "extra_work_id", "material_id", "quantity",
        )),
        ("inventory_transaction", InventoryTransaction, (
            "warehouse_id", "counterpart_warehouse_id", "provider_id", "material_id",
            "connection_id", "operation_type", "quantity", "comment",
        )),
        ("finance_transaction", FinanceTransaction, (
            "provider_id", "connection_id", "expense_id", "extra_work_id",
            "transaction_type", "accrual_to", "amount", "comment",
        )),
    )
    for entity_type, model, fields in specs:
        for item in db.scalars(select(model).order_by(model.id)):
            payload = _mobile_payload(item, fields)
            if entity_type == "material":
                payload["is_active"] = payload.pop("active")
                payload["unit_name"] = payload["unit_name"] or (
                    "м" if _value(item.unit) == "meter" else "шт."
                )
            elif entity_type == "warehouse":
                payload["is_active"] = payload.pop("active")
            elif entity_type == "inventory_transaction":
                payload["occurred_at"] = item.created_at.isoformat()
                payload["extra_work_id"] = None
                if (
                    _value(item.operation_type) == "TRANSFER_OUT"
                    and item.counterpart_warehouse_id is not None
                ):
                    destination = db.get(Warehouse, item.counterpart_warehouse_id)
                    payload["provider_id"] = (
                        str(destination.provider_id)
                        if destination is not None
                        and destination.provider_id is not None
                        else None
                    )
            elif entity_type == "finance_transaction":
                payload["occurred_at"] = item.created_at.isoformat()
            elif entity_type == "expense":
                expense_data = unpack_comment(item)
                payload["category"] = (
                    expense_data["category"] or _value(item.category)
                )
                payload["description"] = expense_data["description"]
                payload["comment"] = expense_data["comment"] or None
                payload["expense_date"] = item.created_at.date().isoformat()
            _translate_site_foreign_keys(
                db,
                organization_id,
                entity_type,
                payload,
            )
            record = db.scalar(
                select(MobileSyncRecord).where(
                    MobileSyncRecord.organization_id == organization_id,
                    MobileSyncRecord.entity_type == entity_type,
                    or_(
                        MobileSyncRecord.entity_id == str(item.id),
                        MobileSyncRecord.site_id == item.id,
                    ),
                )
            )
            if record is None:
                record = MobileSyncRecord(
                    organization_id=organization_id,
                    entity_type=entity_type,
                    entity_id=str(item.id),
                    payload=payload,
                    version=1,
                    site_id=item.id,
                )
                db.add(record)
                db.flush()
            elif record.payload == payload and record.site_id == item.id:
                continue
            else:
                record.payload = payload
                record.site_id = item.id
                record.version += 1
            db.add(MobileSyncChange(
                organization_id=organization_id,
                record_id=record.id,
                entity_type=entity_type,
                entity_id=record.entity_id,
                operation="upsert",
                version=record.version,
            ))
    _mark_site_deletions(db, organization_id)


def _mark_site_deletions(db: Session, organization_id: int) -> None:
    """Publish website deletions to mobile devices, including cascaded rows."""
    for entity_type, model in SITE_MODELS.items():
        records = list(
            db.scalars(
                select(MobileSyncRecord).where(
                    MobileSyncRecord.organization_id == organization_id,
                    MobileSyncRecord.entity_type == entity_type,
                    MobileSyncRecord.site_id.is_not(None),
                    MobileSyncRecord.deleted_at.is_(None),
                )
            )
        )
        for record in records:
            if db.get(model, record.site_id) is not None:
                continue
            record.deleted_at = datetime.now(UTC)
            record.version += 1
            db.add(
                MobileSyncChange(
                    organization_id=organization_id,
                    record_id=record.id,
                    entity_type=entity_type,
                    entity_id=record.entity_id,
                    operation="delete",
                    version=record.version,
                )
            )


def current_token(
    db: DbSession,
    authorization: Annotated[str | None, Header()] = None,
) -> MobileDeviceToken:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Требуется токен устройства")
    token = db.scalar(
        select(MobileDeviceToken).where(
            MobileDeviceToken.token_hash == _token_hash(authorization[7:]),
            MobileDeviceToken.expires_at > datetime.now(UTC),
        )
    )
    if token is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Токен недействителен")
    return token


@router.post("/login", response_model=LoginResponse)
def login(payload: LoginRequest, db: DbSession) -> LoginResponse:
    user = db.scalar(select(User).where(User.username == payload.username.strip()))
    if user is None or not user.is_active or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Неверный логин или пароль")
    memberships = list(
        db.scalars(
            select(MobileMembership)
            .where(MobileMembership.user_id == user.id)
            .order_by(MobileMembership.id)
        )
    )
    if not memberships:
        organization = db.scalar(select(MobileOrganization).order_by(MobileOrganization.id))
        if organization is None:
            organization = MobileOrganization(name="Основная организация")
            db.add(organization)
            db.flush()
        membership = MobileMembership(
            organization_id=organization.id,
            user_id=user.id,
            role=user.role.value,
        )
        db.add(membership)
        db.flush()
        memberships = [membership]
    elif payload.organization_id is not None:
        membership = next(
            (
                item
                for item in memberships
                if item.organization_id == payload.organization_id
            ),
            None,
        )
        if membership is None:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                "Нет доступа к выбранной организации",
            )
    else:
        membership = memberships[0]
    organization = db.get(MobileOrganization, membership.organization_id)
    _bootstrap_site_data(db, membership.organization_id)
    raw_token = secrets.token_urlsafe(48)
    db.add(
        MobileDeviceToken(
            token_hash=_token_hash(raw_token),
            organization_id=membership.organization_id,
            user_id=user.id,
            expires_at=datetime.now(UTC) + timedelta(days=90),
        )
    )
    db.commit()
    return LoginResponse(
        token=raw_token,
        organization_id=organization.id,
        organization_name=organization.name,
        user_id=user.id,
        username=user.username,
        full_name=user.full_name,
        role=membership.role,
        organizations=[
            OrganizationOption(
                id=item.organization_id,
                name=db.get(MobileOrganization, item.organization_id).name,
                role=item.role,
            )
            for item in memberships
        ],
    )


def current_membership(
    db: Session,
    token: MobileDeviceToken,
) -> MobileMembership:
    membership = db.scalar(
        select(MobileMembership).where(
            MobileMembership.organization_id == token.organization_id,
            MobileMembership.user_id == token.user_id,
        )
    )
    if membership is None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Нет доступа к организации")
    return membership


def require_admin(db: Session, token: MobileDeviceToken) -> MobileMembership:
    membership = current_membership(db, token)
    if membership.role != "admin":
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "Требуются права администратора",
        )
    return membership


@router.get("/organizations", response_model=list[OrganizationOption])
def organizations(
    db: DbSession,
    token: Annotated[MobileDeviceToken, Depends(current_token)],
) -> list[OrganizationOption]:
    memberships = list(
        db.scalars(
            select(MobileMembership)
            .where(MobileMembership.user_id == token.user_id)
            .order_by(MobileMembership.id)
        )
    )
    return [
        OrganizationOption(
            id=item.organization_id,
            name=db.get(MobileOrganization, item.organization_id).name,
            role=item.role,
        )
        for item in memberships
    ]


@router.post("/organizations", response_model=OrganizationOption)
def create_organization(
    payload: CreateOrganizationRequest,
    db: DbSession,
    token: Annotated[MobileDeviceToken, Depends(current_token)],
) -> OrganizationOption:
    require_admin(db, token)
    name = payload.name.strip()
    if not name:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Введите название")
    organization = MobileOrganization(name=name)
    db.add(organization)
    db.flush()
    db.add(
        MobileMembership(
            organization_id=organization.id,
            user_id=token.user_id,
            role="admin",
        )
    )
    db.commit()
    return OrganizationOption(id=organization.id, name=name, role="admin")


@router.get(
    "/organizations/{organization_id}/members",
    response_model=list[MemberResponse],
)
def organization_members(
    organization_id: int,
    db: DbSession,
    token: Annotated[MobileDeviceToken, Depends(current_token)],
) -> list[MemberResponse]:
    if token.organization_id != organization_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Выберите эту организацию")
    require_admin(db, token)
    rows = db.execute(
        select(MobileMembership, User)
        .join(User, User.id == MobileMembership.user_id)
        .where(MobileMembership.organization_id == organization_id)
        .order_by(User.full_name, User.username)
    ).all()
    return [
        MemberResponse(
            user_id=user.id,
            username=user.username,
            full_name=user.full_name,
            role=membership.role,
        )
        for membership, user in rows
    ]


@router.post(
    "/organizations/{organization_id}/members",
    response_model=MemberResponse,
)
def add_organization_member(
    organization_id: int,
    payload: AddMemberRequest,
    db: DbSession,
    token: Annotated[MobileDeviceToken, Depends(current_token)],
) -> MemberResponse:
    if token.organization_id != organization_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Выберите эту организацию")
    require_admin(db, token)
    user = db.scalar(
        select(User).where(
            User.username == payload.username.strip(),
            User.is_active.is_(True),
        )
    )
    if user is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Пользователь сайта не найден")
    membership = db.scalar(
        select(MobileMembership).where(
            MobileMembership.organization_id == organization_id,
            MobileMembership.user_id == user.id,
        )
    )
    if membership is None:
        membership = MobileMembership(
            organization_id=organization_id,
            user_id=user.id,
            role=payload.role,
        )
        db.add(membership)
    else:
        membership.role = payload.role
    db.commit()
    return MemberResponse(
        user_id=user.id,
        username=user.username,
        full_name=user.full_name,
        role=membership.role,
    )


@router.delete(
    "/organizations/{organization_id}/members/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def remove_organization_member(
    organization_id: int,
    user_id: int,
    db: DbSession,
    token: Annotated[MobileDeviceToken, Depends(current_token)],
) -> None:
    if token.organization_id != organization_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Выберите эту организацию")
    require_admin(db, token)
    if user_id == token.user_id:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "Нельзя удалить собственный доступ",
        )
    membership = db.scalar(
        select(MobileMembership).where(
            MobileMembership.organization_id == organization_id,
            MobileMembership.user_id == user_id,
        )
    )
    if membership is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Участник не найден")
    if membership.role == "admin":
        admins = db.scalar(
            select(func.count())
            .select_from(MobileMembership)
            .where(
                MobileMembership.organization_id == organization_id,
                MobileMembership.role == "admin",
            )
        )
        if admins <= 1:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                "В организации должен остаться администратор",
            )
    db.delete(membership)
    db.execute(
        delete(MobileDeviceToken).where(
            MobileDeviceToken.organization_id == organization_id,
            MobileDeviceToken.user_id == user_id,
        )
    )
    db.commit()


def _site_id(
    db: Session,
    organization_id: int,
    entity_type: str,
    entity_id: str | None,
) -> int | None:
    if entity_id is None:
        return None
    record = db.scalar(
        select(MobileSyncRecord).where(
            MobileSyncRecord.organization_id == organization_id,
            MobileSyncRecord.entity_type == entity_type,
            MobileSyncRecord.entity_id == str(entity_id),
        )
    )
    if record is not None and record.site_id is not None:
        return record.site_id
    return int(entity_id) if str(entity_id).isdigit() else None


def _publish_record_to_site(
    db: Session,
    record: MobileSyncRecord,
    user_id: int,
) -> bool:
    """Materialize a mobile record in the tables used by the website."""
    if record.site_id is not None or record.deleted_at is not None:
        return True
    data = record.payload
    org_id = record.organization_id
    entity_type = record.entity_type
    item = None
    if entity_type == "provider":
        item = Provider(
            name=data["name"],
            description=data.get("description"),
            is_active=bool(data.get("is_active", True)),
        )
    elif entity_type == "material":
        unit_name = str(data.get("unit_name") or "").lower()
        unit = MaterialUnit.METER if unit_name in {"м", "m", "meter", "метр"} else MaterialUnit.PIECE
        item = Material(
            name=data["name"],
            unit=unit,
            item_type=InventoryItemType(data.get("item_type", "MATERIAL")),
            category=data.get("category"),
            unit_name=data.get("unit_name"),
            active=bool(data.get("is_active", True)),
        )
    elif entity_type == "extra_work_type":
        item = ExtraWorkType(
            name=data["name"],
            description=data.get("description"),
            default_price=Decimal(str(data["default_price"])) if data.get("default_price") is not None else None,
            default_office_amount=Decimal(str(data["default_office_amount"])) if data.get("default_office_amount") is not None else None,
            requires_materials=bool(data.get("requires_materials", False)),
            requires_equipment=bool(data.get("requires_equipment", False)),
            is_active=bool(data.get("is_active", True)),
        )
    elif entity_type == "warehouse":
        item = Warehouse(
            name=data["name"],
            provider_id=_site_id(db, org_id, "provider", data.get("provider_id")),
            active=bool(data.get("is_active", True)),
        )
    elif entity_type == "client":
        provider_id = _site_id(db, org_id, "provider", data.get("provider_id"))
        if provider_id is None:
            return False
        contract_number = data.get("contract_number") or data.get("login")
        login_name = data.get("login") or data.get("contract_number")
        existing_client = db.scalars(
            select(Client).where(
                or_(
                    Client.contract_number == contract_number,
                    Client.login == login_name,
                )
            ).order_by(Client.id)
        ).first()
        if existing_client is not None:
            existing_client.provider_id = provider_id
            existing_client.contract_number = contract_number
            existing_client.login = login_name
            existing_client.address = data.get("address") or existing_client.address
            existing_client.phone = data.get("phone")
            existing_client.comment = data.get("comment")
            record.site_id = existing_client.id
            return True
        item = Client(
            provider_id=provider_id,
            contract_number=contract_number,
            login=login_name,
            address=data.get("address") or "—",
            phone=data.get("phone"),
            comment=data.get("comment"),
        )
    elif entity_type == "connection":
        client_id = _site_id(db, org_id, "client", data.get("client_id"))
        warehouse_id = _site_id(db, org_id, "warehouse", data.get("warehouse_id"))
        if client_id is None or warehouse_id is None:
            return False
        item = Connection(
            client_id=client_id,
            warehouse_id=warehouse_id,
            connection_type=ConnectionType(data["connection_type"]),
            connection_date=date.fromisoformat(data["connection_date"]),
            installer_id=user_id,
            price=Decimal(str(data.get("price") or 0)),
            office_amount=Decimal(str(data.get("office_amount") or 0)),
            installer_amount=Decimal(str(data.get("installer_amount") or 0)),
            comment=data.get("comment"),
        )
    elif entity_type == "connection_material":
        connection_id = _site_id(db, org_id, "connection", data.get("connection_id"))
        material_id = _site_id(db, org_id, "material", data.get("material_id"))
        if connection_id is None or material_id is None:
            return False
        item = ConnectionMaterial(
            connection_id=connection_id,
            material_id=material_id,
            quantity=Decimal(str(data["quantity"])),
            comment=data.get("comment"),
        )
    elif entity_type == "extra_work":
        provider_id = _site_id(db, org_id, "provider", data.get("provider_id"))
        work_type_id = _site_id(db, org_id, "extra_work_type", data.get("work_type_id"))
        if provider_id is None or work_type_id is None:
            return False
        item = ExtraWork(
            provider_id=provider_id,
            work_type_id=work_type_id,
            installer_id=user_id,
            work_date=date.fromisoformat(data["work_date"]),
            amount=Decimal(str(data.get("amount") or 0)),
            office_amount=Decimal(str(data.get("office_amount") or 0)),
            installer_amount=Decimal(str(data.get("installer_amount") or data.get("amount") or 0)),
            status=data.get("status") or "completed",
            comment=data.get("comment"),
        )
    elif entity_type == "extra_work_material":
        extra_work_id = _site_id(db, org_id, "extra_work", data.get("extra_work_id"))
        material_id = _site_id(db, org_id, "material", data.get("material_id"))
        if extra_work_id is None or material_id is None:
            return False
        item = ExtraWorkMaterial(
            extra_work_id=extra_work_id,
            material_id=material_id,
            quantity=Decimal(str(data["quantity"])),
            comment=data.get("comment"),
        )
    elif entity_type == "expense":
        provider_id = _site_id(db, org_id, "provider", data.get("provider_id"))
        if provider_id is None:
            return False
        category_key = data.get("category") or "other"
        category = {
            "fuel": ExpenseCategory.FUEL,
            "tools": ExpenseCategory.TOOLS,
            "transport": ExpenseCategory.TRANSPORT,
            "communication": ExpenseCategory.COMMUNICATION,
        }.get(category_key, ExpenseCategory.OTHER)
        item = Expense(
            user_id=user_id,
            provider_id=provider_id,
            category=category,
            amount=Decimal(str(data["amount"])),
            paid_by=PaidBy(data["paid_by"]),
            comment=pack_comment(
                category_key,
                data.get("description") or category_key,
                data.get("comment"),
            ),
            created_at=datetime.combine(
                date.fromisoformat(data["expense_date"]),
                datetime.min.time(),
            ),
        )
    elif entity_type == "inventory_transaction":
        warehouse_id = _site_id(db, org_id, "warehouse", data.get("warehouse_id"))
        material_id = _site_id(db, org_id, "material", data.get("material_id"))
        if warehouse_id is None or material_id is None:
            return False
        item = InventoryTransaction(
            warehouse_id=warehouse_id,
            counterpart_warehouse_id=_site_id(
                db, org_id, "warehouse", data.get("counterpart_warehouse_id")
            ),
            provider_id=_site_id(db, org_id, "provider", data.get("provider_id")),
            material_id=material_id,
            connection_id=_site_id(
                db, org_id, "connection", data.get("connection_id")
            ),
            user_id=user_id,
            operation_type=InventoryTransactionType(data["operation_type"]),
            quantity=Decimal(str(data["quantity"])),
            comment=data.get("comment"),
            created_at=datetime.fromisoformat(data["occurred_at"]),
        )
    elif entity_type == "finance_transaction":
        item = FinanceTransaction(
            connection_id=_site_id(
                db, org_id, "connection", data.get("connection_id")
            ),
            expense_id=_site_id(db, org_id, "expense", data.get("expense_id")),
            extra_work_id=_site_id(
                db, org_id, "extra_work", data.get("extra_work_id")
            ),
            user_id=user_id,
            provider_id=_site_id(db, org_id, "provider", data.get("provider_id")),
            amount=Decimal(str(data["amount"])),
            transaction_type=FinanceTransactionType(data["transaction_type"]),
            accrual_to=PaidBy(data["accrual_to"]) if data.get("accrual_to") else None,
            comment=data.get("comment"),
            created_at=datetime.fromisoformat(data["occurred_at"]),
        )
    else:
        return True
    db.add(item)
    db.flush()
    record.site_id = item.id
    return True


def _publish_pending_to_site(
    db: Session,
    organization_id: int,
    user_id: int,
) -> list[str]:
    priority = {
        "provider": 10,
        "material": 10,
        "extra_work_type": 10,
        "warehouse": 20,
        "client": 20,
        "connection": 30,
        "extra_work": 30,
        "expense": 30,
        "connection_material": 40,
        "extra_work_material": 40,
        "inventory_transaction": 40,
        "finance_transaction": 40,
    }
    records = list(
        db.scalars(
            select(MobileSyncRecord).where(
                MobileSyncRecord.organization_id == organization_id,
                MobileSyncRecord.site_id.is_(None),
                MobileSyncRecord.deleted_at.is_(None),
            )
        )
    )
    records.sort(key=lambda item: (priority.get(item.entity_type, 100), item.id))
    unresolved = []
    for record in records:
        if not _publish_record_to_site(db, record, user_id):
            unresolved.append(f"{record.entity_type}:{record.entity_id}")
    return unresolved


def _clear_site_business_data(db: Session) -> None:
    """Clear business tables while preserving website users and mobile auth."""
    for model in (
        FinanceTransaction,
        InventoryTransaction,
        ConnectionMaterial,
        ExtraWorkMaterial,
        Expense,
        ExtraWork,
        Connection,
        Client,
        Warehouse,
        Material,
        ExtraWorkType,
        Provider,
    ):
        db.execute(delete(model))
    db.flush()


SITE_MODELS = {
    "provider": Provider,
    "warehouse": Warehouse,
    "material": Material,
    "client": Client,
    "connection": Connection,
    "connection_material": ConnectionMaterial,
    "inventory_transaction": InventoryTransaction,
    "finance_transaction": FinanceTransaction,
    "extra_work_type": ExtraWorkType,
    "extra_work": ExtraWork,
    "extra_work_material": ExtraWorkMaterial,
    "expense": Expense,
}


def _delete_record_from_site(db: Session, record: MobileSyncRecord) -> None:
    model = SITE_MODELS.get(record.entity_type)
    if model is None or record.site_id is None:
        return
    item = db.get(model, record.site_id)
    if item is not None:
        db.delete(item)
        db.flush()
    record.site_id = None


def _update_record_on_site(
    db: Session,
    record: MobileSyncRecord,
    user_id: int,
) -> bool:
    if record.site_id is None:
        return _publish_record_to_site(db, record, user_id)
    model = SITE_MODELS.get(record.entity_type)
    item = db.get(model, record.site_id) if model is not None else None
    if item is None:
        record.site_id = None
        return _publish_record_to_site(db, record, user_id)
    data = record.payload
    org_id = record.organization_id
    kind = record.entity_type
    if kind == "provider":
        item.name, item.description = data["name"], data.get("description")
        item.is_active = bool(data.get("is_active", True))
    elif kind == "warehouse":
        item.name = data["name"]
        item.provider_id = _site_id(db, org_id, "provider", data.get("provider_id"))
        item.active = bool(data.get("is_active", True))
    elif kind == "material":
        item.name = data["name"]
        item.item_type = InventoryItemType(data.get("item_type", "MATERIAL"))
        item.category, item.unit_name = data.get("category"), data.get("unit_name")
        item.active = bool(data.get("is_active", True))
    elif kind == "client":
        item.provider_id = _site_id(db, org_id, "provider", data.get("provider_id"))
        item.contract_number = data.get("contract_number") or data.get("login")
        item.login = data.get("login") or data.get("contract_number")
        item.address, item.phone = data.get("address") or "—", data.get("phone")
        item.comment = data.get("comment")
    elif kind == "connection":
        item.client_id = _site_id(db, org_id, "client", data.get("client_id"))
        item.warehouse_id = _site_id(db, org_id, "warehouse", data.get("warehouse_id"))
        item.connection_type = ConnectionType(data["connection_type"])
        item.connection_date = date.fromisoformat(data["connection_date"])
        item.price = Decimal(str(data.get("price") or 0))
        item.office_amount = Decimal(str(data.get("office_amount") or 0))
        item.installer_amount = Decimal(str(data.get("installer_amount") or 0))
        item.comment = data.get("comment")
    elif kind == "connection_material":
        item.connection_id = _site_id(db, org_id, "connection", data.get("connection_id"))
        item.material_id = _site_id(db, org_id, "material", data.get("material_id"))
        item.quantity, item.comment = Decimal(str(data["quantity"])), data.get("comment")
    elif kind == "extra_work_type":
        item.name, item.description = data["name"], data.get("description")
        item.default_price = Decimal(str(data["default_price"])) if data.get("default_price") is not None else None
        item.default_office_amount = Decimal(str(data["default_office_amount"])) if data.get("default_office_amount") is not None else None
        item.requires_materials = bool(data.get("requires_materials", False))
        item.requires_equipment = bool(data.get("requires_equipment", False))
        item.is_active = bool(data.get("is_active", True))
    elif kind == "extra_work":
        item.provider_id = _site_id(db, org_id, "provider", data.get("provider_id"))
        item.work_type_id = _site_id(db, org_id, "extra_work_type", data.get("work_type_id"))
        item.work_date = date.fromisoformat(data["work_date"])
        item.amount = Decimal(str(data.get("amount") or 0))
        item.office_amount = Decimal(str(data.get("office_amount") or 0))
        item.installer_amount = Decimal(str(data.get("installer_amount") or data.get("amount") or 0))
        item.status, item.comment = data.get("status") or "completed", data.get("comment")
    elif kind == "extra_work_material":
        item.extra_work_id = _site_id(db, org_id, "extra_work", data.get("extra_work_id"))
        item.material_id = _site_id(db, org_id, "material", data.get("material_id"))
        item.quantity = Decimal(str(data["quantity"]))
        item.comment = data.get("comment")
    elif kind == "expense":
        category_key = data.get("category") or "other"
        item.provider_id = _site_id(db, org_id, "provider", data.get("provider_id"))
        item.category = {
            "fuel": ExpenseCategory.FUEL, "tools": ExpenseCategory.TOOLS,
            "transport": ExpenseCategory.TRANSPORT,
            "communication": ExpenseCategory.COMMUNICATION,
        }.get(category_key, ExpenseCategory.OTHER)
        item.amount, item.paid_by = Decimal(str(data["amount"])), PaidBy(data["paid_by"])
        item.comment = pack_comment(category_key, data.get("description") or category_key, data.get("comment"))
        item.created_at = datetime.combine(date.fromisoformat(data["expense_date"]), datetime.min.time())
    elif kind == "inventory_transaction":
        item.warehouse_id = _site_id(db, org_id, "warehouse", data.get("warehouse_id"))
        item.counterpart_warehouse_id = _site_id(db, org_id, "warehouse", data.get("counterpart_warehouse_id"))
        item.provider_id = _site_id(db, org_id, "provider", data.get("provider_id"))
        item.material_id = _site_id(db, org_id, "material", data.get("material_id"))
        item.connection_id = _site_id(db, org_id, "connection", data.get("connection_id"))
        item.operation_type = InventoryTransactionType(data["operation_type"])
        item.quantity, item.comment = Decimal(str(data["quantity"])), data.get("comment")
    elif kind == "finance_transaction":
        item.connection_id = _site_id(db, org_id, "connection", data.get("connection_id"))
        item.expense_id = _site_id(db, org_id, "expense", data.get("expense_id"))
        item.extra_work_id = _site_id(db, org_id, "extra_work", data.get("extra_work_id"))
        item.provider_id = _site_id(db, org_id, "provider", data.get("provider_id"))
        item.amount = Decimal(str(data["amount"]))
        item.transaction_type = FinanceTransactionType(data["transaction_type"])
        item.accrual_to = PaidBy(data["accrual_to"]) if data.get("accrual_to") else None
        item.comment = data.get("comment")
    db.flush()
    return True


@router.post("/sync/push", response_model=list[PushResult])
def push(
    payload: PushRequest,
    db: DbSession,
    token: Annotated[MobileDeviceToken, Depends(current_token)],
) -> list[PushResult]:
    membership = current_membership(db, token)
    operational_types = {
        "client", "connection", "connection_material",
        "inventory_transaction", "finance_transaction",
        "extra_work", "extra_work_material", "expense",
    }
    if membership.role != "admin" and any(item.entity_type not in operational_types for item in payload.changes):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Роль не разрешает изменение справочников")
    results: list[PushResult] = []
    for item in payload.changes:
        record = db.scalar(
            select(MobileSyncRecord).where(
                MobileSyncRecord.organization_id == token.organization_id,
                MobileSyncRecord.entity_type == item.entity_type,
                MobileSyncRecord.entity_id == item.entity_id,
            )
        )
        if record is not None and item.version == record.version and record.payload == item.payload:
            if item.operation == "delete":
                _delete_record_from_site(db, record)
            elif not _update_record_on_site(db, record, token.user_id):
                db.rollback()
                raise HTTPException(
                    status.HTTP_409_CONFLICT,
                    f"Не удалось связать {item.entity_type}:{item.entity_id}",
                )
            results.append(PushResult(entity_type=item.entity_type, entity_id=item.entity_id, status="duplicate", server_version=record.version))
            continue
        if record is not None and item.version <= record.version:
            results.append(PushResult(entity_type=item.entity_type, entity_id=item.entity_id, status="conflict", server_version=record.version))
            continue
        if record is None:
            record = MobileSyncRecord(
                organization_id=token.organization_id,
                entity_type=item.entity_type,
                entity_id=item.entity_id,
                payload=item.payload,
                version=item.version,
            )
            db.add(record)
            db.flush()
        else:
            record.payload = item.payload
            record.version = item.version
        record.deleted_at = datetime.now(UTC) if item.operation == "delete" else None
        db.flush()
        db.add(MobileSyncChange(
            organization_id=token.organization_id,
            record_id=record.id,
            entity_type=item.entity_type,
            entity_id=item.entity_id,
            operation=item.operation,
            version=item.version,
        ))
        if item.operation == "delete":
            _delete_record_from_site(db, record)
        elif not _update_record_on_site(db, record, token.user_id):
            db.rollback()
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                f"Не удалось связать {item.entity_type}:{item.entity_id}",
            )
        results.append(PushResult(entity_type=item.entity_type, entity_id=item.entity_id, status="accepted", server_version=item.version))
    db.commit()
    return results


@router.post("/sync/replace-snapshot")
def replace_snapshot(
    payload: ReplaceSnapshotRequest,
    db: DbSession,
    token: Annotated[MobileDeviceToken, Depends(current_token)],
) -> dict:
    require_admin(db, token)
    if not payload.changes:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Снимок телефона пуст")
    counts: dict[str, int] = {}
    for change in payload.changes:
        counts[change.entity_type] = counts.get(change.entity_type, 0) + 1
    required = {"provider", "warehouse", "material", "client", "connection"}
    missing = sorted(required - counts.keys())
    if missing:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"В снимке отсутствуют обязательные разделы: {', '.join(missing)}",
        )
    db.execute(
        delete(MobileSyncChange).where(
            MobileSyncChange.organization_id == token.organization_id
        )
    )
    db.execute(
        delete(MobileSyncRecord).where(
            MobileSyncRecord.organization_id == token.organization_id
        )
    )
    db.flush()
    for change in payload.changes:
        record = MobileSyncRecord(
            organization_id=token.organization_id,
            entity_type=change.entity_type,
            entity_id=change.entity_id,
            payload=change.payload,
            version=change.version,
        )
        db.add(record)
        db.flush()
        db.add(
            MobileSyncChange(
                organization_id=token.organization_id,
                record_id=record.id,
                entity_type=change.entity_type,
                entity_id=change.entity_id,
                operation="upsert",
                version=change.version,
            )
        )
    db.flush()
    _clear_site_business_data(db)
    unresolved = _publish_pending_to_site(
        db,
        token.organization_id,
        token.user_id,
    )
    if unresolved:
        db.rollback()
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Не удалось связать записи: " + ", ".join(unresolved[:20]),
        )
    db.commit()
    return {"total": len(payload.changes), "counts": counts}


@router.get("/sync/pull", response_model=PullResponse)
def pull(
    db: DbSession,
    token: Annotated[MobileDeviceToken, Depends(current_token)],
    cursor: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=500)] = 200,
) -> PullResponse:
    current_membership(db, token)
    _bootstrap_site_data(db, token.organization_id)
    db.flush()
    changes = list(db.scalars(
        select(MobileSyncChange)
        .where(MobileSyncChange.organization_id == token.organization_id, MobileSyncChange.id > cursor)
        .order_by(MobileSyncChange.id)
        .limit(limit + 1)
    ))
    has_more = len(changes) > limit
    changes = changes[:limit]
    items = []
    for change in changes:
        record = db.get(MobileSyncRecord, change.record_id)
        items.append(PullItem(
            cursor=change.id,
            entity_type=change.entity_type,
            entity_id=change.entity_id,
            operation=change.operation,
            version=change.version,
            payload=record.payload,
        ))
    response = PullResponse(
        cursor=items[-1].cursor if items else cursor,
        has_more=has_more,
        changes=items,
    )
    db.commit()
    return response
