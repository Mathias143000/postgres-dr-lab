#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_env
ensure_artifact_dirs
rm -rf "$DRILL_DIR"
mkdir -p "$DRILL_DIR"

DRILL_START_EPOCH="$(date -u +%s)"
{
  date -u +"started_at=%Y-%m-%dT%H:%M:%SZ"
  echo "started_epoch=$DRILL_START_EPOCH"
  echo "rto_target_seconds=600"
} > "$DRILL_METRICS_FILE"

log "Running full disaster recovery drill."
"$ROOT_DIR/scripts/stack-up.sh"
"$ROOT_DIR/scripts/seed-demo.sh"
"$ROOT_DIR/scripts/backup.sh"
"$ROOT_DIR/scripts/simulate-failure.sh" drop-tickets
"$ROOT_DIR/scripts/restore.sh"
"$ROOT_DIR/scripts/verify-restore.sh"

DRILL_END_EPOCH="$(date -u +%s)"
{
  date -u +"finished_at=%Y-%m-%dT%H:%M:%SZ"
  echo "finished_epoch=$DRILL_END_EPOCH"
  echo "duration_seconds=$((DRILL_END_EPOCH - DRILL_START_EPOCH))"
} >> "$DRILL_METRICS_FILE"

compose ps > "$DRILL_DIR/compose-ps.txt"
"$ROOT_DIR/scripts/write-postmortem.sh" passed

log "Full drill completed successfully. Evidence lives in $DRILL_DIR."
