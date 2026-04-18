#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_env
ensure_artifact_dirs
wait_for_postgres

log "Creating deterministic demo dataset."
psql_exec <<'SQL'
BEGIN;
CREATE TABLE IF NOT EXISTS customers (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  tier TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS tickets (
  id SERIAL PRIMARY KEY,
  customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS drill_markers (
  id SERIAL PRIMARY KEY,
  note TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

TRUNCATE TABLE tickets, customers, drill_markers RESTART IDENTITY CASCADE;

INSERT INTO customers (name, tier) VALUES
  ('Acme Corp', 'gold'),
  ('Northwind', 'silver'),
  ('Globex', 'silver'),
  ('Initech', 'bronze'),
  ('Umbrella', 'gold');

INSERT INTO tickets (customer_id, title, status) VALUES
  (1, 'VPN outage on branch office', 'open'),
  (1, 'Firewall rule review', 'open'),
  (2, 'Mail relay degraded', 'in_progress'),
  (2, 'SSO login failures', 'open'),
  (3, 'Payment gateway timeout', 'resolved'),
  (3, 'API key rotation request', 'open'),
  (4, 'Laptop encryption check', 'resolved'),
  (4, 'Wi-Fi onboarding issue', 'open'),
  (5, 'Database failover rehearsal', 'open'),
  (5, 'New support mailbox creation', 'resolved'),
  (1, 'Backup restore test request', 'in_progress'),
  (2, 'Proxy certificate renewal', 'open');

INSERT INTO drill_markers (note) VALUES
  ('baseline-created');
COMMIT;
SQL

capture_state > "$BASELINE_FILE"
cp "$BASELINE_FILE" "$DRILL_DIR/baseline.tsv"

log "Baseline snapshot written to $BASELINE_FILE."
