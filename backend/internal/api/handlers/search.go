package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/aroy/stashix/internal/auth"
)

type SearchHandler struct {
	db *pgxpool.Pool
}

func NewSearchHandler(db *pgxpool.Pool) *SearchHandler {
	return &SearchHandler{db: db}
}

func (h *SearchHandler) Search(c *gin.Context) {
	q := c.Query("q")
	libraryID := c.Query("library_id")
	ageRating := c.Query("age_rating")

	limit, _ := strconv.Atoi(c.Query("limit"))
	offset, _ := strconv.Atoi(c.Query("offset"))
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	claims := auth.ClaimsFromCtx(c.Request.Context())

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT b.id, b.title, b.series, b.issue_number, b.year, b.format, b.age_rating,
		       ts_rank(b.search_vec, query) AS rank
		FROM books b,
		     plainto_tsquery('english', $1) query
		LEFT JOIN library_permissions lp ON lp.library_id = b.library_id AND lp.user_id=$2
		WHERE ($1 = '' OR b.search_vec @@ query)
		  AND ($3 = '' OR b.library_id::text = $3)
		  AND ($4 = '' OR b.age_rating = $4::age_rating)
		  AND ($5 = 'admin' OR lp.can_read = TRUE)
		ORDER BY rank DESC, b.title
		LIMIT $6 OFFSET $7`,
		q, claims.UserID, libraryID, ageRating, claims.Role, limit, offset,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "search error"})
		return
	}
	defer rows.Close()

	var results []map[string]any
	for rows.Next() {
		vals, _ := rows.Values()
		descs := rows.FieldDescriptions()
		row := make(map[string]any, len(descs))
		for i, d := range descs {
			row[string(d.Name)] = vals[i]
		}
		results = append(results, row)
	}
	if results == nil {
		results = []map[string]any{}
	}
	c.JSON(http.StatusOK, map[string]any{"results": results, "offset": offset, "limit": limit})
}
