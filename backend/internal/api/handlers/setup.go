package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gin-gonic/gin"
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

func (h *SetupHandler) Status(c *gin.Context) {
	var count int
	h.db.QueryRow(c.Request.Context(), `SELECT COUNT(*) FROM users`).Scan(&count)
	c.JSON(http.StatusOK, gin.H{"needs_setup": count == 0})
}

func (h *SetupHandler) Run(c *gin.Context) {
	var count int
	h.db.QueryRow(c.Request.Context(), `SELECT COUNT(*) FROM users`).Scan(&count)
	if count > 0 {
		c.JSON(http.StatusForbidden, gin.H{"error": "setup already complete"})
		return
	}

	var body struct {
		Email    string `json:"email"`
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(c.Request.Body).Decode(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if body.Email == "" || body.Username == "" || body.Password == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "email, username, and password required"})
		return
	}
	if len(body.Password) < 8 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "password must be at least 8 characters"})
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(body.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "hash error"})
		return
	}

	var userID string
	err = h.db.QueryRow(c.Request.Context(), `
		INSERT INTO users (email, username, password_hash, role)
		VALUES ($1, $2, $3, 'admin')
		RETURNING id`,
		body.Email, body.Username, string(hash),
	).Scan(&userID)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "could not create user"})
		return
	}

	pair, err := auth.IssueTokenPair(userID, "admin", h.secret)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "token error"})
		return
	}

	c.JSON(http.StatusCreated, pair)
}
