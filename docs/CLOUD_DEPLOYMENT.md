# Развёртывание общего облака Telecom Manager

> Не меняйте `HOSTING_MODE` на текущем рабочем сервере. Облако разворачивается
> на отдельном VPS с новой PostgreSQL-базой. Так действующая организация и её
> данные остаются независимыми и бессрочными.

## Что потребуется

- отдельный VPS с Docker и Docker Compose;
- домен, например `cloud.example.ru`, с DNS-записью на VPS;
- HTTPS-прокси (Nginx, Caddy или панель сервера);
- отдельные надёжные пароли PostgreSQL и `APP_SECRET_KEY`;
- кошелёк ЮMoney, тарифы и секрет HTTP-уведомлений.

## Настройки `.env`

Скопируйте `.env.example` в `.env`, затем задайте:

```text
APP_ENV=production
APP_DEBUG=false
APP_SECRET_KEY=длинная-случайная-строка

POSTGRES_DB=telecom_cloud
POSTGRES_USER=telecom_cloud
POSTGRES_PASSWORD=длинный-уникальный-пароль

HOSTING_MODE=cloud
CLOUD_TRIAL_DAYS=14
CLOUD_MONTHLY_PRICE=0
CLOUD_YEARLY_PRICE=0
CLOUD_PAYMENT_LINK_MINUTES=60
YOOMONEY_WALLET=
YOOMONEY_NOTIFICATION_SECRET=
```

Пока цены или номер кошелька не заполнены, кнопка оплаты в приложении не
появится. Это безопасный режим до окончания настройки.

## Первый запуск

```bash
git clone https://github.com/magomedov1009/telecom-manager.git /opt/telecom-manager-cloud
cd /opt/telecom-manager-cloud
cp .env.example .env
# заполните .env
docker compose -f docker-compose.cloud.yml up -d --build
docker compose -f docker-compose.cloud.yml run --rm app alembic upgrade head
```

Для облака используйте только `docker-compose.cloud.yml`: он запускает приложение
без режима перезагрузки исходников, не публикует PostgreSQL в интернет и
открывает порт приложения только на `127.0.0.1`. Настройте HTTPS-прокси на
`127.0.0.1:8000`. В приложение указывается адрес `https://cloud.example.ru`
без `/login` и `/api/mobile`.

## ЮMoney

В настройках HTTP-уведомлений ЮMoney задайте только один адрес:

```text
https://cloud.example.ru/api/billing/yoomoney/notification
```

Секрет, показанный ЮMoney, заносится исключительно в
`YOOMONEY_NOTIFICATION_SECRET` на сервере. В GitHub, APK и чат его не
отправляют. После изменения `.env` перезапустите приложение:

```bash
docker compose -f docker-compose.cloud.yml up -d --build app
```

## Резервные копии

Ежедневно создавайте резервную копию и отправляйте её во внешнее хранилище:

```bash
cd /opt/telecom-manager-cloud
docker compose -f docker-compose.cloud.yml exec -T postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > cloud-backup-$(date +%F).sql
```

Периодически проверяйте восстановление копии на отдельном сервере. Подписка
заканчивается без удаления данных, но резервные копии всё равно обязательны.

## Обновление

```bash
cd /opt/telecom-manager-cloud
git pull --ff-only origin main
docker compose -f docker-compose.cloud.yml up -d --build app
docker compose -f docker-compose.cloud.yml run --rm app alembic upgrade head
```
