package handlers

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"

	"github.com/danielgtaylor/huma/v2"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"github.com/aroy/stashix/internal/auth"
	"github.com/aroy/stashix/internal/media"
	"github.com/aroy/stashix/internal/models"
)

type BooksHandler struct {
	db           *gorm.DB
	thumbnailDir string
}

func NewBooksHandler(db *gorm.DB, thumbnailDir string) *BooksHandler {
	return &BooksHandler{db: db, thumbnailDir: thumbnailDir}
}

type BookDetail struct {
	models.Book
	FolderPath string `json:"folder_path,omitempty"`
}

type getBookInput struct {
	ID string `path:"id"`
}

type getBookOutput struct {
	Body *BookDetail
}

func (h *BooksHandler) get(ctx context.Context, input *getBookInput) (*getBookOutput, error) {
	claims := auth.ClaimsFromCtx(ctx)

	var b models.Book
	result := h.db.WithContext(ctx).Raw(`
		SELECT b.id, b.library_id, b.path, b.title, b.type, b.series_id, b.series,
		       b.issue_number, b.volume, b.year, b.publisher, b.format, b.page_count,
		       b.file_size, b.age_rating, b.language, b.summary, b.created_at,
		       rp.current_page
		FROM books b
		LEFT JOIN library_permissions lp ON lp.library_id = b.library_id AND lp.user_id=?
		LEFT JOIN reading_progress rp ON rp.book_id = b.id AND rp.user_id=?
		WHERE b.id=? AND (?='admin' OR lp.can_read=TRUE)
		LIMIT 1`, claims.UserID, claims.UserID, input.ID, claims.Role,
	).Scan(&b)
	if result.Error != nil || result.RowsAffected == 0 {
		return nil, huma.NewError(http.StatusNotFound, "book not found")
	}

	folderPath := ""
	if b.Path != "" {
		var libraryRootPath string
		h.db.WithContext(ctx).Raw(
			`SELECT root_path FROM libraries WHERE id = ?`, b.LibraryID,
		).Scan(&libraryRootPath)
		if libraryRootPath != "" {
			rel, err := filepath.Rel(libraryRootPath, b.Path)
			if err == nil {
				folderPath = rel
			} else {
				folderPath = b.Path
			}
		} else {
			folderPath = b.Path
		}
	}

	return &getBookOutput{Body: &BookDetail{Book: b, FolderPath: folderPath}}, nil
}

type listByLibraryInput struct {
	ID     string `path:"id"`
	Limit  int    `query:"limit" minimum:"1" maximum:"100" default:"50"`
	Offset int    `query:"offset" minimum:"0" default:"0"`
	Sort   string `query:"sort" enum:"series,recent" default:"series"`
	Type   string `query:"type" enum:"all,standalone,issues" default:"all"`
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

	typeFilter := ""
	switch input.Type {
	case "standalone":
		typeFilter = " AND b.type = 'standalone'"
	case "issues":
		typeFilter = " AND b.type = 'issue'"
	}

	orderBy := "ORDER BY b.series NULLS LAST, b.issue_number"
	if input.Sort == "recent" {
		orderBy = "ORDER BY b.created_at DESC"
	}

	query := fmt.Sprintf(`
		SELECT b.id, b.title, b.type, b.series, b.issue_number, b.year, b.format, b.page_count, b.file_size, b.age_rating
		FROM books b
		LEFT JOIN library_permissions lp ON lp.library_id = b.library_id AND lp.user_id=?
		WHERE b.library_id=?
		  AND (?='admin' OR lp.can_read=TRUE)%s
		%s
		LIMIT ? OFFSET ?`, typeFilter, orderBy)

	var books []models.BookSummary
	result := h.db.WithContext(ctx).Raw(query,
		claims.UserID, input.ID, claims.Role, limit, input.Offset,
	).Scan(&books)
	if result.Error != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "db error")
	}
	if books == nil {
		books = []models.BookSummary{}
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
	var row struct {
		Path   string
		Format string
	}
	result := h.db.WithContext(ctx).Raw(
		`SELECT path, format FROM books WHERE id=?`, input.ID,
	).Scan(&row)
	if result.Error != nil || result.RowsAffected == 0 {
		return nil, huma.NewError(http.StatusNotFound, "book not found")
	}

	pageList, err := media.PageList(row.Path, media.Format(row.Format))
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

	result := h.db.WithContext(ctx).Exec(`
		INSERT INTO reading_progress (user_id, book_id, current_page)
		VALUES (?,?,?)
		ON CONFLICT (user_id, book_id) DO UPDATE SET current_page=EXCLUDED.current_page, updated_at=NOW()`,
		claims.UserID, input.ID, input.Body.Page,
	)
	if result.Error != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "db error")
	}

	out := &updateProgressOutput{}
	out.Body.Page = input.Body.Page
	return out, nil
}

func (h *BooksHandler) Page(c *gin.Context) {
	id := c.Param("id")
	pageIdx, err := strconv.Atoi(c.Param("n"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid page number"})
		return
	}

	var row struct {
		Path   string
		Format string
	}
	result := h.db.WithContext(c.Request.Context()).Raw(
		`SELECT path, format FROM books WHERE id=?`, id,
	).Scan(&row)
	if result.Error != nil || result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "book not found"})
		return
	}

	rc, mime, err := media.PageReader(row.Path, media.Format(row.Format), pageIdx)
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
	size := c.Query("thumbnail")

	var coverPath string
	r1 := h.db.WithContext(c.Request.Context()).Raw(
		`SELECT path FROM book_covers WHERE book_id=?`, id,
	).Scan(&coverPath)
	if r1.Error == nil && r1.RowsAffected > 0 && coverPath != "" {
		if size != "" {
			p := coverPath
			media.ServeThumbnail(c, h.thumbnailDir, "books", id, size, func() (io.ReadCloser, error) {
				return os.Open(p)
			})
			return
		}
		c.Header("Cache-Control", "public, max-age=604800")
		c.File(coverPath)
		return
	}

	var row struct {
		Path   string
		Format string
	}
	r2 := h.db.WithContext(c.Request.Context()).Raw(
		`SELECT path, format FROM books WHERE id=?`, id,
	).Scan(&row)
	if r2.Error != nil || r2.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "book not found"})
		return
	}

	if row.Format == "pdf" || row.Format == "epub" {
		c.JSON(http.StatusNotFound, gin.H{"error": "no cover available"})
		return
	}

	if size != "" {
		bookPath, bookFormat := row.Path, row.Format
		media.ServeThumbnail(c, h.thumbnailDir, "books", id, size, func() (io.ReadCloser, error) {
			rc, _, err := media.CoverReader(bookPath, media.Format(bookFormat))
			return rc, err
		})
		return
	}

	rc, mime, err := media.CoverReader(row.Path, media.Format(row.Format))
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

	var row struct {
		Path   string
		Format string
	}
	result := h.db.WithContext(c.Request.Context()).Raw(
		`SELECT path, format FROM books WHERE id=?`, id,
	).Scan(&row)
	if result.Error != nil || result.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "book not found"})
		return
	}

	if row.Format != "epub" && row.Format != "pdf" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "file endpoint only for epub/pdf"})
		return
	}

	c.File(row.Path)
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
