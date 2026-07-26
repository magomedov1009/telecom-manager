from datetime import UTC, datetime, timedelta
import hashlib
import secrets
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select
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
from app.models.users import User

router = APIRouter(prefix="/api/mobile", tags=["mobile-sync"])
DbSession = Annotated[Session, Depends(get_db)]


class LoginRequest(BaseModel):
    username: str
    password: str
    device_name: str = Field(min_length=1, max_length=120)


class LoginResponse(BaseModel):
    token: str
    organization_id: int
    organization_name: str
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
    membership = db.scalar(select(MobileMembership).where(MobileMembership.user_id == user.id))
    if membership is None:
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
    organization = db.get(MobileOrganization, membership.organization_id)
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
    )


@router.post("/sync/push", response_model=list[PushResult])
def push(
    payload: PushRequest,
    db: DbSession,
    token: Annotated[MobileDeviceToken, Depends(current_token)],
) -> list[PushResult]:
    membership = db.scalar(
        select(MobileMembership).where(
            MobileMembership.organization_id == token.organization_id,
            MobileMembership.user_id == token.user_id,
        )
    )
    operational_types = {
        "client", "connection", "connection_material",
        "inventory_transaction", "finance_transaction",
        "extra_work", "extra_work_material", "expense",
    }
    if membership is None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Нет доступа к организации")
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
        results.append(PushResult(entity_type=item.entity_type, entity_id=item.entity_id, status="accepted", server_version=item.version))
    db.commit()
    return results


@router.get("/sync/pull", response_model=PullResponse)
def pull(
    db: DbSession,
    token: Annotated[MobileDeviceToken, Depends(current_token)],
    cursor: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=500)] = 200,
) -> PullResponse:
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
    return PullResponse(cursor=items[-1].cursor if items else cursor, has_more=has_more, changes=items)
