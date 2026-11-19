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
from app.models.inventory import MaterialDebtSettlement
from app.models.users import User
from app.services.reports import (
    _office_claim_balances,
    material_settlements,
    provider_cards,
    resolve_period,
    rows_for_export,
)
from app.services.clients import ClientDeletionError, delete_client
from app.services.connections import ConnectionError, delete_connection


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
        second_provider = Provider(id=2, name="Optima", is_active=True)
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
        second_warehouse = Warehouse(
            id=2,
            provider_id=2,
            name="Optima",
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
        self.db.add_all([provider, second_provider, user, warehouse, second_warehouse, material, work_type])
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

    def test_material_debt_nets_connection_reversals_and_cross_provider_transfers(self) -> None:
        self.db.add_all([
            InventoryTransaction(
                id=4, warehouse_id=1, material_id=1, user_id=1,
                provider_id=2, operation_type=InventoryTransactionType.ADJUSTMENT,
                quantity=Decimal("-5"), created_at=datetime(2026, 7, 3),
            ),
            InventoryTransaction(
                id=7, warehouse_id=1, material_id=1, user_id=1,
                connection_id=1, provider_id=2,
                operation_type=InventoryTransactionType.CONNECTION,
                quantity=Decimal("-6"), created_at=datetime(2026, 7, 3),
            ),
            InventoryTransaction(
                id=8, warehouse_id=1, material_id=1, user_id=1,
                connection_id=1, provider_id=2,
                operation_type=InventoryTransactionType.ADJUSTMENT,
                quantity=Decimal("2"), created_at=datetime(2026, 7, 3),
            ),
            InventoryTransaction(
                id=9, warehouse_id=1, material_id=1, user_id=1,
                connection_id=1, provider_id=2,
                operation_type=InventoryTransactionType.RETURN,
                quantity=Decimal("1"), created_at=datetime(2026, 7, 3),
            ),
            InventoryTransaction(
                id=5, warehouse_id=1, material_id=1, user_id=1,
                counterpart_warehouse_id=2,
                operation_type=InventoryTransactionType.TRANSFER_OUT,
                quantity=Decimal("-8"), created_at=datetime(2026, 7, 4),
            ),
            InventoryTransaction(
                id=6, warehouse_id=2, material_id=1, user_id=1,
                counterpart_warehouse_id=1,
                operation_type=InventoryTransactionType.TRANSFER_OUT,
                quantity=Decimal("-3"), created_at=datetime(2026, 7, 5),
            ),
        ])
        self.db.commit()

        debts = material_settlements(
            self.db,
            resolve_period("custom", date(2026, 7, 1), date(2026, 7, 31)),
            None,
            None,
        )

        self.assertEqual(len(debts), 1)
        self.assertEqual(debts[0]["debtor"].name, "Optima")
        self.assertEqual(debts[0]["creditor"].name, "ELLKO")
        self.assertEqual(debts[0]["quantity"], Decimal("8"))
        self.assertEqual(debts[0]["connections"], Decimal("3"))
        self.assertEqual(debts[0]["transfers"], Decimal("8"))
        self.assertEqual(debts[0]["offset"], Decimal("3"))

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
        self.assertEqual(len(card["extra_work_items"]), 1)
        self.assertEqual(card["extra_work_items"][0].work_type.name, "Ремонт")
        self.assertEqual(len(card["expense_items"]), 2)
        self.assertEqual(card["unpaid_expenses"], Decimal("0"))
        self.assertEqual(card["office_net"], Decimal("300.00"))
        self.assertEqual(card["unpaid_extra_works"], Decimal("100.00"))
        self.assertEqual(card["material_usage"][0]["quantity"], Decimal("2.000"))
        self.assertEqual(card["onu_usage"], Decimal("2.000"))
        _, headers, rows = rows_for_export(
            self.db, {"provider_cards": [card]}, "providers"
        )
        self.assertNotIn("Сумма подключений", headers)
        self.assertNotIn("Доля монтажника", headers)
        self.assertEqual(len(headers), len(rows[0]))

    def test_monthly_material_debt_carries_forward_until_settled(self) -> None:
        self.db.add_all(
            [
                InventoryTransaction(
                    id=20,
                    warehouse_id=1,
                    material_id=1,
                    user_id=1,
                    provider_id=2,
                    connection_id=1,
                    operation_type=InventoryTransactionType.CONNECTION,
                    quantity=Decimal("-2"),
                    created_at=datetime(2026, 9, 15),
                ),
                InventoryTransaction(
                    id=21,
                    warehouse_id=1,
                    material_id=1,
                    user_id=1,
                    provider_id=2,
                    connection_id=1,
                    operation_type=InventoryTransactionType.CONNECTION,
                    quantity=Decimal("-3"),
                    created_at=datetime(2026, 10, 10),
                ),
                MaterialDebtSettlement(
                    id=1,
                    debtor_provider_id=2,
                    creditor_provider_id=1,
                    material_id=1,
                    user_id=1,
                    quantity=Decimal("1"),
                    created_at=datetime(2026, 10, 20),
                ),
            ]
        )
        self.db.commit()

        debts = material_settlements(
            self.db,
            resolve_period("custom", date(2026, 10, 1), date(2026, 10, 31)),
            None,
            None,
        )

        row = next(row for row in debts if row["material"].name == "ONU")
        self.assertEqual(row["opening_quantity"], Decimal("2.000"))
        self.assertEqual(row["period_added"], Decimal("3.000"))
        self.assertEqual(row["period_settled"], Decimal("1.000"))
        self.assertEqual(row["quantity"], Decimal("4.000"))
        _, headers, exported = rows_for_export(
            self.db,
            {
                "material_settlements": type("Page", (), {"items": debts})(),
                "material_settlement_history": [],
            },
            "material_settlements",
        )
        self.assertEqual(len(headers), len(exported[0]))

    def test_provider_onu_usage_nets_connection_returns(self) -> None:
        self.db.add(
            InventoryTransaction(
                id=22,
                warehouse_id=1,
                material_id=1,
                user_id=1,
                provider_id=1,
                connection_id=1,
                operation_type=InventoryTransactionType.RETURN,
                quantity=Decimal("1"),
                created_at=datetime(2026, 7, 12),
            )
        )
        self.db.commit()
        period = resolve_period("custom", date(2026, 7, 1), date(2026, 7, 31))

        card = provider_cards(self.db, period, 1, None)[0]

        self.assertEqual(card["onu_usage"], Decimal("1.000"))

    def test_delete_connection_is_blocked_after_material_consumption(self) -> None:
        admin = self.db.get(User, 1)
        admin.role = UserRole.ADMIN
        connection = self.db.get(Connection, 1)

        with self.assertRaisesRegex(ConnectionError, "списание материала"):
            delete_connection(self.db, connection=connection, user=admin)

        self.assertIsNotNone(self.db.get(Connection, 1))

    def test_delete_client_is_blocked_after_material_consumption(self) -> None:
        admin = self.db.get(User, 1)
        admin.role = UserRole.ADMIN
        client = self.db.get(Client, 1)

        with self.assertRaisesRegex(ClientDeletionError, "расход материала"):
            delete_client(self.db, client=client, user=admin)

        self.assertIsNotNone(self.db.get(Client, 1))

    def test_admin_can_delete_client_without_material_usage(self) -> None:
        admin = self.db.get(User, 1)
        admin.role = UserRole.ADMIN
        client = Client(
            id=2,
            provider_id=1,
            contract_number="C-2",
            login="client-without-usage",
            address="No materials",
        )
        self.db.add(client)
        self.db.commit()

        delete_client(self.db, client=client, user=admin)

        self.assertIsNone(self.db.get(Client, 2))

    def test_linked_office_payment_clears_only_its_work(self) -> None:
        generic_payment = self.db.get(FinanceTransaction, 2)
        generic_payment.amount = Decimal("100")
        self.db.add(
            FinanceTransaction(
                id=3,
                user_id=1,
                provider_id=1,
                extra_work_id=1,
                amount=Decimal("100"),
                transaction_type=FinanceTransactionType.PAYMENT_FROM_OFFICE,
                created_at=datetime(2026, 7, 25),
            )
        )
        self.db.commit()

        period = resolve_period(
            "custom",
            date(2026, 7, 1),
            date(2026, 7, 31),
        )
        card = provider_cards(self.db, period, 1, None)[0]

        self.assertEqual(card["unpaid_expenses"], Decimal("0"))
        self.assertEqual(card["unpaid_extra_works"], Decimal("100.00"))

    def test_linked_connection_payment_clears_only_that_connection(self) -> None:
        client = Client(
            id=2,
            provider_id=1,
            contract_number="C-2",
            login="free-connection",
            address="Free connection",
        )
        self.db.add(client)
        self.db.flush()
        connection = Connection(
            id=2,
            client_id=client.id,
            warehouse_id=1,
            installer_id=1,
            connection_type=ConnectionType.NEW,
            connection_date=date(2026, 7, 14),
            price=Decimal("0"),
            office_amount=Decimal("0"),
            installer_amount=Decimal("300"),
        )
        self.db.add(
            FinanceTransaction(
                id=3,
                user_id=1,
                provider_id=1,
                connection_id=2,
                amount=Decimal("300"),
                transaction_type=FinanceTransactionType.PAYMENT_FROM_OFFICE,
                created_at=datetime(2026, 7, 15),
            )
        )
        self.db.add(connection)
        self.db.commit()

        claims = _office_claim_balances(self.db, 1, {})

        self.assertEqual(claims[("connection", 2)]["remaining"], Decimal("0"))
        self.assertEqual(claims[("expense", 1)]["remaining"], Decimal("0"))
        self.assertEqual(claims[("extra_work", 1)]["remaining"], Decimal("100"))


if __name__ == "__main__":
    unittest.main()
