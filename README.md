# Telecom Manager

Telecom Manager — внутреннее веб-приложение для управления телеком-подключениями, клиентами, материалами, складами, финансами, расходами и дополнительными работами.

## Стек

- Python 3.12
- FastAPI
- SQLAlchemy 2.0
- Alembic
- PostgreSQL
- Jinja2
- Bootstrap 5
- HTMX
- Alpine.js
- Docker / docker compose

## Возможности текущей версии

- Авторизация пользователя.
- Dashboard.
- Вертикальное меню приложения.
- Модуль материалов.
- Расчет остатков только по InventoryTransaction.
- История складских операций.
- Модуль подключений.
- Автоматическое списание материалов при подключении.
- Автоматическое создание финансовой транзакции подключения.
- Запрет отрицательных остатков.

## Структура проекта

```text
telecom-manager/
  alembic/
    versions/              Alembic миграции
  app/
    core/                  Конфигурация, логирование, security
    db/                    SQLAlchemy Base, engine, Session
    dependencies/          FastAPI dependencies
    models/                SQLAlchemy модели и enum
    repositories/          Зарезервировано под слой доступа к данным
    routers/               HTTP маршруты
    schemas/               Зарезервировано под Pydantic схемы
    services/              Бизнес-логика
    static/                CSS, JS, изображения, uploads
    templates/             Jinja2 шаблоны
  docs/                    Дополнительная документация
  logs/                    Логи
  tests/                   Зарезервировано под тесты
```

## Установка

Скопировать env-файл:

```bash
cp .env.example .env
```

Для Windows PowerShell:

```powershell
Copy-Item .env.example .env
```

## Запуск через Docker

```bash
docker compose up -d postgres
docker compose build app
docker compose run --rm app alembic upgrade head
docker compose up app
```

После запуска открыть:

```text
http://localhost:8000/login
```

Данные администратора после миграции:

```text
login: admin
password: admin123
```

## Локальный запуск без Docker

Требуется установленный PostgreSQL.

В `.env` указать:

```text
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=telecom_manager
POSTGRES_USER=telecom_manager
POSTGRES_PASSWORD=telecom_manager_password
```

Установить зависимости:

```bash
python -m pip install -r requirements.txt
```

Применить миграции:

```bash
python -m alembic upgrade head
```

Запустить приложение:

```bash
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

## Alembic

Проверить текущую ревизию:

```bash
python -m alembic current
```

Показать head:

```bash
python -m alembic heads
```

Применить миграции:

```bash
python -m alembic upgrade head
```

Откатить все миграции:

```bash
python -m alembic downgrade base
```

Создать новую миграцию после изменения моделей:

```bash
python -m alembic revision --autogenerate -m "migration name"
```

## База данных

Основные таблицы:

- users
- warehouses
- materials
- inventory_transactions
- clients
- connections
- connection_materials
- finance_transactions
- expenses
- extra_works
- event_logs

Остатки материалов не хранятся отдельным полем. Они вычисляются только по сумме `inventory_transactions.quantity`.

## Справочники seed-данных

Миграция создает склады:

- Эллко
- Оптимасеть

Миграция создает материалы:

- ONU
- Кабель витая пара
- Кабель оптика круглая
- Кабель оптика лапша

Миграция создает администратора:

```text
admin / admin123
```

## Документация проекта

- `PROJECT_SPEC.md` — полная спецификация проекта.
- `CURRENT_STATE.md` — текущее состояние реализации.
- `CHANGELOG.md` — история изменений Sprint 1-3.

## Ограничения текущей среды

Если на машине нет Docker или PostgreSQL, приложение можно проверить только до уровня импорта, шаблонов и локального запуска страниц без обращения к БД. Для полноценной работы нужны PostgreSQL и примененные Alembic миграции.
