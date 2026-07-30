import unittest

from sqlalchemy import create_engine, event, func, select
from sqlalchemy.orm import Session

import app.models  # noqa: F401
from app.core.security import hash_password
from app.db.base import Base
from app.models.enums import UserRole
from app.models.clients import Client, Connection, Provider
from app.models.inventory import InventoryTransaction, Material, Warehouse
from app.models.enums import InventoryItemType, MaterialUnit
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
        operational = PushRequest(changes=[PushItem(
            entity_type="client",
            entity_id="018f0000-0000-7000-8000-000000000003",
            operation="upsert",
            version=1,
            payload={"login": "allowed"},
        )])
        self.assertEqual(
            push(operational, self.db, self.token)[0].status,
            "accepted",
        )

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
        installer_token = self.db.scalar(
            select(MobileDeviceToken).where(
                MobileDeviceToken.organization_id == created.id,
                MobileDeviceToken.user_id == invited.user_id,
            )
        )
        with self.assertRaises(HTTPException) as forbidden:
            create_organization(
                CreateOrganizationRequest(name="Запрещено"),
                self.db,
                installer_token,
            )
        self.assertEqual(forbidden.exception.status_code, 403)

        remove_organization_member(
            created.id,
            invited.user_id,
            self.db,
            selected_token,
        )
        self.assertEqual(len(organization_members(created.id, self.db, selected_token)), 1)
        with self.assertRaises(HTTPException) as revoked:
            pull(self.db, installer_token, cursor=0, limit=200)
        self.assertEqual(revoked.exception.status_code, 403)

    def test_mobile_connection_is_published_to_website_tables(self) -> None:
        provider = Provider(name="ELLKO", is_active=True)
        material = Material(
            name="ONU",
            unit=MaterialUnit.PIECE,
            item_type=InventoryItemType.EQUIPMENT,
            active=True,
        )
        self.db.add_all([provider, material])
        self.db.flush()
        warehouse = Warehouse(
            name="ELLKO warehouse",
            provider_id=provider.id,
            active=True,
        )
        self.db.add(warehouse)
        self.db.flush()
        existing_client = Client(
            provider_id=provider.id,
            contract_number="MOBILE-1",
            login="mobile-client",
            address="Old address",
        )
        self.db.add(existing_client)
        self.db.commit()
        login(LoginRequest(username="admin", password="secret", device_name="phone"), self.db)
        token = list(self.db.scalars(select(MobileDeviceToken)))[-1]
        client_id = "018f0000-0000-7000-8000-100000000001"
        connection_id = "018f0000-0000-7000-8000-100000000002"
        changes = [
            PushItem(
                entity_type="client",
                entity_id=client_id,
                operation="upsert",
                version=1,
                payload={
                    "id": client_id,
                    "provider_id": str(provider.id),
                    "contract_number": "MOBILE-1",
                    "login": "mobile-client",
                    "address": "Mobile street",
                },
            ),
            PushItem(
                entity_type="connection",
                entity_id=connection_id,
                operation="upsert",
                version=1,
                payload={
                    "id": connection_id,
                    "client_id": client_id,
                    "warehouse_id": str(warehouse.id),
                    "connection_type": "NEW",
                    "connection_date": "2026-07-30",
                    "price": 1000,
                    "office_amount": 500,
                    "installer_amount": 500,
                },
            ),
            PushItem(
                entity_type="inventory_transaction",
                entity_id="018f0000-0000-7000-8000-100000000003",
                operation="upsert",
                version=1,
                payload={
                    "warehouse_id": str(warehouse.id),
                    "provider_id": str(provider.id),
                    "material_id": str(material.id),
                    "connection_id": connection_id,
                    "operation_type": "CONNECTION",
                    "quantity": -1,
                    "occurred_at": "2026-07-30T00:00:00+00:00",
                },
            ),
        ]
        results = push(PushRequest(changes=changes), self.db, token)
        self.assertTrue(all(item.status == "accepted" for item in results))
        site_client = self.db.scalar(select(Client).where(Client.login == "mobile-client"))
        self.assertIsNotNone(site_client)
        self.assertEqual(
            self.db.scalar(
                select(func.count()).select_from(Client).where(
                    Client.login == "mobile-client"
                )
            ),
            1,
        )
        self.assertEqual(site_client.address, "Mobile street")
        site_connection = self.db.scalar(
            select(Connection).where(Connection.client_id == site_client.id)
        )
        self.assertIsNotNone(site_connection)
        movement = self.db.scalar(
            select(InventoryTransaction).where(
                InventoryTransaction.connection_id == site_connection.id
            )
        )
        self.assertEqual(movement.quantity, -1)


if __name__ == "__main__":
    unittest.main()
