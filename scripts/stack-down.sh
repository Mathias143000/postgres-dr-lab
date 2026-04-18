#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [[ "${1:-}" == "--volumes" ]]; then
  log "Stopping stack and removing volumes."
  compose down -v
else
  log "Stopping stack."
  compose down
fi
