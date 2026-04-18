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

## 6. Run the full drill

```bash
bash scripts/run-drill.sh
```

Artifacts land in `artifacts/drills/latest/`.

## Failure modes in scope

- accidental table drop
- destructive delete
- empty data volume after rebuild

## Failure modes intentionally out of scope

- cluster failover
- multi-node replication
- point-in-time recovery to arbitrary timestamp
- object-storage offsite repository
