# Recovery Runbook

## 1. Prepare the lab

```bash
cp .env.example .env
bash scripts/stack-up.sh
bash scripts/seed-demo.sh
```

## 2. Create a backup

```bash
bash scripts/backup.sh
```

This writes backup metadata into `artifacts/backups/`.

The backup script also writes freshness evidence:

```bash
bash scripts/report-freshness.sh
```

By default, the latest backup must be no older than 24 hours. Override the policy for stricter rehearsals:

```bash
BACKUP_FRESHNESS_MAX_HOURS=4 bash scripts/report-freshness.sh
```

## 3. Simulate damage

```bash
bash scripts/simulate-failure.sh drop-tickets
```

This intentionally removes the `tickets` table from the primary database.

## 4. Restore from a clean environment

```bash
bash scripts/restore.sh
```

The script:

1. stops the primary container
2. removes the data volume
3. recreates the data volume empty
4. runs `pgbackrest restore`
5. starts PostgreSQL again

## 5. Verify recovery

```bash
bash scripts/verify-restore.sh
```

The verification step compares the restored dataset with the baseline snapshot captured during seeding.

After a successful full drill, the lab writes a postmortem-style summary to `artifacts/drills/latest/postmortem.md`.

## 6. Run the full drill

```bash
bash scripts/run-drill.sh
```

Artifacts land in `artifacts/drills/latest/`.

The most useful review artifacts are:

- `backup-info.json`
- `backup-freshness.txt`
- `drill-metrics.env`
- `restored.tsv`
- `postmortem.md`

## 7. Expose DR metrics

Once the artifacts exist, start the Go exporter:

```bash
bash scripts/run-exporter.sh
```

Then open:

- `http://127.0.0.1:9108/healthz`
- `http://127.0.0.1:9108/metrics`

The exporter reads:

- `artifacts/backups/freshness-report.json`
- `artifacts/drills/latest/drill-metrics.env`
- `artifacts/drills/latest/02-failure.txt`

Validation path for the exporter:

```bash
bash scripts/validate-exporter.sh
```

## Failure modes in scope

- accidental table drop
- destructive delete
- empty data volume after rebuild

## Failure modes intentionally out of scope

- cluster failover
- multi-node replication
- point-in-time recovery to arbitrary timestamp
- object-storage offsite repository
