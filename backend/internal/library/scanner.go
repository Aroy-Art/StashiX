package library

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"gorm.io/gorm"
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
	db    *gorm.DB
	hub   *ws.Hub
	mu    sync.RWMutex
	tasks map[string]ScanProgress
}

func NewScanner(db *gorm.DB, hub *ws.Hub) *Scanner {
	return &Scanner{db: db, hub: hub, tasks: make(map[string]ScanProgress)}
}

func (s *Scanner) ActiveTasks() []ScanProgress {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]ScanProgress, 0, len(s.tasks))
	for _, t := range s.tasks {
		out = append(out, t)
	}
	return out
}

type seriesContext struct {
	publisher string
	series    string
	year      int
	indexMeta *metadata.BookMeta
	coverPath string
}

func (s *Scanner) Scan(ctx context.Context, libraryID, scanRoot string) {
	var libraryRoot string
	s.db.WithContext(ctx).Raw(`SELECT root_path FROM libraries WHERE id = ?`, libraryID).Scan(&libraryRoot)
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
				sc.publisher = parts[0]
				sm := metadata.ParseSeriesDir(parts[1])
				sc.series = sm.Series
				sc.year = sm.Year
			case len(parts) == 1:
				sm := metadata.ParseSeriesDir(parts[0])
				sc.series = sm.Series
				sc.year = sm.Year
			}
		}

		if m, err := metadata.ParseIndexJSON(filepath.Join(dir, "index.json")); err == nil {
			sc.indexMeta = m
		}

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

	var count int64
	s.db.WithContext(ctx).Raw(`SELECT COUNT(*) FROM books WHERE path = ?`, path).Scan(&count)
	if count > 0 {
		return nil
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

	result := s.db.WithContext(ctx).Exec(`
		INSERT INTO books (library_id, path, title, series, issue_number, volume, year, publisher,
		                   format, page_count, file_size, age_rating, language, summary)
		VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
		ON CONFLICT (path) DO NOTHING`,
		libraryID, path, meta.Title, meta.Series, meta.IssueNumber, nullInt(meta.Volume),
		nullInt(meta.Year), meta.Publisher, string(format), pageCount,
		info.Size(), coalesceString(meta.AgeRating, "unknown"), meta.Language, meta.Summary,
	)
	if result.Error != nil {
		return result.Error
	}

	var bookID string
	s.db.WithContext(ctx).Raw(`SELECT id FROM books WHERE path = ?`, path).Scan(&bookID)
	if bookID == "" {
		return nil
	}

	if sc != nil && sc.coverPath != "" {
		s.db.WithContext(ctx).Exec(`
			INSERT INTO book_covers (book_id, path)
			VALUES (?,?)
			ON CONFLICT (book_id) DO UPDATE SET path=EXCLUDED.path, updated_at=NOW()`,
			bookID, sc.coverPath)
	}

	p, _ := json.Marshal(map[string]string{"book_id": bookID, "library_id": libraryID})
	s.hub.Broadcast(ws.Message{Type: "book_added", Payload: p})

	return nil
}

func buildMeta(_ context.Context, format media.Format, path string, sc *seriesContext) *metadata.BookMeta {
	meta := &metadata.BookMeta{}

	if sc != nil {
		meta.Publisher = sc.publisher
		meta.Series = sc.series
		meta.Year = sc.year
	}

	if sc != nil && sc.indexMeta != nil {
		applySeriesMeta(meta, sc.indexMeta)
	}

	if format == media.FormatCBZ || format == media.FormatEPUB {
		if archMeta, err := metadata.ParseZipArchive(path); err == nil && archMeta.Title != "" {
			applyAllMeta(meta, archMeta)
			goto done
		}
	}

	applyFileMeta(meta, metadata.ParseFilename(path))

done:
	if meta.Title == "" {
		meta.Title = strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	}
	return meta
}

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

func coalesceString(v, fallback string) string {
	if v == "" {
		return fallback
	}
	return v
}
