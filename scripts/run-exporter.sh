#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

LISTEN_ADDRESS="${LISTEN_ADDRESS:-0.0.0.0:9108}"
DOCKER_PUBLISH="${DOCKER_PUBLISH:-9108:9108}"
EXPORTER_ARTIFACTS_DIR="${EXPORTER_ARTIFACTS_DIR:-artifacts}"

docker_mount_path() {
  if mount_path="$(cd "$ROOT_DIR" && pwd -W 2>/dev/null)"; then
    printf '%s\n' "$mount_path"
    return 0
  fi

  printf '%s\n' "$ROOT_DIR"
}

if command -v go >/dev/null 2>&1; then
  log "Starting drill exporter with local Go toolchain."
  cd "$ROOT_DIR"
  exec env ARTIFACTS_DIR="$EXPORTER_ARTIFACTS_DIR" LISTEN_ADDRESS="$LISTEN_ADDRESS" go run ./cmd/drill-exporter
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Go or Docker is required to run the drill exporter." >&2
  exit 1
fi

log "Local Go toolchain not found; starting drill exporter with Docker."
exec env MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm \
  -p "$DOCKER_PUBLISH" \
  -e ARTIFACTS_DIR="$EXPORTER_ARTIFACTS_DIR" \
  -e LISTEN_ADDRESS="0.0.0.0:9108" \
  -v "$(docker_mount_path):/workspace" \
  -w /workspace \
  golang:1.23 \
  go run ./cmd/drill-exporter
