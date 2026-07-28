package library

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/aroy/stashix/internal/media"
	"github.com/aroy/stashix/internal/metadata"
	"github.com/aroy/stashix/internal/ws"
)

type ScanProgress struct {
	LibraryID string `json:"library_id"`
	Scanned   int    `json:"scanned"`
	Total     int    `json:"total"`
	Done      bool   `json:"done"`
}

type Scanner struct {
	db  *pgxpool.Pool
	hub *ws.Hub
}

func NewScanner(db *pgxpool.Pool, hub *ws.Hub) *Scanner {
	return &Scanner{db: db, hub: hub}
}

func (s *Scanner) Scan(ctx context.Context, libraryID, rootPath string) {
	paths, err := collectFiles(rootPath)
	if err != nil {
		log.Printf("scan %s: %v", rootPath, err)
		return
	}

	total := len(paths)
	broadcast := func(scanned int, done bool) {
		p, _ := json.Marshal(ScanProgress{LibraryID: libraryID, Scanned: scanned, Total: total, Done: done})
		s.hub.Broadcast(ws.Message{Type: "scan_progress", Payload: p})
	}

	broadcast(0, false)

	for i, path := range paths {
		if ctx.Err() != nil {
			return
		}
		if err := s.importBook(ctx, libraryID, path); err != nil {
			log.Printf("import %s: %v", path, err)
		}
		broadcast(i+1, i+1 == total)
	}
}

func (s *Scanner) importBook(ctx context.Context, libraryID, path string) error {
	format, err := media.DetectFormat(path)
	if err != nil {
		return err
	}

	// skip if already indexed
	var exists bool
	err = s.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM books WHERE path=$1)`, path).Scan(&exists)
	if err != nil || exists {
		return err
	}

	info, err := os.Stat(path)
	if err != nil {
		return err
	}

	// try archive metadata first, fall back to filename
	var meta *metadata.BookMeta
	if format == media.FormatCBZ || format == media.FormatEPUB {
		meta, err = metadata.ParseZipArchive(path)
		if err != nil || meta.Title == "" {
			meta = metadata.ParseFilename(path)
		}
	} else {
		meta = metadata.ParseFilename(path)
	}

	var pageCount int
	if format != media.FormatPDF && format != media.FormatEPUB {
		pages, err := media.PageList(path, format)
		if err == nil {
			pageCount = len(pages)
		}
	}

	_, err = s.db.Exec(ctx, `
		INSERT INTO books (library_id, path, title, series, issue_number, volume, year, publisher,
		                   format, page_count, file_size, age_rating, language, summary)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
		ON CONFLICT (path) DO NOTHING`,
		libraryID, path, meta.Title, meta.Series, meta.IssueNumber, nullInt(meta.Volume),
		nullInt(meta.Year), meta.Publisher, string(format), pageCount,
		info.Size(), nullString(meta.AgeRating), meta.Language, meta.Summary,
	)
	if err != nil {
		return err
	}

	// broadcast new book event
	var bookID string
	s.db.QueryRow(ctx, `SELECT id FROM books WHERE path=$1`, path).Scan(&bookID)
	if bookID != "" {
		p, _ := json.Marshal(map[string]string{"book_id": bookID, "library_id": libraryID})
		s.hub.Broadcast(ws.Message{Type: "book_added", Payload: p})
	}

	return nil
}

func collectFiles(root string) ([]string, error) {
	var paths []string
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		ext := strings.ToLower(filepath.Ext(path))
		switch ext {
		case ".cbz", ".cbr", ".cb7", ".epub", ".pdf":
			paths = append(paths, path)
		}
		return nil
	})
	return paths, err
}

func nullInt(v int) any {
	if v == 0 {
		return nil
	}
	return v
}

func nullString(v string) any {
	if v == "" {
		return nil
	}
	return v
}
