from decimal import Decimal

from sqlalchemy import CheckConstraint, Enum, ForeignKey, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import BaseModel
from app.models.enums import InventoryTransactionType, MaterialUnit


class Warehouse(BaseModel):
    __tablename__ = "warehouses"

    name: Mapped[str] = mapped_column(String(128), unique=True, index=True, nullable=False)
    active: Mapped[bool] = mapped_column(default=True, nullable=False)

    connections: Mapped[list["Connection"]] = relationship(back_populates="warehouse")
    inventory_transactions: Mapped[list["InventoryTransaction"]] = relationship(
        back_populates="warehouse"
    )


class Material(BaseModel):
    __tablename__ = "materials"

    name: Mapped[str] = mapped_column(String(128), unique=True, index=True, nullable=False)
    unit: Mapped[MaterialUnit] = mapped_column(
        Enum(MaterialUnit, name="material_unit"),
        nullable=False,
    )
    active: Mapped[bool] = mapped_column(default=True, nullable=False)

    connection_materials: Mapped[list["ConnectionMaterial"]] = relationship(
        back_populates="material"
    )
    inventory_transactions: Mapped[list["InventoryTransaction"]] = relationship(
        back_populates="material"
    )


class InventoryTransaction(BaseModel):
    __tablename__ = "inventory_transactions"
    __table_args__ = (
        CheckConstraint("quantity <> 0", name="ck_inventory_transactions_quantity_non_zero"),
    )

    warehouse_id: Mapped[int] = mapped_column(
        ForeignKey("warehouses.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    material_id: Mapped[int] = mapped_column(
        ForeignKey("materials.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    connection_id: Mapped[int | None] = mapped_column(
        ForeignKey("connections.id", ondelete="SET NULL"),
        index=True,
    )
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    operation_type: Mapped[InventoryTransactionType] = mapped_column(
        Enum(InventoryTransactionType, name="inventory_transaction_type"),
        index=True,
        nullable=False,
    )
    quantity: Mapped[Decimal] = mapped_column(Numeric(14, 3), nullable=False)
    comment: Mapped[str | None] = mapped_column(Text)

    warehouse: Mapped["Warehouse"] = relationship(back_populates="inventory_transactions")
    material: Mapped["Material"] = relationship(back_populates="inventory_transactions")
    connection: Mapped["Connection | None"] = relationship(back_populates="inventory_transactions")
    user: Mapped["User"] = relationship(
        back_populates="inventory_transactions",
        foreign_keys=[user_id],
    )
