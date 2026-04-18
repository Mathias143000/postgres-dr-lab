#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

MODE="${1:-drop-tickets}"

ensure_env
ensure_artifact_dirs
wait_for_postgres

case "$MODE" in
  drop-tickets)
    log "Simulating destructive failure by dropping tickets table."
    psql_exec -c "DROP TABLE IF EXISTS tickets;"
    ;;
  delete-customers)
    log "Simulating destructive failure by deleting all customer rows."
    psql_exec -c "DELETE FROM customers;"
    ;;
  *)
    echo "Unknown failure mode: $MODE" >&2
    echo "Supported modes: drop-tickets, delete-customers" >&2
    exit 1
    ;;
esac

{
  echo "mode=$MODE"
  date -u +"timestamp=%Y-%m-%dT%H:%M:%SZ"
} > "$DRILL_DIR/02-failure.txt"

log "Failure simulation complete."
