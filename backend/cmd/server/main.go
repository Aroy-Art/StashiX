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

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db: %v", err)
	}
	defer pool.Close()

	hub := ws.NewHub()
	scanner := library.NewScanner(pool, hub)

	fw, err := watcher.New(scanner)
	if err != nil {
		log.Fatalf("watcher: %v", err)
	}
	defer fw.Close()

	// load watched libraries
	rows, err := pool.Query(ctx, `SELECT id, root_path FROM libraries`)
	if err == nil {
		libMap := make(map[string]string)
		for rows.Next() {
			var id, path string
			rows.Scan(&id, &path)
			fw.Add(id, path)
			libMap[path] = id
		}
		rows.Close()
		go fw.Run(ctx, libMap)
	}

	router := api.NewRouter(pool, hub, scanner, cfg.JWTSecret)

	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      router,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 0, // streaming
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
