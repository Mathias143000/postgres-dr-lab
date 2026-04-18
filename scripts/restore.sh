#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_env
ensure_artifact_dirs
RESTORE_LOG="$DRILL_DIR/03-restore.log"
: > "$RESTORE_LOG"

log "Stopping primary database before clean restore."
compose stop postgres >/dev/null

log "Recreating data volume $DATA_VOLUME."
docker volume rm -f "$DATA_VOLUME" >/dev/null 2>&1 || true
docker volume create "$DATA_VOLUME" >/dev/null

log "Restoring backup into a clean data volume."
printf '[%s] restoring backup with --type=immediate\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$RESTORE_LOG"
docker run --rm \
  --entrypoint bash \
  -v "${DATA_VOLUME}:/var/lib/postgresql/data" \
  -v "${REPO_VOLUME}:/var/lib/pgbackrest" \
  -v "${ROOT_DIR}/infra/postgres/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf:ro" \
  "${IMAGE_NAME}" \
  -lc "rm -rf /var/lib/postgresql/data/* /var/lib/postgresql/data/.[!.]* /var/lib/postgresql/data/..?* || true; chown -R postgres:postgres /var/lib/postgresql /var/lib/pgbackrest && gosu postgres pgbackrest --stanza=${PGBACKREST_STANZA} --type=immediate --pg1-path=/var/lib/postgresql/data restore" \
  2>&1 \
  | tee -a "$RESTORE_LOG"

log "Starting restored PostgreSQL."
compose up -d postgres >/dev/null
wait_for_postgres

printf '[%s] restore container finished and postgres is healthy again\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$RESTORE_LOG"
log "Restore completed."
