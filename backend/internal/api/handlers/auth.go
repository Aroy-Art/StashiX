package handlers

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
	"github.com/aroy/stashix/internal/auth"
)

type AuthHandler struct {
	db     *pgxpool.Pool
	secret string
}

func NewAuthHandler(db *pgxpool.Pool, secret string) *AuthHandler {
	return &AuthHandler{db: db, secret: secret}
}

type tokenPairOutput struct {
	Body *auth.TokenPair
}

type loginInput struct {
	Body struct {
		Email    string `json:"email" required:"true"`
		Password string `json:"password" required:"true"`
	}
}

func (h *AuthHandler) login(ctx context.Context, input *loginInput) (*tokenPairOutput, error) {
	var userID, passwordHash, role string
	err := h.db.QueryRow(ctx,
		`SELECT id, password_hash, role FROM users WHERE email=$1`, input.Body.Email,
	).Scan(&userID, &passwordHash, &role)
	if err != nil {
		return nil, huma.NewError(http.StatusUnauthorized, "invalid credentials")
	}

	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(input.Body.Password)); err != nil {
		return nil, huma.NewError(http.StatusUnauthorized, "invalid credentials")
	}

	pair, err := auth.IssueTokenPair(userID, role, h.secret)
	if err != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "token error")
	}

	return &tokenPairOutput{Body: pair}, nil
}

type refreshInput struct {
	Body struct {
		RefreshToken string `json:"refresh_token" required:"true"`
	}
}

func (h *AuthHandler) refresh(ctx context.Context, input *refreshInput) (*tokenPairOutput, error) {
	claims, err := auth.Validate(input.Body.RefreshToken, h.secret)
	if err != nil {
		return nil, huma.NewError(http.StatusUnauthorized, "invalid refresh token")
	}

	pair, err := auth.IssueTokenPair(claims.UserID, claims.Role, h.secret)
	if err != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "token error")
	}

	return &tokenPairOutput{Body: pair}, nil
}

func (h *AuthHandler) Register(api huma.API) {
	noSec := []map[string][]string{}

	huma.Register(api, huma.Operation{
		OperationID: "login",
		Method:      http.MethodPost,
		Path:        "/api/auth/login",
		Tags:        []string{"Auth"},
		Summary:     "Authenticate with email and password",
		Security:    noSec,
	}, h.login)

	huma.Register(api, huma.Operation{
		OperationID: "refreshToken",
		Method:      http.MethodPost,
		Path:        "/api/auth/refresh",
		Tags:        []string{"Auth"},
		Summary:     "Refresh an expired access token",
		Security:    noSec,
	}, h.refresh)
}
