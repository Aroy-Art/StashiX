package library

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"

	"gorm.io/gorm"
	"github.com/aroy/stashix/internal/media"
	"github.com/aroy/stashix/internal/metadata"
	"github.com/aroy/stashix/internal/models"
	"github.com/aroy/stashix/internal/ws"
)

// fileHash computes a fast fingerprint: file size + SHA-256 of first 64 KB.
// This is sufficient for rename detection without reading entire large archives.
func fileHash(path string, size int64) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	buf := make([]byte, 65536)
	n, err := io.ReadFull(f, buf)
	if err != nil && err != io.ErrUnexpectedEOF {
		return "", err
	}
	h := sha256.Sum256(buf[:n])
	return fmt.Sprintf("%d:%x", size, h), nil
}

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
	publisher  string
	series     string
	year       int
	endYear    int
	ongoing    bool
	standalone bool
	indexMeta  *metadata.BookMeta
	coverPath  string
}

func (s *Scanner) Scan(ctx context.Context, libraryID, scanRoot string, force bool) {
	var lib struct {
		RootPath          string `gorm:"column:root_path"`
		StandaloneFolders models.StringSlice `gorm:"column:standalone_folders"`
	}
	s.db.WithContext(ctx).Raw(`SELECT root_path, standalone_folders FROM libraries WHERE id = ?`, libraryID).Scan(&lib)
	libraryRoot := lib.RootPath
	if libraryRoot == "" {
		libraryRoot = scanRoot
	}

	log.Printf("[scan] start libraryID=%s root=%s force=%v standaloneFolders=%v", libraryID, scanRoot, force, []string(lib.StandaloneFolders))

	paths, err := collectFiles(scanRoot)
	if err != nil {
		log.Printf("[scan] collectFiles error: %v", err)
		return
	}

	total := len(paths)
	log.Printf("[scan] found %d files", total)

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

	contexts := buildSeriesContexts(libraryRoot, paths, lib.StandaloneFolders)

	for i, path := range paths {
		if ctx.Err() != nil {
			return
		}
		sc := contexts[filepath.Dir(path)]
		if err := s.importBook(ctx, libraryID, path, sc, force); err != nil {
			log.Printf("import %s: %v", path, err)
		}
		broadcast(i+1, i+1 == total)
	}

	s.pruneDeleted(ctx, libraryID, paths)
}

func (s *Scanner) pruneDeleted(ctx context.Context, libraryID string, scannedPaths []string) {
	if len(scannedPaths) == 0 {
		s.db.WithContext(ctx).Exec(
			`UPDATE books SET deleted_at = NOW() WHERE library_id = ? AND deleted_at IS NULL`,
			libraryID,
		)
		return
	}

	placeholders := make([]string, len(scannedPaths))
	args := make([]interface{}, len(scannedPaths)+1)
	args[0] = libraryID
	for i, p := range scannedPaths {
		placeholders[i] = "?"
		args[i+1] = p
	}
	query := `UPDATE books SET deleted_at = NOW() WHERE library_id = ? AND deleted_at IS NULL AND path NOT IN (` +
		strings.Join(placeholders, ",") + `)`
	res := s.db.WithContext(ctx).Exec(query, args...)
	if res.Error != nil {
		log.Printf("[scan] pruneDeleted error: %v", res.Error)
	} else if res.RowsAffected > 0 {
		log.Printf("[scan] pruneDeleted marked %d books deleted libraryID=%s", res.RowsAffected, libraryID)
	}
}

