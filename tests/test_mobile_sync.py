import unittest

from sqlalchemy import create_engine, event, select
from sqlalchemy.orm import Session

import app.models  # noqa: F401
from app.core.security import hash_password
from app.db.base import Base
from app.models.enums import UserRole
from app.models.mobile_sync import MobileDeviceToken, MobileMembership
from fastapi import HTTPException
from app.models.users import User
from app.routers.mobile_sync import (
    AddMemberRequest,
    CreateOrganizationRequest,
    LoginRequest,
    PushItem,
    PushRequest,
    add_organization_member,
    create_organization,
    login,
    organization_members,
    organizations,
    pull,
    push,
    remove_organization_member,
)


class MobileSyncTest(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine("sqlite:///:memory:")

        @event.listens_for(self.engine, "connect")
        def add_postgres_compatibility(connection, _):
            connection.create_function("num_nonnulls", -1, lambda *values: sum(value is not None for value in values))

        Base.metadata.create_all(self.engine)
        self.db = Session(self.engine)

        self.next_ids = {}

        @event.listens_for(self.db, "before_flush")
        def assign_sqlite_ids(session, _flush_context, _instances):
            for item in session.new:
                if getattr(item, "id", None) is None:
                    model = type(item)
                    item.id = self.next_ids.get(model, 1)
                    self.next_ids[model] = item.id + 1

        self.db.add(User(
            username="admin",
            full_name="Admin",
            hashed_password=hash_password("secret"),
            role=UserRole.ADMIN,
            is_active=True,
        ))
        self.db.add(User(
            username="installer",
            full_name="Installer",
            hashed_password=hash_password("secret"),
            role=UserRole.INSTALLER,
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
        conflict = PushRequest(changes=[PushItem(
            entity_type="provider",
            entity_id="018f0000-0000-7000-8000-000000000001",
            operation="upsert",
            version=1,
            payload={"name": "CHANGED"},
        )])
        self.assertEqual(push(conflict, self.db, self.token)[0].status, "conflict")
        first_page = pull(self.db, self.token, cursor=0, limit=200)
        self.assertEqual(len(first_page.changes), 1)
        self.assertEqual(first_page.changes[0].payload["name"], "ELLKO")
        self.assertEqual(len(pull(self.db, self.token, cursor=first_page.cursor, limit=200).changes), 0)

    def test_installer_cannot_change_catalogs(self) -> None:
        membership = self.db.scalar(select(MobileMembership))
        membership.role = "installer"
        self.db.commit()
        request = PushRequest(changes=[PushItem(
            entity_type="provider",
            entity_id="018f0000-0000-7000-8000-000000000002",
            operation="upsert",
            version=1,
            payload={"name": "Forbidden"},
        )])
        with self.assertRaises(HTTPException) as error:
            push(request, self.db, self.token)
        self.assertEqual(error.exception.status_code, 403)

    def test_admin_creates_organization_and_invites_member(self) -> None:
        created = create_organization(
            CreateOrganizationRequest(name="Другой город"),
            self.db,
            self.token,
        )
        self.assertEqual(created.name, "Другой город")
        self.assertEqual(len(organizations(self.db, self.token)), 2)

        selected_login = login(
            LoginRequest(
                username="admin",
                password="secret",
                device_name="second",
                organization_id=created.id,
            ),
            self.db,
        )
        selected_token = self.db.scalar(
            select(MobileDeviceToken).where(
                MobileDeviceToken.token_hash.is_not(None),
                MobileDeviceToken.organization_id == created.id,
            )
        )
        self.assertEqual(selected_login.organization_id, created.id)
        invited = add_organization_member(
            created.id,
            AddMemberRequest(username="installer", role="installer"),
            self.db,
            selected_token,
        )
        self.assertEqual(invited.username, "installer")
        self.assertEqual(len(organization_members(created.id, self.db, selected_token)), 2)

        installer_login = login(
            LoginRequest(
                username="installer",
                password="secret",
                device_name="installer-phone",
                organization_id=created.id,
            ),
            self.db,
        )
        self.assertEqual(installer_login.role, "installer")
        self.assertEqual(installer_login.organization_id, created.id)

        remove_organization_member(
            created.id,
            invited.user_id,
            self.db,
            selected_token,
        )
        self.assertEqual(len(organization_members(created.id, self.db, selected_token)), 1)


if __name__ == "__main__":
    unittest.main()
