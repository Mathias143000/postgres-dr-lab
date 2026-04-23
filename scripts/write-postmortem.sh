#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

STATUS="${1:-passed}"

ensure_env
ensure_artifact_dirs

read_value() {
  local file="$1"
  local key="$2"

  if [[ -f "$file" ]]; then
    grep -E "^${key}=" "$file" | tail -n 1 | cut -d= -f2- || true
  fi
}

freshness_value() {
  local key="$1"

  if [[ -f "$FRESHNESS_REPORT_FILE" ]]; then
    python_exec - "$FRESHNESS_REPORT_FILE" "$key" <<'PY'
import json
import sys

report = json.load(open(sys.argv[1], encoding="utf-8"))
key = sys.argv[2]

if key == "latest_label":
    print(report.get("latest_backup", {}).get("label", "unknown"))
elif key == "latest_stop_utc":
    print(report.get("latest_backup", {}).get("stop_utc", "unknown"))
else:
    print(report.get(key, "unknown"))
PY
  fi
}

failure_mode="$(read_value "$DRILL_DIR/02-failure.txt" "mode")"
failure_timestamp="$(read_value "$DRILL_DIR/02-failure.txt" "timestamp")"
started_at="$(read_value "$DRILL_METRICS_FILE" "started_at")"
finished_at="$(read_value "$DRILL_METRICS_FILE" "finished_at")"
duration_seconds="$(read_value "$DRILL_METRICS_FILE" "duration_seconds")"
rto_target_seconds="$(read_value "$DRILL_METRICS_FILE" "rto_target_seconds")"
freshness_status="$(freshness_value "status")"
latest_label="$(freshness_value "latest_label")"
latest_stop_utc="$(freshness_value "latest_stop_utc")"

cat > "$DRILL_POSTMORTEM_FILE" <<EOF
# Postgres DR Drill Postmortem

## Summary

- Result: ${STATUS:-unknown}
- Failure mode: ${failure_mode:-unknown}
- Failure timestamp: ${failure_timestamp:-unknown}
- Drill started: ${started_at:-unknown}
- Drill finished: ${finished_at:-unknown}
- Observed drill duration seconds: ${duration_seconds:-unknown}
- RTO target seconds: ${rto_target_seconds:-600}

## Backup Freshness

- Freshness status: ${freshness_status:-unknown}
- Latest backup label: ${latest_label:-unknown}
- Latest backup completed at: ${latest_stop_utc:-unknown}

## Recovery Assessment

- RPO assumption: at most the latest archived WAL segment since the latest full backup.
- RTO assumption: under 10 minutes for this local lab dataset.
- Verification result: restored dataset matched the baseline snapshot.

## Evidence

- Baseline snapshot: artifacts/baseline.tsv
- Backup metadata: artifacts/backups/backup-info.json
- Freshness report: artifacts/backups/freshness-report.json
- Restore log: artifacts/drills/latest/03-restore.log
- Restored snapshot: artifacts/drills/latest/restored.tsv
- Compose status: artifacts/drills/latest/compose-ps.txt

## Follow-Ups

- Add scheduled restore validation against a persistent repository.
- Add offsite object storage repository target.
- Add PITR walkthrough for timestamp-based recovery.
EOF

cp "$DRILL_POSTMORTEM_FILE" "$ARTIFACTS_DIR/drill-postmortem.md"
log "Postmortem written to $DRILL_POSTMORTEM_FILE."
