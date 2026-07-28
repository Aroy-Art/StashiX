package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aroy/stashix/internal/api"
	"github.com/aroy/stashix/internal/config"
	"github.com/aroy/stashix/internal/db"
	"github.com/aroy/stashix/internal/library"
	"github.com/aroy/stashix/internal/watcher"
	"github.com/aroy/stashix/internal/ws"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	if err := db.Migrate(cfg.DatabaseURL, "migrations"); err != nil {
		log.Fatalf("migrate: %v", err)
	}

	gormDB, err := db.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db: %v", err)
	}
	sqlDB, err := gormDB.DB()
	if err != nil {
		log.Fatalf("db.DB(): %v", err)
	}
	defer sqlDB.Close()

	hub := ws.NewHub()
	scanner := library.NewScanner(gormDB, hub)

	fw, err := watcher.New(scanner)
	if err != nil {
		log.Fatalf("watcher: %v", err)
	}
	defer fw.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// load watched libraries
	var libs []struct {
		ID       string
		RootPath string
	}
	gormDB.WithContext(ctx).Raw(`SELECT id::text AS id, root_path FROM libraries`).Scan(&libs)
	if len(libs) > 0 {
		libMap := make(map[string]string, len(libs))
		for _, l := range libs {
			fw.Add(l.ID, l.RootPath)
			libMap[l.RootPath] = l.ID
		}
		go fw.Run(ctx, libMap)
	}

	router := api.NewRouter(gormDB, hub, scanner, cfg.JWTSecret)

	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      router,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 0,
		IdleTimeout:  120 * time.Second,
	}

	go func() {
		log.Printf("listening on :%s", cfg.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("shutting down...")
	shutCtx, shutCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutCancel()
	srv.Shutdown(shutCtx)
}
