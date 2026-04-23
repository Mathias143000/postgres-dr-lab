#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_env
ensure_artifact_dirs
wait_for_postgres

log "Running full pgBackRest backup."
pgbackrest_exec --type=full backup 2>&1 | tee "$DRILL_DIR/01-backup.log"
pgbackrest_exec info --output=json > "$BACKUP_INFO_FILE"
cp "$BACKUP_INFO_FILE" "$DRILL_DIR/backup-info.json"
"$ROOT_DIR/scripts/report-freshness.sh"

log "Backup metadata stored in $BACKUP_INFO_FILE."
