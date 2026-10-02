import hashlib
import unittest
import asyncio
from datetime import UTC, datetime, timedelta
from unittest.mock import MagicMock, patch
from urllib.parse import urlencode
from urllib.request import Request as UrlRequest

from starlette.requests import Request
from fastapi import HTTPException
from sqlalchemy import create_engine, event, func, select
from sqlalchemy.orm import Session

import app.models  # noqa: F401
from app.core.config import settings
from app.core.security import hash_password
from app.db.base import Base
from app.main import create_app
from app.models.billing import CloudPayment, CloudPaymentReceipt, CloudSubscription
from app.models.enums import UserRole
from app.models.mobile_sync import (
    MobileDeviceToken,
    MobileMembership,
    MobileOrganization,
)
from app.models.users import User
from app.routers.billing import (
    CheckoutRequest,
    _RejectNotificationRedirects,
    _forward_yoomoney_notification,
    _add_billing_months,
    _notification_signature,
    checkout_page,
    create_checkout,
    yoomoney_notification,
)
from app.routers.mobile_sync import (
    _subscription_can_sync,
    subscription_payments,
    subscription_status,
)


class BillingTest(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine("sqlite:///:memory:")
        self.next_ids = {}

        @event.listens_for(self.engine, "connect")
        def sqlite_compatibility(connection, _):
            connection.create_function("num_nonnulls", -1, lambda *values: sum(value is not None for value in values))

        self.db = Session(self.engine)

        @event.listens_for(self.db, "before_flush")
        def assign_ids(session, _flush_context, _instances):
            for item in session.new:
                if getattr(item, "id", None) is None:
                    model = type(item)
                    item.id = self.next_ids.get(model, 1)
                    self.next_ids[model] = item.id + 1

        Base.metadata.create_all(self.engine)
        user = User(
            username="cloud-admin",
            full_name="Cloud Admin",
            hashed_password=hash_password("secret"),
            role=UserRole.ADMIN,
            is_active=True,
        )
        self.db.add(user)
        self.db.flush()
        organization = MobileOrganization(name="Новая организация", is_legacy_workspace=False)
        self.db.add(organization)
        self.db.flush()
        self.db.add(MobileMembership(organization_id=organization.id, user_id=user.id, role="admin"))
        self.raw_token = "test-cloud-token"
        self.db.add(
            MobileDeviceToken(
                token_hash=hashlib.sha256(self.raw_token.encode()).hexdigest(),
                organization_id=organization.id,
                user_id=user.id,
                expires_at=datetime.now(UTC) + timedelta(days=1),
            )
        )
        self.db.commit()
        self.token = self.db.scalar(select(MobileDeviceToken))
        self.organization = organization
        self.old = (
            settings.hosting_mode,
            settings.cloud_domain,
            settings.yoomoney_wallet,
            settings.yoomoney_notification_secret,
            settings.cloud_monthly_price,
            settings.cloud_yearly_price,
            settings.cloud_payment_link_minutes,
            settings.yoomoney_fallback_notification_url,
            settings.yoomoney_fallback_label_prefixes,
        )
        settings.hosting_mode = "cloud"
        settings.cloud_domain = "cloud.example.test"
        settings.yoomoney_wallet = "41001111222333"
        settings.yoomoney_notification_secret = "test-secret"
        settings.cloud_monthly_price = 199
        settings.cloud_yearly_price = 1990
        settings.cloud_payment_link_minutes = 60
        settings.yoomoney_fallback_notification_url = (
            "https://pmguard.example.invalid/yoomoney/callback"
        )
        settings.yoomoney_fallback_label_prefixes = "tg_"
        self.app = create_app()

    def tearDown(self) -> None:
        (
            settings.hosting_mode,
            settings.cloud_domain,
            settings.yoomoney_wallet,
            settings.yoomoney_notification_secret,
            settings.cloud_monthly_price,
            settings.cloud_yearly_price,
            settings.cloud_payment_link_minutes,
            settings.yoomoney_fallback_notification_url,
            settings.yoomoney_fallback_label_prefixes,
        ) = self.old
        self.db.close()
        self.engine.dispose()

    def test_notification_signature_matches_yoomoney_official_example(self) -> None:
        values = {
            "notification_type": "p2p-incoming",
            "operation_id": "904035776918098009",
            "amount": "0.99",
            "withdraw_amount": "1.00",
            "currency": "643",
            "datetime": "2014-04-28T16:31:28Z",
            "sender": "41003188981230",
            "codepro": "false",
            "label": "YM.label.12345",
            "test_notification": "false",
            "unaccepted": "false",
            "sha1_hash": "8693ddf402fe5dcc4c4744d466cabada2628148c",
            "lastname": "{% translate %}Иванов{% /translate %}",
            "firstname": "{% translate %}Иван{% /translate %}",
            "fathersname": "{% translate %}Иванович{% /translate %}",
            "email": "address@example.ru",
            "phone": "+79253332211",
            "city": "{% translate %}Москва{% /translate %}",
            "street": "{% translate %}Тверская{% /translate %}",
            "building": "12",
            "suite": "10",
            "flat": "10",
            "zip": "125075",
        }

        with patch.object(settings, "yoomoney_notification_secret", "secret123"):
            signature = _notification_signature(values)

        self.assertEqual(
            signature,
            "092318d12a1249b8ff5cb7b93e1b409a35bfe01eadee9525a147dc977b4eb056",
        )

    def test_yoomoney_notification_limits_streamed_body_even_without_content_length(self) -> None:
        class OversizedNotificationRequest:
            headers = {"content-type": "application/x-www-form-urlencoded"}

            async def stream(self):
                yield b"x" * (16 * 1024)
                yield b"x"

        with self.assertRaises(HTTPException) as rejected:
            asyncio.run(yoomoney_notification(OversizedNotificationRequest(), self.db))

        self.assertEqual(rejected.exception.status_code, 413)

    def test_billing_periods_follow_calendar_and_preserve_anchor_day(self) -> None:
        jan_31 = datetime(2027, 1, 31, tzinfo=UTC)
        february = _add_billing_months(jan_31, 1, anchor_day=31)
        march = _add_billing_months(february, 1, anchor_day=31)
        leap_day = _add_billing_months(
            datetime(2028, 2, 29, tzinfo=UTC),
            12,
            anchor_day=29,
        )

        self.assertEqual(february, datetime(2027, 2, 28, tzinfo=UTC))
        self.assertEqual(march, datetime(2027, 3, 31, tzinfo=UTC))
        self.assertEqual(leap_day, datetime(2029, 2, 28, tzinfo=UTC))

    def test_checkout_is_hidden_and_rejected_without_notification_secret(self) -> None:
        previous_secret = settings.yoomoney_notification_secret
        try:
            checkout_request = Request(
                {
                    "type": "http",
                    "method": "POST",
                    "scheme": "https",
                    "path": "/api/mobile/subscription/checkout",
                    "raw_path": b"/api/mobile/subscription/checkout",
                    "query_string": b"",
                    "headers": [],
                    "client": ("testclient", 50000),
                    "server": ("testserver", 443),
                    "root_path": "",
                    "app": self.app,
                    "router": self.app.router,
                }
            )
            create_checkout(
                CheckoutRequest(plan_code="monthly"),
                checkout_request,
                self.db,
                self.token,
            )
            payment = self.db.scalar(select(CloudPayment))

            settings.yoomoney_notification_secret = None
            status_response = subscription_status(self.db, self.token)
            self.assertFalse(status_response.checkout_available)

            with self.assertRaises(HTTPException) as unavailable:
                create_checkout(
                    CheckoutRequest(plan_code="monthly"),
                    checkout_request,
                    self.db,
                    self.token,
                )
            self.assertEqual(unavailable.exception.status_code, 503)

            page_request = Request(
                {
                    "type": "http",
                    "method": "GET",
                    "scheme": "https",
                    "path": f"/billing/checkout/{payment.public_token}",
                    "raw_path": f"/billing/checkout/{payment.public_token}".encode(),
                    "query_string": b"",
                    "headers": [],
                    "client": ("testclient", 50000),
                    "server": ("testserver", 443),
                    "root_path": "",
                    "app": self.app,
                    "router": self.app.router,
                }
            )
            with self.assertRaises(HTTPException) as unavailable_page:
                checkout_page(payment.public_token, page_request, self.db)
            self.assertEqual(unavailable_page.exception.status_code, 503)
        finally:
            settings.yoomoney_notification_secret = previous_secret

    def test_legacy_and_self_hosted_workspaces_are_never_billed(self) -> None:
        request = Request(
            {
                "type": "http",
                "method": "POST",
                "scheme": "https",
                "path": "/api/mobile/subscription/checkout",
                "raw_path": b"/api/mobile/subscription/checkout",
                "query_string": b"",
                "headers": [(b"host", b"attacker.example.invalid")],
                "client": ("testclient", 50000),
                "server": ("cloud.example.test", 443),
                "root_path": "",
                "app": self.app,
                "router": self.app.router,
            }
        )
        self.organization.is_legacy_workspace = True
        self.db.commit()

        legacy_status = subscription_status(self.db, self.token)
        self.assertEqual(legacy_status.plan_code, "lifetime")
        self.assertTrue(legacy_status.can_sync)
        self.assertFalse(legacy_status.checkout_available)
        with self.assertRaises(HTTPException) as legacy_checkout:
            create_checkout(
                CheckoutRequest(plan_code="monthly"),
                request,
                self.db,
                self.token,
            )
        self.assertEqual(legacy_checkout.exception.status_code, 409)
        self.assertIsNone(self.db.scalar(select(CloudPayment)))

        self.organization.is_legacy_workspace = False
        settings.hosting_mode = "self_hosted"
        self.db.commit()
        self_hosted_status = subscription_status(self.db, self.token)
        self.assertEqual(self_hosted_status.plan_code, "lifetime")
        self.assertTrue(self_hosted_status.can_sync)
        self.assertFalse(self_hosted_status.checkout_available)
        with self.assertRaises(HTTPException) as self_hosted_checkout:
            create_checkout(
                CheckoutRequest(plan_code="monthly"),
                request,
                self.db,
                self.token,
            )
        self.assertEqual(self_hosted_checkout.exception.status_code, 409)
        self.assertIsNone(self.db.scalar(select(CloudPayment)))

    def test_checkout_requires_delivery_for_configured_fallback_labels(self) -> None:
        old_url = settings.yoomoney_fallback_notification_url
        try:
            settings.yoomoney_fallback_notification_url = None
            status_response = subscription_status(self.db, self.token)
            self.assertFalse(status_response.checkout_available)

            request = Request(
                {
                    "type": "http",
                    "method": "POST",
                    "scheme": "https",
                    "path": "/api/mobile/subscription/checkout",
                    "raw_path": b"/api/mobile/subscription/checkout",
                    "query_string": b"",
                    "headers": [],
                    "client": ("testclient", 50000),
                    "server": ("testserver", 443),
                    "root_path": "",
                    "app": self.app,
                    "router": self.app.router,
                }
            )
            with self.assertRaises(HTTPException) as unavailable:
                create_checkout(
                    CheckoutRequest(plan_code="monthly"),
                    request,
                    self.db,
                    self.token,
                )
            self.assertEqual(unavailable.exception.status_code, 503)
        finally:
            settings.yoomoney_fallback_notification_url = old_url

    def test_checkout_form_uses_stored_price_and_documented_fields(self) -> None:
        checkout_request = Request(
            {
                "type": "http",
                "method": "POST",
                "scheme": "https",
                "path": "/api/mobile/subscription/checkout",
                "raw_path": b"/api/mobile/subscription/checkout",
                "query_string": b"",
                "headers": [],
                "client": ("testclient", 50000),
                "server": ("attacker.example.invalid", 443),
                "root_path": "",
                "app": self.app,
                "router": self.app.router,
            }
        )
        result = create_checkout(
            CheckoutRequest(plan_code="yearly"),
            checkout_request,
            self.db,
            self.token,
        )
        payment = self.db.scalar(select(CloudPayment))
        page_request = Request(
            {
                "type": "http",
                "method": "GET",
                "scheme": "https",
                "path": f"/billing/checkout/{payment.public_token}",
                "raw_path": f"/billing/checkout/{payment.public_token}".encode(),
                "query_string": b"",
                "headers": [(b"host", b"attacker.example.invalid")],
                "client": ("testclient", 50000),
                "server": ("cloud.example.test", 443),
                "root_path": "",
                "app": self.app,
                "router": self.app.router,
            }
        )

        response = checkout_page(payment.public_token, page_request, self.db)
        html = response.body.decode("utf-8")

        self.assertEqual(response.headers["cache-control"], "no-store, private")
        self.assertEqual(response.headers["referrer-policy"], "no-referrer")
        self.assertIn("name=\"receiver\" value=\"41001111222333\"", html)
        self.assertIn(f'name="label" value="{payment.label}"', html)
        self.assertIn('name="sum" value="1990.00"', html)
        self.assertNotIn('name="targets"', html)
        self.assertIn("1990.00 ₽", html)
        self.assertEqual(
            result.checkout_url,
            f"https://cloud.example.test/billing/checkout/{payment.public_token}",
        )
        self.assertIn(
            'name="successURL" value="https://cloud.example.test/billing/complete"',
            html,
        )

    def test_open_checkout_keeps_its_original_price_after_tariff_change(self) -> None:
        request = Request(
            {
                "type": "http",
                "method": "POST",
                "scheme": "https",
                "path": "/api/mobile/subscription/checkout",
                "raw_path": b"/api/mobile/subscription/checkout",
                "query_string": b"",
                "headers": [],
                "client": ("testclient", 50000),
                "server": ("cloud.example.test", 443),
                "root_path": "",
                "app": self.app,
                "router": self.app.router,
            }
        )
        previous_price = settings.cloud_monthly_price
        try:
            create_checkout(CheckoutRequest(plan_code="monthly"), request, self.db, self.token)
            payment = self.db.scalar(select(CloudPayment))
            settings.cloud_monthly_price = 299

            page_request = Request(
                {
                    "type": "http",
                    "method": "GET",
                    "scheme": "https",
                    "path": f"/billing/checkout/{payment.public_token}",
                    "raw_path": f"/billing/checkout/{payment.public_token}".encode(),
                    "query_string": b"",
                    "headers": [],
                    "client": ("testclient", 50000),
                    "server": ("cloud.example.test", 443),
                    "root_path": "",
                    "app": self.app,
                    "router": self.app.router,
                }
            )
            response = checkout_page(payment.public_token, page_request, self.db)
            self.assertIn('name="sum" value="199.00"', response.body.decode("utf-8"))

            values = {
                "notification_type": "card-incoming",
                "operation_id": "payment-at-original-price",
                "amount": "193.03",
                "withdraw_amount": "199.00",
                "currency": "643",
                "datetime": "2026-10-02T10:00:00Z",
                "sender": "",
                "codepro": "false",
                "label": payment.label,
                "unaccepted": "false",
            }
            values["sign"] = _notification_signature(values)

            class NotificationRequest:
                async def form(self):
                    return values

            result = asyncio.run(yoomoney_notification(NotificationRequest(), self.db))
            self.assertEqual(result.status_code, 200)
            self.assertEqual(payment.amount, 199)
            self.assertEqual(payment.status, "paid")
        finally:
            settings.cloud_monthly_price = previous_price

    def test_subscription_status_exposes_only_positive_plan_prices(self) -> None:
        original = (
            settings.cloud_monthly_price,
            settings.cloud_yearly_price,
        )
        try:
            for monthly, yearly, expected_monthly, expected_yearly in (
                (0, 1990, None, 1990),
                (199, 0, 199, None),
                (0, 0, None, None),
            ):
                with self.subTest(monthly=monthly, yearly=yearly):
                    settings.cloud_monthly_price = monthly
                    settings.cloud_yearly_price = yearly
                    status_response = subscription_status(self.db, self.token)
                    self.assertEqual(
                        status_response.checkout_available,
                        monthly > 0 or yearly > 0,
                    )
                    self.assertEqual(status_response.monthly_price, expected_monthly)
                    self.assertEqual(status_response.yearly_price, expected_yearly)
        finally:
            settings.cloud_monthly_price, settings.cloud_yearly_price = original

    def test_only_organization_admin_can_create_a_checkout(self) -> None:
        membership = self.db.scalar(select(MobileMembership))
        membership.role = "installer"
        self.db.commit()
        request = Request(
            {
                "type": "http",
                "method": "POST",
                "scheme": "https",
                "path": "/api/mobile/subscription/checkout",
                "raw_path": b"/api/mobile/subscription/checkout",
                "query_string": b"",
                "headers": [],
                "client": ("testclient", 50000),
                "server": ("testserver", 443),
                "root_path": "",
                "app": self.app,
                "router": self.app.router,
            }
        )

        with self.assertRaises(HTTPException) as rejected:
            create_checkout(
                CheckoutRequest(plan_code="monthly"),
                request,
                self.db,
                self.token,
            )
        self.assertEqual(rejected.exception.status_code, 403)

    def test_paid_yoomoney_notification_extends_cloud_access_once(self) -> None:
        request = Request(
            {
                "type": "http",
                "method": "POST",
                "scheme": "https",
                "path": "/api/mobile/subscription/checkout",
                "raw_path": b"/api/mobile/subscription/checkout",
                "query_string": b"",
                "headers": [],
                "client": ("testclient", 50000),
                "server": ("testserver", 443),
                "root_path": "",
                "app": self.app,
                "router": self.app.router,
            }
        )
        response = create_checkout(
            CheckoutRequest(plan_code="monthly"),
            request,
            self.db,
            self.token,
        )
        self.assertIn("/billing/checkout/", response.checkout_url)
        payment = self.db.scalar(select(CloudPayment))
        self.assertEqual(payment.amount, 199)
        values = {
            "notification_type": "card-incoming",
            "operation_id": "operation-1",
            "amount": "193.03",
            "withdraw_amount": "199.00",
            "currency": "643",
            "datetime": "2026-10-01T10:00:00Z",
            "sender": "",
            "codepro": "false",
            "label": payment.label,
            "unaccepted": "false",
        }
        values["sign"] = _notification_signature(values)
        class NotificationRequest:
            headers = {"content-type": "application/x-www-form-urlencoded"}

            async def stream(self):
                yield urlencode(values).encode("utf-8")

        confirmed = asyncio.run(yoomoney_notification(NotificationRequest(), self.db))
        self.assertEqual(confirmed.status_code, 200)
        subscription = self.db.scalar(select(CloudSubscription))
        self.assertEqual(subscription.status, "active")
        self.assertEqual(subscription.plan_code, "monthly")
        self.assertEqual(self.db.scalar(select(CloudPayment)).status, "paid")
        retry = asyncio.run(yoomoney_notification(NotificationRequest(), self.db))
        self.assertEqual(retry.status_code, 200)
        self.assertEqual(self.db.scalar(select(CloudSubscription)).plan_code, "monthly")

    def test_yearly_purchase_extends_the_existing_monthly_term(self) -> None:
        starts_at = datetime(2026, 8, 31, 12, 0, tzinfo=UTC)
        existing_expiry = datetime(2026, 10, 31, 12, 0, tzinfo=UTC)
        subscription = CloudSubscription(
            organization_id=self.organization.id,
            plan_code="monthly",
            status="active",
            starts_at=starts_at,
            expires_at=existing_expiry,
        )
        payment = CloudPayment(
            organization_id=self.organization.id,
            public_token="yearly-renewal-payment",
            label="TM-yearly-renewal",
            plan_code="yearly",
            amount=1990,
            status="pending",
        )
        self.db.add_all([subscription, payment])
        self.db.commit()

        values = {
            "notification_type": "card-incoming",
            "operation_id": "yearly-renewal-operation",
            "amount": "1930.30",
            "withdraw_amount": "1990.00",
            "currency": "643",
            "datetime": "2026-10-02T10:00:00Z",
            "sender": "",
            "codepro": "false",
            "label": payment.label,
            "unaccepted": "false",
        }
        values["sign"] = _notification_signature(values)

        class NotificationRequest:
            async def form(self):
                return values

        response = asyncio.run(yoomoney_notification(NotificationRequest(), self.db))

        self.assertEqual(response.status_code, 200)
        self.db.refresh(subscription)
        self.assertEqual(subscription.plan_code, "yearly")
        resulting_expiry = subscription.expires_at
        if resulting_expiry.tzinfo is None:
            resulting_expiry = resulting_expiry.replace(tzinfo=UTC)
        self.assertEqual(
            resulting_expiry,
            _add_billing_months(existing_expiry, 12, anchor_day=31),
        )

    def test_expired_cloud_subscription_can_create_a_renewal_checkout(self) -> None:
        subscription = CloudSubscription(
            organization_id=self.organization.id,
            plan_code="monthly",
            status="expired",
            starts_at=datetime.now(UTC) - timedelta(days=60),
            expires_at=datetime.now(UTC) - timedelta(days=30),
        )
        self.db.add(subscription)
        self.db.commit()
        request = Request(
            {
                "type": "http",
                "method": "POST",
                "scheme": "https",
                "path": "/api/mobile/subscription/checkout",
                "raw_path": b"/api/mobile/subscription/checkout",
                "query_string": b"",
                "headers": [],
                "client": ("testclient", 50000),
                "server": ("cloud.example.test", 443),
                "root_path": "",
                "app": self.app,
                "router": self.app.router,
            }
        )

        status_response = subscription_status(self.db, self.token)
        checkout = create_checkout(
            CheckoutRequest(plan_code="monthly"),
            request,
            self.db,
            self.token,
        )

        self.assertFalse(status_response.can_sync)
        self.assertTrue(status_response.checkout_available)
        self.assertIn("/billing/checkout/", checkout.checkout_url)
        payment = self.db.scalar(select(CloudPayment))
        self.assertEqual(payment.status, "pending")
        self.assertEqual(payment.plan_code, "monthly")

    def test_distinct_charges_for_one_checkout_are_each_credited_once(self) -> None:
        payment = CloudPayment(
            organization_id=self.organization.id,
            public_token="reused-form-payment",
            label="TM-reused-form",
            plan_code="monthly",
            amount=199,
            status="pending",
        )
        self.db.add(payment)
        self.db.commit()

        class NotificationRequest:
            def __init__(self, values):
                self.values = values

            async def form(self):
                return self.values

        def notify(operation_id: str):
            values = {
                "notification_type": "card-incoming",
                "operation_id": operation_id,
                "amount": "193.03",
                "withdraw_amount": "199.00",
                "currency": "643",
                "datetime": "2026-10-02T10:00:00Z",
                "sender": "",
                "codepro": "false",
                "label": payment.label,
                "unaccepted": "false",
            }
            values["sign"] = _notification_signature(values)
            return asyncio.run(yoomoney_notification(NotificationRequest(values), self.db))

        first = notify("reused-form-operation-one")
        self.assertEqual(first.status_code, 200)
        subscription = self.db.scalar(select(CloudSubscription))
        first_expiry = subscription.expires_at
        if first_expiry.tzinfo is None:
            first_expiry = first_expiry.replace(tzinfo=UTC)

        second = notify("reused-form-operation-two")
        self.assertEqual(second.status_code, 200)
        subscription = self.db.scalar(select(CloudSubscription))
        second_expiry = subscription.expires_at
        if second_expiry.tzinfo is None:
            second_expiry = second_expiry.replace(tzinfo=UTC)
        self.assertEqual(
            second_expiry,
            _add_billing_months(first_expiry, 1, subscription.starts_at.day),
        )
        self.assertEqual(
            self.db.scalar(select(func.count()).select_from(CloudPaymentReceipt)),
            2,
        )
        history = subscription_payments(self.db, self.token)
        self.assertEqual(len(history), 2)
        self.assertTrue(all(item.status == "paid" for item in history))

        retry = notify("reused-form-operation-two")
        self.assertEqual(retry.status_code, 200)
        refreshed = self.db.scalar(select(CloudSubscription))
        retry_expiry = refreshed.expires_at
        if retry_expiry.tzinfo is None:
            retry_expiry = retry_expiry.replace(tzinfo=UTC)
        self.assertEqual(retry_expiry, second_expiry)
        self.assertEqual(
            self.db.scalar(select(func.count()).select_from(CloudPaymentReceipt)),
            2,
        )

    def test_yoomoney_signature_matches_official_documentation_example(self) -> None:
        previous_secret = settings.yoomoney_notification_secret
        settings.yoomoney_notification_secret = "secret123"
        values = {
            "notification_type": "p2p-incoming",
            "operation_id": "904035776918098009",
            "amount": "0.99",
            "withdraw_amount": "1.00",
            "currency": "643",
            "datetime": "2014-04-28T16:31:28Z",
            "sender": "41003188981230",
            "codepro": "false",
            "label": "YM.label.12345",
            "test_notification": "false",
            "unaccepted": "false",
            "lastname": "{% translate %}Иванов{% /translate %}",
            "firstname": "{% translate %}Иван{% /translate %}",
            "fathersname": "{% translate %}Иванович{% /translate %}",
            "email": "address@example.ru",
            "phone": "+79253332211",
            "city": "{% translate %}Москва{% /translate %}",
            "street": "{% translate %}Тверская{% /translate %}",
            "building": "12",
            "suite": "10",
            "flat": "10",
            "zip": "125075",
            "sha1_hash": "8693ddf402fe5dcc4c4744d466cabada2628148c",
        }

        try:
            self.assertEqual(
                _notification_signature(values),
                "092318d12a1249b8ff5cb7b93e1b409a35bfe01eadee9525a147dc977b4eb056",
            )
        finally:
            settings.yoomoney_notification_secret = previous_secret

    def test_deprecated_sha1_hash_does_not_authenticate_notification(self) -> None:
        values = {
            "notification_type": "p2p-incoming",
            "operation_id": "deprecated-sha1-only",
            "amount": "199.00",
            "currency": "643",
            "label": "TMdeprecated-signature",
            "sha1_hash": "8693ddf402fe5dcc4c4744d466cabada2628148c",
        }

        class NotificationRequest:
            async def form(self):
                return values

        with self.assertRaises(HTTPException) as rejected:
            asyncio.run(yoomoney_notification(NotificationRequest(), self.db))

        self.assertEqual(rejected.exception.status_code, 401)
        self.assertEqual(
            self.db.scalar(select(func.count()).select_from(CloudPaymentReceipt)),
            0,
        )

    def test_yoomoney_rejects_signed_non_payment_notifications(self) -> None:
        values = {
            "notification_type": "operation-debit",
            "operation_id": "operation-debit-1",
            "label": "TMnot-a-payment",
        }
        values["sign"] = _notification_signature(values)

        class NotificationRequest:
            async def form(self):
                return values

        with self.assertRaises(HTTPException) as rejected:
            asyncio.run(yoomoney_notification(NotificationRequest(), self.db))
        self.assertEqual(rejected.exception.status_code, 422)

    def test_yoomoney_rejects_duplicate_notification_fields(self) -> None:
        class DuplicateForm:
            def multi_items(self):
                return [
                    ("notification_type", "card-incoming"),
                    ("notification_type", "p2p-incoming"),
                    ("test_notification", "true"),
                ]

        class NotificationRequest:
            async def form(self, **_kwargs):
                return DuplicateForm()

        with self.assertRaises(HTTPException) as rejected:
            asyncio.run(yoomoney_notification(NotificationRequest(), self.db))

        self.assertEqual(rejected.exception.status_code, 422)

    def test_yoomoney_test_notification_is_acknowledged_without_payment_side_effects(self) -> None:
        payment = CloudPayment(
            organization_id=self.organization.id,
            public_token="test-notification-payment",
            label="TMtest-notification",
            plan_code="monthly",
            amount=199,
            status="pending",
        )
        self.db.add(payment)
        self.db.commit()

        class NotificationRequest:
            async def form(self):
                return {
                    "notification_type": "p2p-incoming",
                    "label": payment.label,
                    "test_notification": "true",
                }

        with patch("app.routers.billing._forward_yoomoney_notification") as forward:
            response = asyncio.run(yoomoney_notification(NotificationRequest(), self.db))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.db.get(CloudPayment, payment.id).status, "pending")
        self.assertIsNone(self.db.scalar(select(CloudSubscription)))
        forward.assert_not_called()

    def test_yoomoney_rejects_amount_mismatch_without_activating_subscription(self) -> None:
        payment = CloudPayment(
            organization_id=self.organization.id,
            public_token="wrong-amount-payment",
            label="TMwrong-amount",
            plan_code="monthly",
            amount=199,
            status="pending",
        )
        self.db.add(payment)
        self.db.commit()
        values = {
            "notification_type": "card-incoming",
            "operation_id": "wrong-amount-operation",
            "amount": "193.03",
            "withdraw_amount": "198.99",
            "currency": "643",
            "datetime": "2026-10-01T10:00:00Z",
            "sender": "",
            "codepro": "false",
            "label": payment.label,
            "unaccepted": "false",
        }
        values["sign"] = _notification_signature(values)

        class NotificationRequest:
            async def form(self):
                return values

        with self.assertRaises(HTTPException) as rejected:
            asyncio.run(yoomoney_notification(NotificationRequest(), self.db))

        self.assertEqual(rejected.exception.status_code, 422)
        self.assertEqual(self.db.get(CloudPayment, payment.id).status, "pending")
        self.assertIsNone(self.db.scalar(select(CloudSubscription)))

    def test_yoomoney_operation_id_cannot_be_reused_for_another_order(self) -> None:
        first_payment = CloudPayment(
            organization_id=self.organization.id,
            public_token="already-paid-order",
            label="TMalready-paid-order",
            plan_code="monthly",
            amount=199,
            status="paid",
            provider_operation_id="reused-operation-id",
        )
        second_payment = CloudPayment(
            organization_id=self.organization.id,
            public_token="second-order",
            label="TMsecond-order",
            plan_code="yearly",
            amount=1990,
            status="pending",
        )
        self.db.add_all([first_payment, second_payment])
        self.db.commit()
        values = {
            "notification_type": "card-incoming",
            "operation_id": "reused-operation-id",
            "amount": "1930.30",
            "withdraw_amount": "1990.00",
            "currency": "643",
            "datetime": "2026-10-01T10:00:00Z",
            "sender": "",
            "codepro": "false",
            "label": second_payment.label,
            "unaccepted": "false",
        }
        values["sign"] = _notification_signature(values)

        class NotificationRequest:
            async def form(self):
                return values

        response = asyncio.run(yoomoney_notification(NotificationRequest(), self.db))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.db.get(CloudPayment, second_payment.id).status, "pending")
        self.assertIsNone(self.db.scalar(select(CloudSubscription)))

    def test_new_checkout_supersedes_previous_pending_link(self) -> None:
        request = Request(
            {
                "type": "http", "method": "POST", "scheme": "https",
                "path": "/api/mobile/subscription/checkout", "raw_path": b"/api/mobile/subscription/checkout",
                "query_string": b"", "headers": [], "client": ("testclient", 50000),
                "server": ("testserver", 443), "root_path": "", "app": self.app,
                "router": self.app.router,
            }
        )
        create_checkout(CheckoutRequest(plan_code="monthly"), request, self.db, self.token)
        create_checkout(CheckoutRequest(plan_code="yearly"), request, self.db, self.token)
        payments = list(self.db.scalars(select(CloudPayment).order_by(CloudPayment.id)))
        self.assertEqual([payment.status for payment in payments], ["superseded", "pending"])
        old_checkout_request = Request(
            {
                "type": "http",
                "method": "GET",
                "scheme": "https",
                "path": f"/billing/checkout/{payments[0].public_token}",
                "raw_path": f"/billing/checkout/{payments[0].public_token}".encode(),
                "query_string": b"",
                "headers": [],
                "client": ("testclient", 50000),
                "server": ("cloud.example.test", 443),
                "root_path": "",
                "app": self.app,
                "router": self.app.router,
            }
        )
        with self.assertRaises(HTTPException) as unavailable:
            checkout_page(payments[0].public_token, old_checkout_request, self.db)
        self.assertEqual(unavailable.exception.status_code, 404)

    def test_expired_checkout_link_is_disabled(self) -> None:
        payment = CloudPayment(
            organization_id=self.organization.id,
            public_token="expired-token",
            label="TMexpired",
            plan_code="monthly",
            amount=199,
            status="pending",
            created_at=datetime.now(UTC) - timedelta(minutes=61),
        )
        self.db.add(payment)
        self.db.commit()
        request = Request(
            {
                "type": "http", "method": "GET", "scheme": "https", "path": "/billing/checkout/expired-token",
                "raw_path": b"/billing/checkout/expired-token", "query_string": b"", "headers": [],
                "client": ("testclient", 50000), "server": ("testserver", 443), "root_path": "", "app": self.app,
                "router": self.app.router,
            }
        )
        with self.assertRaises(HTTPException) as raised:
            checkout_page("expired-token", request, self.db)
        self.assertEqual(raised.exception.status_code, 410)
        self.assertEqual(self.db.get(CloudPayment, payment.id).status, "expired")

    def test_late_notification_for_expired_order_honors_confirmed_payment(self) -> None:
        payment = CloudPayment(
            organization_id=self.organization.id,
            public_token="expired-payment-token",
            label="TMexpired-payment",
            plan_code="monthly",
            amount=199,
            status="pending",
            created_at=datetime.now(UTC) - timedelta(minutes=61),
        )
        self.db.add(payment)
        self.db.commit()
        values = {
            "notification_type": "card-incoming",
            "operation_id": "expired-operation",
            "amount": "193.03",
            "withdraw_amount": "199.00",
            "currency": "643",
            "datetime": "2026-10-01T10:00:00Z",
            "sender": "",
            "codepro": "false",
            "label": payment.label,
            "unaccepted": "false",
        }
        values["sign"] = _notification_signature(values)

        class NotificationRequest:
            async def form(self):
                return values

        response = asyncio.run(yoomoney_notification(NotificationRequest(), self.db))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.db.get(CloudPayment, payment.id).status, "paid")
        subscription = self.db.scalar(select(CloudSubscription))
        self.assertEqual(subscription.status, "active")
        expiry = subscription.expires_at
        if expiry.tzinfo is None:
            expiry = expiry.replace(tzinfo=UTC)
        self.assertGreater(expiry, datetime.now(UTC))
        self.assertTrue(_subscription_can_sync(self.organization, subscription))

    def test_payment_after_subscription_expired_starts_term_now_and_restores_sync(self) -> None:
        subscription = CloudSubscription(
            organization_id=self.organization.id,
            plan_code="monthly",
            status="active",
            starts_at=datetime.now(UTC) - timedelta(days=90),
            expires_at=datetime.now(UTC) - timedelta(days=60),
        )
        self.db.add(subscription)
        payment = CloudPayment(
            organization_id=self.organization.id,
            public_token="expired-subscription-payment",
            label="TM-expired-subscription",
            plan_code="monthly",
            amount=199,
            status="pending",
        )
        self.db.add(payment)
        self.db.commit()

        values = {
            "notification_type": "card-incoming",
            "operation_id": "renew-after-expiry",
            "amount": "193.03",
            "withdraw_amount": "199.00",
            "currency": "643",
            "datetime": "2026-10-01T10:00:00Z",
            "sender": "",
            "codepro": "false",
            "label": payment.label,
            "unaccepted": "false",
        }
        values["sign"] = _notification_signature(values)

        class NotificationRequest:
            async def form(self):
                return values

        before_payment = datetime.now(UTC)
        response = asyncio.run(yoomoney_notification(NotificationRequest(), self.db))

        self.assertEqual(response.status_code, 200)
        refreshed = self.db.get(CloudSubscription, subscription.id)
        starts_at = refreshed.starts_at
        expires_at = refreshed.expires_at
        if starts_at.tzinfo is None:
            starts_at = starts_at.replace(tzinfo=UTC)
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=UTC)
        self.assertGreaterEqual(starts_at, before_payment)
        self.assertGreater(expires_at, datetime.now(UTC))
        self.assertTrue(_subscription_can_sync(self.organization, refreshed))

    def test_pmguard_forward_requires_success_json_and_accepted_status(self) -> None:
        response = MagicMock()
        response.status = 201
        response.read.return_value = b'{"success": true, "action": "extended"}'
        response.__enter__.return_value = response
        opener = MagicMock()
        opener.open.return_value = response
        with patch("app.routers.billing.build_opener", return_value=opener):
            self.assertTrue(
                _forward_yoomoney_notification(
                    "https://pmguard.example.invalid/yoomoney/callback",
                    {"label": "tg_123_plan_1_456"},
                )
            )

        response.read.return_value = b'{"success": false, "error": "Bad label"}'
        with patch("app.routers.billing.build_opener", return_value=opener):
            self.assertFalse(
                _forward_yoomoney_notification(
                    "https://pmguard.example.invalid/yoomoney/callback",
                    {"label": "tg_123_plan_1_456"},
                )
            )

        response.status = 201
        response.read.return_value = b'{"success": true}' + b" " * 4097
        with patch("app.routers.billing.build_opener", return_value=opener):
            self.assertFalse(
                _forward_yoomoney_notification(
                    "https://pmguard.example.invalid/yoomoney/callback",
                    {"label": "tg_123_plan_1_456"},
                )
            )

        response.status = 503
        response.read.return_value = b'{"success": true}'
        with patch("app.routers.billing.build_opener", return_value=opener):
            self.assertFalse(
                _forward_yoomoney_notification(
                    "https://pmguard.example.invalid/yoomoney/callback",
                    {"label": "tg_123_plan_1_456"},
                )
            )

    def test_pmguard_forward_rejects_redirects_before_following_them(self) -> None:
        handler = _RejectNotificationRedirects()
        request = UrlRequest(
            "https://pmguard.example.invalid/yoomoney/callback",
            data=b"label=tg_test",
            method="POST",
        )

        redirected = handler.redirect_request(
            request,
            MagicMock(),
            307,
            "Temporary Redirect",
            {},
            "https://other.example.invalid/collect",
        )

        self.assertIsNone(redirected)

    def test_pmguard_notifications_route_only_configured_label_prefixes(self) -> None:
        old_url = settings.yoomoney_fallback_notification_url
        old_prefixes = settings.yoomoney_fallback_label_prefixes
        settings.yoomoney_fallback_notification_url = (
            "https://pmguard.example.invalid/yoomoney/callback"
        )
        settings.yoomoney_fallback_label_prefixes = "tg_"

        class NotificationRequest:
            def __init__(self, values):
                self.values = values

            async def form(self):
                return self.values

        try:
            values = {
                "notification_type": "p2p-incoming",
                "operation_id": "pmguard-operation",
                "amount": "193.03",
                "withdraw_amount": "199.00",
                "currency": "643",
                "datetime": "2026-10-01T10:00:00Z",
                "sender": "",
                "codepro": "false",
                "label": "tg_123_plan_1_456",
                "unaccepted": "false",
            }
            values["sign"] = _notification_signature(values)
            with patch(
                "app.routers.billing._forward_yoomoney_notification",
                return_value=True,
            ) as forward:
                result = asyncio.run(
                    yoomoney_notification(NotificationRequest(values), self.db)
                )
            self.assertEqual(result.status_code, 200)
            forward.assert_called_once_with(
                "https://pmguard.example.invalid/yoomoney/callback",
                values,
            )

            for field, invalid_value in (
                ("currency", "840"),
                ("unaccepted", "true"),
                ("codepro", "true"),
            ):
                original_value = values[field]
                values[field] = invalid_value
                values["sign"] = _notification_signature(values)
                with self.subTest(field=field), patch(
                    "app.routers.billing._forward_yoomoney_notification",
                    return_value=True,
                ) as forward:
                    with self.assertRaises(HTTPException) as raised:
                        asyncio.run(
                            yoomoney_notification(
                                NotificationRequest(values),
                                self.db,
                            )
                        )
                    self.assertEqual(raised.exception.status_code, 422)
                    forward.assert_not_called()
                values[field] = original_value

            values["label"] = "unrelated-order-123"
            values["sign"] = _notification_signature(values)
            with patch(
                "app.routers.billing._forward_yoomoney_notification",
                return_value=True,
            ) as forward:
                with self.assertRaises(HTTPException) as raised:
                    asyncio.run(
                        yoomoney_notification(NotificationRequest(values), self.db)
                    )
            self.assertEqual(raised.exception.status_code, 404)
            forward.assert_not_called()
        finally:
            settings.yoomoney_fallback_notification_url = old_url
            settings.yoomoney_fallback_label_prefixes = old_prefixes

