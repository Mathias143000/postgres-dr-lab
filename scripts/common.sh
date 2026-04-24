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

postgres_is_in_recovery() {
  local recovery_state

  recovery_state="$(psql_exec -At -c "SELECT pg_is_in_recovery();")"
  [[ "$recovery_state" == "t" ]]
}

wait_for_writable_primary() {
  for _ in $(seq 1 30); do
    if ! postgres_is_in_recovery; then
      return 0
    fi
    sleep 2
  done

  log "PostgreSQL stayed in recovery mode for too long."
  return 1
}

ensure_writable_primary() {
  if ! postgres_is_in_recovery; then
    return 0
  fi

  log "PostgreSQL is in recovery mode; promoting it back to a writable primary."
  psql_exec -At -c "SELECT pg_wal_replay_resume();" >/dev/null
  wait_for_writable_primary
}

pgbackrest_exec() {
  ensure_env
  compose exec -T -u postgres postgres pgbackrest --stanza="$PGBACKREST_STANZA" "$@"
}

python_exec() {
  local candidate

  for candidate in python3 python py; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "import sys" >/dev/null 2>&1; then
      "$candidate" "$@"
      return $?
    fi
  done

  echo "Python is required for evidence report generation." >&2
  return 1
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
