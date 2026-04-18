#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_env
ensure_artifact_dirs

log "Starting postgres-dr-lab."
compose up -d --build
wait_for_postgres

log "Ensuring pgBackRest stanza exists."
pgbackrest_exec stanza-create >/dev/null

log "Stack is ready."
