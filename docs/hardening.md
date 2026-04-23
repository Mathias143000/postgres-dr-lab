# DR Hardening

This lab is intentionally small, so hardening focuses on recovery evidence instead of adding unrelated platform components.

## What Is Covered

- backup freshness check after every `pgBackRest` backup
- machine-readable freshness report in `artifacts/backups/freshness-report.json`
- drill timing in `artifacts/drills/latest/drill-metrics.env`
- postmortem-style incident note after a successful full drill
- CI path for shell syntax, Compose config, and the full recovery drill

## Freshness Policy

The default freshness threshold is 24 hours:

```bash
bash scripts/report-freshness.sh
```

The threshold can be changed for stricter checks:

```bash
BACKUP_FRESHNESS_MAX_HOURS=4 bash scripts/report-freshness.sh
```

The script fails when the latest backup is older than the threshold. This keeps the lab honest: stale backup metadata is treated as a failed recovery-readiness signal.

## Drill Evidence

The full drill now writes:

- `artifacts/drills/latest/backup-freshness.txt`
- `artifacts/drills/latest/drill-metrics.env`
- `artifacts/drills/latest/postmortem.md`
- `artifacts/drill-postmortem.md`

These files are intentionally ignored by Git. They are runtime evidence, not source code.

## Remaining Backlog

- scheduled restore validation
- object-storage backup repository
- PITR walkthrough
- Prometheus-style backup freshness exporter
