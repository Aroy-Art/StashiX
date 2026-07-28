package handlers

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"gorm.io/gorm"
	"github.com/aroy/stashix/internal/auth"
)

type UserHandler struct {
	db *gorm.DB
}

func NewUserHandler(db *gorm.DB) *UserHandler {
	return &UserHandler{db: db}
}

type profileOutput struct {
	Body struct {
		Username  string `json:"username"`
		Email     string `json:"email"`
		FirstName string `json:"first_name"`
		LastName  string `json:"last_name"`
		IsStaff   bool   `json:"is_staff"`
		IsAdmin   bool   `json:"is_admin"`
	}
}

func (h *UserHandler) profile(ctx context.Context, _ *struct{}) (*profileOutput, error) {
	claims := auth.ClaimsFromCtx(ctx)
	if claims == nil {
		return nil, huma.NewError(http.StatusUnauthorized, "unauthorized")
	}

	var row struct {
		Username  string
		Email     string
		FirstName string
		LastName  string
		Role      string
	}
	result := h.db.WithContext(ctx).Raw(
		`SELECT username, email, first_name, last_name, role FROM users WHERE id = ? LIMIT 1`,
		claims.UserID,
	).Scan(&row)
	if result.Error != nil || result.RowsAffected == 0 {
		return nil, huma.NewError(http.StatusNotFound, "user not found")
	}

	out := &profileOutput{}
	out.Body.Username = row.Username
	out.Body.Email = row.Email
	out.Body.FirstName = row.FirstName
	out.Body.LastName = row.LastName
	out.Body.IsStaff = row.Role == "admin"
	out.Body.IsAdmin = row.Role == "admin"
	return out, nil
}

func (h *UserHandler) Register(api huma.API) {
	huma.Register(api, huma.Operation{
		OperationID: "getUserProfile",
		Method:      http.MethodGet,
		Path:        "/api/user/profile",
		Tags:        []string{"User"},
		Summary:     "Get current user profile",
	}, h.profile)
}
