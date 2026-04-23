# Postgres DR Lab

A compact disaster recovery lab built around `PostgreSQL` and `pgBackRest`.

The point of this repository is not to look like a huge platform. The point is to show one operational story clearly:

- create a reproducible backup
- simulate destructive data loss
- restore from a clean environment
- verify that the recovered dataset matches the baseline

## Portfolio Role

This is the reliability and recovery flagship in the portfolio.

Use this repository when the discussion is about:

- recovery readiness instead of only deployment readiness
- explicit `RPO` / `RTO` assumptions
- repeatable restore drills
- evidence that recovery was actually executed, not only described

This repo is intentionally narrow. Its job is not to be a general platform demo, but to prove that backup and restore thinking is treated as a first-class engineering concern.

## What This Repo Demonstrates

- `PostgreSQL` runtime in containers
- `pgBackRest` as the backup and restore engine
- WAL archiving enabled on the primary database
- scripted recovery drill with logs and evidence
- backup freshness report after each full backup
- postmortem-style drill summary with RPO/RTO signals
- CI path for shell syntax, Compose config, and the full recovery drill
- explicit `RPO` and `RTO` assumptions
- runbook-oriented documentation instead of only setup notes

## Architecture

See the full diagram in [docs/architecture.md](./docs/architecture.md).

```text
Bash scripts
    |
    v
Docker Compose
    |
    v
PostgreSQL primary ---> pgBackRest repo volume
    |                        |
    | archive-push           | backup metadata + WAL
    +------------------------+

Clean restore workflow:
stop primary -> wipe data volume -> pgbackrest restore -> start primary -> verify state
```

## Review Path

For a fast technical review, the best order is:

1. this README for drill scope and assumptions
2. [docs/architecture.md](./docs/architecture.md) for the recovery shape
3. [docs/runbook.md](./docs/runbook.md) for the operator sequence
4. [docs/hardening.md](./docs/hardening.md) for backup freshness and postmortem evidence
5. `scripts/run-drill.sh` for the end-to-end flow
6. `scripts/restore.sh` and `scripts/verify-restore.sh` for the actual recovery proof

## Fixed Stack

- `PostgreSQL 16`
- `pgBackRest`
- local lab via `docker compose`

## Local Endpoints

| Component | URL |
| --- | --- |
| PostgreSQL primary | `localhost:15432` |

Default credentials come from [`.env.example`](./.env.example):

- database: `drilldb`
- user: `postgres`
- password: `postgres`

## Quick Start

```bash
cp .env.example .env
bash scripts/stack-up.sh
bash scripts/seed-demo.sh
```

## Full Recovery Drill

The fastest way to demonstrate the whole lab is one command:

```bash
bash scripts/run-drill.sh
```

This executes:

1. stack startup
2. seed data creation
3. full backup
4. backup freshness report
5. destructive failure simulation
6. clean restore
7. verification against baseline snapshot
8. postmortem-style drill summary

Evidence lands in `artifacts/drills/latest/`.

## Operator Scripts

- [scripts/bootstrap.sh](./scripts/bootstrap.sh) prepares `.env`
- [scripts/stack-up.sh](./scripts/stack-up.sh) starts the lab and initializes the stanza
- [scripts/stack-down.sh](./scripts/stack-down.sh) stops the lab
- [scripts/seed-demo.sh](./scripts/seed-demo.sh) creates a deterministic baseline dataset
- [scripts/backup.sh](./scripts/backup.sh) runs a full backup and stores `pgBackRest` metadata
- [scripts/report-freshness.sh](./scripts/report-freshness.sh) checks whether the latest backup is fresh enough for the lab policy
- [scripts/simulate-failure.sh](./scripts/simulate-failure.sh) drops data on purpose
- [scripts/restore.sh](./scripts/restore.sh) wipes the data volume and restores into a clean environment
- [scripts/verify-restore.sh](./scripts/verify-restore.sh) compares the restored state with the baseline
- [scripts/write-postmortem.sh](./scripts/write-postmortem.sh) writes the recovery drill postmortem artifact
- [scripts/run-drill.sh](./scripts/run-drill.sh) runs the entire recovery scenario end-to-end

## Recovery Scope

In scope:

- full backup flow
- restore from clean environment
- destructive deletion or table loss
- verification after restore
- runbook and evidence collection

Out of scope for this version:

- HA cluster failover
- offsite object storage repository
- cross-region recovery
- PITR to arbitrary timestamp

## RPO And RTO Assumptions

These are demo assumptions, not production guarantees:

| Signal | Demo target |
| --- | --- |
| RPO | at most the last archived WAL segment since the latest full backup |
| RTO | under 10 minutes on a local laptop for this tiny dataset |

The value of the lab is not the absolute number. The value is that the recovery assumptions are stated explicitly and can be discussed.

## Failure Modes Covered

- `drop-tickets`: simulates accidental table destruction
- `delete-customers`: simulates destructive delete
- clean-volume restore: simulates node rebuild or empty data directory recovery

## Recovery Runbook

The step-by-step operator flow lives in [docs/runbook.md](./docs/runbook.md).

Short version:

```bash
bash scripts/stack-up.sh
bash scripts/seed-demo.sh
bash scripts/backup.sh
bash scripts/report-freshness.sh
bash scripts/simulate-failure.sh drop-tickets
bash scripts/restore.sh
bash scripts/verify-restore.sh
```

## Operational Evidence

After a successful drill you should have:

- `artifacts/baseline.tsv`
- `artifacts/backups/backup-info.json`
- `artifacts/backups/freshness-report.json`
- `artifacts/drills/latest/01-backup.log`
- `artifacts/drills/latest/backup-freshness.txt`
- `artifacts/drills/latest/02-failure.txt`
- `artifacts/drills/latest/03-restore.log`
- `artifacts/drills/latest/drill-metrics.env`
- `artifacts/drills/latest/restored.tsv`
- `artifacts/drills/latest/compose-ps.txt`
- `artifacts/drills/latest/postmortem.md`

This is the portfolio-friendly proof that the scenario was not only described, but actually executed.

## Portfolio Visible Ready Checklist

This repo is considered ready for portfolio use when it has:

- a clean README
- an architecture diagram
- a quick demo flow
- a recovery runbook
- drill evidence in `artifacts/`
- known limitations and future work

## Known Limitations

- single-node lab only
- no scheduler for automated restore drills yet
- no remote backup repository
- backup freshness is checked from `pgBackRest` metadata, not exported as a live metric yet
- no TLS or secret manager because this lab is focused on DR mechanics

## Future Improvements

- scheduled restore validation
- PITR walkthrough
- Prometheus-style backup freshness exporter
- offsite repository target
