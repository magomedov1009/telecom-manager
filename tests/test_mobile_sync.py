import unittest

from sqlalchemy import create_engine, event, select
from sqlalchemy.orm import Session

import app.models  # noqa: F401
from app.core.security import hash_password
from app.db.base import Base
from app.models.enums import UserRole
from app.models.mobile_sync import MobileDeviceToken
from app.models.users import User
from app.routers.mobile_sync import LoginRequest, PushItem, PushRequest, login, pull, push


class MobileSyncTest(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine("sqlite:///:memory:")

        @event.listens_for(self.engine, "connect")
        def add_postgres_compatibility(connection, _):
            connection.create_function("num_nonnulls", -1, lambda *values: sum(value is not None for value in values))

        Base.metadata.create_all(self.engine)
        self.db = Session(self.engine)

        @event.listens_for(self.db, "before_flush")
        def assign_sqlite_ids(session, _flush_context, _instances):
            next_id = 1
            for item in session.new:
                if getattr(item, "id", None) is None:
                    item.id = next_id
                    next_id += 1

        self.db.add(User(
            username="admin",
            full_name="Admin",
            hashed_password=hash_password("secret"),
            role=UserRole.ADMIN,
            is_active=True,
        ))
        self.db.commit()
        login(LoginRequest(username="admin", password="secret", device_name="test"), self.db)
        self.token = self.db.scalar(select(MobileDeviceToken))

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def test_push_is_idempotent_and_pull_uses_cursor(self) -> None:
        request = PushRequest(changes=[PushItem(
            entity_type="provider",
            entity_id="018f0000-0000-7000-8000-000000000001",
            operation="upsert",
            version=1,
            payload={"name": "ELLKO"},
        )])
        self.assertEqual(push(request, self.db, self.token)[0].status, "accepted")
        self.assertEqual(push(request, self.db, self.token)[0].status, "duplicate")
        first_page = pull(self.db, self.token, cursor=0, limit=200)
        self.assertEqual(len(first_page.changes), 1)
        self.assertEqual(first_page.changes[0].payload["name"], "ELLKO")
        self.assertEqual(len(pull(self.db, self.token, cursor=first_page.cursor, limit=200).changes), 0)


if __name__ == "__main__":
    unittest.main()
