package exporter

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type ArtifactError struct {
	Stage string
	Err   error
}

func (e *ArtifactError) Error() string {
	return fmt.Sprintf("%s: %v", e.Stage, e.Err)
}

func (e *ArtifactError) Unwrap() error {
	return e.Err
}

type Snapshot struct {
	Freshness  FreshnessReport
	Drill      DrillMetrics
	Failure    FailureInfo
	ScrapedAt  time.Time
	Artifacts  string
	ExporterUp bool
}

type FreshnessReport struct {
	Status        string     `json:"status"`
	MaxAgeHours   float64    `json:"max_age_hours"`
	MaxAgeSeconds int64      `json:"max_age_seconds"`
	LatestBackup  BackupInfo `json:"latest_backup"`
	AgeSeconds    int64      `json:"age_seconds"`
}

type BackupInfo struct {
	Stanza    string `json:"stanza"`
	Label     string `json:"label"`
	Type      string `json:"type"`
	StopEpoch int64  `json:"stop_epoch"`
	StopUTC   string `json:"stop_utc"`
}

type DrillMetrics struct {
	StartedAt        string
	StartedEpoch     int64
	FinishedAt       string
	FinishedEpoch    int64
	DurationSeconds  int64
	RTOTargetSeconds int64
}

type FailureInfo struct {
	Mode      string
	Timestamp string
}

func BuildMetricsPayload(artifactsDir string, version string, now time.Time) (string, error) {
	snapshot, err := LoadSnapshot(artifactsDir, now)
	if err != nil {
		return "", err
	}
	return RenderMetrics(snapshot, version), nil
}

func LoadSnapshot(artifactsDir string, now time.Time) (Snapshot, error) {
	freshness, err := loadFreshnessReport(filepath.Join(artifactsDir, "backups", "freshness-report.json"))
	if err != nil {
		return Snapshot{}, err
	}

	drill, err := loadDrillMetrics(filepath.Join(artifactsDir, "drills", "latest", "drill-metrics.env"))
	if err != nil {
		return Snapshot{}, err
	}

	failure, err := loadFailureInfo(filepath.Join(artifactsDir, "drills", "latest", "02-failure.txt"))
	if err != nil {
		return Snapshot{}, err
	}

	return Snapshot{
		Freshness:  freshness,
		Drill:      drill,
		Failure:    failure,
		ScrapedAt:  now,
		Artifacts:  artifactsDir,
		ExporterUp: true,
	}, nil
}

