package handlers

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/aroy/stashix/internal/auth"
	"github.com/aroy/stashix/internal/library"
	"github.com/aroy/stashix/internal/ws"
)

type LibraryHandler struct {
	db      *pgxpool.Pool
	scanner *library.Scanner
	hub     *ws.Hub
}

func NewLibraryHandler(db *pgxpool.Pool, scanner *library.Scanner, hub *ws.Hub) *LibraryHandler {
	return &LibraryHandler{db: db, scanner: scanner, hub: hub}
}

func (h *LibraryHandler) List(c *gin.Context) {
	claims := auth.ClaimsFromCtx(c.Request.Context())

	var rows []map[string]any
	var err error

	if claims.Role == "admin" {
		rows, err = queryLibraries(c.Request.Context(), h.db, `SELECT id::text, name, root_path, created_at FROM libraries ORDER BY name`)
	} else {
		rows, err = queryLibraries(c.Request.Context(), h.db, `
			SELECT l.id::text, l.name, l.root_path, l.created_at
			FROM libraries l
			JOIN library_permissions lp ON lp.library_id = l.id
			WHERE lp.user_id = $1 AND lp.can_read = TRUE
			ORDER BY l.name`, claims.UserID)
	}

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if rows == nil {
		rows = []map[string]any{}
	}
	c.JSON(http.StatusOK, rows)
}

func (h *LibraryHandler) Create(c *gin.Context) {
	var body struct {
		Name     string `json:"name"`
		RootPath string `json:"root_path"`
	}
	if err := json.NewDecoder(c.Request.Body).Decode(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}

	var id string
	err := h.db.QueryRow(c.Request.Context(),
		`INSERT INTO libraries (name, root_path) VALUES ($1,$2) RETURNING id`,
		body.Name, body.RootPath,
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	go h.scanner.Scan(context.Background(), id, body.RootPath)

	c.JSON(http.StatusCreated, gin.H{"id": id})
}

func (h *LibraryHandler) Scan(c *gin.Context) {
	id := c.Param("id")
	var rootPath string
	err := h.db.QueryRow(c.Request.Context(), `SELECT root_path FROM libraries WHERE id=$1`, id).Scan(&rootPath)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "library not found"})
		return
	}
	go h.scanner.Scan(context.Background(), id, rootPath)
	c.JSON(http.StatusAccepted, gin.H{"status": "scanning"})
}

func queryLibraries(ctx context.Context, db *pgxpool.Pool, query string, args ...any) ([]map[string]any, error) {
	rows, err := db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var results []map[string]any
	for rows.Next() {
		vals, err := rows.Values()
		if err != nil {
			return nil, err
		}
		descs := rows.FieldDescriptions()
		row := make(map[string]any, len(descs))
		for i, d := range descs {
			row[string(d.Name)] = vals[i]
		}
		results = append(results, row)
	}
	return results, nil
}
