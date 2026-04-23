#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_env
ensure_artifact_dirs

log "Starting postgres-dr-lab."
compose up -d --build
wait_for_postgres

log "Ensuring pgBackRest stanza exists."
for attempt in $(seq 1 5); do
  if pgbackrest_exec stanza-create >/dev/null; then
    break
  fi

  if [[ "$attempt" == "5" ]]; then
    log "pgBackRest stanza-create failed after $attempt attempts."
    exit 1
  fi

  log "pgBackRest stanza-create is not ready yet; retrying ($attempt/5)."
  sleep 3
done

log "Stack is ready."
