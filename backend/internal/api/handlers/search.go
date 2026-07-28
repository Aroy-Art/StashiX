package handlers

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/aroy/stashix/internal/auth"
	"github.com/aroy/stashix/internal/models"
)

type SearchHandler struct {
	db *pgxpool.Pool
}

func NewSearchHandler(db *pgxpool.Pool) *SearchHandler {
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

	rows, err := h.db.Query(ctx, `
		SELECT b.id, b.title, b.series, b.issue_number, b.year, b.format, b.age_rating,
		       ts_rank(b.search_vec, query) AS rank, b.page_count
		FROM books b,
		     plainto_tsquery('english', $1) query
		LEFT JOIN library_permissions lp ON lp.library_id = b.library_id AND lp.user_id=$2
		WHERE ($1 = '' OR b.search_vec @@ query)
		  AND ($3 = '' OR b.library_id::text = $3)
		  AND ($4 = '' OR b.age_rating = $4::age_rating)
		  AND ($5 = 'admin' OR lp.can_read = TRUE)
		ORDER BY rank DESC, b.title
		LIMIT $6 OFFSET $7`,
		input.Q, claims.UserID, input.LibraryID, input.AgeRating, claims.Role, limit, input.Offset,
	)
	if err != nil {
		return nil, huma.NewError(http.StatusInternalServerError, "search error")
	}
	defer rows.Close()

	out := &searchOutput{}
	out.Body.Results = []models.BookSummary{}
	out.Body.Offset = input.Offset
	out.Body.Limit = limit

	for rows.Next() {
		var b models.BookSummary
		var rank float64
		if err := rows.Scan(&b.ID, &b.Title, &b.Series, &b.IssueNumber, &b.Year, &b.Format, &b.AgeRating, &rank, &b.PageCount); err != nil {
			return nil, huma.NewError(http.StatusInternalServerError, "db error")
		}
		out.Body.Results = append(out.Body.Results, b)
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
