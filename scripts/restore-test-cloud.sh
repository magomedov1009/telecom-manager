#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

die() {
    printf 'Ошибка тестового восстановления: %s\n' "$*" >&2
    exit 1
}

[[ $# -eq 1 ]] || die "укажите путь к архиву: $0 /path/to/cloud-backup.dump"
archive="$1"
[[ -f "$archive" && -r "$archive" && -s "$archive" ]] \
    || die "архив не найден, пуст или недоступен для чтения: $archive"
command -v docker >/dev/null 2>&1 || die 'не найден docker'

image="${POSTGRES_RESTORE_TEST_IMAGE:-postgres:16-alpine}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
container_name="telecom-manager-restore-test-${timestamp}-$$-${RANDOM}"
database="telecom_restore_test"
database_user="telecom_restore_test"
container_started=false

cleanup() {
    if [[ "$container_started" == true ]]; then
        docker rm --force "$container_name" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# This disposable database has no network, published port, or persistent volume.
docker run --detach \
    --network none \
    --name "$container_name" \
    --env POSTGRES_HOST_AUTH_METHOD=trust \
    --env "POSTGRES_DB=$database" \
    --env "POSTGRES_USER=$database_user" \
    "$image" >/dev/null \
    || die 'не удалось запустить изолированный временный PostgreSQL'
container_started=true

ready=false
for _ in {1..60}; do
    # pg_isready can accept connections to PostgreSQL's temporary initdb server
    # before the requested database exists. Verify a real query instead.
    if docker exec "$container_name" psql \
        -U "$database_user" -d "$database" -Atqc 'SELECT 1' >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 1
done
[[ "$ready" == true ]] || die 'временный PostgreSQL не перешёл в состояние готовности'

docker exec --interactive "$container_name" \
    pg_restore --exit-on-error --no-owner --no-privileges \
        -U "$database_user" -d "$database" \
    < "$archive" \
    || die 'PostgreSQL не смог восстановить архив'

table_count="$(docker exec "$container_name" psql \
    -U "$database_user" -d "$database" -Atqc \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'")"
[[ "$table_count" =~ ^[0-9]+$ && "$table_count" -gt 0 ]] \
    || die 'после восстановления в схеме public нет таблиц'

alembic_version="$(docker exec "$container_name" psql \
    -U "$database_user" -d "$database" -Atqc \
    'SELECT version_num FROM alembic_version' 2>/dev/null || true)"
[[ -n "$alembic_version" ]] || die 'после восстановления не найдена версия миграции Alembic'

printf 'Восстановление проверено во временной изолированной БД: версия %s, таблиц %s.\n' \
    "$alembic_version" "$table_count"
