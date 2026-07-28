package handlers

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/aroy/stashix/internal/auth"
)

func requireAdmin(ctx context.Context) error {
	claims := auth.ClaimsFromCtx(ctx)
	if claims == nil || claims.Role != "admin" {
		return huma.NewError(http.StatusForbidden, "admin access required")
	}
	return nil
}
