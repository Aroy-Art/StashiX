package handlers

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"gorm.io/gorm"
	"github.com/aroy/stashix/internal/auth"
	"github.com/aroy/stashix/internal/models"
)

type SearchHandler struct {
	db *gorm.DB
}

func NewSearchHandler(db *gorm.DB) *SearchHandler {
	return &SearchHandler{db: db}
}

type searchInput struct {
	Q         string `query:"q"`
	LibraryID string `query:"library_id"`
	AgeRating string `query:"age_rating"`
	Limit     int    `query:"limit" minimum:"1" maximum:"100" default:"50"`
	Offset    int    `query:"offset" minimum:"0" default:"0"`
}

type searchOutput struct {
	Body struct {
		Results []models.BookSummary `json:"results"`
		Total   int                  `json:"total"`
		Offset  int                  `json:"offset"`
		Limit   int                  `json:"limit"`
	}
}

func (h *SearchHandler) search(ctx context.Context, input *searchInput) (*searchOutput, error) {
	claims := auth.ClaimsFromCtx(ctx)
	if claims == nil {
		return nil, huma.NewError(http.StatusUnauthorized, "unauthorized")
	}

	var results []struct {
		models.BookSummary
		Rank  float64
		Total int
	}
	result := h.db.WithContext(ctx).Raw(`
		SELECT b.id, b.title, b.type, b.series, b.issue_number, b.year, b.format, b.age_rating,
		       b.page_count, b.file_size,
		       CASE WHEN ? = '' THEN 0.0
		            ELSE ts_rank(b.search_vec, plainto_tsquery('english', ?))
		       END AS rank,
		       COUNT(*) OVER() AS total
		FROM books b
		LEFT JOIN library_permissions lp ON lp.library_id = b.library_id AND lp.user_id=?
		WHERE (? = '' OR b.search_vec @@ plainto_tsquery('english', ?))
		  AND (? = '' OR b.library_id::text = ?)
		  AND (? = '' OR b.age_rating::text = ?)
		  AND (? = 'admin' OR lp.can_read = TRUE)
		ORDER BY rank DESC, b.title
		LIMIT ? OFFSET ?`,
		input.Q, input.Q,
		claims.UserID,
		input.Q, input.Q,
		input.LibraryID, input.LibraryID,
		input.AgeRating, input.AgeRating,
		claims.Role,
		input.Limit, input.Offset,
	).Scan(&results)
	if result.Error != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "search error")
	}

	out := &searchOutput{}
	out.Body.Results = []models.BookSummary{}
	out.Body.Offset = input.Offset
	out.Body.Limit = input.Limit

	for _, r := range results {
		out.Body.Total = r.Total
		out.Body.Results = append(out.Body.Results, r.BookSummary)
	}
	return out, nil
}

func (h *SearchHandler) Register(api huma.API) {
	huma.Register(api, huma.Operation{
		OperationID: "search",
		Method:      http.MethodGet,
		Path:        "/api/search",
		Tags:        []string{"Search"},
		Summary:     "Full-text search across books",
	}, h.search)
}
