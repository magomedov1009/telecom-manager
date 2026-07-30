"""Remove website rows created by the temporary mobile-to-site bridge."""

import argparse

from sqlalchemy import delete, select, update

from app.db.session import SessionLocal
from app.models.clients import Connection, ConnectionMaterial
from app.models.finance import FinanceTransaction
from app.models.inventory import InventoryTransaction
from app.models.mobile_sync import MobileSyncRecord


ENTITY_MODELS = (
    ("finance_transaction", FinanceTransaction),
    ("inventory_transaction", InventoryTransaction),
    ("connection_material", ConnectionMaterial),
    ("connection", Connection),
)


def mapped_ids(db, entity_type: str) -> list[int]:
    return list(
        db.scalars(
            select(MobileSyncRecord.site_id).where(
                MobileSyncRecord.entity_type == entity_type,
                MobileSyncRecord.site_id.is_not(None),
                MobileSyncRecord.entity_id.contains("-"),
            )
        )
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually delete bridge-created website rows.",
    )
    args = parser.parse_args()
    with SessionLocal() as db:
        rows = {name: mapped_ids(db, name) for name, _ in ENTITY_MODELS}
        for name, _ in ENTITY_MODELS:
            print(f"{name}: {len(rows[name])}")
        if not args.apply:
            print("Preview only. Run again with --apply after making a backup.")
            return
        for name, model in ENTITY_MODELS:
            if rows[name]:
                db.execute(delete(model).where(model.id.in_(rows[name])))
        entity_types = [name for name, _ in ENTITY_MODELS]
        db.execute(
            update(MobileSyncRecord)
            .where(
                MobileSyncRecord.entity_type.in_(entity_types),
                MobileSyncRecord.entity_id.contains("-"),
            )
            .values(site_id=None)
        )
        db.commit()
        print("Rollback complete.")


if __name__ == "__main__":
    main()
