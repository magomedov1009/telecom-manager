"""External YooMoney checkout for the shared cloud service.

The mobile app never receives the wallet's notification secret.  It creates a
short opaque checkout link, then opens it in the system browser.
"""

from datetime import UTC, datetime, timedelta
from decimal import Decimal
import asyncio
import calendar
import hashlib
import hmac
import json
import logging
import secrets
from typing import Annotated
from urllib.parse import parse_qsl, quote, urlencode
from urllib.error import HTTPError, URLError
from urllib.request import (
    HTTPRedirectHandler,
    Request as UrlRequest,
    build_opener,
)

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import HTMLResponse, Response
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db
from app.models.billing import CloudPayment, CloudPaymentReceipt, CloudSubscription
from app.models.mobile_sync import MobileDeviceToken, MobileOrganization
from app.routers.mobile_sync import current_token, require_admin


router = APIRouter(tags=["billing"])
templates = Jinja2Templates(directory="app/templates")
DbSession = Annotated[Session, Depends(get_db)]
YOOMONEY_NOTIFICATION_MAX_BYTES = 16 * 1024
YOOMONEY_NOTIFICATION_MAX_FIELDS = 64
ROBOKASSA_NOTIFICATION_MAX_BYTES = 16 * 1024
ROBOKASSA_NOTIFICATION_MAX_FIELDS = 64
logger = logging.getLogger(__name__)


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


def _ensure_cloud_checkout(
    organization: MobileOrganization,
    provider: str | None = None,
) -> None:
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
    selected_provider = provider or settings.cloud_payment_provider
    if selected_provider not in {"yoomoney", "robokassa"}:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Выбранный способ оплаты не поддерживается",
        )
    if not settings.payment_provider_is_ready(selected_provider):
        provider_label = "ЮMoney" if selected_provider == "yoomoney" else "Robokassa"
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            f"Оплата {provider_label} пока не настроена",
        )


def _utc(value: datetime) -> datetime:
    """Normalize values returned by PostgreSQL and SQLite for comparisons."""
    return value if value.tzinfo is not None else value.replace(tzinfo=UTC)


def _add_billing_months(value: datetime, months: int, anchor_day: int) -> datetime:
    """Add calendar months while keeping the subscription's original day."""
    month_index = value.year * 12 + value.month - 1 + months
    year, zero_based_month = divmod(month_index, 12)
    month = zero_based_month + 1
    day = min(anchor_day, calendar.monthrange(year, month)[1])
    return value.replace(year=year, month=month, day=day)


