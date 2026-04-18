#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_env
ensure_artifact_dirs
rm -rf "$DRILL_DIR"
mkdir -p "$DRILL_DIR"

log "Running full disaster recovery drill."
"$ROOT_DIR/scripts/stack-up.sh"
"$ROOT_DIR/scripts/seed-demo.sh"
"$ROOT_DIR/scripts/backup.sh"
"$ROOT_DIR/scripts/simulate-failure.sh" drop-tickets
"$ROOT_DIR/scripts/restore.sh"
"$ROOT_DIR/scripts/verify-restore.sh"

compose ps > "$DRILL_DIR/compose-ps.txt"

log "Full drill completed successfully. Evidence lives in $DRILL_DIR."
