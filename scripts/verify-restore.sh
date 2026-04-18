#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_env
ensure_artifact_dirs
wait_for_postgres

if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "Baseline file not found: $BASELINE_FILE" >&2
  exit 1
fi

capture_state > "$DRILL_DIR/restored.tsv"

if ! diff -u "$BASELINE_FILE" "$DRILL_DIR/restored.tsv" > "$DRILL_DIR/04-verify.diff"; then
  echo "Restore verification failed. See $DRILL_DIR/04-verify.diff" >&2
  exit 1
fi

cp "$DRILL_DIR/restored.tsv" "$ARTIFACTS_DIR/restored.tsv"
rm -f "$DRILL_DIR/04-verify.diff"

log "Restore verification passed."
