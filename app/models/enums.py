from enum import StrEnum


class UserRole(StrEnum):
    ADMIN = "admin"
    OFFICE = "office"
    INSTALLER = "installer"


class PaidBy(StrEnum):
    INSTALLER = "INSTALLER"
    OFFICE = "OFFICE"


class InventoryItemType(StrEnum):
    MATERIAL = "MATERIAL"
    EQUIPMENT = "EQUIPMENT"


class MaterialUnit(StrEnum):
    PIECE = "piece"
    METER = "meter"


class Provider(StrEnum):
    ELLKO = "ELLKO"
    OPTIMASET = "OPTIMASET"


class InventoryTransactionType(StrEnum):
    RECEIPT = "RECEIPT"
    CONNECTION = "CONNECTION"
    TRANSFER_IN = "TRANSFER_IN"
    TRANSFER_OUT = "TRANSFER_OUT"
    RETURN = "RETURN"
    ISSUE_TO_THIRD_PARTY = "ISSUE_TO_THIRD_PARTY"
    WRITE_OFF = "WRITE_OFF"
    ADJUSTMENT = "ADJUSTMENT"


class ConnectionType(StrEnum):
    NEW = "NEW"
    RECONNECT = "RECONNECT"
    ONU_REPLACE = "ONU_REPLACE"
    CABLE_REPLACE = "CABLE_REPLACE"
    WITHOUT_MATERIALS = "WITHOUT_MATERIALS"
    CUSTOM = "CUSTOM"


class FinanceTransactionType(StrEnum):
    CONNECTION = "CONNECTION"
    EXTRA_WORK = "EXTRA_WORK"
    EXPENSE = "EXPENSE"
    PAYMENT_TO_OFFICE = "PAYMENT_TO_OFFICE"
    PAYMENT_FROM_OFFICE = "PAYMENT_FROM_OFFICE"
    ADJUSTMENT = "ADJUSTMENT"


class ExpenseCategory(StrEnum):
    FUEL = "fuel"
    TOOLS = "tools"
    TRANSPORT = "transport"
    COMMUNICATION = "communication"
    OTHER = "other"


class EventAction(StrEnum):
    CREATE = "create"
    UPDATE = "update"
    DELETE = "delete"
    LOGIN = "login"
    LOGOUT = "logout"
    INVENTORY_TRANSACTION = "inventory_transaction"
    FINANCE_OPERATION = "finance_operation"


