#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="${COMPOSE_FILE:-$project_dir/docker-compose.cloud.yml}"
backup_dir="${BACKUP_DIR:-$project_dir/backups}"
remote_dir="${RCLONE_REMOTE_DIR:-}"
local_retention_days="${LOCAL_BACKUP_RETENTION_DAYS:-7}"

die() {
    printf 'Ошибка резервного копирования: %s\n' "$*" >&2
    exit 1
}

[[ -f "$compose_file" ]] || die "не найден Compose-файл: $compose_file"
[[ -f "$project_dir/.env" ]] || die "не найден облачный .env: $project_dir/.env"
[[ "$local_retention_days" =~ ^[1-9][0-9]{0,3}$ ]] \
    || die 'LOCAL_BACKUP_RETENTION_DAYS должно быть целым числом от 1 до 3650'
(( local_retention_days <= 3650 )) \
    || die 'LOCAL_BACKUP_RETENTION_DAYS не может превышать 3650 дней'
command -v docker >/dev/null 2>&1 || die 'не найден docker'
command -v sha256sum >/dev/null 2>&1 || die 'не найден sha256sum'
if [[ -n "$remote_dir" ]]; then
    command -v rclone >/dev/null 2>&1 || die 'не найден rclone'
fi

mkdir -p -- "$backup_dir"
chmod 700 -- "$backup_dir"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="$backup_dir/cloud-backup-$timestamp.dump"
temporary="$backup_dir/.cloud-backup-$timestamp.partial"
cleanup() {
    [[ ! -e "$temporary" ]] || rm -f -- "$temporary"
}
trap cleanup EXIT

docker compose -f "$compose_file" exec -T postgres \
    sh -ec 'pg_dump -Fc -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$temporary" \
    || die 'pg_dump завершился с ошибкой'
[[ -s "$temporary" ]] || die 'pg_dump создал пустой архив'

# Use the same PostgreSQL image/toolchain as the running database to inspect
# the archive before it is retained or uploaded.
docker compose -f "$compose_file" exec -T postgres \
    sh -ec 'archive="$(mktemp)"; trap '\''rm -f -- "$archive"'\'' EXIT; cat > "$archive"; pg_restore --list "$archive" >/dev/null' \
    < "$temporary" \
    || die 'pg_restore не смог прочитать архив'

mv -- "$temporary" "$archive"
chmod 600 -- "$archive"
sha256sum -- "$archive"

if [[ -n "$remote_dir" ]]; then
    remote_archive="${remote_dir%/}/$(basename -- "$archive")"
    rclone copyto --immutable -- "$archive" "$remote_archive" \
        || die "загрузка во внешнее хранилище не удалась; локальный архив сохранён: $archive"
    rclone check --one-way -- "$archive" "$remote_archive" \
        || die "проверка внешней копии не прошла; локальный архив сохранён: $archive"
    printf 'Внешняя копия успешно проверена.\n'
else
    printf 'Создана только локальная копия; внешнее хранилище не настроено.\n'
fi

# Prune only after the new archive has passed pg_restore --list. When an
# off-site remote is configured, the remote checksum check above must also pass.
find "$backup_dir" -maxdepth 1 -type f \
    -name 'cloud-backup-*.dump' \
    -mmin "+$((local_retention_days * 1440))" \
    -print -delete

printf 'Проверенный архив создан: %s\n' "$archive"
