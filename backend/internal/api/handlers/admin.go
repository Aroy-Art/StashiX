package handlers

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"gorm.io/gorm"
	"golang.org/x/crypto/bcrypt"
	"github.com/aroy/stashix/internal/models"
)

type AdminHandler struct {
	db *gorm.DB
}

func NewAdminHandler(db *gorm.DB) *AdminHandler {
	return &AdminHandler{db: db}
}

type userListOutput struct {
	Body []models.User
}

func (h *AdminHandler) listUsers(ctx context.Context, _ *struct{}) (*userListOutput, error) {
	if err := requireAdmin(ctx); err != nil {
		return nil, err
	}

	var users []models.User
	result := h.db.WithContext(ctx).Raw(
		`SELECT id, email, username, role, birth_date, created_at FROM users ORDER BY created_at DESC`,
	).Scan(&users)
	if result.Error != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "db error")
	}
	return &userListOutput{Body: users}, nil
}

type createUserInput struct {
	Body struct {
		Email     string `json:"email" required:"true"`
		Username  string `json:"username" required:"true"`
		Password  string `json:"password" required:"true"`
		Role      string `json:"role" enum:"admin,user" default:"user"`
		BirthDate string `json:"birth_date"`
	}
}

type createUserOutput struct {
	Body struct {
		ID string `json:"id"`
	}
}

func (h *AdminHandler) createUser(ctx context.Context, input *createUserInput) (*createUserOutput, error) {
	if err := requireAdmin(ctx); err != nil {
		return nil, err
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(input.Body.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "hash error")
	}

	role := input.Body.Role
	if role == "" {
		role = "user"
	}

	var id string
	result := h.db.WithContext(ctx).Raw(`
		INSERT INTO users (email, username, password_hash, role, birth_date)
		VALUES (?,?,?,?,NULLIF(?,'')::DATE)
		RETURNING id`,
		input.Body.Email, input.Body.Username, string(hash), role, input.Body.BirthDate,
	).Scan(&id)
	if result.Error != nil {
		return nil, huma.NewError(http.StatusConflict, "user already exists or invalid data")
	}

	out := &createUserOutput{}
	out.Body.ID = id
	return out, nil
}

type setPermissionsInput struct {
	ID   string `path:"id"`
	Body struct {
		LibraryID    string  `json:"library_id" required:"true"`
		CanRead      bool    `json:"can_read" required:"true"`
		MaxAgeRating *string `json:"max_age_rating"`
	}
}

type setPermissionsOutput struct {
	Body struct {
		OK bool `json:"ok"`
	}
}

func (h *AdminHandler) setPermissions(ctx context.Context, input *setPermissionsInput) (*setPermissionsOutput, error) {
	if err := requireAdmin(ctx); err != nil {
		return nil, err
	}

	result := h.db.WithContext(ctx).Exec(`
		INSERT INTO library_permissions (user_id, library_id, can_read, max_age_rating)
		VALUES (?,?,?,?::age_rating)
		ON CONFLICT (user_id, library_id) DO UPDATE
		  SET can_read=EXCLUDED.can_read, max_age_rating=EXCLUDED.max_age_rating`,
		input.ID, input.Body.LibraryID, input.Body.CanRead, input.Body.MaxAgeRating,
	)
	if result.Error != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "db error")
	}

	out := &setPermissionsOutput{}
	out.Body.OK = true
	return out, nil
}

func (h *AdminHandler) Register(api huma.API) {
	huma.Register(api, huma.Operation{
		OperationID: "listUsers",
		Method:      http.MethodGet,
		Path:        "/api/admin/users",
		Tags:        []string{"Admin"},
		Summary:     "List all users",
	}, h.listUsers)

	huma.Register(api, huma.Operation{
		OperationID:   "createUser",
		Method:        http.MethodPost,
		Path:          "/api/admin/users",
		Tags:          []string{"Admin"},
		Summary:       "Create a new user",
		DefaultStatus: http.StatusCreated,
	}, h.createUser)

	huma.Register(api, huma.Operation{
		OperationID: "setPermissions",
		Method:      http.MethodPatch,
		Path:        "/api/admin/users/{id}/permissions",
		Tags:        []string{"Admin"},
		Summary:     "Set a user's library permissions",
	}, h.setPermissions)
}
