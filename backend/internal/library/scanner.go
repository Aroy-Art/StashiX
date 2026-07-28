package library

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"

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
	db    *pgxpool.Pool
	hub   *ws.Hub
	mu    sync.RWMutex
	tasks map[string]ScanProgress // libraryID → current progress
}

func NewScanner(db *pgxpool.Pool, hub *ws.Hub) *Scanner {
	return &Scanner{db: db, hub: hub, tasks: make(map[string]ScanProgress)}
}

// ActiveTasks returns a snapshot of all currently running scans.
func (s *Scanner) ActiveTasks() []ScanProgress {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]ScanProgress, 0, len(s.tasks))
	for _, t := range s.tasks {
		out = append(out, t)
	}
	return out
}

// seriesContext holds directory-derived metadata for all books in a series folder.
type seriesContext struct {
	publisher string
	series    string
	year      int
	indexMeta *metadata.BookMeta // from index.json, nil if absent
	coverPath string             // path to cover image, "" if absent
}

func (s *Scanner) Scan(ctx context.Context, libraryID, scanRoot string) {
	// Resolve the library's true root path so we can compute relative directory depths
	// even when scanRoot is a subdirectory (e.g., called from the file watcher).
	var libraryRoot string
	_ = s.db.QueryRow(ctx, `SELECT root_path FROM libraries WHERE id=$1`, libraryID).Scan(&libraryRoot)
	if libraryRoot == "" {
		libraryRoot = scanRoot
	}

	paths, err := collectFiles(scanRoot)
	if err != nil {
		log.Printf("scan %s: %v", scanRoot, err)
		return
	}

	total := len(paths)

	s.mu.Lock()
	s.tasks[libraryID] = ScanProgress{LibraryID: libraryID, Scanned: 0, Total: total, Done: false}
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		delete(s.tasks, libraryID)
		s.mu.Unlock()
	}()

	broadcast := func(scanned int, done bool) {
		p := ScanProgress{LibraryID: libraryID, Scanned: scanned, Total: total, Done: done}
		s.mu.Lock()
		s.tasks[libraryID] = p
		s.mu.Unlock()
		data, _ := json.Marshal(p)
		s.hub.Broadcast(ws.Message{Type: "scan_progress", Payload: data})
	}

	broadcast(0, false)

	contexts := buildSeriesContexts(libraryRoot, paths)

	for i, path := range paths {
		if ctx.Err() != nil {
			return
		}
		sc := contexts[filepath.Dir(path)]
		if err := s.importBook(ctx, libraryID, path, sc); err != nil {
			log.Printf("import %s: %v", path, err)
		}
		broadcast(i+1, i+1 == total)
	}
}

// buildSeriesContexts inspects each unique directory containing files and collects
// publisher/series names from the path hierarchy, index.json, and cover images.
func buildSeriesContexts(libraryRoot string, paths []string) map[string]*seriesContext {
	seenDirs := make(map[string]bool, len(paths))
	for _, p := range paths {
		seenDirs[filepath.Dir(p)] = true
	}

	contexts := make(map[string]*seriesContext, len(seenDirs))
	for dir := range seenDirs {
		sc := &seriesContext{}

		if rel, err := filepath.Rel(libraryRoot, dir); err == nil && rel != "." {
			parts := strings.Split(rel, string(os.PathSeparator))
			switch {
			case len(parts) >= 2:
				// publisher/series/… layout
				sc.publisher = parts[0]
				sm := metadata.ParseSeriesDir(parts[1])
				sc.series = sm.Series
				sc.year = sm.Year
			case len(parts) == 1:
				// files sit directly in a single subdirectory
				sm := metadata.ParseSeriesDir(parts[0])
				sc.series = sm.Series
				sc.year = sm.Year
			}
		}

		// Load index.json if present
		if m, err := metadata.ParseIndexJSON(filepath.Join(dir, "index.json")); err == nil {
			sc.indexMeta = m
		}

		// Find cover image (cover.jpg, cover.png, etc.)
		for _, name := range []string{"cover.jpg", "cover.jpeg", "cover.png", "cover.webp"} {
			cp := filepath.Join(dir, name)
			if _, err := os.Stat(cp); err == nil {
				sc.coverPath = cp
				break
			}
		}

		contexts[dir] = sc
	}
	return contexts
}

