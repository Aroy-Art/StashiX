package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/aroy/stashix/internal/auth"
	"github.com/aroy/stashix/internal/media"
)

type BooksHandler struct {
	db *pgxpool.Pool
}

func NewBooksHandler(db *pgxpool.Pool) *BooksHandler {
	return &BooksHandler{db: db}
}

func (h *BooksHandler) Get(c *gin.Context) {
	id := c.Param("id")
	claims := auth.ClaimsFromCtx(c.Request.Context())

	row, err := h.db.Query(c.Request.Context(), `
		SELECT b.id, b.library_id, b.path, b.title, b.series, b.issue_number,
		       b.volume, b.year, b.publisher, b.format, b.page_count, b.file_size,
		       b.age_rating, b.language, b.summary, b.created_at
		FROM books b
		JOIN library_permissions lp ON lp.library_id = b.library_id
		WHERE b.id=$1 AND (lp.user_id=$2 OR $3='admin')
		LIMIT 1`, id, claims.UserID, claims.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer row.Close()

	if !row.Next() {
		c.JSON(http.StatusNotFound, gin.H{"error": "book not found"})
		return
	}
	vals, _ := row.Values()
	descs := row.FieldDescriptions()
	result := make(map[string]any, len(descs))
	for i, d := range descs {
		result[string(d.Name)] = vals[i]
	}
	c.JSON(http.StatusOK, result)
}

func (h *BooksHandler) Pages(c *gin.Context) {
	id := c.Param("id")

	var path, format string
	err := h.db.QueryRow(c.Request.Context(), `SELECT path, format FROM books WHERE id=$1`, id).Scan(&path, &format)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "book not found"})
		return
	}

	fmt := media.Format(format)
	pages, err := media.PageList(path, fmt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not read archive"})
		return
	}

	urls := make([]string, len(pages))
	for i := range pages {
		urls[i] = "/api/books/" + id + "/page/" + strconv.Itoa(i)
	}
	c.JSON(http.StatusOK, map[string]any{"count": len(pages), "pages": urls})
}

func (h *BooksHandler) Page(c *gin.Context) {
	id := c.Param("id")
	pageStr := c.Param("n")
	pageIdx, err := strconv.Atoi(pageStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid page number"})
		return
	}

	var path, format string
	if err := h.db.QueryRow(c.Request.Context(), `SELECT path, format FROM books WHERE id=$1`, id).Scan(&path, &format); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "book not found"})
		return
	}

	rc, mime, err := media.PageReader(path, media.Format(format), pageIdx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rc.Close()

	c.DataFromReader(http.StatusOK, -1, mime, rc, map[string]string{
		"Cache-Control": "public, max-age=86400",
	})
}

func (h *BooksHandler) File(c *gin.Context) {
	id := c.Param("id")

	var path, format string
	if err := h.db.QueryRow(c.Request.Context(), `SELECT path, format FROM books WHERE id=$1`, id).Scan(&path, &format); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "book not found"})
		return
	}

	if format != "epub" && format != "pdf" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "file endpoint only for epub/pdf"})
		return
	}

	c.File(path)
}

func (h *BooksHandler) Cover(c *gin.Context) {
	id := c.Param("id")

	var coverPath string
	err := h.db.QueryRow(c.Request.Context(), `SELECT path FROM book_covers WHERE book_id=$1`, id).Scan(&coverPath)
	if err == nil && coverPath != "" {
		c.File(coverPath)
		return
	}

	var bookPath, format string
	if err := h.db.QueryRow(c.Request.Context(), `SELECT path, format FROM books WHERE id=$1`, id).Scan(&bookPath, &format); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "book not found"})
		return
	}

	if format == "pdf" || format == "epub" {
		c.JSON(http.StatusNotFound, gin.H{"error": "no cover available"})
		return
	}

	rc, mime, err := media.CoverReader(bookPath, media.Format(format))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not read cover"})
		return
	}
	defer rc.Close()

	c.DataFromReader(http.StatusOK, -1, mime, rc, map[string]string{
		"Cache-Control": "public, max-age=604800",
	})
}

func (h *BooksHandler) UpdateProgress(c *gin.Context) {
	id := c.Param("id")
	claims := auth.ClaimsFromCtx(c.Request.Context())

	var body struct {
		Page int `json:"page"`
	}
	if err := json.NewDecoder(c.Request.Body).Decode(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}

	_, err := h.db.Exec(c.Request.Context(), `
		INSERT INTO reading_progress (user_id, book_id, current_page)
		VALUES ($1,$2,$3)
		ON CONFLICT (user_id, book_id) DO UPDATE SET current_page=$3, updated_at=NOW()`,
		claims.UserID, id, body.Page,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	c.JSON(http.StatusOK, map[string]any{"page": body.Page})
}

func (h *BooksHandler) ListByLibrary(c *gin.Context) {
	libID := c.Param("id")
	claims := auth.ClaimsFromCtx(c.Request.Context())

	limit, _ := strconv.Atoi(c.Query("limit"))
	offset, _ := strconv.Atoi(c.Query("offset"))
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	rows, err := h.db.Query(c.Request.Context(), `
		SELECT b.id, b.title, b.series, b.issue_number, b.year, b.format, b.page_count, b.age_rating
		FROM books b
		LEFT JOIN library_permissions lp ON lp.library_id = b.library_id AND lp.user_id=$2
		WHERE b.library_id=$1
		  AND ($3='admin' OR lp.can_read=TRUE)
		ORDER BY b.series NULLS LAST, b.issue_number
		LIMIT $4 OFFSET $5`,
		libID, claims.UserID, claims.Role, limit, offset,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
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
	c.JSON(http.StatusOK, results)
}
