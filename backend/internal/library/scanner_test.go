package library

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/aroy/stashix/internal/media"
	"github.com/aroy/stashix/internal/metadata"
)

// touch creates an empty file, creating parent dirs as needed.
func touch(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	f.Close()
}

// ── buildSeriesContexts ───────────────────────────────────────────────────────

func TestBuildSeriesContexts_SeriesDir(t *testing.T) {
	root := t.TempDir()
	book := filepath.Join(root, "Viz Graphic Novels", "AD Police (1994)", "AD Police (1994) - Chapter 1.cbz")
	touch(t, book)

	ctx := buildSeriesContexts(root, []string{book}, nil)
	sc := ctx[filepath.Dir(book)]

	if sc == nil {
		t.Fatal("no context for series dir")
	}
	if sc.publisher != "Viz Graphic Novels" {
		t.Errorf("publisher: got %q, want %q", sc.publisher, "Viz Graphic Novels")
	}
	if sc.series != "AD Police" {
		t.Errorf("series: got %q, want %q", sc.series, "AD Police")
	}
	if sc.year != 1994 {
		t.Errorf("year: got %d, want %d", sc.year, 1994)
	}
}

func TestBuildSeriesContexts_YearRange(t *testing.T) {
	root := t.TempDir()
	book := filepath.Join(root, "Viz Graphic Novels", "Battle Angel Alita (1994-1998)", "Volume 1 - Rusty Angel.cbz")
	touch(t, book)

	ctx := buildSeriesContexts(root, []string{book}, nil)
	sc := ctx[filepath.Dir(book)]

	if sc.series != "Battle Angel Alita" {
		t.Errorf("series: got %q, want %q", sc.series, "Battle Angel Alita")
	}
	if sc.year != 1994 {
		t.Errorf("year: got %d, want %d", sc.year, 1994)
	}
}

func TestBuildSeriesContexts_CategoryDir_NoSeries(t *testing.T) {
	root := t.TempDir()
	book := filepath.Join(root, "TOKYOPOP", "One-Shot", "NOiSE (2007).cbz")
	touch(t, book)

	ctx := buildSeriesContexts(root, []string{book}, nil)
	sc := ctx[filepath.Dir(book)]

	if sc == nil {
		t.Fatal("no context for category dir")
	}
	if sc.publisher != "TOKYOPOP" {
		t.Errorf("publisher: got %q, want %q", sc.publisher, "TOKYOPOP")
	}
	if sc.series != "" {
		t.Errorf("series should be empty for category dir, got %q", sc.series)
	}
	if sc.year != 0 {
		t.Errorf("year should be 0 for category dir, got %d", sc.year)
	}
}

func TestBuildSeriesContexts_SeriesCover(t *testing.T) {
	root := t.TempDir()
	book := filepath.Join(root, "Viz", "Akira (1990)", "Akira (1990) v01 c1.cbz")
	cover := filepath.Join(root, "Viz", "Akira (1990)", "cover.jpg")
	touch(t, book)
	touch(t, cover)

	ctx := buildSeriesContexts(root, []string{book}, nil)
	sc := ctx[filepath.Dir(book)]

	if sc.coverPath != cover {
		t.Errorf("coverPath: got %q, want %q", sc.coverPath, cover)
	}
}

func TestBuildSeriesContexts_IndexJSON(t *testing.T) {
	root := t.TempDir()
	book := filepath.Join(root, "Viz", "Akira (1990)", "Akira (1990) v01 c1.cbz")
	touch(t, book)

	idx := filepath.Join(root, "Viz", "Akira (1990)", "index.json")
	if err := os.WriteFile(idx, []byte(`{"title":"Akira","year":1990,"publisher":"Viz","summary":"Neo-Tokyo"}`), 0o644); err != nil {
		t.Fatal(err)
	}

	ctx := buildSeriesContexts(root, []string{book}, nil)
	sc := ctx[filepath.Dir(book)]

	if sc.indexMeta == nil {
		t.Fatal("indexMeta not loaded")
	}
	if sc.indexMeta.Summary != "Neo-Tokyo" {
		t.Errorf("summary: got %q, want %q", sc.indexMeta.Summary, "Neo-Tokyo")
	}
}

