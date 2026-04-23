package main

import (
	"log/slog"
	"net/http"
	"os"
	"time"

	"example.com/postgres-dr-lab/internal/exporter"
)

var version = "dev"

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	artifactsDir := getenv("ARTIFACTS_DIR", "artifacts")
	listenAddress := getenv("LISTEN_ADDRESS", "0.0.0.0:9108")

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Content-Type", "application/json")
		writer.WriteHeader(http.StatusOK)
		_, _ = writer.Write([]byte(`{"status":"ok"}`))
	})
	mux.HandleFunc("/metrics", func(writer http.ResponseWriter, request *http.Request) {
		now := time.Now().UTC()
		payload, err := exporter.BuildMetricsPayload(artifactsDir, version, now)
		if err != nil {
			logger.Error(
				"exporter scrape failed",
				slog.String("artifacts_dir", artifactsDir),
				slog.String("error", err.Error()),
			)
			payload = exporter.RenderErrorMetrics(version, now, err)
		}

		writer.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		writer.WriteHeader(http.StatusOK)
		_, _ = writer.Write([]byte(payload))
	})
	mux.HandleFunc("/", func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Content-Type", "text/plain; charset=utf-8")
		writer.WriteHeader(http.StatusOK)
		_, _ = writer.Write([]byte("postgres-dr-lab drill exporter\n/healthz\n/metrics\n"))
	})

	server := &http.Server{
		Addr:              listenAddress,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	logger.Info(
		"starting drill exporter",
		slog.String("listen_address", listenAddress),
		slog.String("artifacts_dir", artifactsDir),
	)

	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		logger.Error("exporter stopped unexpectedly", slog.String("error", err.Error()))
		os.Exit(1)
	}
}

func getenv(key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}
