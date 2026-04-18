#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$ROOT_DIR/.env" ]]; then
  cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
  echo "Created .env from .env.example."
else
  echo ".env already exists."
fi

mkdir -p "$ROOT_DIR/artifacts"

cat <<'EOF'
Next steps:
  1. bash scripts/stack-up.sh
  2. bash scripts/seed-demo.sh
  3. bash scripts/run-drill.sh
EOF
