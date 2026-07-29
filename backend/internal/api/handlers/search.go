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
		Offset  int                  `json:"offset"`
		Limit   int                  `json:"limit"`
	}
}

func (h *SearchHandler) search(ctx context.Context, input *searchInput) (*searchOutput, error) {
	claims := auth.ClaimsFromCtx(ctx)

	limit := input.Limit
	if limit <= 0 {
		limit = 50
	}

	var results []struct {
		models.BookSummary
		Rank float64
	}
	result := h.db.WithContext(ctx).Raw(`
		SELECT b.id, b.title, b.series, b.issue_number, b.year, b.format, b.age_rating,
		       ts_rank(b.search_vec, plainto_tsquery('english', ?)) AS rank, b.page_count
		FROM books b
		LEFT JOIN library_permissions lp ON lp.library_id = b.library_id AND lp.user_id=?
		WHERE (? = '' OR b.search_vec @@ plainto_tsquery('english', ?))
		  AND (? = '' OR b.library_id::text = ?)
		  AND (? IS NULL OR b.age_rating = ?::age_rating)
		  AND (? = 'admin' OR lp.can_read = TRUE)
		ORDER BY rank DESC, b.title
		LIMIT ? OFFSET ?`,
		input.Q, claims.UserID,
		input.Q, input.Q,
		input.LibraryID, input.LibraryID,
		nullIfEmpty(input.AgeRating), nullIfEmpty(input.AgeRating),
		claims.Role,
		limit, input.Offset,
	).Scan(&results)
	if result.Error != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "search error")
	}

	out := &searchOutput{}
	out.Body.Results = []models.BookSummary{}
	out.Body.Offset = input.Offset
	out.Body.Limit = limit

	for _, r := range results {
		out.Body.Results = append(out.Body.Results, r.BookSummary)
	}
	return out, nil
}

func nullIfEmpty(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
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
