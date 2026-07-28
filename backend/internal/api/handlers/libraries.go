package handlers

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/aroy/stashix/internal/auth"
	"github.com/aroy/stashix/internal/library"
	"github.com/aroy/stashix/internal/models"
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

type libraryListOutput struct {
	Body []models.Library
}

func (h *LibraryHandler) list(ctx context.Context, _ *struct{}) (*libraryListOutput, error) {
	claims := auth.ClaimsFromCtx(ctx)

	var query string
	var args []any
	if claims.Role == "admin" {
		query = `SELECT id::text, name, root_path, created_at FROM libraries ORDER BY name`
	} else {
		query = `
			SELECT l.id::text, l.name, l.root_path, l.created_at
			FROM libraries l
			JOIN library_permissions lp ON lp.library_id = l.id
			WHERE lp.user_id = $1 AND lp.can_read = TRUE
			ORDER BY l.name`
		args = []any{claims.UserID}
	}

	rows, err := h.db.Query(ctx, query, args...)
	if err != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "db error")
	}
	defer rows.Close()

	libs := []models.Library{}
	for rows.Next() {
		var l models.Library
		if err := rows.Scan(&l.ID, &l.Name, &l.RootPath, &l.CreatedAt); err != nil {
			return nil, huma.NewError(http.StatusInternalServerError, "db error")
		}
		libs = append(libs, l)
	}
	return &libraryListOutput{Body: libs}, nil
}

type createLibraryInput struct {
	Body struct {
		Name     string `json:"name" required:"true"`
		RootPath string `json:"root_path" required:"true"`
	}
}

type createLibraryOutput struct {
	Body struct {
		ID string `json:"id"`
	}
}

func (h *LibraryHandler) create(ctx context.Context, input *createLibraryInput) (*createLibraryOutput, error) {
	if err := requireAdmin(ctx); err != nil {
		return nil, err
	}

	var id string
	err := h.db.QueryRow(ctx,
		`INSERT INTO libraries (name, root_path) VALUES ($1,$2) RETURNING id`,
		input.Body.Name, input.Body.RootPath,
	).Scan(&id)
	if err != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "db error")
	}

	go h.scanner.Scan(context.Background(), id, input.Body.RootPath)

	out := &createLibraryOutput{}
	out.Body.ID = id
	return out, nil
}

type scanLibraryInput struct {
	ID string `path:"id"`
}

type scanLibraryOutput struct {
	Body struct {
		Status string `json:"status"`
	}
}

func (h *LibraryHandler) scan(ctx context.Context, input *scanLibraryInput) (*scanLibraryOutput, error) {
	if err := requireAdmin(ctx); err != nil {
		return nil, err
	}

	var rootPath string
	err := h.db.QueryRow(ctx, `SELECT root_path FROM libraries WHERE id=$1`, input.ID).Scan(&rootPath)
	if err != nil {
		return nil, huma.NewError(http.StatusNotFound, "library not found")
	}

	go h.scanner.Scan(context.Background(), input.ID, rootPath)

	out := &scanLibraryOutput{}
	out.Body.Status = "scanning"
	return out, nil
}

type tasksOutput struct {
	Body []library.ScanProgress
}

func (h *LibraryHandler) tasks(ctx context.Context, _ *struct{}) (*tasksOutput, error) {
	tasks := h.scanner.ActiveTasks()
	if tasks == nil {
		tasks = []library.ScanProgress{}
	}
	return &tasksOutput{Body: tasks}, nil
}

func (h *LibraryHandler) Register(api huma.API) {
	huma.Register(api, huma.Operation{
		OperationID: "listLibraries",
		Method:      http.MethodGet,
		Path:        "/api/libraries",
		Tags:        []string{"Libraries"},
		Summary:     "List libraries accessible to the current user",
	}, h.list)

	huma.Register(api, huma.Operation{
		OperationID:   "createLibrary",
		Method:        http.MethodPost,
		Path:          "/api/libraries",
		Tags:          []string{"Libraries"},
		Summary:       "Create a new library and trigger initial scan (admin)",
		DefaultStatus: http.StatusCreated,
	}, h.create)

	huma.Register(api, huma.Operation{
		OperationID:   "scanLibrary",
		Method:        http.MethodPost,
		Path:          "/api/libraries/{id}/scan",
		Tags:          []string{"Libraries"},
		Summary:       "Trigger a rescan of a library (admin)",
		DefaultStatus: http.StatusAccepted,
	}, h.scan)

	huma.Register(api, huma.Operation{
		OperationID: "listTasks",
		Method:      http.MethodGet,
		Path:        "/api/tasks",
		Tags:        []string{"Libraries"},
		Summary:     "Get currently active library scan tasks",
	}, h.tasks)
}
