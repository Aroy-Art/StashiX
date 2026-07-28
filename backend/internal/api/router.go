package api

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/aroy/stashix/internal/api/handlers"
	"github.com/aroy/stashix/internal/auth"
	"github.com/aroy/stashix/internal/library"
	"github.com/aroy/stashix/internal/ws"
)

func NewRouter(db *pgxpool.Pool, hub *ws.Hub, scanner *library.Scanner, jwtSecret string) http.Handler {
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Logger())
	r.Use(gin.Recovery())
	r.Use(cors.New(cors.Config{
		AllowAllOrigins:  true,
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Accept", "Authorization", "Content-Type"},
		AllowCredentials: false,
		MaxAge:           300 * time.Second,
	}))

	authH := handlers.NewAuthHandler(db, jwtSecret)
	libH := handlers.NewLibraryHandler(db, scanner, hub)
	booksH := handlers.NewBooksHandler(db)
	searchH := handlers.NewSearchHandler(db)
	adminH := handlers.NewAdminHandler(db)
	setupH := handlers.NewSetupHandler(db, jwtSecret)

	wsRouter := ws.NewRouter(hub)
	registerWSHandlers(wsRouter, db)

	registerDocs(r)

	// public
	r.GET("/api/setup/status", setupH.Status)
	r.POST("/api/setup", setupH.Run)
	r.POST("/api/auth/login", authH.Login)
	r.POST("/api/auth/refresh", authH.Refresh)

	// authenticated
	authed := r.Group("")
	authed.Use(auth.GinMiddleware(jwtSecret))
	{
		authed.GET("/ws", gin.WrapH(wsRouter))

		authed.GET("/api/libraries", libH.List)
		authed.GET("/api/tasks", libH.Tasks)

		authed.GET("/api/libraries/:id/books", booksH.ListByLibrary)
		authed.GET("/api/books/:id", booksH.Get)
		authed.GET("/api/books/:id/pages", booksH.Pages)
		authed.GET("/api/books/:id/page/:n", booksH.Page)
		authed.GET("/api/books/:id/file", booksH.File)
		authed.GET("/api/books/:id/cover", booksH.Cover)
		authed.PUT("/api/books/:id/progress", booksH.UpdateProgress)

		authed.GET("/api/search", searchH.Search)

		// admin only
		admin := authed.Group("")
		admin.Use(auth.GinAdminOnly())
		{
			admin.GET("/api/admin/users", adminH.ListUsers)
			admin.POST("/api/admin/users", adminH.CreateUser)
			admin.PATCH("/api/admin/users/:id/permissions", adminH.SetPermissions)
			admin.POST("/api/libraries", libH.Create)
			admin.POST("/api/libraries/:id/scan", libH.Scan)
		}
	}

	return r
}

// registerWSHandlers wires WS message types to their handler funcs.
// Each handler mirrors its REST counterpart — same logic, WS transport.
func registerWSHandlers(r *ws.Router, db *pgxpool.Pool) {
	// progress sync — client sends page update over WS
	r.Handle("update_progress", func(ctx context.Context, userID string, payload json.RawMessage) (any, error) {
		var body struct {
			BookID string `json:"book_id"`
			Page   int    `json:"page"`
		}
		if err := json.Unmarshal(payload, &body); err != nil {
			return nil, err
		}
		_, err := db.Exec(ctx, `
			INSERT INTO reading_progress (user_id, book_id, current_page)
			VALUES ($1,$2,$3)
			ON CONFLICT (user_id, book_id) DO UPDATE SET current_page=$3, updated_at=NOW()`,
			userID, body.BookID, body.Page,
		)
		return map[string]any{"page": body.Page}, err
	})
}