func (s *Scanner) importBook(ctx context.Context, libraryID, path string, sc *seriesContext) error {
	format, err := media.DetectFormat(path)
	if err != nil {
		return err
	}

	var exists bool
	if err := s.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM books WHERE path=$1)`, path).Scan(&exists); err != nil || exists {
		return err
	}

	info, err := os.Stat(path)
	if err != nil {
		return err
	}

	meta := buildMeta(ctx, format, path, sc)

	var pageCount int
	if format != media.FormatPDF && format != media.FormatEPUB {
		if pages, err := media.PageList(path, format); err == nil {
			pageCount = len(pages)
		}
	}
	if meta.PageCount > 0 && pageCount == 0 {
		pageCount = meta.PageCount
	}

	_, err = s.db.Exec(ctx, `
		INSERT INTO books (library_id, path, title, series, issue_number, volume, year, publisher,
		                   format, page_count, file_size, age_rating, language, summary)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
		ON CONFLICT (path) DO NOTHING`,
		libraryID, path, meta.Title, meta.Series, meta.IssueNumber, nullInt(meta.Volume),
		nullInt(meta.Year), meta.Publisher, string(format), pageCount,
		info.Size(), coalesceString(meta.AgeRating, "unknown"), meta.Language, meta.Summary,
	)
	if err != nil {
		return err
	}

	var bookID string
	s.db.QueryRow(ctx, `SELECT id FROM books WHERE path=$1`, path).Scan(&bookID)
	if bookID == "" {
		return nil
	}

	if sc != nil && sc.coverPath != "" {
		_, _ = s.db.Exec(ctx, `
			INSERT INTO book_covers (book_id, path)
			VALUES ($1, $2)
			ON CONFLICT (book_id) DO UPDATE SET path=$2, updated_at=NOW()`,
			bookID, sc.coverPath)
	}

	p, _ := json.Marshal(map[string]string{"book_id": bookID, "library_id": libraryID})
	s.hub.Broadcast(ws.Message{Type: "book_added", Payload: p})

	return nil
}

// buildMeta constructs the final BookMeta for a file by merging sources in
// priority order: directory structure → index.json → filename → archive XML.
func buildMeta(_ context.Context, format media.Format, path string, sc *seriesContext) *metadata.BookMeta {
	meta := &metadata.BookMeta{}

	// 1. Directory structure (lowest priority)
	if sc != nil {
		meta.Publisher = sc.publisher
		meta.Series = sc.series
		meta.Year = sc.year
	}

	// 2. index.json — series-level sidecar (refines publisher/series/summary/rating)
	if sc != nil && sc.indexMeta != nil {
		applySeriesMeta(meta, sc.indexMeta)
	}

	// 3. Archive embedded XML (ComicInfo / MetronInfo) — highest priority
	if format == media.FormatCBZ || format == media.FormatEPUB {
		if archMeta, err := metadata.ParseZipArchive(path); err == nil && archMeta.Title != "" {
			applyAllMeta(meta, archMeta)
			goto done
		}
	}

	// 4. Filename parsing — fills per-book fields not covered by context
	applyFileMeta(meta, metadata.ParseFilename(path))

done:
	if meta.Title == "" {
		meta.Title = strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	}
	return meta
}

// applySeriesMeta copies series-level fields (non-per-book) from src to dst,
// overriding empty strings but not non-empty values already set.
func applySeriesMeta(dst, src *metadata.BookMeta) {
	if src.Series != "" {
		dst.Series = src.Series
	}
	if src.Publisher != "" {
		dst.Publisher = src.Publisher
	}
	if src.Summary != "" {
		dst.Summary = src.Summary
	}
	if src.AgeRating != "" && src.AgeRating != "unknown" {
		dst.AgeRating = src.AgeRating
	}
	if src.Language != "" {
		dst.Language = src.Language
	}
	if src.Year != 0 && dst.Year == 0 {
		dst.Year = src.Year
	}
}

// applyAllMeta copies all fields from src, overriding dst (archive XML wins).
func applyAllMeta(dst, src *metadata.BookMeta) {
	if src.Title != "" {
		dst.Title = src.Title
	}
	if src.Series != "" {
		dst.Series = src.Series
	}
	if src.IssueNumber != "" {
		dst.IssueNumber = src.IssueNumber
	}
	if src.Volume != 0 {
		dst.Volume = src.Volume
	}
	if src.Year != 0 {
		dst.Year = src.Year
	}
	if src.Publisher != "" {
		dst.Publisher = src.Publisher
	}
	if src.Summary != "" {
		dst.Summary = src.Summary
	}
	if src.AgeRating != "" {
		dst.AgeRating = src.AgeRating
	}
	if src.Language != "" {
		dst.Language = src.Language
	}
	if src.PageCount != 0 {
		dst.PageCount = src.PageCount
	}
}

// applyFileMeta applies per-book fields from filename parsing without overriding
// series/publisher already resolved from directory context.
func applyFileMeta(dst, src *metadata.BookMeta) {
	if src.Title != "" {
		dst.Title = src.Title
	}
	if src.IssueNumber != "" {
		dst.IssueNumber = src.IssueNumber
	}
	if src.Volume != 0 {
		dst.Volume = src.Volume
	}
	if src.Year != 0 && dst.Year == 0 {
		dst.Year = src.Year
	}
	// Only apply series/publisher from filename if context didn't provide them
	if dst.Series == "" && src.Series != "" {
		dst.Series = src.Series
	}
	if dst.Publisher == "" && src.Publisher != "" {
		dst.Publisher = src.Publisher
	}
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

func coalesceString(v, fallback string) string {
	if v == "" {
		return fallback
	}
	return v
}
