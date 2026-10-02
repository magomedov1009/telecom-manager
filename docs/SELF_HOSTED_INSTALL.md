# Самостоятельный сервер клиента

Этот вариант предназначен для компании, которая арендует свой VPS или
использует собственный сервер. Синхронизация не требует облачной подписки и
данные остаются на сервере клиента.

## Требования

- Ubuntu 22.04/24.04 или другой Linux-сервер;
- Docker Engine и Docker Compose;
- минимум 2 ГБ оперативной памяти и 20 ГБ диска;
- домен и HTTPS, если устройства будут подключаться через интернет.

## Установка

```bash
git clone https://github.com/magomedov1009/telecom-manager.git /opt/telecom-manager
cd /opt/telecom-manager
cp .env.example .env
```

В `.env` обязательно задайте отдельные случайные пароли PostgreSQL и приложения,
`APP_ENV=production` и `APP_DEBUG=false`. Для простого безопасного чтения `.env`
используйте случайные пароли из букв, цифр, `_` и `-`; ключ приложения должен
быть не короче 32 символов, пароль PostgreSQL — не короче 24 символов. Оставьте:

```text
HOSTING_MODE=self_hosted
```

Production Compose включает строгую проверку при старте: сервер откажется
запускаться с шаблонным или слишком коротким ключом/паролем либо с включённым
debug. Он включает HTTPS-only флаг для сессионной cookie. Старый
`docker-compose.yml` этой проверкой не затрагивается, чтобы сохранить
совместимость существующей установки.

Только для новой пустой установки установите перед первой миграцией
`BOOTSTRAP_CLEAN_DEMO_PROVIDER_CATALOG=true`: миграция удалит нетронутые
исторические демо-пары на пустой базе. Шаблон `.env.example` выключает эту
операцию по умолчанию. На существующей базе оставьте параметр `false` или
удалите его из `.env`; миграция также пропускает очистку, если обнаруживает
организацию или рабочие записи.

Production-конфигурация не публикует PostgreSQL наружу, не монтирует исходный
код с автоперезагрузкой и открывает приложение только для локального HTTPS-прокси
на `127.0.0.1:8002`. Режим `self_hosted` и адрес собственной БД Compose задаёт
явно, независимо от этих параметров в `.env`. На первом запуске примените
миграции до старта приложения:

```bash
docker compose -f docker-compose.self-hosted.yml build app
docker compose -f docker-compose.self-hosted.yml up -d postgres
docker compose -f docker-compose.self-hosted.yml run --rm app alembic upgrade head
docker compose -f docker-compose.self-hosted.yml up -d app
```

Контейнер приложения работает от отдельного непривилегированного пользователя.

Compose считает приложение готовым после успешного запроса к PostgreSQL через
`/health/ready`; `/health/live` отдельно сообщает, что процесс приложения
запущен.

На новой пустой установке начальные провайдеры «Эллко» и «Оптимасеть» не
создаются: организация добавляет свои провайдеры и склады при первом запуске.
На существующей базе миграции сохраняют провайдеров и рабочие данные.

При чистой установке создаётся начальная учётная запись `admin` / `admin123`.
До публикации сайта выполните вход через SSH-туннель, смените этот пароль в
разделе «Настройки → Пользователи», затем настройте публичный HTTPS-прокси:

```bash
ssh -L 8002:127.0.0.1:8002 user@IP_СЕРВЕРА
```

Пока туннель открыт, на своём компьютере откройте `http://localhost:8002/login`.
Не выставляйте приложение в Интернет с начальным паролем.

Настройте HTTPS-прокси. Например, для Caddy:

```text
telecom.example.ru {
    encode zstd gzip
    reverse_proxy 127.0.0.1:8002
}
```

После настройки откройте `https://telecom.example.ru/login`. В мобильном
приложении укажите `https://telecom.example.ru` в разделе «Синхронизация».
Не открывайте PostgreSQL-порт в firewall; он нужен только приложению внутри
закрытой Docker-сети.

## Обновление

Перед обновлением сохраните архив, проверьте его через `pg_restore --list` и
скопируйте во внешнее хранилище. Затем соберите новый образ, остановите
приложение, выполните миграции и после их успеха запустите новую версию:

```bash
cd /opt/telecom-manager
backup="telecom-manager-backup-$(date +%F-%H%M%S).dump"
docker compose -f docker-compose.self-hosted.yml exec -T postgres sh -c 'pg_dump -Fc -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$backup"
docker compose -f docker-compose.self-hosted.yml exec -T postgres pg_restore --list - < "$backup"
git pull --ff-only origin main
docker compose -f docker-compose.self-hosted.yml build app
docker compose -f docker-compose.self-hosted.yml stop app
docker compose -f docker-compose.self-hosted.yml run --rm app alembic upgrade head
docker compose -f docker-compose.self-hosted.yml up -d app
```

Если миграция завершилась ошибкой, оставьте приложение остановленным и не
запускайте новый код на неизвестной версии схемы. Сохраните текст ошибки;
перед восстановлением проверьте архив и восстанавливайте его только в отдельную
пустую базу.

## Резервная копия

Создайте копию базы до обновления и храните её вне сервера:

```bash
backup="telecom-manager-backup-$(date +%F-%H%M%S).dump"
docker compose -f docker-compose.self-hosted.yml exec -T postgres sh -c 'pg_dump -Fc -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$backup"
docker compose -f docker-compose.self-hosted.yml exec -T postgres pg_restore --list - < "$backup"
```

Файл создаётся на VPS. Команда `pg_restore --list` проверяет читаемость архива,
но не заменяет тестовое восстановление. Скопируйте его во внешнее хранилище
или на защищённый компьютер, например командой `scp`:

```bash
scp user@IP_СЕРВЕРА:/opt/telecom-manager/telecom-manager-backup-ГГГГ-ММ-ДД-ЧЧММСС.dump .
```

Восстановление выполняют только в пустую базу после отдельной проверки копии:

```bash
docker compose -f docker-compose.self-hosted.yml exec -T postgres sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner -' < telecom-manager-backup-ГГГГ-ММ-ДД-ЧЧММСС.dump
```

## Что не требуется

- кошелёк ЮMoney;
- настройка облачных тарифов;
- оплата за синхронизацию через Telecom Manager.

Клиент сам отвечает за сервер, домен, резервные копии и обновления.