func buildSeriesContexts(libraryRoot string, paths []string, standaloneFolders []string) map[string]*seriesContext {
	sfSet := make(map[string]bool, len(standaloneFolders))
	for _, f := range standaloneFolders {
		sfSet[strings.ToLower(f)] = true
	}

	seenDirs := make(map[string]bool, len(paths))
	for _, p := range paths {
		seenDirs[filepath.Dir(p)] = true
	}

	contexts := make(map[string]*seriesContext, len(seenDirs))
	for dir := range seenDirs {
		sc := &seriesContext{}

		if len(sfSet) > 0 && sfSet[strings.ToLower(filepath.Base(dir))] {
			// parent folder is configured as a standalone container — leave series empty
			sc.standalone = true
			log.Printf("[scan] standalone folder matched dir=%s", dir)
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
			continue
		}

		if rel, err := filepath.Rel(libraryRoot, dir); err == nil && rel != "." {
			parts := strings.Split(rel, string(os.PathSeparator))
			switch {
			case len(parts) >= 2:
				sc.publisher = parts[0]
				sm := metadata.ParseSeriesDir(parts[1])
				if sm.Year != 0 {
					sc.series = sm.Series
					sc.year = sm.Year
					sc.endYear = sm.EndYear
					sc.ongoing = sm.Ongoing
				}
			case len(parts) == 1:
				sm := metadata.ParseSeriesDir(parts[0])
				sc.series = sm.Series
				sc.year = sm.Year
				sc.endYear = sm.EndYear
				sc.ongoing = sm.Ongoing
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

		log.Printf("[scan] dir=%s publisher=%q series=%q year=%d cover=%v indexMeta=%v",
			dir, sc.publisher, sc.series, sc.year, sc.coverPath != "", sc.indexMeta != nil)
		contexts[dir] = sc
	}
	return contexts
}

var adultRe = regexp.MustCompile(`(?i)\badult\b|18\+|r-?18|\(18\)|\[18\]`)

func isAdultContent(path string) bool {
	for _, part := range strings.Split(filepath.ToSlash(path), "/") {
		if adultRe.MatchString(part) {
			return true
		}
	}
	return false
}

func (s *Scanner) importBook(ctx context.Context, libraryID, path string, sc *seriesContext, force bool) error {
	format, err := media.DetectFormat(path)
	if err != nil {
		return err
	}

	info, err := os.Stat(path)
	if err != nil {
		return err
	}

	hash, hashErr := fileHash(path, info.Size())

	if !force {
		var existing struct {
			ID        string
			DeletedAt *time.Time
		}
		s.db.WithContext(ctx).Raw(`SELECT id, deleted_at FROM books WHERE path = ?`, path).Scan(&existing)
		if existing.ID != "" {
			if existing.DeletedAt != nil {
				// File was marked deleted but is back on disk — restore it.
				updates := map[string]interface{}{"deleted_at": nil}
				if hashErr == nil {
					updates["file_hash"] = hash
				}
				s.db.WithContext(ctx).Exec(
					`UPDATE books SET deleted_at = NULL, file_hash = ? WHERE id = ?`,
					nullString(hash), existing.ID,
				)
				log.Printf("[scan] restored deleted book id=%s path=%s", existing.ID, path)
			} else {
				log.Printf("[scan] skip already-exists path=%s", path)
			}
			return nil
		}

		// New path — check if it's a rename of an existing book by hash.
		if hashErr == nil && hash != "" {
			var renamedBook struct {
				ID   string
				Path string
			}
			s.db.WithContext(ctx).Raw(
				`SELECT id, path FROM books WHERE library_id = ? AND file_hash = ? AND path != ? LIMIT 1`,
				libraryID, hash, path,
			).Scan(&renamedBook)
			if renamedBook.ID != "" {
				s.db.WithContext(ctx).Exec(
					`UPDATE books SET path = ?, deleted_at = NULL WHERE id = ?`,
					path, renamedBook.ID,
				)
				log.Printf("[scan] rename detected id=%s old=%s new=%s", renamedBook.ID, renamedBook.Path, path)
				return nil
			}
		}
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

	bookType := "issue"
	if meta.Series == "" {
		bookType = "standalone"
	}

	log.Printf("[scan] import path=%s title=%q type=%s series=%q volume=%d issue=%q year=%d publisher=%q",
		path, meta.Title, bookType, meta.Series, meta.Volume, meta.IssueNumber, meta.Year, meta.Publisher)

	// Resolve publisher and imprint
	publisherID := s.upsertPublisher(ctx, meta.Publisher, meta.PublisherSourceID)
	imprintID := ""
	if publisherID != "" && meta.ImprintName != "" {
		imprintID = s.upsertImprint(ctx, publisherID, meta.ImprintName, meta.ImprintSourceID)
	}

	var startYear, endYear int
	var ongoing bool
	if sc != nil {
		startYear = sc.year
		endYear = sc.endYear
		ongoing = sc.ongoing
	}
	// Prefer MetronInfo's SeriesStartYear if available
	if meta.SeriesStartYear != 0 {
		startYear = meta.SeriesStartYear
	}

	adult := isAdultContent(path)

	seriesID := s.upsertSeries(ctx, libraryID, meta, publisherID, imprintID, startYear, endYear, ongoing, adult)
	if seriesID != "" && sc != nil && sc.coverPath != "" {
		s.upsertSeriesCover(ctx, seriesID, sc.coverPath)
	}

	onConflict := `ON CONFLICT (path) DO UPDATE SET
		deleted_at = NULL, file_hash = EXCLUDED.file_hash`
	if force {
		onConflict = `ON CONFLICT (path) DO UPDATE SET
			title=EXCLUDED.title, type=EXCLUDED.type, series=EXCLUDED.series, series_id=EXCLUDED.series_id,
			issue_number=EXCLUDED.issue_number, alternative_number=EXCLUDED.alternative_number,
			volume=EXCLUDED.volume, year=EXCLUDED.year, publisher=EXCLUDED.publisher,
			publisher_id=EXCLUDED.publisher_id, imprint_id=EXCLUDED.imprint_id,
			format=EXCLUDED.format, comic_format=EXCLUDED.comic_format,
			page_count=EXCLUDED.page_count, file_size=EXCLUDED.file_size,
			age_rating=EXCLUDED.age_rating, adult=books.adult OR EXCLUDED.adult,
			language=EXCLUDED.language, summary=EXCLUDED.summary,
			notes=EXCLUDED.notes, collection_title=EXCLUDED.collection_title,
			manga_volume=EXCLUDED.manga_volume, cover_date=EXCLUDED.cover_date,
			store_date=EXCLUDED.store_date, isbn=EXCLUDED.isbn, upc=EXCLUDED.upc,
			community_rating=EXCLUDED.community_rating,
			community_rating_count=EXCLUDED.community_rating_count,
			last_modified=EXCLUDED.last_modified, file_hash=EXCLUDED.file_hash,
			deleted_at=NULL, updated_at=NOW()`
	}

	hashVal := ""
	if hashErr == nil {
		hashVal = hash
	}

	result := s.db.WithContext(ctx).Exec(`
		INSERT INTO books (
			library_id, path, title, type, series, series_id,
			issue_number, alternative_number, volume, year,
			publisher, publisher_id, imprint_id,
			format, comic_format, page_count, file_size,
			age_rating, adult, language, summary, notes,
			collection_title, manga_volume, cover_date, store_date,
			isbn, upc, community_rating, community_rating_count,
			last_modified, file_hash
		) VALUES (
			?,?,?,?,?,?,
			?,?,?,?,
			?,?,?,
			?,?,?,?,
			?,?,?,?,?,
			?,?,?,?,
			?,?,?,?,
			?,?
		) `+onConflict,
		libraryID, path, meta.Title, bookType, meta.Series, nullString(seriesID),
		nullString(meta.IssueNumber), nullString(meta.AlternativeNumber), nullInt(meta.Volume), nullInt(meta.Year),
		nullString(meta.Publisher), nullString(publisherID), nullString(imprintID),
		string(format), nullString(meta.SeriesFormat), pageCount, info.Size(),
		coalesceString(meta.AgeRating, "unknown"), adult, nullString(meta.Language), nullString(meta.Summary), nullString(meta.Notes),
		nullString(meta.CollectionTitle), nullString(meta.MangaVolume), nullString(meta.CoverDate), nullString(meta.StoreDate),
		nullString(meta.ISBN), nullString(meta.UPC), nullFloat(meta.CommunityRating), nullInt(meta.CommunityRatingCount),
		nullTime(meta.LastModified), nullString(hashVal),
	)
	if result.Error != nil {
		log.Printf("[scan] INSERT books error path=%s: %v", path, result.Error)
		return result.Error
	}
	log.Printf("[scan] INSERT books rows=%d path=%s", result.RowsAffected, path)

	var bookID string
	s.db.WithContext(ctx).Raw(`SELECT id FROM books WHERE path = ?`, path).Scan(&bookID)
	if bookID == "" {
		return nil
	}

	coverPath := bookCoverImage(path)
	if coverPath != "" {
		s.db.WithContext(ctx).Exec(`
			INSERT INTO book_covers (book_id, path)
			VALUES (?,?)
			ON CONFLICT (book_id) DO UPDATE SET path=EXCLUDED.path, updated_at=NOW()`,
			bookID, coverPath)
	}

	s.insertBookRelations(ctx, bookID, meta, force)

	p, _ := json.Marshal(map[string]string{"book_id": bookID, "library_id": libraryID})
	s.hub.Broadcast(ws.Message{Type: "book_added", Payload: p})

	return nil
}

func (s *Scanner) insertBookRelations(ctx context.Context, bookID string, meta *metadata.BookMeta, force bool) {
	if force {
		for _, table := range []string{
			"book_external_ids", "book_urls", "book_genres", "book_tags",
			"book_story_arcs", "book_characters", "book_teams", "book_universes",
			"book_locations", "book_credits", "book_stories", "book_prices", "book_reprints",
		} {
			s.db.WithContext(ctx).Exec(fmt.Sprintf(`DELETE FROM %s WHERE book_id = ?`, table), bookID)
		}
	}

	for _, eid := range meta.ExternalIDs {
		s.db.WithContext(ctx).Exec(`
			INSERT INTO book_external_ids (book_id, source, source_id, is_primary)
			VALUES (?,?,?,?)
			ON CONFLICT (book_id, source) DO UPDATE SET source_id=EXCLUDED.source_id, is_primary=EXCLUDED.is_primary`,
			bookID, eid.Source, eid.SourceID, eid.IsPrimary)
	}

	for _, g := range meta.Genres {
		if gID := s.upsertEntity(ctx, "genres", g.Name, g.SourceID); gID != "" {
			s.db.WithContext(ctx).Exec(`INSERT INTO book_genres (book_id, genre_id) VALUES (?,?) ON CONFLICT DO NOTHING`, bookID, gID)
		}
	}

	for _, t := range meta.Tags {
		if tID := s.upsertEntity(ctx, "tags", t.Name, t.SourceID); tID != "" {
			s.db.WithContext(ctx).Exec(`INSERT INTO book_tags (book_id, tag_id) VALUES (?,?) ON CONFLICT DO NOTHING`, bookID, tID)
		}
	}

	for _, a := range meta.Arcs {
		if aID := s.upsertEntity(ctx, "story_arcs", a.Name, a.SourceID); aID != "" {
			s.db.WithContext(ctx).Exec(`INSERT INTO book_story_arcs (book_id, arc_id, arc_number) VALUES (?,?,?) ON CONFLICT DO NOTHING`,
				bookID, aID, nullInt(a.Number))
		}
	}

	for _, c := range meta.Characters {
		if cID := s.upsertEntity(ctx, "characters", c.Name, c.SourceID); cID != "" {
			s.db.WithContext(ctx).Exec(`INSERT INTO book_characters (book_id, character_id) VALUES (?,?) ON CONFLICT DO NOTHING`, bookID, cID)
		}
	}

	for _, t := range meta.Teams {
		if tID := s.upsertEntity(ctx, "teams", t.Name, t.SourceID); tID != "" {
			s.db.WithContext(ctx).Exec(`INSERT INTO book_teams (book_id, team_id) VALUES (?,?) ON CONFLICT DO NOTHING`, bookID, tID)
		}
	}

	for _, u := range meta.Universes {
		if uID := s.upsertUniverse(ctx, u.Name, u.Designation, u.SourceID); uID != "" {
			s.db.WithContext(ctx).Exec(`INSERT INTO book_universes (book_id, universe_id) VALUES (?,?) ON CONFLICT DO NOTHING`, bookID, uID)
		}
	}

	for _, l := range meta.Locations {
		if lID := s.upsertEntity(ctx, "locations", l.Name, l.SourceID); lID != "" {
			s.db.WithContext(ctx).Exec(`INSERT INTO book_locations (book_id, location_id) VALUES (?,?) ON CONFLICT DO NOTHING`, bookID, lID)
		}
	}

	for _, c := range meta.Credits {
		if c.CreatorName == "" {
			continue
		}
		creatorID := s.upsertEntity(ctx, "creators", c.CreatorName, c.CreatorSourceID)
		if creatorID == "" {
			continue
		}
		for _, role := range c.Roles {
			s.db.WithContext(ctx).Exec(`INSERT INTO book_credits (book_id, creator_id, role) VALUES (?,?,?)`, bookID, creatorID, role)
		}
	}

	for i, st := range meta.Stories {
		s.db.WithContext(ctx).Exec(`INSERT INTO book_stories (book_id, title, source_id, sort_order) VALUES (?,?,?,?)`,
			bookID, st.Name, nullString(st.SourceID), i)
	}

	for _, p := range meta.Prices {
		s.db.WithContext(ctx).Exec(`INSERT INTO book_prices (book_id, country, price) VALUES (?,?,?)`, bookID, p.Country, p.Amount)
	}

	for _, u := range meta.URLs {
		s.db.WithContext(ctx).Exec(`INSERT INTO book_urls (book_id, url, is_primary) VALUES (?,?,?)`, bookID, u.URL, u.IsPrimary)
	}

	for _, r := range meta.Reprints {
		if r.Name == "" {
			continue
		}
		s.db.WithContext(ctx).Exec(`INSERT INTO book_reprints (book_id, name, source_id) VALUES (?,?,?)`,
			bookID, r.Name, nullString(r.SourceID))
	}
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

	fileMeta := metadata.ParseFilename(path)
	if sc != nil && sc.standalone {
		fileMeta.Series = ""
	}

	if format == media.FormatCBZ || format == media.FormatEPUB {
		if archMeta, err := metadata.ParseZipArchive(path); err == nil && archMeta.Title != "" {
			if sc != nil && sc.standalone {
				archMeta.Series = ""
			}
			applyAllMeta(meta, archMeta)
			goto done
		}
	}

	applyFileMeta(meta, fileMeta)

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

	// MetronInfo extended fields
	if len(src.ExternalIDs) > 0 {
		dst.ExternalIDs = src.ExternalIDs
	}
	if src.PublisherSourceID != "" {
		dst.PublisherSourceID = src.PublisherSourceID
	}
	if src.ImprintName != "" {
		dst.ImprintName = src.ImprintName
		dst.ImprintSourceID = src.ImprintSourceID
	}
	if src.SeriesSourceID != "" {
		dst.SeriesSourceID = src.SeriesSourceID
	}
	if src.SeriesSortName != "" {
		dst.SeriesSortName = src.SeriesSortName
	}
	if src.SeriesLanguage != "" {
		dst.SeriesLanguage = src.SeriesLanguage
	}
	if src.SeriesFormat != "" {
		dst.SeriesFormat = src.SeriesFormat
	}
	if src.SeriesStartYear != 0 {
		dst.SeriesStartYear = src.SeriesStartYear
	}
	if src.SeriesIssueCount != 0 {
		dst.SeriesIssueCount = src.SeriesIssueCount
	}
	if src.SeriesVolumeCount != 0 {
		dst.SeriesVolumeCount = src.SeriesVolumeCount
	}
	if len(src.SeriesAlternativeNames) > 0 {
		dst.SeriesAlternativeNames = src.SeriesAlternativeNames
	}
	if src.CollectionTitle != "" {
		dst.CollectionTitle = src.CollectionTitle
	}
	if src.AlternativeNumber != "" {
		dst.AlternativeNumber = src.AlternativeNumber
	}
	if src.MangaVolume != "" {
		dst.MangaVolume = src.MangaVolume
	}
	if src.CoverDate != "" {
		dst.CoverDate = src.CoverDate
	}
	if src.StoreDate != "" {
		dst.StoreDate = src.StoreDate
	}
	if src.Notes != "" {
		dst.Notes = src.Notes
	}
	if src.ISBN != "" {
		dst.ISBN = src.ISBN
	}
	if src.UPC != "" {
		dst.UPC = src.UPC
	}
	if src.CommunityRating != 0 {
		dst.CommunityRating = src.CommunityRating
		dst.CommunityRatingCount = src.CommunityRatingCount
	}
	if src.LastModified != nil {
		dst.LastModified = src.LastModified
	}
	if len(src.Genres) > 0 {
		dst.Genres = src.Genres
	}
	if len(src.Tags) > 0 {
		dst.Tags = src.Tags
	}
	if len(src.Arcs) > 0 {
		dst.Arcs = src.Arcs
	}
	if len(src.Characters) > 0 {
		dst.Characters = src.Characters
	}
	if len(src.Teams) > 0 {
		dst.Teams = src.Teams
	}
	if len(src.Universes) > 0 {
		dst.Universes = src.Universes
	}
	if len(src.Locations) > 0 {
		dst.Locations = src.Locations
	}
	if len(src.Reprints) > 0 {
		dst.Reprints = src.Reprints
	}
	if len(src.Stories) > 0 {
		dst.Stories = src.Stories
	}
	if len(src.Prices) > 0 {
		dst.Prices = src.Prices
	}
	if len(src.URLs) > 0 {
		dst.URLs = src.URLs
	}
	if len(src.Credits) > 0 {
		dst.Credits = src.Credits
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

func (s *Scanner) upsertPublisher(ctx context.Context, name, sourceID string) string {
	if name == "" {
		return ""
	}
	var id string
	res := s.db.WithContext(ctx).Raw(`
		INSERT INTO publishers (name, source_id)
		VALUES (?, ?)
		ON CONFLICT (name) DO UPDATE SET name=EXCLUDED.name
		RETURNING id`,
		name, nullString(sourceID),
	).Scan(&id)
	if res.Error != nil {
		log.Printf("[scan] upsertPublisher error name=%q: %v", name, res.Error)
	}
	return id
}

func (s *Scanner) upsertImprint(ctx context.Context, publisherID, name, sourceID string) string {
	if name == "" {
		return ""
	}
	var id string
	res := s.db.WithContext(ctx).Raw(`
		INSERT INTO imprints (publisher_id, name, source_id)
		VALUES (?, ?, ?)
		ON CONFLICT (publisher_id, name) DO UPDATE SET name=EXCLUDED.name
		RETURNING id`,
		publisherID, name, nullString(sourceID),
	).Scan(&id)
	if res.Error != nil {
		log.Printf("[scan] upsertImprint error name=%q: %v", name, res.Error)
	}
	return id
}

// upsertEntity handles normalized lookup tables: genres, tags, characters, teams, locations, creators, story_arcs.
func (s *Scanner) upsertEntity(ctx context.Context, table, name, sourceID string) string {
	if name == "" {
		return ""
	}
	var id string
	// #nosec G201 — table name is always a hardcoded literal from internal callers
	res := s.db.WithContext(ctx).Raw(
		fmt.Sprintf(`INSERT INTO %s (name, source_id) VALUES (?, ?) ON CONFLICT (name) DO UPDATE SET name=EXCLUDED.name RETURNING id`, table),
		name, nullString(sourceID),
	).Scan(&id)
	if res.Error != nil {
		log.Printf("[scan] upsertEntity table=%s name=%q: %v", table, name, res.Error)
	}
	return id
}

func (s *Scanner) upsertUniverse(ctx context.Context, name, designation, sourceID string) string {
	if name == "" {
		return ""
	}
	var id string
	res := s.db.WithContext(ctx).Raw(`
		INSERT INTO universes (name, designation, source_id)
		VALUES (?, ?, ?)
		ON CONFLICT (name) DO UPDATE SET designation=EXCLUDED.designation
		RETURNING id`,
		name, nullString(designation), nullString(sourceID),
	).Scan(&id)
	if res.Error != nil {
		log.Printf("[scan] upsertUniverse name=%q: %v", name, res.Error)
	}
	return id
}

func (s *Scanner) upsertSeries(ctx context.Context, libraryID string, meta *metadata.BookMeta, publisherID, imprintID string, startYear, endYear int, ongoing, adult bool) string {
	if meta.Series == "" {
		return ""
	}
	var id string
	res := s.db.WithContext(ctx).Raw(`
		INSERT INTO series (library_id, name, sort_name, volume, language, format,
		                    publisher, publisher_id, imprint_id,
		                    start_year, end_year, ongoing, adult,
		                    issue_count, volume_count)
		VALUES (?,?,?,?,?,?,  ?,?,?,  ?,?,?,?,  ?,?)
		ON CONFLICT (library_id, name) DO UPDATE SET
			sort_name   = COALESCE(EXCLUDED.sort_name,   series.sort_name),
			volume      = COALESCE(EXCLUDED.volume,      series.volume),
			language    = EXCLUDED.language,
			format      = COALESCE(EXCLUDED.format,      series.format),
			publisher   = COALESCE(EXCLUDED.publisher,   series.publisher),
			publisher_id= COALESCE(EXCLUDED.publisher_id,series.publisher_id),
			imprint_id  = COALESCE(EXCLUDED.imprint_id,  series.imprint_id),
			start_year  = COALESCE(EXCLUDED.start_year,  series.start_year),
			end_year    = COALESCE(EXCLUDED.end_year,    series.end_year),
			ongoing     = EXCLUDED.ongoing,
			adult       = series.adult OR EXCLUDED.adult,
			issue_count = COALESCE(EXCLUDED.issue_count, series.issue_count),
			volume_count= COALESCE(EXCLUDED.volume_count,series.volume_count)
		RETURNING id`,
		libraryID, meta.Series, nullString(meta.SeriesSortName), nullInt(meta.Volume),
		coalesceString(meta.SeriesLanguage, "en"), nullString(meta.SeriesFormat),
		nullString(meta.Publisher), nullString(publisherID), nullString(imprintID),
		nullInt(startYear), nullInt(endYear), ongoing, adult,
		nullInt(meta.SeriesIssueCount), nullInt(meta.SeriesVolumeCount),
	).Scan(&id)
	if res.Error != nil {
		log.Printf("[scan] upsertSeries error name=%q: %v", meta.Series, res.Error)
		return ""
	}

	if id == "" {
		return ""
	}

	// Series external ID - derive source from book's primary external ID
	if meta.SeriesSourceID != "" {
		source := ""
		for _, eid := range meta.ExternalIDs {
			if eid.IsPrimary {
				source = eid.Source
				break
			}
		}
		if source == "" && len(meta.ExternalIDs) > 0 {
			source = meta.ExternalIDs[0].Source
		}
		if source != "" {
			s.db.WithContext(ctx).Exec(`
				INSERT INTO series_external_ids (series_id, source, source_id, is_primary)
				VALUES (?,?,?,true)
				ON CONFLICT (series_id, source) DO UPDATE SET source_id=EXCLUDED.source_id`,
				id, source, meta.SeriesSourceID)
		}
	}

	// Series alternative names
	for _, an := range meta.SeriesAlternativeNames {
		s.db.WithContext(ctx).Exec(`
			INSERT INTO series_alternative_names (series_id, name, language, source_id)
			VALUES (?,?,?,?)
			ON CONFLICT DO NOTHING`,
			id, an.Name, coalesceString(an.Language, "en"), nullString(an.SourceID))
	}

	return id
}

func (s *Scanner) upsertSeriesCover(ctx context.Context, seriesID, coverPath string) {
	res := s.db.WithContext(ctx).Exec(`
		INSERT INTO series_covers (series_id, path)
		VALUES (?, ?)
		ON CONFLICT (series_id) DO UPDATE SET path=EXCLUDED.path, updated_at=NOW()`,
		seriesID, coverPath)
	if res.Error != nil {
		log.Printf("[scan] upsertSeriesCover error seriesID=%s: %v", seriesID, res.Error)
	}
}

// bookCoverImage returns a sidecar image path for a book file, or "".
func bookCoverImage(bookPath string) string {
	base := strings.TrimSuffix(bookPath, filepath.Ext(bookPath))
	for _, ext := range []string{".jpg", ".jpeg", ".png", ".webp"} {
		p := base + ext
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

func collectFiles(root string) ([]string, error) {
	var paths []string
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			log.Printf("[scan] walk error path=%s: %v", path, err)
			return err
		}
		if d.IsDir() {
			log.Printf("[scan] enter dir=%s", path)
			return nil
		}
		ext := strings.ToLower(filepath.Ext(path))
		switch ext {
		case ".cbz", ".cbr", ".cb7", ".epub", ".pdf":
			log.Printf("[scan] found file=%s", path)
			paths = append(paths, path)
		default:
			log.Printf("[scan] skip file=%s (not a book format)", path)
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

func nullFloat(v float64) any {
	if v == 0 {
		return nil
	}
	return v
}

func nullTime(v *time.Time) any {
	if v == nil {
		return nil
	}
	return *v
}

func coalesceString(v, fallback string) string {
	if v == "" {
		return fallback
	}
	return v
}
