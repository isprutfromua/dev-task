#!/usr/bin/env bash
# Creates an encrypted, application-consistent restic backup from the Ghost host.
set -euo pipefail
umask 077
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
[[ -f .env ]] || { printf 'Missing %s/.env\n' "$SCRIPT_DIR" >&2; exit 1; }
set -a; . ./.env; set +a
for variable in RESTIC_REPOSITORY RESTIC_PASSWORD; do
  [[ -n ${!variable:-} ]] || { printf '%s is required for backups.\n' "$variable" >&2; exit 1; }
done
command -v docker >/dev/null || { printf 'Docker is required.\n' >&2; exit 1; }
command -v restic >/dev/null || { printf 'Install restic first.\n' >&2; exit 1; }

backup_dir="$(mktemp -d /var/tmp/ghost-backup.XXXXXX)"
cleanup() { rm -rf "$backup_dir"; }
trap cleanup EXIT

log 'Dumping MySQL database'
docker compose exec -T db sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --events ghost' >"$backup_dir/ghost.sql"
log 'Exporting Ghost content volume'
docker run --rm -v ghost_content:/source:ro -v "$backup_dir":/backup alpine:3.21 \
  tar -C /source -czf /backup/ghost-content.tar.gz .
log 'Saving compose metadata and encrypted backup'
cp docker-compose.yml Caddyfile "$backup_dir/"
restic snapshots >/dev/null 2>&1 || restic init
restic backup --tag ghost --tag "$(hostname -s)" "$backup_dir"
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
log 'Backup complete'
