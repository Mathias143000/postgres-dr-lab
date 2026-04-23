#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_env
ensure_artifact_dirs

MAX_HOURS="${BACKUP_FRESHNESS_MAX_HOURS:-24}"

if [[ ! -f "$BACKUP_INFO_FILE" ]]; then
  echo "Backup metadata not found: $BACKUP_INFO_FILE" >&2
  echo "Run scripts/backup.sh first." >&2
  exit 1
fi

python_exec - "$BACKUP_INFO_FILE" "$FRESHNESS_REPORT_FILE" "$DRILL_DIR/backup-freshness.txt" "$MAX_HOURS" <<'PY'
from __future__ import annotations

import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


backup_info_path = Path(sys.argv[1])
report_path = Path(sys.argv[2])
summary_path = Path(sys.argv[3])
max_hours = float(sys.argv[4])

data = json.loads(backup_info_path.read_text(encoding="utf-8"))
stanzas = data if isinstance(data, list) else [data]

latest: dict[str, object] | None = None
latest_stop = -1

for stanza in stanzas:
    if not isinstance(stanza, dict):
        continue
    for backup in stanza.get("backup", []):
        if not isinstance(backup, dict):
            continue
        timestamp = backup.get("timestamp", {})
        if not isinstance(timestamp, dict):
            continue
        stop = timestamp.get("stop") or timestamp.get("start")
        if isinstance(stop, int) and stop > latest_stop:
            latest = {
                "stanza": stanza.get("name", "unknown"),
                "label": backup.get("label", "unknown"),
                "type": backup.get("type", "unknown"),
                "stop_epoch": stop,
            }
            latest_stop = stop

if latest is None:
    raise SystemExit("No backup timestamp found in pgBackRest metadata.")

now_epoch = int(time.time())
age_seconds = max(0, now_epoch - latest_stop)
max_age_seconds = int(max_hours * 3600)
status = "fresh" if age_seconds <= max_age_seconds else "stale"

latest["stop_utc"] = datetime.fromtimestamp(latest_stop, tz=timezone.utc).isoformat().replace("+00:00", "Z")
report = {
    "status": status,
    "max_age_hours": max_hours,
    "max_age_seconds": max_age_seconds,
    "latest_backup": latest,
    "age_seconds": age_seconds,
}

report_path.parent.mkdir(parents=True, exist_ok=True)
summary_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
summary_path.write_text(
    "\n".join(
        [
            f"status={status}",
            f"latest_label={latest['label']}",
            f"latest_type={latest['type']}",
            f"latest_stop_utc={latest['stop_utc']}",
            f"age_seconds={age_seconds}",
            f"max_age_seconds={max_age_seconds}",
            "",
        ]
    ),
    encoding="utf-8",
)

print(f"Backup freshness status: {status}")
print(f"Report: {report_path}")

if status != "fresh":
    raise SystemExit(1)
PY