func RenderMetrics(snapshot Snapshot, version string) string {
	lines := []string{
		"# HELP postgres_dr_exporter_build_info Build information for the DR exporter",
		"# TYPE postgres_dr_exporter_build_info gauge",
		fmt.Sprintf(`postgres_dr_exporter_build_info{version="%s"} 1`, labelValue(version)),
		"# HELP postgres_dr_exporter_last_scrape_success Whether the last scrape loaded drill artifacts successfully",
		"# TYPE postgres_dr_exporter_last_scrape_success gauge",
		"postgres_dr_exporter_last_scrape_success 1",
		"# HELP postgres_dr_exporter_last_scrape_timestamp_seconds Unix timestamp of the last scrape",
		"# TYPE postgres_dr_exporter_last_scrape_timestamp_seconds gauge",
		fmt.Sprintf("postgres_dr_exporter_last_scrape_timestamp_seconds %d", snapshot.ScrapedAt.Unix()),
		"# HELP postgres_dr_backup_is_fresh Whether the latest backup is within the configured freshness threshold",
		"# TYPE postgres_dr_backup_is_fresh gauge",
		fmt.Sprintf("postgres_dr_backup_is_fresh %d", boolToGauge(snapshot.Freshness.Status == "fresh")),
		"# HELP postgres_dr_backup_freshness_status Backup freshness status with a status label",
		"# TYPE postgres_dr_backup_freshness_status gauge",
		fmt.Sprintf(
			`postgres_dr_backup_freshness_status{status="%s"} 1`,
			labelValue(snapshot.Freshness.Status),
		),
		"# HELP postgres_dr_backup_age_seconds Age of the latest backup in seconds",
		"# TYPE postgres_dr_backup_age_seconds gauge",
		fmt.Sprintf("postgres_dr_backup_age_seconds %d", snapshot.Freshness.AgeSeconds),
		"# HELP postgres_dr_backup_max_age_seconds Maximum allowed backup age in seconds",
		"# TYPE postgres_dr_backup_max_age_seconds gauge",
		fmt.Sprintf("postgres_dr_backup_max_age_seconds %d", snapshot.Freshness.MaxAgeSeconds),
		"# HELP postgres_dr_backup_latest_stop_time_seconds Completion time of the latest backup",
		"# TYPE postgres_dr_backup_latest_stop_time_seconds gauge",
		fmt.Sprintf("postgres_dr_backup_latest_stop_time_seconds %d", snapshot.Freshness.LatestBackup.StopEpoch),
		"# HELP postgres_dr_backup_info Static information about the latest backup artifact",
		"# TYPE postgres_dr_backup_info gauge",
		fmt.Sprintf(
			`postgres_dr_backup_info{stanza="%s",label="%s",type="%s"} 1`,
			labelValue(snapshot.Freshness.LatestBackup.Stanza),
			labelValue(snapshot.Freshness.LatestBackup.Label),
			labelValue(snapshot.Freshness.LatestBackup.Type),
		),
		"# HELP postgres_dr_recovery_drill_duration_seconds Duration of the latest recovery drill",
		"# TYPE postgres_dr_recovery_drill_duration_seconds gauge",
		fmt.Sprintf("postgres_dr_recovery_drill_duration_seconds %d", snapshot.Drill.DurationSeconds),
		"# HELP postgres_dr_recovery_drill_rto_target_seconds Configured RTO target for the drill",
		"# TYPE postgres_dr_recovery_drill_rto_target_seconds gauge",
		fmt.Sprintf("postgres_dr_recovery_drill_rto_target_seconds %d", snapshot.Drill.RTOTargetSeconds),
		"# HELP postgres_dr_recovery_drill_rto_objective_met Whether the latest drill stayed within the RTO target",
		"# TYPE postgres_dr_recovery_drill_rto_objective_met gauge",
		fmt.Sprintf(
			"postgres_dr_recovery_drill_rto_objective_met %d",
			boolToGauge(snapshot.Drill.DurationSeconds <= snapshot.Drill.RTOTargetSeconds),
		),
		"# HELP postgres_dr_recovery_drill_started_time_seconds Start time of the latest drill",
		"# TYPE postgres_dr_recovery_drill_started_time_seconds gauge",
		fmt.Sprintf("postgres_dr_recovery_drill_started_time_seconds %d", snapshot.Drill.StartedEpoch),
		"# HELP postgres_dr_recovery_drill_finished_time_seconds Finish time of the latest drill",
		"# TYPE postgres_dr_recovery_drill_finished_time_seconds gauge",
		fmt.Sprintf("postgres_dr_recovery_drill_finished_time_seconds %d", snapshot.Drill.FinishedEpoch),
		"# HELP postgres_dr_recovery_drill_failure_mode_info Failure mode used in the latest drill",
		"# TYPE postgres_dr_recovery_drill_failure_mode_info gauge",
		fmt.Sprintf(
			`postgres_dr_recovery_drill_failure_mode_info{mode="%s"} 1`,
			labelValue(snapshot.Failure.Mode),
		),
	}

	return strings.Join(lines, "\n") + "\n"
}

func RenderErrorMetrics(version string, now time.Time, err error) string {
	stage, reason := classifyError(err)

	lines := []string{
		"# HELP postgres_dr_exporter_build_info Build information for the DR exporter",
		"# TYPE postgres_dr_exporter_build_info gauge",
		fmt.Sprintf(`postgres_dr_exporter_build_info{version="%s"} 1`, labelValue(version)),
		"# HELP postgres_dr_exporter_last_scrape_success Whether the last scrape loaded drill artifacts successfully",
		"# TYPE postgres_dr_exporter_last_scrape_success gauge",
		"postgres_dr_exporter_last_scrape_success 0",
		"# HELP postgres_dr_exporter_last_scrape_timestamp_seconds Unix timestamp of the last scrape",
		"# TYPE postgres_dr_exporter_last_scrape_timestamp_seconds gauge",
		fmt.Sprintf("postgres_dr_exporter_last_scrape_timestamp_seconds %d", now.Unix()),
		"# HELP postgres_dr_exporter_error_info Details about the last exporter read failure",
		"# TYPE postgres_dr_exporter_error_info gauge",
		fmt.Sprintf(
			`postgres_dr_exporter_error_info{stage="%s",reason="%s"} 1`,
			labelValue(stage),
			labelValue(reason),
		),
	}

	return strings.Join(lines, "\n") + "\n"
}

