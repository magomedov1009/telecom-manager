"""External YooMoney checkout for the shared cloud service.

The mobile app never receives the wallet's notification secret.  It creates a
short opaque checkout link, then opens it in the system browser.
"""

from datetime import UTC, datetime, timedelta
from decimal import Decimal
import asyncio
import hashlib
import hmac
import secrets
from typing import Annotated
from urllib.parse import quote, urlencode
from urllib.error import HTTPError, URLError
from urllib.request import Request as UrlRequest, urlopen

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import HTMLResponse, Response
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db
from app.models.billing import CloudPayment, CloudSubscription
from app.models.mobile_sync import MobileDeviceToken, MobileOrganization
from app.routers.mobile_sync import current_token


router = APIRouter(tags=["billing"])
templates = Jinja2Templates(directory="app/templates")
DbSession = Annotated[Session, Depends(get_db)]


class CheckoutRequest(BaseModel):
    plan_code: str


class CheckoutResponse(BaseModel):
    checkout_url: str


def _price_for(plan_code: str) -> Decimal:
    prices = {
        "monthly": settings.cloud_monthly_price,
        "yearly": settings.cloud_yearly_price,
    }
    price = prices.get(plan_code)
    if price is None or price <= 0:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Выберите доступный тариф",
        )
    return Decimal(price).quantize(Decimal("0.01"))


def _ensure_cloud_checkout(organization: MobileOrganization) -> None:
    if settings.hosting_mode != "cloud":
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "На собственном сервере подписка не требуется",
        )
    if organization.is_legacy_workspace:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "Для этой организации подписка не требуется",
        )
    if not settings.yoomoney_wallet:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Оплата пока не настроена",
        )


def _utc(value: datetime) -> datetime:
    """Normalize values returned by PostgreSQL and SQLite for comparisons."""
    return value if value.tzinfo is not None else value.replace(tzinfo=UTC)


@router.post("/api/mobile/subscription/checkout", response_model=CheckoutResponse)
def create_checkout(
    payload: CheckoutRequest,
    request: Request,
    db: DbSession,
    token: Annotated[MobileDeviceToken, Depends(current_token)],
) -> CheckoutResponse:
    organization = db.get(MobileOrganization, token.organization_id)
    if organization is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Организация не найдена")
    _ensure_cloud_checkout(organization)
    # A customer should only ever have one active payment form. This avoids
    # accidentally paying twice after pressing the button more than once.
    for pending in db.scalars(
        select(CloudPayment).where(
            CloudPayment.organization_id == organization.id,
            CloudPayment.status == "pending",
        )
    ):
        pending.status = "superseded"
    payment = CloudPayment(
        organization_id=organization.id,
        public_token=secrets.token_urlsafe(32),
        label=f"TM{secrets.token_hex(16)}",
        plan_code=payload.plan_code,
        amount=_price_for(payload.plan_code),
        status="pending",
    )
    db.add(payment)
    db.commit()
    db.refresh(payment)
    return CheckoutResponse(
        checkout_url=str(request.url_for("billing_checkout", token=payment.public_token)),
    )


@router.get("/billing/checkout/{token}", response_class=HTMLResponse, name="billing_checkout")
def checkout_page(token: str, request: Request, db: DbSession) -> HTMLResponse:
    payment = db.scalar(select(CloudPayment).where(CloudPayment.public_token == token))
    if payment is None or payment.status != "pending":
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Ссылка на оплату не найдена или уже использована")
    expires_at = _utc(payment.created_at) + timedelta(
        minutes=max(1, settings.cloud_payment_link_minutes)
    )
    if expires_at <= datetime.now(UTC):
        payment.status = "expired"
        db.commit()
        raise HTTPException(status.HTTP_410_GONE, "Срок действия ссылки на оплату истёк")
    if not settings.yoomoney_wallet:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Оплата пока не настроена")
    organization = db.get(MobileOrganization, payment.organization_id)
    return templates.TemplateResponse(
        request=request,
        name="billing/checkout.html",
        context={
            "app_name": settings.app_name,
            "organization": organization,
            "payment": payment,
            "wallet": settings.yoomoney_wallet,
            "success_url": str(request.url_for("billing_complete")),
            "plan_label": "1 месяц" if payment.plan_code == "monthly" else "1 год",
        },
    )


