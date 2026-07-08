from datetime import date
from decimal import Decimal

from sqlalchemy import Boolean, CheckConstraint, Date, Enum, ForeignKey, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import BaseModel
from app.models.enums import ConnectionType


class Provider(BaseModel):
    __tablename__ = "providers"

    name: Mapped[str] = mapped_column(String(128), unique=True, index=True, nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(default=True, nullable=False, index=True)

    clients: Mapped[list["Client"]] = relationship(back_populates="provider")
    extra_works: Mapped[list["ExtraWork"]] = relationship(back_populates="provider")
    expenses: Mapped[list["Expense"]] = relationship(back_populates="provider")
    finance_transactions: Mapped[list["FinanceTransaction"]] = relationship(back_populates="provider")
    inventory_transactions: Mapped[list["InventoryTransaction"]] = relationship(back_populates="provider")


class Client(BaseModel):
    __tablename__ = "clients"

    provider_id: Mapped[int] = mapped_column(
        ForeignKey("providers.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    contract_number: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    login: Mapped[str] = mapped_column(String(128), unique=True, index=True, nullable=False)
    address: Mapped[str] = mapped_column(String(500), nullable=False)
    phone: Mapped[str | None] = mapped_column(String(32), index=True)
    comment: Mapped[str | None] = mapped_column(Text)

    provider: Mapped["Provider"] = relationship(back_populates="clients")
    connections: Mapped[list["Connection"]] = relationship(
        back_populates="client",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )
    extra_works: Mapped[list["ExtraWork"]] = relationship(
        back_populates="client",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )


class Connection(BaseModel):
    __tablename__ = "connections"
    __table_args__ = (
        CheckConstraint("price >= 0", name="ck_connections_price_non_negative"),
        CheckConstraint("office_amount >= 0", name="ck_connections_office_amount_non_negative"),
        CheckConstraint("installer_amount >= 0", name="ck_connections_installer_amount_non_negative"),
    )

    client_id: Mapped[int] = mapped_column(
        ForeignKey("clients.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    warehouse_id: Mapped[int] = mapped_column(
        ForeignKey("warehouses.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    connection_type: Mapped[ConnectionType] = mapped_column(
        Enum(ConnectionType, name="connection_type"),
        index=True,
        nullable=False,
    )
    connection_date: Mapped[date] = mapped_column(Date, index=True, nullable=False)
    installer_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    price: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0, nullable=False)
    office_amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0, nullable=False)
    installer_amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0, nullable=False)
    comment: Mapped[str | None] = mapped_column(Text)

    client: Mapped["Client"] = relationship(back_populates="connections")
    warehouse: Mapped["Warehouse"] = relationship(back_populates="connections")
    installer: Mapped["User"] = relationship(
        back_populates="connections",
        foreign_keys=[installer_id],
    )
    connection_materials: Mapped[list["ConnectionMaterial"]] = relationship(
        back_populates="connection",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )
    inventory_transactions: Mapped[list["InventoryTransaction"]] = relationship(
        back_populates="connection"
    )
    finance_transactions: Mapped[list["FinanceTransaction"]] = relationship(
        back_populates="connection",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )
    extra_works: Mapped[list["ExtraWork"]] = relationship(back_populates="connection")


class ConnectionMaterial(BaseModel):
    __tablename__ = "connection_materials"
    __table_args__ = (
        CheckConstraint("quantity > 0", name="ck_connection_materials_quantity_positive"),
    )

    connection_id: Mapped[int] = mapped_column(
        ForeignKey("connections.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    material_id: Mapped[int] = mapped_column(
        ForeignKey("materials.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    quantity: Mapped[Decimal] = mapped_column(Numeric(14, 3), nullable=False)
    comment: Mapped[str | None] = mapped_column(Text)

    connection: Mapped["Connection"] = relationship(back_populates="connection_materials")
    material: Mapped["Material"] = relationship(back_populates="connection_materials")


class ExtraWorkType(BaseModel):
    __tablename__ = "extra_work_types"

    name: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    default_price: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    default_office_amount: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    requires_materials: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    requires_equipment: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)

    extra_works: Mapped[list["ExtraWork"]] = relationship(back_populates="work_type")


class ExtraWork(BaseModel):
    __tablename__ = "extra_works"

    provider_id: Mapped[int] = mapped_column(
        ForeignKey("providers.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    work_type_id: Mapped[int | None] = mapped_column(
        ForeignKey("extra_work_types.id", ondelete="SET NULL"),
        index=True,
    )
    client_id: Mapped[int] = mapped_column(
        ForeignKey("clients.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    connection_id: Mapped[int | None] = mapped_column(
        ForeignKey("connections.id", ondelete="SET NULL"),
        index=True,
    )
    installer_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    work_date: Mapped[date] = mapped_column(Date, index=True, nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0, nullable=False)
    office_amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0, nullable=False)
    installer_amount: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0, nullable=False)
    extra_expenses: Mapped[Decimal] = mapped_column(Numeric(14, 2), default=0, nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="completed", nullable=False, index=True)
    comment: Mapped[str | None] = mapped_column(Text)

    provider: Mapped["Provider"] = relationship(back_populates="extra_works")
    work_type: Mapped["ExtraWorkType | None"] = relationship(back_populates="extra_works")
    client: Mapped["Client"] = relationship(back_populates="extra_works")
    connection: Mapped["Connection | None"] = relationship(back_populates="extra_works")
    installer: Mapped["User"] = relationship(
        back_populates="extra_works",
        foreign_keys=[installer_id],
    )
    materials: Mapped[list["ExtraWorkMaterial"]] = relationship(
        back_populates="extra_work",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )
    finance_transactions: Mapped[list["FinanceTransaction"]] = relationship(
        back_populates="extra_work",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )


class ExtraWorkMaterial(BaseModel):
    __tablename__ = "extra_work_materials"
    __table_args__ = (
        CheckConstraint("quantity > 0", name="ck_extra_work_materials_quantity_positive"),
    )

    extra_work_id: Mapped[int] = mapped_column(
        ForeignKey("extra_works.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    material_id: Mapped[int] = mapped_column(
        ForeignKey("materials.id", ondelete="RESTRICT"),
        index=True,
        nullable=False,
    )
    quantity: Mapped[Decimal] = mapped_column(Numeric(14, 3), nullable=False)
    comment: Mapped[str | None] = mapped_column(Text)

    extra_work: Mapped["ExtraWork"] = relationship(back_populates="materials")
    material: Mapped["Material"] = relationship()
