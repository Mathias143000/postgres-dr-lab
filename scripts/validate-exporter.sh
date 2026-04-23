#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

docker_mount_path() {
  if mount_path="$(cd "$ROOT_DIR" && pwd -W 2>/dev/null)"; then
    printf '%s\n' "$mount_path"
    return 0
  fi

  printf '%s\n' "$ROOT_DIR"
}

if command -v go >/dev/null 2>&1; then
  log "Validating drill exporter with local Go toolchain."
  cd "$ROOT_DIR"
  go test ./...
  go vet ./...
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Go or Docker is required to validate the drill exporter." >&2
  exit 1
fi

log "Local Go toolchain not found; validating drill exporter with Docker."
env MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm \
  -v "$(docker_mount_path):/workspace" \
  -w /workspace \
  golang:1.23 \
  go test ./...

env MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm \
  -v "$(docker_mount_path):/workspace" \
  -w /workspace \
  golang:1.23 \
  go vet ./...
