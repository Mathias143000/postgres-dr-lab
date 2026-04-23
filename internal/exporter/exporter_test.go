package exporter

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestBuildMetricsPayload(t *testing.T) {
	artifactsDir := seedArtifacts(t)

	payload, err := BuildMetricsPayload(artifactsDir, "test", time.Unix(1776951020, 0).UTC())
	if err != nil {
		t.Fatalf("build metrics payload: %v", err)
	}

	expectedLines := []string{
		`postgres_dr_exporter_build_info{version="test"} 1`,
		"postgres_dr_exporter_last_scrape_success 1",
		"postgres_dr_backup_is_fresh 1",
		`postgres_dr_backup_info{stanza="demo",label="20260423-132934F",type="full"} 1`,
		"postgres_dr_recovery_drill_duration_seconds 53",
		"postgres_dr_recovery_drill_rto_objective_met 1",
		`postgres_dr_recovery_drill_failure_mode_info{mode="drop-tickets"} 1`,
	}

	for _, line := range expectedLines {
		if !strings.Contains(payload, line) {
			t.Fatalf("expected payload to contain %q, got %q", line, payload)
		}
	}
}

func TestRenderErrorMetricsForMissingArtifact(t *testing.T) {
	now := time.Unix(1776951020, 0).UTC()
	err := &ArtifactError{Stage: "freshness_report", Err: os.ErrNotExist}

	payload := RenderErrorMetrics("test", now, err)

	if !strings.Contains(payload, "postgres_dr_exporter_last_scrape_success 0") {
		t.Fatalf("expected failed scrape metric, got %q", payload)
	}
	if !strings.Contains(payload, `postgres_dr_exporter_error_info{stage="freshness_report",reason="artifact_missing"} 1`) {
		t.Fatalf("expected artifact missing metric, got %q", payload)
	}
}

func TestClassifyErrorFallsBackForUnexpectedError(t *testing.T) {
	stage, reason := classifyError(errors.New("boom"))
	if stage != "unknown" || reason != "unexpected_failure" {
		t.Fatalf("unexpected classification: %s %s", stage, reason)
	}
}

func seedArtifacts(t *testing.T) string {
	t.Helper()

	root := t.TempDir()

	writeFile(
		t,
		filepath.Join(root, "backups", "freshness-report.json"),
		`{
  "status": "fresh",
  "max_age_hours": 24.0,
  "max_age_seconds": 86400,
  "latest_backup": {
    "stanza": "demo",
    "label": "20260423-132934F",
    "type": "full",
    "stop_epoch": 1776950984,
    "stop_utc": "2026-04-23T13:29:44Z"
  },
  "age_seconds": 2
}
`,
	)
	writeFile(
		t,
		filepath.Join(root, "drills", "latest", "drill-metrics.env"),
		`started_at=2026-04-23T13:29:20Z
started_epoch=1776950960
rto_target_seconds=600
finished_at=2026-04-23T13:30:13Z
finished_epoch=1776951013
duration_seconds=53
`,
	)
	writeFile(
		t,
		filepath.Join(root, "drills", "latest", "02-failure.txt"),
		`mode=drop-tickets
timestamp=2026-04-23T13:29:48Z
`,
	)

	return root
}

func writeFile(t *testing.T, path string, contents string) {
	t.Helper()

	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", path, err)
	}
	if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}
