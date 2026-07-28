package handlers

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
	"github.com/aroy/stashix/internal/auth"
)

type SetupHandler struct {
	db     *pgxpool.Pool
	secret string
}

func NewSetupHandler(db *pgxpool.Pool, secret string) *SetupHandler {
	return &SetupHandler{db: db, secret: secret}
}

type setupStatusOutput struct {
	Body struct {
		NeedsSetup bool `json:"needs_setup"`
	}
}

func (h *SetupHandler) status(ctx context.Context, _ *struct{}) (*setupStatusOutput, error) {
	var count int
	h.db.QueryRow(ctx, `SELECT COUNT(*) FROM users`).Scan(&count)
	out := &setupStatusOutput{}
	out.Body.NeedsSetup = count == 0
	return out, nil
}

type setupRunInput struct {
	Body struct {
		Email    string `json:"email" required:"true"`
		Username string `json:"username" required:"true"`
		Password string `json:"password" required:"true" minLength:"8"`
	}
}

func (h *SetupHandler) run(ctx context.Context, input *setupRunInput) (*tokenPairOutput, error) {
	var count int
	h.db.QueryRow(ctx, `SELECT COUNT(*) FROM users`).Scan(&count)
	if count > 0 {
		return nil, huma.NewError(http.StatusForbidden, "setup already complete")
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(input.Body.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "hash error")
	}

	var userID string
	err = h.db.QueryRow(ctx, `
		INSERT INTO users (email, username, password_hash, role)
		VALUES ($1, $2, $3, 'admin')
		RETURNING id`,
		input.Body.Email, input.Body.Username, string(hash),
	).Scan(&userID)
	if err != nil {
		return nil, huma.NewError(http.StatusConflict, "could not create user")
	}

	pair, err := auth.IssueTokenPair(userID, "admin", h.secret)
	if err != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "token error")
	}

	return &tokenPairOutput{Body: pair}, nil
}

func (h *SetupHandler) Register(api huma.API) {
	noSec := []map[string][]string{}

	huma.Register(api, huma.Operation{
		OperationID: "getSetupStatus",
		Method:      http.MethodGet,
		Path:        "/api/setup/status",
		Tags:        []string{"Setup"},
		Summary:     "Check if initial setup is required",
		Security:    noSec,
	}, h.status)

	huma.Register(api, huma.Operation{
		OperationID:   "runSetup",
		Method:        http.MethodPost,
		Path:          "/api/setup",
		Tags:          []string{"Setup"},
		Summary:       "Create initial admin user",
		Security:      noSec,
		DefaultStatus: http.StatusCreated,
	}, h.run)
}
