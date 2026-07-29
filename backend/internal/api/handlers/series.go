package handlers

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"github.com/aroy/stashix/internal/auth"
	"github.com/aroy/stashix/internal/media"
	"github.com/aroy/stashix/internal/models"
)

type SeriesHandler struct {
	db *gorm.DB
}

func NewSeriesHandler(db *gorm.DB) *SeriesHandler {
	return &SeriesHandler{db: db}
}

type SeriesDetail struct {
	models.Series
	Books []models.BookSummary `json:"books"`
}

type getSeriesInput struct {
	ID string `path:"id"`
}

type getSeriesOutput struct {
	Body *SeriesDetail
}

func (h *SeriesHandler) get(ctx context.Context, input *getSeriesInput) (*getSeriesOutput, error) {
	claims := auth.ClaimsFromCtx(ctx)

	var s models.Series
	result := h.db.WithContext(ctx).Raw(`
		SELECT s.id, s.library_id, s.name, s.publisher, s.start_year, s.end_year, s.ongoing, s.created_at
		FROM series s
		WHERE s.id = ?
		  AND (? = 'admin' OR EXISTS (
		    SELECT 1 FROM library_permissions lp
		    WHERE lp.library_id = s.library_id AND lp.user_id = ? AND lp.can_read = TRUE
		  ))
		LIMIT 1`, input.ID, claims.Role, claims.UserID,
	).Scan(&s)
	if result.Error != nil || result.RowsAffected == 0 {
		return nil, huma.NewError(http.StatusNotFound, "series not found")
	}

	var books []models.BookSummary
	h.db.WithContext(ctx).Raw(`
		SELECT b.id, b.title, b.type, b.series, b.issue_number, b.year, b.format, b.page_count, b.file_size, b.age_rating,
		       rp.current_page
		FROM books b
		LEFT JOIN reading_progress rp ON rp.book_id = b.id AND rp.user_id = ?
		WHERE b.series_id = ?
		ORDER BY b.volume NULLS FIRST, b.issue_number`,
		claims.UserID, input.ID,
	).Scan(&books)
	if books == nil {
		books = []models.BookSummary{}
	}

	return &getSeriesOutput{Body: &SeriesDetail{Series: s, Books: books}}, nil
}

type listSeriesInput struct {
	ID string `path:"id"`
}

type seriesListOutput struct {
	Body []models.Series
}

func (h *SeriesHandler) listByLibrary(ctx context.Context, input *listSeriesInput) (*seriesListOutput, error) {
	claims := auth.ClaimsFromCtx(ctx)

	var seriesList []models.Series
	h.db.WithContext(ctx).Raw(`
		SELECT s.id, s.library_id, s.name, s.publisher, s.start_year, s.end_year, s.ongoing, s.created_at,
		       (SELECT b.id FROM books b WHERE b.series_id = s.id ORDER BY b.created_at ASC LIMIT 1) AS cover_book_id,
		       (SELECT COUNT(*) FROM books b WHERE b.series_id = s.id) AS book_count
		FROM series s
		LEFT JOIN library_permissions lp ON lp.library_id = s.library_id AND lp.user_id = ?
		WHERE s.library_id = ?
		  AND (? = 'admin' OR lp.can_read = TRUE)
		ORDER BY s.created_at DESC`,
		claims.UserID, input.ID, claims.Role,
	).Scan(&seriesList)
	if seriesList == nil {
		seriesList = []models.Series{}
	}

	return &seriesListOutput{Body: seriesList}, nil
}

func (h *SeriesHandler) Cover(c *gin.Context) {
	id := c.Param("id")
	claims := auth.ClaimsFromCtx(c.Request.Context())
	if claims == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var coverBookID string
	r1 := h.db.WithContext(c.Request.Context()).Raw(`
		SELECT b.id FROM books b
		JOIN series s ON s.id = b.series_id
		WHERE s.id = ?
		  AND (? = 'admin' OR EXISTS (
		    SELECT 1 FROM library_permissions lp
		    WHERE lp.library_id = s.library_id AND lp.user_id = ? AND lp.can_read = TRUE
		  ))
		ORDER BY b.created_at ASC LIMIT 1`, id, claims.Role, claims.UserID,
	).Scan(&coverBookID)
	if r1.Error != nil || r1.RowsAffected == 0 || coverBookID == "" {
		c.JSON(http.StatusNotFound, gin.H{"error": "no cover available"})
		return
	}

	var coverPath string
	r2 := h.db.WithContext(c.Request.Context()).Raw(
		`SELECT path FROM book_covers WHERE book_id=?`, coverBookID,
	).Scan(&coverPath)
	if r2.Error == nil && r2.RowsAffected > 0 && coverPath != "" {
		c.File(coverPath)
		return
	}

	var row struct {
		Path   string
		Format string
	}
	r3 := h.db.WithContext(c.Request.Context()).Raw(
		`SELECT path, format FROM books WHERE id=?`, coverBookID,
	).Scan(&row)
	if r3.Error != nil || r3.RowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "no cover available"})
		return
	}

	if row.Format == "pdf" || row.Format == "epub" {
		c.JSON(http.StatusNotFound, gin.H{"error": "no cover available"})
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

func (h *SeriesHandler) Register(api huma.API) {
	huma.Register(api, huma.Operation{
		OperationID: "getSeries",
		Method:      http.MethodGet,
		Path:        "/api/series/{id}",
		Tags:        []string{"Series"},
		Summary:     "Get series with books",
	}, h.get)

	huma.Register(api, huma.Operation{
		OperationID: "listSeriesByLibrary",
		Method:      http.MethodGet,
		Path:        "/api/libraries/{id}/series",
		Tags:        []string{"Series"},
		Summary:     "List series in a library",
	}, h.listByLibrary)
}
