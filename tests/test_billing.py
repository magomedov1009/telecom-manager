import hashlib
import unittest
import asyncio
from datetime import UTC, datetime, timedelta

from starlette.requests import Request
from fastapi import HTTPException
from sqlalchemy import create_engine, event, select
from sqlalchemy.orm import Session

import app.models  # noqa: F401
from app.core.config import settings
from app.core.security import hash_password
from app.db.base import Base
from app.main import create_app
from app.models.billing import CloudPayment, CloudSubscription
from app.models.enums import UserRole
from app.models.mobile_sync import MobileDeviceToken, MobileMembership, MobileOrganization
from app.models.users import User
from app.routers.billing import (
    CheckoutRequest,
    _notification_signature,
    checkout_page,
    create_checkout,
    yoomoney_notification,
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
            settings.yoomoney_wallet,
            settings.yoomoney_notification_secret,
            settings.cloud_monthly_price,
            settings.cloud_yearly_price,
            settings.cloud_payment_link_minutes,
        )
        settings.hosting_mode = "cloud"
        settings.yoomoney_wallet = "41001111222333"
        settings.yoomoney_notification_secret = "test-secret"
        settings.cloud_monthly_price = 199
        settings.cloud_yearly_price = 1990
        settings.cloud_payment_link_minutes = 60
        self.app = create_app()

    def tearDown(self) -> None:
        (
            settings.hosting_mode,
            settings.yoomoney_wallet,
            settings.yoomoney_notification_secret,
            settings.cloud_monthly_price,
            settings.cloud_yearly_price,
            settings.cloud_payment_link_minutes,
        ) = self.old
        self.db.close()
        self.engine.dispose()

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
            async def form(self):
                return values

        confirmed = asyncio.run(yoomoney_notification(NotificationRequest(), self.db))
        self.assertEqual(confirmed.status_code, 200)
        subscription = self.db.scalar(select(CloudSubscription))
        self.assertEqual(subscription.status, "active")
        self.assertEqual(subscription.plan_code, "monthly")
        self.assertEqual(self.db.scalar(select(CloudPayment)).status, "paid")
        retry = asyncio.run(yoomoney_notification(NotificationRequest(), self.db))
        self.assertEqual(retry.status_code, 200)
        self.assertEqual(self.db.scalar(select(CloudSubscription)).plan_code, "monthly")

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

    def test_notification_for_expired_order_does_not_activate_subscription(self) -> None:
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

        with self.assertRaises(HTTPException) as raised:
            asyncio.run(yoomoney_notification(NotificationRequest(), self.db))
        self.assertEqual(raised.exception.status_code, 410)
        self.assertEqual(self.db.get(CloudPayment, payment.id).status, "expired")
        self.assertIsNone(self.db.scalar(select(CloudSubscription)))