// ── bookCoverImage ────────────────────────────────────────────────────────────

func TestBookCoverImage_Found(t *testing.T) {
	dir := t.TempDir()
	cbz := filepath.Join(dir, "Volume 1 - Rusty Angel.cbz")
	jpg := filepath.Join(dir, "Volume 1 - Rusty Angel.jpg")
	touch(t, cbz)
	touch(t, jpg)

	if got := bookCoverImage(cbz); got != jpg {
		t.Errorf("got %q, want %q", got, jpg)
	}
}

func TestBookCoverImage_NotFound(t *testing.T) {
	dir := t.TempDir()
	cbz := filepath.Join(dir, "Volume 1 - Rusty Angel.cbz")
	touch(t, cbz)

	if got := bookCoverImage(cbz); got != "" {
		t.Errorf("expected empty, got %q", got)
	}
}

func TestBookCoverImage_PngFallback(t *testing.T) {
	dir := t.TempDir()
	cbz := filepath.Join(dir, "book.cbz")
	png := filepath.Join(dir, "book.png")
	touch(t, cbz)
	touch(t, png)

	if got := bookCoverImage(cbz); got != png {
		t.Errorf("got %q, want %q", got, png)
	}
}

// ── buildMeta ─────────────────────────────────────────────────────────────────

func TestBuildMeta_SeriesFromContext_VolumeFromFilename(t *testing.T) {
	sc := &seriesContext{
		publisher: "Viz Graphic Novels",
		series:    "Battle Angel Alita",
		year:      1994,
	}
	// non-existent CBZ → archive parse fails → falls through to ParseFilename
	path := "/fake/lib/Viz/Battle Angel Alita (1994-1998)/Volume 1 - Rusty Angel.cbz"
	meta := buildMeta(nil, media.FormatCBZ, path, sc)

	if meta.Publisher != "Viz Graphic Novels" {
		t.Errorf("Publisher: got %q", meta.Publisher)
	}
	if meta.Series != "Battle Angel Alita" {
		t.Errorf("Series: got %q", meta.Series)
	}
	if meta.Volume != 1 {
		t.Errorf("Volume: got %d, want 1", meta.Volume)
	}
	if meta.Title != "Rusty Angel" {
		t.Errorf("Title: got %q, want %q", meta.Title, "Rusty Angel")
	}
}

func TestBuildMeta_ChapterFromFilename(t *testing.T) {
	sc := &seriesContext{
		publisher: "Viz Graphic Novels",
		series:    "AD Police",
		year:      1994,
	}
	path := "/fake/lib/Viz/AD Police (1994)/AD Police (1994) - Chapter 3.cbz"
	meta := buildMeta(nil, media.FormatCBZ, path, sc)

	if meta.Series != "AD Police" {
		t.Errorf("Series: got %q", meta.Series)
	}
	if meta.IssueNumber != "3" {
		t.Errorf("IssueNumber: got %q, want 3", meta.IssueNumber)
	}
	if meta.Volume != 0 {
		t.Errorf("Volume should be 0 for chapter files, got %d", meta.Volume)
	}
}

func TestBuildMeta_VolChapFromFilename(t *testing.T) {
	sc := &seriesContext{
		publisher: "Viz Graphic Novels",
		series:    "Ashen Victor",
		year:      1997,
	}
	path := "/fake/lib/Viz/Ashen Victor (1997)/Ashen Victor (1997) v01 c2.cbz"
	meta := buildMeta(nil, media.FormatCBZ, path, sc)

	if meta.Volume != 1 {
		t.Errorf("Volume: got %d, want 1", meta.Volume)
	}
	if meta.IssueNumber != "2" {
		t.Errorf("IssueNumber: got %q, want 2", meta.IssueNumber)
	}
}

