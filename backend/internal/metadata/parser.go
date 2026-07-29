package metadata

import (
	"archive/zip"
	"encoding/json"
	"encoding/xml"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

type BookMeta struct {
	Title       string
	Series      string
	IssueNumber string
	Volume      int
	Year        int
	EndYear     int  // series end year, only set by ParseSeriesDir for year-range dirs
	Ongoing     bool // true when dir uses "(YYYY-)" trailing-dash notation
	Publisher   string
	Summary     string
	AgeRating   string
	Language    string
	PageCount   int
}

// comicInfoXML maps ComicInfo.xml fields.
type comicInfoXML struct {
	Title     string `xml:"Title"`
	Series    string `xml:"Series"`
	Number    string `xml:"Number"`
	Volume    int    `xml:"Volume"`
	Year      int    `xml:"Year"`
	Publisher string `xml:"Publisher"`
	Summary   string `xml:"Summary"`
	AgeRating string `xml:"AgeRating"`
	Language  string `xml:"LanguageISO"`
	PageCount int    `xml:"PageCount"`
}

// metronInfoXML maps MetronInfo.xml fields.
type metronInfoXML struct {
	Series struct {
		Name   string `xml:"name,attr"`
		Volume int    `xml:"volume,attr"`
	} `xml:"Series"`
	Number    string `xml:"Number"`
	Publisher struct {
		Name string `xml:"name,attr"`
	} `xml:"Publisher"`
	Summary string `xml:"Summary"`
	Rating  struct {
		Name string `xml:"name,attr"`
	} `xml:"Rating"`
	Cover struct {
		Year int `xml:"year,attr"`
	} `xml:"Cover"`
}

var (
	// "Series Name #12 (2020)" or "Series Name v2 #12"
	reSeries = regexp.MustCompile(`(?i)^(.+?)(?:\s+v(\d+))?\s+#(\d+(?:\.\d+)?)(?:\s+\((\d{4})\))?`)
	reYear   = regexp.MustCompile(`\((\d{4})\)`)
	// "Series Name (Year) - Chapter N"
	reChapter = regexp.MustCompile(`(?i)^(.+?)(?:\s+\((\d{4})\))?\s+-\s+[Cc]hapter\s+(\d+(?:\.\d+)?)`)
	// "Volume N - Title" or "Volume N"
	reVolTitle = regexp.MustCompile(`(?i)^[Vv]olume\s+(\d+)(?:\s+-\s+(.+))?$`)
	// "Series v01 c1" (e.g., "Ashen Victor (1997) v01 c1")
	reVolChap = regexp.MustCompile(`(?i)^(.+?)\s+v(\d+)\s+c(\d+(?:\.\d+)?)`)
	// "Series 001 (Year) (tag) (group)" — zero-padded issue without # prefix
	reIssueNum = regexp.MustCompile(`(?i)^(.+?)\s+(\d{3,})(?:\s+\((\d{4})\))?(?:\s+\([^)]+\))*\s*$`)
	// trailing year patterns in directory names:
	//   "(1992)"    → single year
	//   "(2004-2005)" → range
	//   "(2003-)"   → ongoing (trailing dash, no end year)
	reDirYear = regexp.MustCompile(`\s*\((\d{4})(-(\d{4})?)?\)\s*$`)
)

// ParseZipArchive extracts metadata from a zip-based archive (CBZ, EPUB).
func ParseZipArchive(path string) (*BookMeta, error) {
	r, err := zip.OpenReader(path)
	if err != nil {
		return nil, err
	}
	defer r.Close()

	meta := &BookMeta{}

	for _, f := range r.File {
		name := strings.ToLower(filepath.Base(f.Name))
		switch name {
		case "comicinfo.xml":
			if err := parseXMLFile(f, &comicInfoXML{}, func(v any) {
				ci := v.(*comicInfoXML)
				meta.Title = ci.Title
				meta.Series = ci.Series
				meta.IssueNumber = ci.Number
				meta.Volume = ci.Volume
				meta.Year = ci.Year
				meta.Publisher = ci.Publisher
				meta.Summary = ci.Summary
				meta.AgeRating = normalizeRating(ci.AgeRating)
				meta.Language = ci.Language
				meta.PageCount = ci.PageCount
			}); err == nil {
				return meta, nil
			}
		case "metroninfo.xml":
			if err := parseXMLFile(f, &metronInfoXML{}, func(v any) {
				mi := v.(*metronInfoXML)
				meta.Series = mi.Series.Name
				meta.Volume = mi.Series.Volume
				meta.IssueNumber = mi.Number
				meta.Publisher = mi.Publisher.Name
				meta.Summary = mi.Summary
				meta.AgeRating = normalizeRating(mi.Rating.Name)
				meta.Year = mi.Cover.Year
			}); err == nil {
				return meta, nil
			}
		}
	}

	return meta, nil
}

// ParseFilename extracts best-effort metadata from a filename.
// Patterns tried in order:
//  1. "Series v01 c1" — volume + chapter
//  2. "Series (Year) - Chapter N" — chapter with optional year
//  3. "Volume N - Title" — volume-based with title
//  4. "Series #N (Year)" — issue number
func ParseFilename(path string) *BookMeta {
	name := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	meta := &BookMeta{}

	// "Series v01 c1" (e.g., "Ashen Victor (1997) v01 c1")
	if m := reVolChap.FindStringSubmatch(name); m != nil {
		meta.Series = strings.TrimSpace(m[1])
		v, _ := strconv.Atoi(m[2])
		meta.Volume = v
		meta.IssueNumber = stripLeadingZeros(m[3])
		meta.Title = meta.Series
		return meta
	}

	// "Series (Year) - Chapter N" (e.g., "AD Police (1994) - Chapter 1")
	if m := reChapter.FindStringSubmatch(name); m != nil {
		meta.Series = strings.TrimSpace(m[1])
		if m[2] != "" {
			y, _ := strconv.Atoi(m[2])
			meta.Year = y
		}
		meta.IssueNumber = stripLeadingZeros(m[3])
		meta.Title = meta.Series + " Chapter " + meta.IssueNumber
		return meta
	}

	// "Volume N - Title" (e.g., "Volume 1 - Rusty Angel")
	if m := reVolTitle.FindStringSubmatch(name); m != nil {
		v, _ := strconv.Atoi(m[1])
		meta.Volume = v
		if m[2] != "" {
			meta.Title = strings.TrimSpace(m[2])
		} else {
			meta.Title = "Volume " + m[1]
		}
		return meta
	}

	// "Series #N (Year)" or "Series v2 #12"
	if m := reSeries.FindStringSubmatch(name); m != nil {
		meta.Series = strings.TrimSpace(m[1])
		if m[2] != "" {
			v, _ := strconv.Atoi(m[2])
			meta.Volume = v
		}
		meta.IssueNumber = stripLeadingZeros(m[3])
		if m[4] != "" {
			y, _ := strconv.Atoi(m[4])
			meta.Year = y
		}
		meta.Title = meta.Series
		if meta.IssueNumber != "" {
			meta.Title += " #" + meta.IssueNumber
		}
		return meta
	}

	// "Series 001 (Year) (tag) (group)" — zero-padded issue without # prefix
	if m := reIssueNum.FindStringSubmatch(name); m != nil {
		meta.Series = strings.TrimSpace(m[1])
		meta.IssueNumber = stripLeadingZeros(m[2])
		if m[3] != "" {
			y, _ := strconv.Atoi(m[3])
			meta.Year = y
		}
		meta.Title = meta.Series + " #" + meta.IssueNumber
		return meta
	}

	meta.Title = name
	if m := reYear.FindStringSubmatch(name); m != nil {
		y, _ := strconv.Atoi(m[1])
		meta.Year = y
		meta.Title = strings.TrimSpace(reYear.ReplaceAllString(name, ""))
	}
	return meta
}

// ParseSeriesDir derives series name and year(s) from a directory name.
// "(1992)"      → Year=1992
// "(2004-2005)" → Year=2004, EndYear=2005
// "(2003-)"     → Year=2003, Ongoing=true
func ParseSeriesDir(name string) *BookMeta {
	meta := &BookMeta{}
	if m := reDirYear.FindStringSubmatch(name); m != nil {
		meta.Series = strings.TrimSpace(reDirYear.ReplaceAllString(name, ""))
		y, _ := strconv.Atoi(m[1])
		meta.Year = y
		if m[2] != "" { // dash present
			if m[3] != "" { // end year present → range
				ey, _ := strconv.Atoi(m[3])
				meta.EndYear = ey
			} else { // trailing dash only → ongoing
				meta.Ongoing = true
			}
		}
	} else {
		meta.Series = name
	}
	return meta
}

// ParseIndexJSON reads a Stashix index.json sidecar file and returns series-level metadata.
func ParseIndexJSON(path string) (*BookMeta, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var idx struct {
		Title     string `json:"title"`
		Year      int    `json:"year"`
		Publisher string `json:"publisher"`
		Summary   string `json:"summary"`
		AgeRating string `json:"age_rating"`
		Language  string `json:"language"`
	}
	if err := json.Unmarshal(data, &idx); err != nil {
		return nil, err
	}
	return &BookMeta{
		Series:    idx.Title,
		Year:      idx.Year,
		Publisher: idx.Publisher,
		Summary:   idx.Summary,
		AgeRating: normalizeRating(idx.AgeRating),
		Language:  idx.Language,
	}, nil
}

func parseXMLFile(f *zip.File, target any, apply func(any)) error {
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()

	data, err := io.ReadAll(rc)
	if err != nil {
		return err
	}
	if err := xml.Unmarshal(data, target); err != nil {
		return err
	}
	apply(target)
	return nil
}

// TODO Update to the proper age tags https://metron-project.github.io/docs/metroninfo/ratings

func stripLeadingZeros(s string) string {
	parts := strings.SplitN(s, ".", 2)
	n, err := strconv.Atoi(parts[0])
	if err != nil {
		return s
	}
	if len(parts) == 2 {
		return strconv.Itoa(n) + "." + parts[1]
	}
	return strconv.Itoa(n)
}

func normalizeRating(r string) string {
	switch strings.ToLower(r) {
	case "everyone", "g", "all ages":
		return "everyone"
	case "teen", "pg", "pg-13":
		return "teen"
	case "mature", "r":
		return "mature"
	case "explicit", "x", "adult", "nc-17":
		return "explicit"
	default:
		return "unknown"
	}
}
