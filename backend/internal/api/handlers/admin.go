package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

type AdminHandler struct {
	db *pgxpool.Pool
}

func NewAdminHandler(db *pgxpool.Pool) *AdminHandler {
	return &AdminHandler{db: db}
}

func (h *AdminHandler) ListUsers(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(),
		`SELECT id, email, username, role, birth_date, created_at FROM users ORDER BY created_at DESC`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	var users []map[string]any
	for rows.Next() {
		vals, _ := rows.Values()
		descs := rows.FieldDescriptions()
		row := make(map[string]any, len(descs))
		for i, d := range descs {
			row[string(d.Name)] = vals[i]
		}
		users = append(users, row)
	}
	if users == nil {
		users = []map[string]any{}
	}
	c.JSON(http.StatusOK, users)
}

func (h *AdminHandler) CreateUser(c *gin.Context) {
	var body struct {
		Email     string `json:"email"`
		Username  string `json:"username"`
		Password  string `json:"password"`
		Role      string `json:"role"`
		BirthDate string `json:"birth_date"`
	}
	if err := json.NewDecoder(c.Request.Body).Decode(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(body.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "hash error"})
		return
	}

	role := body.Role
	if role == "" {
		role = "user"
	}

	var id string
	err = h.db.QueryRow(c.Request.Context(), `
		INSERT INTO users (email, username, password_hash, role, birth_date)
		VALUES ($1,$2,$3,$4,NULLIF($5,'')::DATE)
		RETURNING id`,
		body.Email, body.Username, string(hash), role, body.BirthDate,
	).Scan(&id)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "user already exists or invalid data"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"id": id})
}

func (h *AdminHandler) SetPermissions(c *gin.Context) {
	userID := c.Param("id")

	var body struct {
		LibraryID    string  `json:"library_id"`
		CanRead      bool    `json:"can_read"`
		MaxAgeRating *string `json:"max_age_rating"`
	}
	if err := json.NewDecoder(c.Request.Body).Decode(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}

	_, err := h.db.Exec(c.Request.Context(), `
		INSERT INTO library_permissions (user_id, library_id, can_read, max_age_rating)
		VALUES ($1,$2,$3,$4::age_rating)
		ON CONFLICT (user_id, library_id) DO UPDATE
		  SET can_read=$3, max_age_rating=$4::age_rating`,
		userID, body.LibraryID, body.CanRead, body.MaxAgeRating,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"ok": true})
}
