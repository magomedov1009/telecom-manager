import unittest
from datetime import date, datetime, timedelta
from decimal import Decimal

from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session

import app.models  # noqa: F401
from app.db.base import Base
from app.models.clients import (
    Client,
    Connection,
    ExtraWork,
    ExtraWorkType,
    Provider,
)
from app.models.enums import (
    ConnectionType,
    ExpenseCategory,
    FinanceTransactionType,
    InventoryItemType,
    InventoryTransactionType,
    MaterialUnit,
    PaidBy,
    UserRole,
)
from app.models.finance import Expense, FinanceTransaction
from app.models.inventory import InventoryTransaction, Material, Warehouse
from app.models.users import User
from app.services.reports import provider_cards, resolve_period


class ReportsSummaryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine("sqlite:///:memory:")

        @event.listens_for(self.engine, "connect")
        def add_postgres_compatibility(connection, _):
            connection.create_function(
                "num_nonnulls",
                -1,
                lambda *values: sum(value is not None for value in values),
            )

        Base.metadata.create_all(self.engine)
        self.db = Session(self.engine)
        provider = Provider(id=1, name="ELLKO", is_active=True)
        user = User(
            id=1,
            username="installer",
            full_name="Installer",
            hashed_password="x",
            role=UserRole.INSTALLER,
            is_active=True,
        )
        warehouse = Warehouse(
            id=1,
            provider_id=1,
            name="ELLKO",
            active=True,
        )
        material = Material(
            id=1,
            name="ONU",
            unit=MaterialUnit.PIECE,
            unit_name="шт.",
            item_type=InventoryItemType.EQUIPMENT,
            active=True,
        )
        work_type = ExtraWorkType(
            id=1,
            name="Ремонт",
            requires_materials=False,
            requires_equipment=False,
            is_active=True,
        )
        self.db.add_all([provider, user, warehouse, material, work_type])
        self.db.flush()
        client = Client(
            id=1,
            provider_id=1,
            contract_number="C-1",
            login="client-1",
            address="Address",
        )
        self.db.add(client)
        self.db.flush()
        connection = Connection(
            id=1,
            client_id=1,
            warehouse_id=1,
            installer_id=1,
            connection_type=ConnectionType.NEW,
            connection_date=date(2026, 7, 10),
            price=Decimal("1000"),
            office_amount=Decimal("300"),
            installer_amount=Decimal("700"),
        )
        self.db.add_all(
            [
                connection,
                Expense(
                    id=1,
                    user_id=1,
                    provider_id=1,
                    category=ExpenseCategory.FUEL,
                    amount=Decimal("100"),
                    paid_by=PaidBy.INSTALLER,
                    created_at=datetime(2026, 7, 11),
                ),
                Expense(
                    id=2,
                    user_id=1,
                    provider_id=1,
                    category=ExpenseCategory.FUEL,
                    amount=Decimal("50"),
                    paid_by=PaidBy.OFFICE,
                    created_at=datetime(2026, 7, 12),
                ),
                ExtraWork(
                    id=1,
                    provider_id=1,
                    work_type_id=1,
                    installer_id=1,
                    work_date=date(2026, 7, 13),
                    amount=Decimal("200"),
                    office_amount=Decimal("0"),
                    installer_amount=Decimal("200"),
                    status="completed",
                ),
                FinanceTransaction(
                    id=1,
                    user_id=1,
                    provider_id=1,
                    amount=Decimal("200"),
                    transaction_type=FinanceTransactionType.EXTRA_WORK,
                    accrual_to=PaidBy.INSTALLER,
                    created_at=datetime(2026, 7, 13),
                ),
                FinanceTransaction(
                    id=2,
                    user_id=1,
                    provider_id=1,
                    amount=Decimal("200"),
                    transaction_type=FinanceTransactionType.PAYMENT_FROM_OFFICE,
                    created_at=datetime(2026, 7, 20),
                ),
                InventoryTransaction(
                    id=1,
                    warehouse_id=1,
                    provider_id=1,
                    material_id=1,
                    connection_id=1,
                    user_id=1,
                    operation_type=InventoryTransactionType.CONNECTION,
                    quantity=Decimal("-2"),
                    created_at=datetime(2026, 7, 10),
                ),
            ]
        )
        self.db.commit()

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def test_previous_month_uses_full_calendar_month(self) -> None:
        today = date.today()
        expected_end = today.replace(day=1) - timedelta(days=1)
        period = resolve_period("previous_month", None, None)
        self.assertEqual(period["date_from"], expected_end.replace(day=1))
        self.assertEqual(period["date_to"], expected_end)

    def test_provider_summary_uses_only_unpaid_office_expenses(self) -> None:
        period = resolve_period(
            "custom",
            date(2026, 7, 1),
            date(2026, 7, 31),
        )
        card = provider_cards(self.db, period, 1, None)[0]

        self.assertEqual(card["connections"], 1)
        self.assertEqual(card["connection_total"], Decimal("1000.00"))
        self.assertEqual(card["office_total"], Decimal("300.00"))
        self.assertEqual(card["installer_total"], Decimal("700.00"))
        self.assertEqual(card["unpaid_expenses"], Decimal("100.00"))
        self.assertEqual(card["office_net"], Decimal("200.00"))
        self.assertEqual(card["unpaid_extra_works"], Decimal("0"))
        self.assertEqual(card["material_usage"][0]["quantity"], Decimal("2.000"))


if __name__ == "__main__":
    unittest.main()