@router.post("/api/mobile/subscription/checkout", response_model=CheckoutResponse)
def create_checkout(
    payload: CheckoutRequest,
    request: Request,
    db: DbSession,
    token: Annotated[MobileDeviceToken, Depends(current_token)],
) -> CheckoutResponse:
    require_admin(db, token)
    organization = db.scalar(
        select(MobileOrganization)
        .where(MobileOrganization.id == token.organization_id)
        .with_for_update()
    )
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
        provider=settings.cloud_payment_provider,
        status="pending",
    )
    db.add(payment)
    db.commit()
    db.refresh(payment)
    return CheckoutResponse(
        checkout_url=(
            f"{settings.cloud_public_base_url}/billing/checkout/{payment.public_token}"
        ),
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
    organization = db.get(MobileOrganization, payment.organization_id)
    if organization is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Организация не найдена")
    _ensure_cloud_checkout(organization, payment.provider)
    amount = f"{payment.amount:.2f}"
    robokassa_signature = ""
    if payment.provider == "robokassa":
        signature_data = (
            f"{settings.robokassa_merchant_login}:{amount}:"
            f"{payment.id}:{settings.robokassa_password1}"
        )
        robokassa_signature = hashlib.md5(signature_data.encode("utf-8")).hexdigest()
    return templates.TemplateResponse(
        request=request,
        name="billing/checkout.html",
        headers={
            "Cache-Control": "no-store, private",
            "Referrer-Policy": "no-referrer",
        },
        context={
            "app_name": settings.app_name,
            "organization": organization,
            "payment": payment,
            "wallet": settings.yoomoney_wallet,
            "provider": payment.provider,
            "merchant_login": settings.robokassa_merchant_login,
            "robokassa_signature": robokassa_signature,
            "amount": amount,
            "invoice_id": payment.id,
            "success_url": f"{settings.cloud_public_base_url}/billing/complete",
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


def _robokassa_notification_signature(amount: str, invoice_id: str) -> str:
    password = settings.robokassa_password2
    if not password:
        return ""
    return hashlib.md5(
        f"{amount}:{invoice_id}:{password}".encode("utf-8")
    ).hexdigest()


def _credit_successful_payment(
    db: Session,
    payment: CloudPayment,
    operation_id: str,
    amount: Decimal,
    provider: str,
) -> None:
    """Record a confirmed charge once and extend the matching organization."""
    # Different valid checkout orders can be confirmed close together. Locking
    # the organization also serializes the first paid subscription row creation.
    db.scalar(
        select(MobileOrganization.id)
        .where(MobileOrganization.id == payment.organization_id)
        .with_for_update()
    )
    receipt = db.scalar(
        select(CloudPaymentReceipt)
        .where(CloudPaymentReceipt.provider_operation_id == operation_id)
        .with_for_update()
    )
    if receipt is not None:
        if receipt.payment_id != payment.id:
            logger.error(
                "Payment provider operation was already credited to another order",
                extra={
                    "provider": provider,
                    "operation_id_hash": hashlib.sha256(
                        operation_id.encode("utf-8")
                    ).hexdigest(),
                },
            )
        return
    existing = db.scalar(
        select(CloudPayment).where(CloudPayment.provider_operation_id == operation_id)
    )
    if existing is not None:
        if existing.id != payment.id:
            logger.error(
                "Payment provider operation was already credited to another order",
                extra={
                    "provider": provider,
                    "operation_id_hash": hashlib.sha256(
                        operation_id.encode("utf-8")
                    ).hexdigest(),
                },
            )
        # Compatibility with successful payments recorded before receipts.
        return
    subscription = db.scalar(
        select(CloudSubscription)
        .where(CloudSubscription.organization_id == payment.organization_id)
        .with_for_update()
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
    first_paid_period = subscription.status != "active" or not (
        previous_expiry and previous_expiry > now
    )
    base = previous_expiry if previous_expiry and previous_expiry > now else now
    if first_paid_period:
        subscription.starts_at = base
        anchor_day = base.day
    else:
        anchor_day = (subscription.starts_at or base).day
    subscription.plan_code = payment.plan_code
    subscription.status = "active"
    subscription.expires_at = _add_billing_months(
        base,
        1 if payment.plan_code == "monthly" else 12,
        anchor_day,
    )
    subscription.payment_provider = provider
    subscription.payment_reference = operation_id
    db.add(
        CloudPaymentReceipt(
            payment_id=payment.id,
            provider_operation_id=operation_id,
            amount=amount,
            paid_at=now,
        )
    )
    if payment.status != "paid":
        payment.status = "paid"
        payment.provider_operation_id = operation_id
        payment.paid_at = now
    db.commit()


@router.post("/api/billing/robokassa/result", response_class=Response)
async def robokassa_result(request: Request, db: DbSession) -> Response:
    """Verify Robokassa's server-to-server ResultURL payment confirmation."""
    if not settings.robokassa_password2:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Уведомления Robokassa не настроены",
        )
    content_type = (
        request.headers.get("content-type", "")
        .split(";", 1)[0]
        .strip()
        .lower()
    )
    if content_type != "application/x-www-form-urlencoded":
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            "Ожидается форма Robokassa",
        )
    content_length = request.headers.get("content-length")
    if content_length is not None:
        try:
            if int(content_length) > ROBOKASSA_NOTIFICATION_MAX_BYTES:
                raise HTTPException(
                    status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    "Уведомление слишком большое",
                )
        except ValueError as error:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                "Некорректный Content-Length",
            ) from error
    body = bytearray()
    async for chunk in request.stream():
        body.extend(chunk)
        if len(body) > ROBOKASSA_NOTIFICATION_MAX_BYTES:
            raise HTTPException(
                status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                "Уведомление слишком большое",
            )
    try:
        items = parse_qsl(
            body.decode("utf-8"),
            keep_blank_values=True,
            max_num_fields=ROBOKASSA_NOTIFICATION_MAX_FIELDS,
            encoding="utf-8",
            errors="strict",
        )
    except (UnicodeDecodeError, ValueError) as error:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Некорректная форма уведомления",
        ) from error
    keys = [key.casefold() for key, _ in items]
    if len(keys) != len(set(keys)):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Уведомление содержит повторяющиеся поля",
        )
    values = {key.casefold(): value for key, value in items}
    invoice_id = values.get("invid", "")
    amount_text = values.get("outsum", "")
    received_signature = values.get("signaturevalue", "")
    if not invoice_id.isdigit() or not amount_text or not received_signature:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Не указаны обязательные поля оплаты",
        )
    expected_signature = _robokassa_notification_signature(amount_text, invoice_id)
    if not hmac.compare_digest(
        received_signature.casefold(), expected_signature.casefold()
    ):
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            "Неверная подпись уведомления",
        )
    try:
        amount = Decimal(amount_text).quantize(Decimal("0.01"))
        internal_id = int(invoice_id)
    except Exception as error:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Неверная сумма или номер счета",
        ) from error
    payment = db.scalar(
        select(CloudPayment).where(CloudPayment.id == internal_id).with_for_update()
    )
    if payment is None or payment.provider != "robokassa":
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Заказ Robokassa не найден")
    if amount != payment.amount:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Сумма заказа не совпадает",
        )
    operation_id = f"robokassa:{invoice_id}"
    _credit_successful_payment(db, payment, operation_id, amount, "robokassa")
    return Response(
        content=f"OK{invoice_id}",
        media_type="text/plain",
        status_code=status.HTTP_200_OK,
    )