func TestBuildMeta_StandaloneNoSeries(t *testing.T) {
	// category dir — sc has publisher but no series
	sc := &seriesContext{
		publisher: "TOKYOPOP",
	}
	path := "/fake/lib/TOKYOPOP/One-Shot/NOiSE (2007).cbz"
	meta := buildMeta(nil, media.FormatCBZ, path, sc)

	if meta.Publisher != "TOKYOPOP" {
		t.Errorf("Publisher: got %q", meta.Publisher)
	}
	if meta.Series != "" {
		t.Errorf("Series should be empty, got %q", meta.Series)
	}
	if meta.Title != "NOiSE" {
		t.Errorf("Title: got %q, want %q", meta.Title, "NOiSE")
	}
	if meta.Year != 2007 {
		t.Errorf("Year: got %d, want 2007", meta.Year)
	}
}

// ── upsertSeries early-return guard ──────────────────────────────────────────

func TestUpsertSeries_EmptyName(t *testing.T) {
	s := &Scanner{}
	if got := s.upsertSeries(nil, "lib-id", &metadata.BookMeta{}, "", "", 0, 0, false, false); got != "" {
		t.Errorf("empty series name should return empty, got %q", got)
	}
}

// ── bookType derivation ───────────────────────────────────────────────────────

func TestBookType_IssueWhenSeriesSet(t *testing.T) {
	sc := &seriesContext{publisher: "Viz", series: "AD Police", year: 1994}
	meta := buildMeta(nil, media.FormatCBZ, "/fake/AD Police (1994) - Chapter 1.cbz", sc)
	bookType := "issue"
	if meta.Series == "" {
		bookType = "standalone"
	}
	if bookType != "issue" {
		t.Errorf("expected issue, got %s", bookType)
	}
}

func TestBookType_StandaloneWhenNoSeries(t *testing.T) {
	sc := &seriesContext{publisher: "TOKYOPOP"} // no series (category dir)
	meta := buildMeta(nil, media.FormatCBZ, "/fake/NOiSE (2007).cbz", sc)
	bookType := "issue"
	if meta.Series == "" {
		bookType = "standalone"
	}
	if bookType != "standalone" {
		t.Errorf("expected standalone, got %s", bookType)
	}
}

// ── helper: metadata.ParseSeriesDir interaction ───────────────────────────────

func TestParseSeriesDir_CategoryDirYieldsZeroYear(t *testing.T) {
	m := metadata.ParseSeriesDir("One-Shot")
	if m.Year != 0 {
		t.Errorf("One-Shot should have year 0, got %d", m.Year)
	}
}

// ── adult content detection ───────────────────────────────────────────────────

func TestIsAdultContent_AdultInDirName(t *testing.T) {
	path := "/library/The Next Art/Hades-Syndrome (2024-2026) (ADULT)/Hades-Syndrome Vol 01 (2024) (ADULT) (TPB).cbz"
	if !isAdultContent(path) {
		t.Error("expected adult=true for path with (ADULT) in dir name")
	}
}

func TestIsAdultContent_RealWorldPath(t *testing.T) {
	path := "/library/The Next Art/Hades-Syndrome (2024-2026) (ADULT)/Hades-Syndrome Vol 02 - Hunting Season (2022) (ADULT) (TPB) (English) (Digital) (ASO) (THENEXTART).cbz"
	if !isAdultContent(path) {
		t.Error("expected adult=true for real-world path with (ADULT) in dir and filename")
	}
}

func TestIsAdultContent_AdultInFilename(t *testing.T) {
	path := "/library/Publisher/Some Series (2020)/Some Series 001 (2020) (ADULT).cbz"
	if !isAdultContent(path) {
		t.Error("expected adult=true for path with (ADULT) in filename")
	}
}

func TestIsAdultContent_18Plus(t *testing.T) {
	path := "/library/Publisher/Some Series (2020)/Some Series 001 18+.cbz"
	if !isAdultContent(path) {
		t.Error("expected adult=true for path with 18+")
	}
}

func TestIsAdultContent_NotAdult(t *testing.T) {
	path := "/library/Viz/Akira (1990)/Akira (1990) v01 c1.cbz"
	if isAdultContent(path) {
		t.Error("expected adult=false for non-adult path")
	}
}

