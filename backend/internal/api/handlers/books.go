package handlers

import (
	"context"
	"net/http"
	"strconv"

	"github.com/danielgtaylor/huma/v2"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/aroy/stashix/internal/auth"
	"github.com/aroy/stashix/internal/media"
	"github.com/aroy/stashix/internal/models"
)

type BooksHandler struct {
	db *pgxpool.Pool
}

func NewBooksHandler(db *pgxpool.Pool) *BooksHandler {
	return &BooksHandler{db: db}
}

// ─── huma handlers (JSON) ────────────────────────────────────────────────────

type getBookInput struct {
	ID string `path:"id"`
}

type getBookOutput struct {
	Body *models.Book
}

func (h *BooksHandler) get(ctx context.Context, input *getBookInput) (*getBookOutput, error) {
	claims := auth.ClaimsFromCtx(ctx)

	var b models.Book
	err := h.db.QueryRow(ctx, `
		SELECT b.id, b.library_id, b.path, b.title, b.series, b.issue_number,
		       b.volume, b.year, b.publisher, b.format, b.page_count, b.file_size,
		       b.age_rating, b.language, b.summary, b.created_at
		FROM books b
		JOIN library_permissions lp ON lp.library_id = b.library_id
		WHERE b.id=$1 AND (lp.user_id=$2 OR $3='admin')
		LIMIT 1`, input.ID, claims.UserID, claims.Role,
	).Scan(
		&b.ID, &b.LibraryID, &b.Path, &b.Title,
		&b.Series, &b.IssueNumber, &b.Volume, &b.Year,
		&b.Publisher, &b.Format, &b.PageCount, &b.FileSize,
		&b.AgeRating, &b.Language, &b.Summary, &b.CreatedAt,
	)
	if err != nil {
		return nil, huma.NewError(http.StatusNotFound, "book not found")
	}
	return &getBookOutput{Body: &b}, nil
}

type listByLibraryInput struct {
	ID     string `path:"id"`
	Limit  int    `query:"limit" minimum:"1" maximum:"100" default:"50"`
	Offset int    `query:"offset" minimum:"0" default:"0"`
}

type bookListOutput struct {
	Body []models.BookSummary
}

func (h *BooksHandler) listByLibrary(ctx context.Context, input *listByLibraryInput) (*bookListOutput, error) {
	claims := auth.ClaimsFromCtx(ctx)

	limit := input.Limit
	if limit <= 0 {
		limit = 50
	}

	rows, err := h.db.Query(ctx, `
		SELECT b.id, b.title, b.series, b.issue_number, b.year, b.format, b.page_count, b.age_rating
		FROM books b
		LEFT JOIN library_permissions lp ON lp.library_id = b.library_id AND lp.user_id=$2
		WHERE b.library_id=$1
		  AND ($3='admin' OR lp.can_read=TRUE)
		ORDER BY b.series NULLS LAST, b.issue_number
		LIMIT $4 OFFSET $5`,
		input.ID, claims.UserID, claims.Role, limit, input.Offset,
	)
	if err != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "db error")
	}
	defer rows.Close()

	books := []models.BookSummary{}
	for rows.Next() {
		var b models.BookSummary
		if err := rows.Scan(&b.ID, &b.Title, &b.Series, &b.IssueNumber, &b.Year, &b.Format, &b.PageCount, &b.AgeRating); err != nil {
			return nil, huma.NewError(http.StatusInternalServerError, "db error")
		}
		books = append(books, b)
	}
	return &bookListOutput{Body: books}, nil
}

type pagesInput struct {
	ID string `path:"id"`
}

type pagesOutput struct {
	Body struct {
		Count int      `json:"count"`
		Pages []string `json:"pages"`
	}
}

func (h *BooksHandler) pages(ctx context.Context, input *pagesInput) (*pagesOutput, error) {
	var path, format string
	if err := h.db.QueryRow(ctx, `SELECT path, format FROM books WHERE id=$1`, input.ID).Scan(&path, &format); err != nil {
		return nil, huma.NewError(http.StatusNotFound, "book not found")
	}

	pageList, err := media.PageList(path, media.Format(format))
	if err != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "could not read archive")
	}

	urls := make([]string, len(pageList))
	for i := range pageList {
		urls[i] = "/api/books/" + input.ID + "/page/" + strconv.Itoa(i)
	}

	out := &pagesOutput{}
	out.Body.Count = len(pageList)
	out.Body.Pages = urls
	return out, nil
}

type updateProgressInput struct {
	ID   string `path:"id"`
	Body struct {
		Page int `json:"page" minimum:"0" required:"true"`
	}
}

type updateProgressOutput struct {
	Body struct {
		Page int `json:"page"`
	}
}

func (h *BooksHandler) updateProgress(ctx context.Context, input *updateProgressInput) (*updateProgressOutput, error) {
	claims := auth.ClaimsFromCtx(ctx)

	_, err := h.db.Exec(ctx, `
		INSERT INTO reading_progress (user_id, book_id, current_page)
		VALUES ($1,$2,$3)
		ON CONFLICT (user_id, book_id) DO UPDATE SET current_page=$3, updated_at=NOW()`,
		claims.UserID, input.ID, input.Body.Page,
	)
	if err != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "db error")
	}

	out := &updateProgressOutput{}
	out.Body.Page = input.Body.Page
	return out, nil
}

// ─── gin handlers (binary streams) ───────────────────────────────────────────

func (h *BooksHandler) Page(c *gin.Context) {
	id := c.Param("id")
	pageIdx, err := strconv.Atoi(c.Param("n"))
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

func (h *BooksHandler) Cover(c *gin.Context) {
	id := c.Param("id")

	var coverPath string
	if err := h.db.QueryRow(c.Request.Context(), `SELECT path FROM book_covers WHERE book_id=$1`, id).Scan(&coverPath); err == nil && coverPath != "" {
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

func (h *BooksHandler) Register(api huma.API) {
	huma.Register(api, huma.Operation{
		OperationID: "getBook",
		Method:      http.MethodGet,
		Path:        "/api/books/{id}",
		Tags:        []string{"Books"},
		Summary:     "Get full book metadata",
	}, h.get)

	huma.Register(api, huma.Operation{
		OperationID: "listBooksByLibrary",
		Method:      http.MethodGet,
		Path:        "/api/libraries/{id}/books",
		Tags:        []string{"Books"},
		Summary:     "List books in a library with pagination",
	}, h.listByLibrary)

	huma.Register(api, huma.Operation{
		OperationID: "getBookPages",
		Method:      http.MethodGet,
		Path:        "/api/books/{id}/pages",
		Tags:        []string{"Books"},
		Summary:     "Get page count and URL list",
	}, h.pages)

	huma.Register(api, huma.Operation{
		OperationID: "updateProgress",
		Method:      http.MethodPut,
		Path:        "/api/books/{id}/progress",
		Tags:        []string{"Books"},
		Summary:     "Update reading progress for the current user",
	}, h.updateProgress)
}
