# Самостоятельный сервер клиента

Этот вариант предназначен для компании, которая арендует свой VPS или
использует собственный сервер. Синхронизация не требует облачной подписки и
данные остаются на сервере клиента.

## Требования

- Ubuntu 22.04/24.04 или другой Linux-сервер;
- Docker Engine и Docker Compose;
- минимум 2 ГБ оперативной памяти и 20 ГБ диска;
- домен и HTTPS рекомендуются, если устройства будут подключаться извне.

## Установка

```bash
git clone https://github.com/magomedov1009/telecom-manager.git /opt/telecom-manager
cd /opt/telecom-manager
cp .env.example .env
```

В `.env` обязательно замените пароли PostgreSQL и секрет приложения. Оставьте
следующее значение:

```text
HOSTING_MODE=self_hosted
```

Запустите систему:

```bash
docker compose up -d --build
docker compose run --rm app alembic upgrade head
```

После запуска откройте `http://IP_СЕРВЕРА:8000/login`. В мобильном приложении
укажите этот же адрес в разделе «Синхронизация».

## Обновление

```bash
cd /opt/telecom-manager
git pull --ff-only origin main
docker compose up -d --build app
docker compose run --rm app alembic upgrade head
```

## Резервная копия

Создайте копию базы до обновления и храните её вне сервера:

```bash
docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > telecom-manager-backup.sql
```

Восстановление выполняют только в пустую базу после отдельной проверки копии:

```bash
docker compose exec -T postgres psql -U "$POSTGRES_USER" "$POSTGRES_DB" < telecom-manager-backup.sql
```

## Что не требуется

- кошелёк ЮMoney;
- настройка облачных тарифов;
- оплата за синхронизацию через Telecom Manager.

Клиент сам отвечает за сервер, домен, резервные копии и обновления.
