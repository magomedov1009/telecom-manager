"""Read-only audit of the mobile snapshot published to the website."""

import argparse
from collections import Counter

from sqlalchemy import func, select

from app.db.session import SessionLocal
from app.models.clients import (
    Client,
    Connection,
    ConnectionMaterial,
    ExtraWork,
    ExtraWorkMaterial,
    ExtraWorkType,
    Provider,
)
from app.models.finance import Expense, FinanceTransaction
from app.models.inventory import InventoryTransaction, Material, Warehouse
from app.models.mobile_sync import (
    MobileOrganization,
    MobileSyncChange,
    MobileSyncRecord,
)


MODELS = {
    "provider": Provider,
    "warehouse": Warehouse,
    "material": Material,
    "client": Client,
    "connection": Connection,
    "connection_material": ConnectionMaterial,
    "inventory_transaction": InventoryTransaction,
    "finance_transaction": FinanceTransaction,
    "extra_work_type": ExtraWorkType,
    "extra_work": ExtraWork,
    "extra_work_material": ExtraWorkMaterial,
    "expense": Expense,
}

REFERENCES = {
    "warehouse": {"provider_id": "provider"},
    "client": {"provider_id": "provider"},
    "connection": {
        "client_id": "client",
        "warehouse_id": "warehouse",
    },
    "connection_material": {
        "connection_id": "connection",
        "material_id": "material",
    },
    "inventory_transaction": {
        "warehouse_id": "warehouse",
        "counterpart_warehouse_id": "warehouse",
        "provider_id": "provider",
        "material_id": "material",
        "connection_id": "connection",
        "extra_work_id": "extra_work",
    },
    "finance_transaction": {
        "provider_id": "provider",
        "connection_id": "connection",
        "expense_id": "expense",
        "extra_work_id": "extra_work",
    },
    "extra_work": {
        "provider_id": "provider",
        "work_type_id": "extra_work_type",
    },
    "extra_work_material": {
        "extra_work_id": "extra_work",
        "material_id": "material",
    },
    "expense": {"provider_id": "provider"},
}


def audit_restore(db, organization_id: int) -> tuple[list[dict], list[str]]:
    records = list(
        db.scalars(
            select(MobileSyncRecord).where(
                MobileSyncRecord.organization_id == organization_id,
                MobileSyncRecord.deleted_at.is_(None),
                MobileSyncRecord.entity_type.in_(MODELS),
            )
        )
    )
    by_type = {
        entity_type: [item for item in records if item.entity_type == entity_type]
        for entity_type in MODELS
    }
    active_ids = {
        entity_type: {item.entity_id for item in items}
        for entity_type, items in by_type.items()
    }
    rows = []
    errors = []
    for entity_type, model in MODELS.items():
        items = by_type[entity_type]
        site_count = db.scalar(select(func.count()).select_from(model)) or 0
        mapped = [item for item in items if item.site_id is not None]
        site_ids = [item.site_id for item in mapped]
        duplicate_mappings = sum(
            count - 1 for count in Counter(site_ids).values() if count > 1
        )
        broken_mappings = sum(
            1 for item in mapped if db.get(model, item.site_id) is None
        )
        unresolved_references = 0
        for item in items:
            for field, target_type in REFERENCES.get(entity_type, {}).items():
                target_id = item.payload.get(field)
                if target_id is not None and str(target_id) not in active_ids[target_type]:
                    unresolved_references += 1
        rows.append(
            {
                "type": entity_type,
                "phone": len(items),
                "website": site_count,
                "mapped": len(mapped),
                "duplicate_mappings": duplicate_mappings,
                "broken_mappings": broken_mappings,
                "unresolved_references": unresolved_references,
            }
        )
        if len(items) != site_count:
            errors.append(
                f"{entity_type}: phone={len(items)}, website={site_count}"
            )
        if len(mapped) != len(items):
            errors.append(
                f"{entity_type}: {len(items) - len(mapped)} records are not published"
            )
        if duplicate_mappings:
            errors.append(
                f"{entity_type}: {duplicate_mappings} duplicate website mappings"
            )
        if broken_mappings:
            errors.append(
                f"{entity_type}: {broken_mappings} broken website mappings"
            )
        if unresolved_references:
            errors.append(
                f"{entity_type}: {unresolved_references} unresolved references"
            )

    mismatched_changes = (
        db.scalar(
            select(func.count())
            .select_from(MobileSyncChange)
            .join(MobileSyncRecord, MobileSyncRecord.id == MobileSyncChange.record_id)
            .where(
                MobileSyncChange.organization_id == organization_id,
                MobileSyncChange.entity_id != MobileSyncRecord.entity_id,
            )
        )
        or 0
    )
    if mismatched_changes:
        errors.append(
            f"sync log: {mismatched_changes} changes have a wrong mobile UUID"
        )
    return rows, errors


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--organization-id", type=int)
    parser.add_argument("--expect-clients", type=int)
    parser.add_argument("--expect-connections", type=int)
    args = parser.parse_args()

    with SessionLocal() as db:
        organization_id = args.organization_id or db.scalar(
            select(MobileOrganization.id).order_by(MobileOrganization.id)
        )
        if organization_id is None:
            raise SystemExit("Mobile organization not found.")
        rows, errors = audit_restore(db, organization_id)
        print(f"organization_id: {organization_id}")
        print(
            "type                         phone website mapped duplicates broken refs"
        )
        for row in rows:
            print(
                f"{row['type']:<28} "
                f"{row['phone']:>5} {row['website']:>7} {row['mapped']:>6} "
                f"{row['duplicate_mappings']:>10} "
                f"{row['broken_mappings']:>6} "
                f"{row['unresolved_references']:>4}"
            )
        counts = {row["type"]: row["phone"] for row in rows}
        if (
            args.expect_clients is not None
            and counts["client"] != args.expect_clients
        ):
            errors.append(
                f"expected {args.expect_clients} clients, found {counts['client']}"
            )
        if (
            args.expect_connections is not None
            and counts["connection"] != args.expect_connections
        ):
            errors.append(
                "expected "
                f"{args.expect_connections} connections, "
                f"found {counts['connection']}"
            )
        if errors:
            print("\nAUDIT FAILED")
            for error in errors:
                print(f"- {error}")
            raise SystemExit(1)
        print("\nAUDIT PASSED: phone snapshot and website data match.")


if __name__ == "__main__":
    main()
