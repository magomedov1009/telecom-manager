"""Replace website clients/connections with the authoritative mobile snapshot."""

import argparse

from sqlalchemy import delete, func, select, update

from app.db.session import SessionLocal
from app.models.clients import Client, Connection, ConnectionMaterial
from app.models.finance import FinanceTransaction
from app.models.inventory import InventoryTransaction
from app.models.mobile_sync import (
    MobileMembership,
    MobileOrganization,
    MobileSyncRecord,
)
from app.routers.mobile_sync import _publish_pending_to_site


ROOT_TYPES = ("client", "connection")
CHILD_TYPES = (
    "connection_material",
    "inventory_transaction",
    "finance_transaction",
)


def active_records(db, organization_id: int, entity_type: str):
    return list(
        db.scalars(
            select(MobileSyncRecord).where(
                MobileSyncRecord.organization_id == organization_id,
                MobileSyncRecord.entity_type == entity_type,
                MobileSyncRecord.deleted_at.is_(None),
            )
        )
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--organization-id", type=int)
    parser.add_argument("--expect-clients", type=int)
    parser.add_argument("--expect-connections", type=int)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    with SessionLocal() as db:
        organization_id = args.organization_id or db.scalar(
            select(MobileOrganization.id).order_by(MobileOrganization.id)
        )
        if organization_id is None:
            raise SystemExit("Mobile organization not found.")
        mobile_clients = active_records(db, organization_id, "client")
        mobile_connections = active_records(db, organization_id, "connection")
        site_clients = db.scalar(select(func.count()).select_from(Client)) or 0
        site_connections = (
            db.scalar(select(func.count()).select_from(Connection)) or 0
        )
        print(f"organization_id: {organization_id}")
        print(f"mobile clients: {len(mobile_clients)}")
        print(f"mobile connections: {len(mobile_connections)}")
        print(f"website clients before: {site_clients}")
        print(f"website connections before: {site_connections}")
        if not args.apply:
            print("Preview only. No database changes were made.")
            return
        if args.expect_clients is None or args.expect_connections is None:
            raise SystemExit(
                "--expect-clients and --expect-connections are required with --apply."
            )
        if len(mobile_clients) != args.expect_clients:
            raise SystemExit(
                f"Aborted: expected {args.expect_clients} mobile clients, "
                f"found {len(mobile_clients)}."
            )
        if len(mobile_connections) != args.expect_connections:
            raise SystemExit(
                f"Aborted: expected {args.expect_connections} mobile connections, "
                f"found {len(mobile_connections)}."
            )
        membership = db.scalar(
            select(MobileMembership)
            .where(MobileMembership.organization_id == organization_id)
            .order_by(MobileMembership.id)
        )
        if membership is None:
            raise SystemExit("Mobile organization has no user.")

        # Remove only connection-owned operational data. Other expenses,
        # extra works and standalone inventory movements remain untouched.
        connection_ids = select(Connection.id)
        db.execute(
            delete(FinanceTransaction).where(
                FinanceTransaction.connection_id.in_(connection_ids)
            )
        )
        db.execute(
            delete(InventoryTransaction).where(
                InventoryTransaction.connection_id.in_(connection_ids)
            )
        )
        db.execute(delete(ConnectionMaterial))
        db.execute(delete(Connection))
        db.execute(delete(Client))

        records = list(
            db.scalars(
                select(MobileSyncRecord).where(
                    MobileSyncRecord.organization_id == organization_id,
                    MobileSyncRecord.entity_type.in_(ROOT_TYPES + CHILD_TYPES),
                )
            )
        )
        reset_ids = []
        for record in records:
            if record.entity_type in ROOT_TYPES:
                reset_ids.append(record.id)
            elif record.payload.get("connection_id") is not None:
                reset_ids.append(record.id)
        if reset_ids:
            db.execute(
                update(MobileSyncRecord)
                .where(MobileSyncRecord.id.in_(reset_ids))
                .values(site_id=None)
            )
        db.flush()
        _publish_pending_to_site(db, organization_id, membership.user_id)
        db.commit()

        print(
            "website clients after: "
            f"{db.scalar(select(func.count()).select_from(Client)) or 0}"
        )
        print(
            "website connections after: "
            f"{db.scalar(select(func.count()).select_from(Connection)) or 0}"
        )
        print("Restore complete.")


if __name__ == "__main__":
    main()