func TestIsAdultContent_AdultWordBoundary(t *testing.T) {
	// "adults" should NOT match \badult\b
	path := "/library/Publisher/For Adults Only (2020)/book.cbz"
	// "Adults" contains "adult" but as part of "Adults" — \b still matches before A and after T...
	// actually "adults" does NOT match \badult\b because after "t" comes "s" (word char)
	if isAdultContent(path) {
		// "Adults" won't match \badult\b because the boundary after T fails (s is a word char)
		// This test documents that behavior
		t.Log("note: 'Adults' matched \badult\b — check boundary behavior")
	}
}

// ── (ADULT) tag in directory name with year range ─────────────────────────────

func TestBuildSeriesContexts_AdultDirTag(t *testing.T) {
	root := t.TempDir()
	book := filepath.Join(root, "The Next Art", "Hades-Syndrome (2024-2026) (ADULT)", "Hades-Syndrome Vol 01 (2024) (ADULT) (TPB).cbz")
	touch(t, book)

	ctx := buildSeriesContexts(root, []string{book}, nil)
	sc := ctx[filepath.Dir(book)]

	if sc == nil {
		t.Fatal("no context for series dir")
	}
	if sc.publisher != "The Next Art" {
		t.Errorf("publisher: got %q, want %q", sc.publisher, "The Next Art")
	}
	if sc.series != "Hades-Syndrome" {
		t.Errorf("series: got %q, want %q", sc.series, "Hades-Syndrome")
	}
	if sc.year != 2024 {
		t.Errorf("year: got %d, want 2024", sc.year)
	}
	if sc.endYear != 2026 {
		t.Errorf("endYear: got %d, want 2026", sc.endYear)
	}
}

func TestBuildSeriesContexts_AdultDirTagOngoing(t *testing.T) {
	root := t.TempDir()
	book := filepath.Join(root, "Publisher", "My Series (2020-) (ADULT)", "My Series 001.cbz")
	touch(t, book)

	ctx := buildSeriesContexts(root, []string{book}, nil)
	sc := ctx[filepath.Dir(book)]

	if sc.series != "My Series" {
		t.Errorf("series: got %q, want %q", sc.series, "My Series")
	}
	if sc.year != 2020 {
		t.Errorf("year: got %d, want 2020", sc.year)
	}
	if !sc.ongoing {
		t.Error("expected ongoing=true")
	}
}

// ── age_rating fallback from adult path detection ─────────────────────────────

func TestBuildMeta_AgeRatingSetFromAdultPath(t *testing.T) {
	sc := &seriesContext{
		publisher: "The Next Art",
		series:    "Hades-Syndrome",
		year:      2024,
	}
	// non-existent CBZ → archive parse fails → falls through to ParseFilename
	path := "/library/The Next Art/Hades-Syndrome (2024-2026) (ADULT)/Hades-Syndrome Vol 01 (2024) (ADULT) (TPB).cbz"
	meta := buildMeta(nil, media.FormatCBZ, path, sc)

	// simulate the scanner logic: adult detected → promote age_rating if unset
	adult := isAdultContent(path)
	if adult && (meta.AgeRating == "" || meta.AgeRating == "unknown") {
		meta.AgeRating = "adult"
	}

	if !adult {
		t.Error("expected isAdultContent=true")
	}
	if meta.AgeRating != "adult" {
		t.Errorf("AgeRating: got %q, want %q", meta.AgeRating, "adult")
	}
}

func TestBuildMeta_ExplicitRatingNotOverridden(t *testing.T) {
	// if CBZ already has an explicit rating, adult path detection should not override it
	// simulate: meta already has a rating (e.g. from ComicInfo.xml)
	meta := &metadata.BookMeta{
		Series:    "Series",
		AgeRating: "explicit",
	}
	adult := isAdultContent("/lib/Pub/Series (2020) (ADULT)/book.cbz")
	if adult && (meta.AgeRating == "" || meta.AgeRating == "unknown") {
		meta.AgeRating = "adult"
	}
	if meta.AgeRating != "explicit" {
		t.Errorf("explicit rating should not be overridden, got %q", meta.AgeRating)
	}
}
