# Развёртывание общего облака Telecom Manager

> Облако можно развернуть на том же VPS, что и текущий сайт, или на отдельном.
> В обоих случаях используйте отдельные контейнеры и новую PostgreSQL-базу.
> Не меняйте `HOSTING_MODE` текущего рабочего сервера.

## Что потребуется

- VPS с Docker и Docker Compose (можно использовать текущий сервер, если хватает ресурсов);
- домен, например `cloud.example.ru`, с DNS-записью на VPS;
- HTTPS-прокси (Nginx, Caddy или панель сервера);
- отдельные надёжные пароли PostgreSQL и `APP_SECRET_KEY`;
- кошелёк ЮMoney, тарифы и секрет HTTP-уведомлений.

Для размещения рядом с текущим сайтом задайте облаку отдельный домен или
поддомен. Текущий сайт продолжит слушать свой порт. База облака использует
отдельный закрытый контейнер и том `telecom-manager-cloud-postgres-data`.
Проверьте свободную память VPS перед запуском: облако добавляет ещё приложение
и PostgreSQL.

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
YOOMONEY_FALLBACK_NOTIFICATION_URL=
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
открывает порт приложения только на `127.0.0.1:8001`. Настройте HTTPS-прокси на
`127.0.0.1:8001`. В приложение указывается адрес `https://cloud.example.ru`
без `/login` и `/api/mobile`.

Например, для Caddy создайте `/etc/caddy/Caddyfile`, заменив домен на свой:

```text
cloud.example.ru {
    encode zstd gzip
    reverse_proxy 127.0.0.1:8001
}
```

DNS домена должен указывать на VPS, а входящие порты 80 и 443 должны быть
доступны. После настройки HTTPS проверьте страницы `/privacy-policy` и
`/account-deletion` перед публикацией приложения.

## ЮMoney

Один кошелёк ЮMoney принимает HTTP-уведомления только на один адрес. Если он
уже подключён к pmguard, не заменяйте его адрес на Telecom Manager до настройки
общего маршрутизатора: тот должен распределять уведомления по `label`, сохраняя
их доставку обоим проектам. Номер кошелька и секрет уведомлений можно использовать
из существующей настройки; секрет храните только в `.env` сервера. В этой версии
Telecom Manager принимает свои заказы с меткой `TM...`, а остальные
подписанные уведомления пересылает на адрес из
`YOOMONEY_FALLBACK_NOTIFICATION_URL`. Укажите там текущий URL обработчика pmguard,
проверьте его доступность с VPS и только после этого поменяйте адрес callback в ЮMoney.

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
