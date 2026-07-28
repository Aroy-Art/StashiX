package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/danielgtaylor/huma/v2"
	"github.com/danielgtaylor/huma/v2/adapters/humagin"
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"github.com/aroy/stashix/internal/api/handlers"
	"github.com/aroy/stashix/internal/auth"
	"github.com/aroy/stashix/internal/library"
	"github.com/aroy/stashix/internal/ws"
)

func NewRouter(db *gorm.DB, hub *ws.Hub, scanner *library.Scanner, jwtSecret string) http.Handler {
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

	publicPaths := map[string]struct{}{
		"/api/auth/login":   {},
		"/api/auth/refresh": {},
		"/api/setup":        {},
		"/api/setup/status": {},
	}
	ginAuth := auth.GinMiddleware(jwtSecret)
	r.Use(func(c *gin.Context) {
		p := c.Request.URL.Path
		if strings.HasPrefix(p, "/docs") ||
			strings.HasPrefix(p, "/openapi") ||
			strings.HasPrefix(p, "/schemas") {
			c.Next()
			return
		}
		if _, ok := publicPaths[p]; ok {
			c.Next()
			return
		}
		ginAuth(c)
	})

	config := huma.DefaultConfig("Stashix API", "1.0.0")
	config.Info.Description = "Comic and book library management API."
	config.Components.SecuritySchemes = map[string]*huma.SecurityScheme{
		"bearerAuth": {Type: "http", Scheme: "bearer", BearerFormat: "JWT"},
	}
	config.Security = []map[string][]string{{"bearerAuth": {}}}

	api := humagin.New(r, config)

	wsRouter := ws.NewRouter(hub)
	registerWSHandlers(wsRouter, db)
	r.GET("/ws", gin.WrapH(wsRouter))

	booksH := handlers.NewBooksHandler(db)
	r.GET("/api/books/:id/page/:n", booksH.Page)
	r.GET("/api/books/:id/cover", booksH.Cover)
	r.GET("/api/books/:id/file", booksH.File)

	handlers.NewAuthHandler(db, jwtSecret).Register(api)
	handlers.NewSetupHandler(db, jwtSecret).Register(api)
	handlers.NewLibraryHandler(db, scanner, hub).Register(api)
	booksH.Register(api)
	handlers.NewSearchHandler(db).Register(api)
	handlers.NewAdminHandler(db).Register(api)
	handlers.NewUserHandler(db).Register(api)

	return r
}

func registerWSHandlers(r *ws.Router, db *gorm.DB) {
	r.Handle("update_progress", func(ctx context.Context, userID string, payload json.RawMessage) (any, error) {
		var body struct {
			BookID string `json:"book_id"`
			Page   int    `json:"page"`
		}
		if err := json.Unmarshal(payload, &body); err != nil {
			return nil, err
		}
		result := db.WithContext(ctx).Exec(`
			INSERT INTO reading_progress (user_id, book_id, current_page)
			VALUES (?,?,?)
			ON CONFLICT (user_id, book_id) DO UPDATE SET current_page=EXCLUDED.current_page, updated_at=NOW()`,
			userID, body.BookID, body.Page,
		)
		return map[string]any{"page": body.Page}, result.Error
	})
}
