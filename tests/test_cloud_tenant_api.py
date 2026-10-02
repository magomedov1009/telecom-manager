from __future__ import annotations

import asyncio
import importlib.util
import json
import unittest
from pathlib import Path
from urllib.parse import urlsplit
from unittest.mock import patch

from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

import app.models  # noqa: F401
from app.core.config import settings
from app.db.base import Base
from app.db.session import get_db
from app.main import create_app
from app.models.enums import UserRole
from app.models.users import User


_BOOTSTRAP_ADMIN_MIGRATION_PATH = (
    Path(__file__).parents[1]
    / "alembic"
    / "versions"
    / "202610040025_clean_cloud_bootstrap_admin.py"
)
_BOOTSTRAP_ADMIN_MIGRATION_SPEC = importlib.util.spec_from_file_location(
    "cloud_tenant_api_bootstrap_admin_migration",
    _BOOTSTRAP_ADMIN_MIGRATION_PATH,
)
assert _BOOTSTRAP_ADMIN_MIGRATION_SPEC is not None
assert _BOOTSTRAP_ADMIN_MIGRATION_SPEC.loader is not None
_BOOTSTRAP_ADMIN_MIGRATION = importlib.util.module_from_spec(
    _BOOTSTRAP_ADMIN_MIGRATION_SPEC
)
_BOOTSTRAP_ADMIN_MIGRATION_SPEC.loader.exec_module(_BOOTSTRAP_ADMIN_MIGRATION)


class ApiResponse:
    def __init__(self, status_code: int, content: bytes) -> None:
        self.status_code = status_code
        self.content = content
        self.text = content.decode("utf-8")

    def json(self):
        return json.loads(self.content)


class CloudTenantApiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )

        @event.listens_for(self.engine, "connect")
        def add_postgres_compatibility(connection, _):
            connection.create_function(
                "num_nonnulls",
                -1,
                lambda *values: sum(value is not None for value in values),
            )

        Base.metadata.create_all(self.engine)
        self.db = Session(self.engine)
        self.next_ids: dict[type, int] = {}

        @event.listens_for(self.db, "before_flush")
        def assign_sqlite_ids(session, _flush_context, _instances):
            for item in session.new:
                if getattr(item, "id", None) is None:
                    model = type(item)
                    item.id = self.next_ids.get(model, 1)
                    self.next_ids[model] = item.id + 1

        self.app = create_app()

        def override_get_db():
            yield self.db

        self.app.dependency_overrides[get_db] = override_get_db
        self.hosting_mode_patch = patch.object(settings, "hosting_mode", "cloud")
        self.hosting_mode_patch.start()

    def request(self, method: str, path: str, *, token: str | None = None,
                payload: dict | None = None) -> ApiResponse:
        parsed = urlsplit(path)
        body = json.dumps(payload).encode("utf-8") if payload is not None else b""
        headers = []
        if payload is not None:
            headers.append((b"content-type", b"application/json"))
        if token is not None:
            headers.append((b"authorization", f"Bearer {token}".encode("ascii")))

        async def send_request() -> ApiResponse:
            request_sent = False
            response_messages = []

            async def receive():
                nonlocal request_sent
                if request_sent:
                    return {"type": "http.disconnect"}
                request_sent = True
                return {
                    "type": "http.request",
                    "body": body,
                    "more_body": False,
                }

            async def send(message):
                response_messages.append(message)

            scope = {
                "type": "http",
                "asgi": {"version": "3.0", "spec_version": "2.3"},
                "http_version": "1.1",
                "method": method,
                "scheme": "https",
                "path": parsed.path,
                "raw_path": parsed.path.encode("utf-8"),
                "query_string": parsed.query.encode("utf-8"),
                "root_path": "",
                "headers": headers,
                "client": ("testclient", 50000),
                "server": ("testserver", 443),
                "app": self.app,
                "router": self.app.router,
                "state": {},
            }
            await self.app(scope, receive, send)
            start = next(
                message
                for message in response_messages
                if message["type"] == "http.response.start"
            )
            content = b"".join(
                message.get("body", b"")
                for message in response_messages
                if message["type"] == "http.response.body"
            )
            return ApiResponse(start["status"], content)

        return asyncio.run(send_request())

    def tearDown(self) -> None:
        self.hosting_mode_patch.stop()
        self.app.dependency_overrides.clear()
        self.db.close()
        self.engine.dispose()

    def test_http_sync_isolates_same_record_id_between_two_organizations(self) -> None:
        first = self.request(
            "POST",
            "/api/mobile/register",
            payload={
                "organization_name": "Организация один",
                "full_name": "Владелец один",
                "username": "tenant-api-one",
                "password": "safe-password",
                "device_name": "phone-one",
            },
        )
        second = self.request(
            "POST",
            "/api/mobile/register",
            payload={
                "organization_name": "Организация два",
                "full_name": "Владелец два",
                "username": "tenant-api-two",
                "password": "safe-password",
                "device_name": "phone-two",
            },
        )
        self.assertEqual(first.status_code, 201, first.text)
        self.assertEqual(second.status_code, 201, second.text)
        first_auth = first.json()
        second_auth = second.json()
        self.assertNotEqual(first_auth["organization_id"], second_auth["organization_id"])

        entity_id = "018f0000-0000-7000-8000-000000000077"

        def push(token: str, name: str) -> None:
            response = self.request(
                "POST",
                "/api/mobile/sync/push",
                token=token,
                payload={
                    "changes": [
                        {
                            "entity_type": "provider",
                            "entity_id": entity_id,
                            "operation": "upsert",
                            "version": 1,
                            "payload": {"name": name},
                        }
                    ]
                },
            )
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual(response.json()[0]["status"], "accepted")

        def pulled_names(token: str) -> dict[str, str]:
            response = self.request(
                "GET",
                "/api/mobile/sync/pull?cursor=0&limit=200",
                token=token,
            )
            self.assertEqual(response.status_code, 200, response.text)
            return {
                item["entity_id"]: item["payload"]["name"]
                for item in response.json()["changes"]
                if item["entity_id"] == entity_id
            }

        push(first_auth["token"], "Только первой организации")
        self.assertEqual(
            pulled_names(first_auth["token"]),
            {entity_id: "Только первой организации"},
        )
        self.assertEqual(pulled_names(second_auth["token"]), {})

        push(second_auth["token"], "Только второй организации")
        self.assertEqual(
            pulled_names(first_auth["token"]),
            {entity_id: "Только первой организации"},
        )
        self.assertEqual(
            pulled_names(second_auth["token"]),
            {entity_id: "Только второй организации"},
        )

    def test_first_cloud_owner_can_register_admin_after_safe_bootstrap_migration(self) -> None:
        seeded_admin = User(
            id=1,
            username="admin",
            full_name="Administrator",
            hashed_password=_BOOTSTRAP_ADMIN_MIGRATION._SEEDED_ADMIN_HASH,
            role=UserRole.ADMIN,
            is_active=True,
        )
        self.db.add(seeded_admin)
        self.db.commit()

        with (
            patch.object(_BOOTSTRAP_ADMIN_MIGRATION.settings, "hosting_mode", "cloud"),
            patch.object(
                _BOOTSTRAP_ADMIN_MIGRATION.settings,
                "bootstrap_clean_cloud_defaults",
                True,
            ),
            patch.object(
                _BOOTSTRAP_ADMIN_MIGRATION.op,
                "get_bind",
                return_value=self.db.connection(),
            ),
        ):
            _BOOTSTRAP_ADMIN_MIGRATION.upgrade()
        self.db.expire_all()

        response = self.request(
            "POST",
            "/api/mobile/register",
            payload={
                "organization_name": "Первая облачная организация",
                "full_name": "Владелец",
                "username": "admin",
                "password": "safe-password",
                "device_name": "first-phone",
            },
        )

        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()["username"], "admin")

    def test_login_route_enforces_shared_ip_attempt_limit(self) -> None:
        payload = {
            "username": "unknown-login-user",
            "password": "wrong-password",
            "device_name": "test-phone",
        }
        for _ in range(30):
            response = self.request("POST", "/api/mobile/login", payload=payload)
            self.assertEqual(response.status_code, 401)

        limited = self.request("POST", "/api/mobile/login", payload=payload)
        self.assertEqual(limited.status_code, 429, limited.text)


if __name__ == "__main__":
    unittest.main()
