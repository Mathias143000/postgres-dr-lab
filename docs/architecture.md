# Architecture

```text
                   +----------------------+
                   |   Bash drill scripts |
                   +----------+-----------+
                              |
                              v
                    +--------------------+
                    |  Docker Compose    |
                    |  postgres-dr-lab   |
                    +---------+----------+
                              |
                              v
                  +--------------------------+
                  | PostgreSQL primary       |
                  | - sample data            |
                  | - WAL archiving enabled  |
                  | - pgBackRest installed   |
                  +------------+-------------+
                               |
                archive-push / | \ backup / restore
                               |
                               v
                  +--------------------------+
                  | pgBackRest repository    |
                  | - full backups           |
                  | - archived WAL           |
                  | - backup metadata        |
                  +------------+-------------+
                               |
                               v
                  +--------------------------+
                  | Clean restore workflow   |
                  | - wipe data volume       |
                  | - restore from repo      |
                  | - restart PostgreSQL     |
                  | - verify restored state  |
                  +--------------------------+
                               |
                               v
                  +--------------------------+
                  | Drill artifacts          |
                  | - freshness-report.json  |
                  | - drill-metrics.env      |
                  | - 02-failure.txt         |
                  +------------+-------------+
                               |
                               v
                  +--------------------------+
                  | Go drill exporter        |
                  | - reads local evidence   |
                  | - exposes /metrics       |
                  +--------------------------+
```

The lab keeps the topology intentionally small so the recovery story is easy to explain:

- one primary database
- one repository volume for `pgBackRest`
- one deterministic seed dataset
- one scripted recovery drill that can be replayed on demand
- one small Go exporter that turns drill evidence into scrapeable signals