@router.get("/billing/complete", response_class=HTMLResponse, name="billing_complete")
def payment_complete(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request,
        name="billing/complete.html",
        context={"app_name": settings.app_name},
    )


def _notification_signature(values: dict[str, str]) -> str:
    secret = settings.yoomoney_notification_secret
    if not secret:
        return ""
    serialized = "&".join(
        f"{key}={quote(value, safe='')}"
        for key, value in sorted(values.items())
        if key != "sign"
    )
    return hmac.new(
        secret.encode("utf-8"),
        serialized.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def _forward_yoomoney_notification(url: str, values: dict[str, str]) -> bool:
    body = urlencode(values).encode("utf-8")
    request = UrlRequest(
        url,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=10) as response:
            return response.status == 200
    except HTTPError as error:
        return error.code == 200
    except (URLError, TimeoutError):
        return False


@router.post("/api/billing/yoomoney/notification", status_code=status.HTTP_200_OK)
async def yoomoney_notification(request: Request, db: DbSession) -> Response:
    """Accept one signed YooMoney notification and extend access once."""
    if not settings.yoomoney_notification_secret:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Уведомления не настроены")
    form = await request.form()
    values = {str(key): str(value) for key, value in form.items()}
    if not values or not any(values.values()) or values.get("test_notification") == "true":
        return Response(status_code=status.HTTP_200_OK)
    received_sign = values.get("sign", "")
    expected_sign = _notification_signature(values)
    if not hmac.compare_digest(received_sign, expected_sign):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Неверная подпись уведомления")
    label = values.get("label", "")
    payment = db.scalar(select(CloudPayment).where(CloudPayment.label == label))
    if payment is None:
        # Telecom Manager owns the TM label namespace. All other correctly
        # signed labels can be dispatched to another YooMoney integration.
        fallback_url = settings.yoomoney_fallback_notification_url
        if label.startswith("TM") or not fallback_url:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "Заказ не найден")
        forwarded = await asyncio.to_thread(
            _forward_yoomoney_notification,
            fallback_url,
            values,
        )
        if not forwarded:
            raise HTTPException(
                status.HTTP_503_SERVICE_UNAVAILABLE,
                "Не удалось доставить уведомление в связанный сервис",
            )
        return Response(status_code=status.HTTP_200_OK)
    if values.get("currency") != "643" or values.get("unaccepted") != "false":
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Неподходящий статус платежа")
    if payment.status == "paid":
        return Response(status_code=status.HTTP_200_OK)
    # YooMoney may deliver a valid confirmation late. Once its signature,
    # amount, currency and operation id are verified below, honor the payment
    # even if the checkout URL expired or was superseded in the meantime.
    operation_id = values.get("operation_id")
    if not operation_id:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Не указан номер операции")
    try:
        withdrawn = Decimal(values.get("withdraw_amount", ""))
    except Exception as error:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Неверная сумма") from error
    if withdrawn != payment.amount:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Сумма заказа не совпадает")
    existing = db.scalar(
        select(CloudPayment).where(CloudPayment.provider_operation_id == operation_id)
    )
    if existing is not None and existing.id != payment.id:
        raise HTTPException(status.HTTP_409_CONFLICT, "Операция уже обработана")
    subscription = db.scalar(
        select(CloudSubscription).where(
            CloudSubscription.organization_id == payment.organization_id
        )
    )
    if subscription is None:
        subscription = CloudSubscription(
            organization_id=payment.organization_id,
            plan_code=payment.plan_code,
            status="active",
        )
        db.add(subscription)
    now = datetime.now(UTC)
    previous_expiry = subscription.expires_at
    if previous_expiry is not None and previous_expiry.tzinfo is None:
        previous_expiry = previous_expiry.replace(tzinfo=UTC)
    base = previous_expiry if previous_expiry and previous_expiry > now else now
    subscription.plan_code = payment.plan_code
    subscription.status = "active"
    subscription.starts_at = subscription.starts_at or now
    subscription.expires_at = base + timedelta(days=31 if payment.plan_code == "monthly" else 365)
    subscription.payment_provider = "yoomoney"
    subscription.payment_reference = operation_id
    payment.status = "paid"
    payment.provider_operation_id = operation_id
    payment.paid_at = now
    db.commit()
    return Response(status_code=status.HTTP_200_OK)
