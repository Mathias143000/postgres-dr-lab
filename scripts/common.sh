#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
ARTIFACTS_DIR="$ROOT_DIR/artifacts"
BASELINE_FILE="$ARTIFACTS_DIR/baseline.tsv"
BACKUP_INFO_FILE="$ARTIFACTS_DIR/backups/backup-info.json"
FRESHNESS_REPORT_FILE="$ARTIFACTS_DIR/backups/freshness-report.json"
DRILL_DIR="$ARTIFACTS_DIR/drills/latest"
DRILL_METRICS_FILE="$DRILL_DIR/drill-metrics.env"
DRILL_POSTMORTEM_FILE="$DRILL_DIR/postmortem.md"
COMPOSE_PROJECT_NAME="postgres-dr-lab"
DATA_VOLUME="${COMPOSE_PROJECT_NAME}_postgres-data"
REPO_VOLUME="${COMPOSE_PROJECT_NAME}_pgbackrest-repo"
IMAGE_NAME="${COMPOSE_PROJECT_NAME}-postgres"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

ensure_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ROOT_DIR/.env.example" "$ENV_FILE"
    log "Created .env from .env.example."
  fi

  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a

  export PGBACKREST_STANZA="${PGBACKREST_STANZA:-demo}"
}

compose() {
  docker compose --project-directory "$ROOT_DIR" -f "$ROOT_DIR/docker-compose.yml" "$@"
}

wait_for_postgres() {
  ensure_env
  for _ in $(seq 1 60); do
    if compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  log "PostgreSQL did not become healthy in time."
  return 1
}

psql_exec() {
  ensure_env
  compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 "$@"
}

pgbackrest_exec() {
  ensure_env
  compose exec -T -u postgres postgres pgbackrest --stanza="$PGBACKREST_STANZA" "$@"
}

python_exec() {
  if command -v python3 >/dev/null 2>&1; then
    python3 "$@"
  elif command -v python >/dev/null 2>&1; then
    python "$@"
  else
    echo "Python is required for evidence report generation." >&2
    return 1
  fi
}

capture_state_query() {
  cat <<'SQL'
SELECT 'customers' AS dataset, COUNT(*) AS row_count, COALESCE(MD5(string_agg(name || ':' || tier, ',' ORDER BY id)), 'empty') AS checksum FROM customers
UNION ALL
SELECT 'tickets' AS dataset, COUNT(*) AS row_count, COALESCE(MD5(string_agg(title || ':' || status || ':' || customer_id, ',' ORDER BY id)), 'empty') AS checksum FROM tickets
UNION ALL
SELECT 'drill_markers' AS dataset, COUNT(*) AS row_count, COALESCE(MD5(string_agg(note, ',' ORDER BY id)), 'empty') AS checksum FROM drill_markers
ORDER BY dataset;
SQL
}

capture_state() {
  psql_exec -At -F $'\t' -c "$(capture_state_query)"
}

ensure_artifact_dirs() {
  mkdir -p "$ARTIFACTS_DIR" "$ARTIFACTS_DIR/backups" "$DRILL_DIR"
}