func loadFreshnessReport(path string) (FreshnessReport, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return FreshnessReport{}, &ArtifactError{Stage: "freshness_report", Err: err}
	}

	var report FreshnessReport
	if err := json.Unmarshal(data, &report); err != nil {
		return FreshnessReport{}, &ArtifactError{Stage: "freshness_report", Err: err}
	}
	if report.Status == "" {
		return FreshnessReport{}, &ArtifactError{Stage: "freshness_report", Err: errors.New("missing status")}
	}
	return report, nil
}

func loadDrillMetrics(path string) (DrillMetrics, error) {
	values, err := loadKeyValueFile(path)
	if err != nil {
		return DrillMetrics{}, &ArtifactError{Stage: "drill_metrics", Err: err}
	}

	startedEpoch, err := strconv.ParseInt(values["started_epoch"], 10, 64)
	if err != nil {
		return DrillMetrics{}, &ArtifactError{Stage: "drill_metrics", Err: fmt.Errorf("parse started_epoch: %w", err)}
	}
	finishedEpoch, err := strconv.ParseInt(values["finished_epoch"], 10, 64)
	if err != nil {
		return DrillMetrics{}, &ArtifactError{Stage: "drill_metrics", Err: fmt.Errorf("parse finished_epoch: %w", err)}
	}
	durationSeconds, err := strconv.ParseInt(values["duration_seconds"], 10, 64)
	if err != nil {
		return DrillMetrics{}, &ArtifactError{Stage: "drill_metrics", Err: fmt.Errorf("parse duration_seconds: %w", err)}
	}
	rtoTargetSeconds, err := strconv.ParseInt(values["rto_target_seconds"], 10, 64)
	if err != nil {
		return DrillMetrics{}, &ArtifactError{Stage: "drill_metrics", Err: fmt.Errorf("parse rto_target_seconds: %w", err)}
	}

	return DrillMetrics{
		StartedAt:        values["started_at"],
		StartedEpoch:     startedEpoch,
		FinishedAt:       values["finished_at"],
		FinishedEpoch:    finishedEpoch,
		DurationSeconds:  durationSeconds,
		RTOTargetSeconds: rtoTargetSeconds,
	}, nil
}

func loadFailureInfo(path string) (FailureInfo, error) {
	values, err := loadKeyValueFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return FailureInfo{Mode: "unknown", Timestamp: ""}, nil
		}
		return FailureInfo{}, &ArtifactError{Stage: "failure_mode", Err: err}
	}

	mode := values["mode"]
	if mode == "" {
		mode = "unknown"
	}
	return FailureInfo{
		Mode:      mode,
		Timestamp: values["timestamp"],
	}, nil
}

func loadKeyValueFile(path string) (map[string]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	values := make(map[string]string)
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		key, value, found := strings.Cut(line, "=")
		if !found {
			return nil, fmt.Errorf("invalid line %q", line)
		}
		values[key] = value
	}

	return values, nil
}

func classifyError(err error) (string, string) {
	var artifactError *ArtifactError
	if errors.As(err, &artifactError) {
		if errors.Is(artifactError.Err, os.ErrNotExist) {
			return artifactError.Stage, "artifact_missing"
		}
		return artifactError.Stage, "parse_failure"
	}
	return "unknown", "unexpected_failure"
}

func boolToGauge(value bool) int {
	if value {
		return 1
	}
	return 0
}

func labelValue(value string) string {
	replacer := strings.NewReplacer(`\`, `\\`, "\n", `\n`, `"`, `\"`)
	return replacer.Replace(value)
}