def _forward_yoomoney_notification(url: str, values: dict[str, str]) -> bool:
    body = urlencode(values).encode("utf-8")
    request = UrlRequest(
        url,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        # Forwarding includes payer and operation details. Never let a payment
        # endpoint redirect that payload to another host or downgrade it to HTTP.
        opener = build_opener(_RejectNotificationRedirects())
        with opener.open(request, timeout=10) as response:
            if response.status not in {200, 201}:
                return False
            response_body = response.read(4097)
            if len(response_body) > 4096:
                return False
            result = json.loads(response_body)
            # PMGuard's NestJS POST endpoint returns 201 after successful
            # processing and includes a JSON success flag. The outer
            # YooMoney-facing handler still acknowledges with HTTP 200.
            return isinstance(result, dict) and result.get("success") is True
    except (json.JSONDecodeError, UnicodeDecodeError):
        return False
    except (HTTPError, URLError, TimeoutError):
        return False


class _RejectNotificationRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


@router.post("/api/billing/yoomoney/notification", status_code=status.HTTP_200_OK)
async def yoomoney_notification(request: Request, db: DbSession) -> Response:
    """Accept one signed YooMoney notification and extend access once."""
    if not settings.yoomoney_notification_secret:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Уведомления не настроены")
    if hasattr(request, "stream") and hasattr(request, "headers"):
        content_type = request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
        if content_type != "application/x-www-form-urlencoded":
            raise HTTPException(
                status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                "Ожидается форма уведомления YooMoney",
            )
        content_length = request.headers.get("content-length")
        if content_length is not None:
            try:
                if int(content_length) > YOOMONEY_NOTIFICATION_MAX_BYTES:
                    raise HTTPException(
                        status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        "Уведомление слишком большое",
                    )
            except ValueError as error:
                raise HTTPException(
                    status.HTTP_400_BAD_REQUEST,
                    "Некорректный Content-Length",
                ) from error
        body = bytearray()
        async for chunk in request.stream():
            body.extend(chunk)
            if len(body) > YOOMONEY_NOTIFICATION_MAX_BYTES:
                raise HTTPException(
                    status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    "Уведомление слишком большое",
                )
        try:
            form_items = parse_qsl(
                body.decode("utf-8"),
                keep_blank_values=True,
                max_num_fields=YOOMONEY_NOTIFICATION_MAX_FIELDS,
                encoding="utf-8",
                errors="strict",
            )
        except (UnicodeDecodeError, ValueError) as error:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                "Некорректная форма уведомления",
            ) from error
    else:
        # Lightweight request doubles in unit tests may expose only form().
        form_request = request.form()
        form = await form_request
        multi_items = getattr(form, "multi_items", None)
        form_items = list(multi_items() if multi_items else form.items())
    # FormData is a multi-dict. Silently collapsing duplicate names to a dict
    # can make signature verification and business validation disagree about
    # which amount/label a sender intended. YooMoney sends one value per key.
    form_keys = [str(key) for key, _ in form_items]
    if len(form_keys) != len(set(form_keys)):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Уведомление содержит повторяющиеся поля",
        )
    values = {str(key): str(value) for key, value in form_items}
    if not values or not any(values.values()) or values.get("test_notification") == "true":
        return Response(status_code=status.HTTP_200_OK)
    received_sign = values.get("sign", "")
    expected_sign = _notification_signature(values)
    if not hmac.compare_digest(received_sign, expected_sign):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Неверная подпись уведомления")
    if values.get("notification_type") not in {"p2p-incoming", "card-incoming"}:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Неподдерживаемый тип уведомления",
        )
    if (
        values.get("currency") != "643"
        or values.get("unaccepted") != "false"
        or values.get("codepro") != "false"
    ):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Неподходящий статус платежа",
        )
    label = values.get("label", "")
    payment = db.scalar(
        select(CloudPayment)
        .where(CloudPayment.label == label)
        .with_for_update()
    )
    if payment is None:
        # Dispatch only labels that belong to a configured integration. This
        # prevents an unknown Telecom Manager order from being misrouted.
        fallback_url = settings.yoomoney_fallback_notification_url
        prefixes = tuple(
            value.strip()
            for value in settings.yoomoney_fallback_label_prefixes.split(",")
            if value.strip()
        )
        if not fallback_url or not label or not any(
            label.startswith(prefix) for prefix in prefixes
        ):
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
    # YooMoney may deliver a valid confirmation late. Once its signature,
    # amount, currency and operation id are verified below, honor the payment
    # even if the checkout URL expired or was superseded in the meantime. A
    # reusable form may also result in multiple distinct charges with one label;
    # record and credit every real operation, while deduplicating retries.
    operation_id = values.get("operation_id")
    if not operation_id:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Не указан номер операции")
    try:
        withdrawn = Decimal(values.get("withdraw_amount", ""))
    except Exception as error:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Неверная сумма") from error
    if withdrawn != payment.amount:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Сумма заказа не совпадает")
    if payment.provider != "yoomoney":
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Заказ ЮMoney не найден")
    _credit_successful_payment(db, payment, operation_id, withdrawn, "yoomoney")
    return Response(status_code=status.HTTP_200_OK)
