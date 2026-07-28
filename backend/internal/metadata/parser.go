package metadata

import (
	"archive/zip"
	"encoding/xml"
	"io"
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
	Publisher   string
	Summary     string
	AgeRating   string
	Language    string
	PageCount   int
}

// comicInfoXML maps ComicInfo.xml fields.
type comicInfoXML struct {
	Title       string `xml:"Title"`
	Series      string `xml:"Series"`
	Number      string `xml:"Number"`
	Volume      int    `xml:"Volume"`
	Year        int    `xml:"Year"`
	Publisher   string `xml:"Publisher"`
	Summary     string `xml:"Summary"`
	AgeRating   string `xml:"AgeRating"`
	Language    string `xml:"LanguageISO"`
	PageCount   int    `xml:"PageCount"`
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
	Summary  string `xml:"Summary"`
	Rating   struct {
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
func ParseFilename(path string) *BookMeta {
	name := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	meta := &BookMeta{}

	if m := reSeries.FindStringSubmatch(name); m != nil {
		meta.Series = strings.TrimSpace(m[1])
		if m[2] != "" {
			v, _ := strconv.Atoi(m[2])
			meta.Volume = v
		}
		meta.IssueNumber = m[3]
		if m[4] != "" {
			y, _ := strconv.Atoi(m[4])
			meta.Year = y
		}
		meta.Title = meta.Series
		if meta.IssueNumber != "" {
			meta.Title += " #" + meta.IssueNumber
		}
	} else {
		meta.Title = name
		if m := reYear.FindStringSubmatch(name); m != nil {
			y, _ := strconv.Atoi(m[1])
			meta.Year = y
		}
	}

	return meta
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
