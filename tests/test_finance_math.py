import unittest
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session

import app.models  # noqa: F401 - registers all metadata
from app.db.base import Base
from app.models.clients import Client, Connection, Provider
from app.models.enums import (
    ConnectionType,
    ExpenseCategory,
    FinanceTransactionType,
    PaidBy,
    UserRole,
)
from app.models.finance import Expense, FinanceTransaction
from app.models.inventory import Warehouse
from app.models.users import User
from app.services.finance import (
    get_expense_summary,
    get_finance_items,
    get_finance_stats,
)


class FinanceMathTest(unittest.TestCase):
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
        self.db.add_all(
            [
                Provider(id=1, name="ELLKO", is_active=True),
                Provider(id=2, name="OTHER", is_active=True),
                User(
                    id=1,
                    username="installer",
                    full_name="Installer",
                    hashed_password="x",
                    role=UserRole.INSTALLER,
                    is_active=True,
                ),
                Expense(
                    id=1,
                    user_id=1,
                    provider_id=1,
                    category=ExpenseCategory.FUEL,
                    amount=Decimal("100"),
                    paid_by=PaidBy.INSTALLER,
                    created_at=datetime(2026, 6, 15),
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
                Expense(
                    id=3,
                    user_id=1,
                    provider_id=2,
                    category=ExpenseCategory.FUEL,
                    amount=Decimal("999"),
                    paid_by=PaidBy.INSTALLER,
                    created_at=datetime(2026, 7, 12),
                ),
            ]
        )
        transactions = [
            (1, 1, "1000", "CONNECTION", "INSTALLER", "2026-06-10"),
            (2, 1, "2000", "CONNECTION", "OFFICE", "2026-06-10"),
            (3, 1, "500", "EXTRA_WORK", "INSTALLER", "2026-06-20"),
            (4, 1, "-100", "EXPENSE", None, "2026-06-15"),
            (5, 1, "-100", "PAYMENT_TO_OFFICE", None, "2026-06-25"),
            (6, 1, "1000", "CONNECTION", "INSTALLER", "2026-07-05"),
            (7, 1, "300", "PAYMENT_FROM_OFFICE", None, "2026-07-10"),
            (8, 1, "-500", "PAYMENT_TO_OFFICE", None, "2026-07-11"),
            (9, 1, "-50", "EXPENSE", None, "2026-07-12"),
            (10, 2, "-999", "EXPENSE", None, "2026-07-12"),
        ]
        for identifier, provider_id, amount, kind, accrual, created_at in transactions:
            self.db.add(
                FinanceTransaction(
                    id=identifier,
                    user_id=1,
                    provider_id=provider_id,
                    amount=Decimal(amount),
                    transaction_type=FinanceTransactionType(kind),
                    accrual_to=PaidBy(accrual) if accrual else None,
                    created_at=datetime.fromisoformat(created_at),
                )
            )
        self.db.commit()

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def test_monthly_totals_and_cumulative_debt(self) -> None:
        filters = {
            "date_from": date(2026, 7, 1),
            "date_to": date(2026, 7, 31),
            "provider_id": 1,
        }
        stats = get_finance_stats(self.db, filters)

        self.assertEqual(stats.installer_accrued, Decimal("1000.00"))
        self.assertEqual(stats.expenses_total, Decimal("50.00"))
        self.assertEqual(stats.profit, Decimal("950.00"))
        self.assertEqual(stats.customer_received, Decimal("1000.00"))
        self.assertEqual(stats.paid_to_office, Decimal("500.00"))
        self.assertEqual(stats.available_installer_cash, Decimal("800.00"))
        self.assertEqual(stats.office_owes_me, Decimal("0"))
        self.assertEqual(stats.i_owe_office, Decimal("1100.00"))

        self.assertEqual(
            get_expense_summary(self.db, filters)["total"],
            Decimal("50.00"),
        )
        self.assertTrue(
            all(item.provider_id == 1 for item in get_finance_items(self.db, filters))
        )

    def test_free_connection_fee_is_office_debt(self) -> None:
        filters = {
            "date_from": date(2026, 7, 1),
            "date_to": date(2026, 7, 31),
            "provider_id": 1,
        }
        balance_before = get_finance_stats(self.db, filters).balance
        warehouse = Warehouse(id=1, name="Main", provider_id=1, active=True)
        client = Client(
            id=1,
            provider_id=1,
            contract_number="free-1",
            login="101336537",
            address="Free office request",
        )
        self.db.add_all([warehouse, client])
        self.db.flush()
        self.db.add(
            Connection(
                id=1,
                client_id=client.id,
                warehouse_id=warehouse.id,
                installer_id=1,
                connection_type=ConnectionType.WITHOUT_MATERIALS,
                connection_date=date(2026, 7, 20),
                price=Decimal("0"),
                office_amount=Decimal("0"),
                installer_amount=Decimal("1000"),
            )
        )
        self.db.commit()

        stats = get_finance_stats(self.db, filters)

        self.assertEqual(stats.balance, balance_before + Decimal("1000"))
        self.assertEqual(stats.office_owes_me, Decimal("0"))
        self.assertEqual(stats.i_owe_office, Decimal("100.00"))


if __name__ == "__main__":
    unittest.main()
