package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	DatabaseURL   string
	JWTSecret     string
	Port          string
	DataDir       string
	ThumbnailDir  string
	MaxUploadSize int64
}

func Load() (*Config, error) {
	cfg := &Config{
		DatabaseURL:   env("DATABASE_URL", ""),
		JWTSecret:     env("JWT_SECRET", ""),
		Port:          env("PORT", "8080"),
		DataDir:       env("DATA_DIR", "/data"),
		ThumbnailDir:  env("THUMBNAIL_DIR", "/data/thumbnails"),
		MaxUploadSize: envInt64("MAX_UPLOAD_SIZE", 500<<20), // 500 MB
	}

	if cfg.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}
	if cfg.JWTSecret == "" {
		return nil, fmt.Errorf("JWT_SECRET is required")
	}

	return cfg, nil
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envInt64(key string, fallback int64) int64 {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			return n
		}
	}
	return fallback
}
