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
	"time"
)

// Resource types for MetronInfo entities.

type ExternalID struct {
	Source    string
	SourceID  string
	IsPrimary bool
}

type AlternativeName struct {
	Name     string
	Language string
	SourceID string
}

type NamedResource struct {
	Name     string
	SourceID string
}

type UniverseResource struct {
	Name        string
	Designation string
	SourceID    string
}

type Arc struct {
	Name     string
	Number   int
	SourceID string
}

type Price struct {
	Country string
	Amount  float64
}

type BookURL struct {
	URL       string
	IsPrimary bool
}

type Credit struct {
	CreatorName     string
	CreatorSourceID string
	Roles           []string
}

type BookMeta struct {
	Title       string
	Series      string
	IssueNumber string
	Volume      int
	Year        int
	EndYear     int  // series end year from dir "(YYYY-YYYY)"
	Ongoing     bool // from dir "(YYYY-)" trailing dash
	Publisher   string
	Summary     string
	AgeRating   string
	Language    string
	PageCount   int

	// MetronInfo extended
	ExternalIDs            []ExternalID
	PublisherSourceID      string
	ImprintName            string
	ImprintSourceID        string
	SeriesSourceID         string
	SeriesSortName         string
	SeriesLanguage         string
	SeriesFormat           string // comic_format enum value
	SeriesStartYear        int
	SeriesIssueCount       int
	SeriesVolumeCount      int
	SeriesAlternativeNames []AlternativeName
	CollectionTitle        string
	AlternativeNumber      string
	MangaVolume            string
	Stories                []NamedResource
	Prices                 []Price
	CoverDate              string // YYYY-MM-DD
	StoreDate              string // YYYY-MM-DD
	Notes                  string
	Genres                 []NamedResource
	Tags                   []NamedResource
	Arcs                   []Arc
	Characters             []NamedResource
	Teams                  []NamedResource
	Universes              []UniverseResource
	Locations              []NamedResource
	Reprints               []NamedResource
	ISBN                   string
	UPC                    string
	CommunityRating        float64
	CommunityRatingCount   int
	URLs                   []BookURL
	Credits                []Credit
	LastModified           *time.Time
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

// metronInfoXML maps MetronInfo.xml fields per the MetronInfo schema.
type metronInfoXML struct {
	IDS struct {
		IDs []struct {
			Source    string `xml:"source,attr"`
			Primary   bool   `xml:"primary,attr"`
			Value     string `xml:",chardata"`
		} `xml:"ID"`
	} `xml:"IDS"`

	Publisher struct {
		ID      string `xml:"id,attr"`
		Name    string `xml:"Name"`
		Imprint struct {
			ID    string `xml:"id,attr"`
			Value string `xml:",chardata"`
		} `xml:"Imprint"`
	} `xml:"Publisher"`

	Series struct {
		Lang        string `xml:"lang,attr"`
		ID          string `xml:"id,attr"`
		Name        string `xml:"Name"`
		SortName    string `xml:"SortName"`
		Volume      int    `xml:"Volume"`
		Format      string `xml:"Format"`
		StartYear   int    `xml:"StartYear"`
		IssueCount  int    `xml:"IssueCount"`
		VolumeCount int    `xml:"VolumeCount"`
		AlternativeNames struct {
			Names []struct {
				ID    string `xml:"id,attr"`
				Lang  string `xml:"lang,attr"`
				Value string `xml:",chardata"`
			} `xml:"AlternativeName"`
		} `xml:"AlternativeNames"`
	} `xml:"Series"`

	MangaVolume       string `xml:"MangaVolume"`
	CollectionTitle   string `xml:"CollectionTitle"`
	Number            string `xml:"Number"`
	AlternativeNumber string `xml:"AlternativeNumber"`

	Stories struct {
		Stories []struct {
			ID    string `xml:"id,attr"`
			Value string `xml:",chardata"`
		} `xml:"Story"`
	} `xml:"Stories"`

	Summary string `xml:"Summary"`
	Notes   string `xml:"Notes"`

	Prices struct {
		Prices []struct {
			Country string  `xml:"country,attr"`
			Value   float64 `xml:",chardata"`
		} `xml:"Price"`
	} `xml:"Prices"`

	CoverDate string `xml:"CoverDate"`
	StoreDate string `xml:"StoreDate"`
	PageCount int    `xml:"PageCount"`

	Genres struct {
		Genres []struct {
			ID    string `xml:"id,attr"`
			Value string `xml:",chardata"`
		} `xml:"Genre"`
	} `xml:"Genres"`

	Tags struct {
		Tags []struct {
			ID    string `xml:"id,attr"`
			Value string `xml:",chardata"`
		} `xml:"Tag"`
	} `xml:"Tags"`

	Arcs struct {
		Arcs []struct {
			ID     string `xml:"id,attr"`
			Name   string `xml:"Name"`
			Number int    `xml:"Number"`
		} `xml:"Arc"`
	} `xml:"Arcs"`

	Characters struct {
		Characters []struct {
			ID    string `xml:"id,attr"`
			Value string `xml:",chardata"`
		} `xml:"Character"`
	} `xml:"Characters"`

	Teams struct {
		Teams []struct {
			ID    string `xml:"id,attr"`
			Value string `xml:",chardata"`
		} `xml:"Team"`
	} `xml:"Teams"`

	Universes struct {
		Universes []struct {
			ID          string `xml:"id,attr"`
			Name        string `xml:"Name"`
			Designation string `xml:"Designation"`
		} `xml:"Universe"`
	} `xml:"Universes"`

	Locations struct {
		Locations []struct {
			ID    string `xml:"id,attr"`
			Value string `xml:",chardata"`
		} `xml:"Location"`
	} `xml:"Locations"`

	Reprints struct {
		Reprints []struct {
			ID    string `xml:"id,attr"`
			Value string `xml:",chardata"`
		} `xml:"Reprint"`
	} `xml:"Reprints"`

	GTIN struct {
		ISBN string `xml:"ISBN"`
		UPC  string `xml:"UPC"`
	} `xml:"GTIN"`

	AgeRating string `xml:"AgeRating"`

	CommunityRating struct {
		AverageRating float64 `xml:"AverageRating"`
		RatingCount   int     `xml:"RatingCount"`
	} `xml:"CommunityRating"`

	URLs struct {
		URLs []struct {
			Primary bool   `xml:"primary,attr"`
			Value   string `xml:",chardata"`
		} `xml:"URL"`
	} `xml:"URLs"`

	Credits struct {
		Credits []struct {
			Creator struct {
				ID    string `xml:"id,attr"`
				Value string `xml:",chardata"`
			} `xml:"Creator"`
			Roles struct {
				Roles []struct {
					ID    string `xml:"id,attr"`
					Value string `xml:",chardata"`
				} `xml:"Role"`
			} `xml:"Roles"`
		} `xml:"Credit"`
	} `xml:"Credits"`

	LastModified string `xml:"LastModified"`
}

var (
	reSeries   = regexp.MustCompile(`(?i)^(.+?)(?:\s+v(\d+))?\s+#(\d+(?:\.\d+)?)(?:\s+\((\d{4})\))?`)
	reYear     = regexp.MustCompile(`\((\d{4})\)`)
	reChapter  = regexp.MustCompile(`(?i)^(.+?)(?:\s+\((\d{4})\))?\s+-\s+[Cc]hapter\s+(\d+(?:\.\d+)?)`)
	reVolTitle = regexp.MustCompile(`(?i)^[Vv]olume\s+(\d+)(?:\s+-\s+(.+))?$`)
	reVolChap  = regexp.MustCompile(`(?i)^(.+?)\s+v(\d+)\s+c(\d+(?:\.\d+)?)`)
	reIssueNum = regexp.MustCompile(`(?i)^(.+?)\s+(\d{1,4})(?:\s+\((\d{4})\))?(?:\s+(?:\([^)]+\)|\S+))*\s*$`)
	reDirYear  = regexp.MustCompile(`\s*\((\d{4})(-(\d{4})?)?\)\s*$`)
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
				applyMetronInfo(meta, mi)
			}); err == nil {
				return meta, nil
			}
		}
	}

	return meta, nil
}

func applyMetronInfo(meta *BookMeta, mi *metronInfoXML) {
	meta.Series = mi.Series.Name
	meta.Volume = mi.Series.Volume
	meta.IssueNumber = mi.Number
	meta.Publisher = mi.Publisher.Name
	meta.Summary = mi.Summary
	meta.AgeRating = normalizeRating(mi.AgeRating)
	meta.PageCount = mi.PageCount
	meta.Language = mi.Series.Lang
	meta.Notes = mi.Notes
	meta.CollectionTitle = mi.CollectionTitle
	meta.AlternativeNumber = mi.AlternativeNumber
	meta.MangaVolume = mi.MangaVolume
	meta.CoverDate = mi.CoverDate
	meta.StoreDate = mi.StoreDate
	meta.ISBN = mi.GTIN.ISBN
	meta.UPC = mi.GTIN.UPC

	// Build title from CollectionTitle or Series+Number
	if mi.CollectionTitle != "" {
		meta.Title = mi.CollectionTitle
	} else if mi.Series.Name != "" && mi.Number != "" {
		meta.Title = mi.Series.Name + " #" + mi.Number
	} else if mi.Series.Name != "" {
		meta.Title = mi.Series.Name
	}

	// Year from CoverDate, fallback to Series.StartYear
	if mi.CoverDate != "" && len(mi.CoverDate) >= 4 {
		if y, err := strconv.Atoi(mi.CoverDate[:4]); err == nil {
			meta.Year = y
		}
	} else if mi.Series.StartYear != 0 {
		meta.Year = mi.Series.StartYear
	}

	// Community rating
	if mi.CommunityRating.AverageRating > 0 {
		meta.CommunityRating = mi.CommunityRating.AverageRating
		meta.CommunityRatingCount = mi.CommunityRating.RatingCount
	}

	// Series extended
	meta.SeriesSourceID = mi.Series.ID
	meta.SeriesSortName = mi.Series.SortName
	meta.SeriesLanguage = mi.Series.Lang
	meta.SeriesFormat = mi.Series.Format
	meta.SeriesStartYear = mi.Series.StartYear
	meta.SeriesIssueCount = mi.Series.IssueCount
	meta.SeriesVolumeCount = mi.Series.VolumeCount

	// Publisher source ID and imprint
	meta.PublisherSourceID = mi.Publisher.ID
	if mi.Publisher.Imprint.Value != "" {
		meta.ImprintName = mi.Publisher.Imprint.Value
		meta.ImprintSourceID = mi.Publisher.Imprint.ID
	}

	// Series alternative names
	for _, an := range mi.Series.AlternativeNames.Names {
		meta.SeriesAlternativeNames = append(meta.SeriesAlternativeNames, AlternativeName{
			Name:     an.Value,
			Language: an.Lang,
			SourceID: an.ID,
		})
	}

	// External IDs (book-level)
	for _, id := range mi.IDS.IDs {
		meta.ExternalIDs = append(meta.ExternalIDs, ExternalID{
			Source:    id.Source,
			SourceID:  id.Value,
			IsPrimary: id.Primary,
		})
	}

	// Genres, Tags, Characters, Teams, Locations
	for _, g := range mi.Genres.Genres {
		meta.Genres = append(meta.Genres, NamedResource{Name: g.Value, SourceID: g.ID})
	}
	for _, t := range mi.Tags.Tags {
		meta.Tags = append(meta.Tags, NamedResource{Name: t.Value, SourceID: t.ID})
	}
	for _, c := range mi.Characters.Characters {
		meta.Characters = append(meta.Characters, NamedResource{Name: c.Value, SourceID: c.ID})
	}
	for _, t := range mi.Teams.Teams {
		meta.Teams = append(meta.Teams, NamedResource{Name: t.Value, SourceID: t.ID})
	}
	for _, l := range mi.Locations.Locations {
		meta.Locations = append(meta.Locations, NamedResource{Name: l.Value, SourceID: l.ID})
	}
	for _, r := range mi.Reprints.Reprints {
		meta.Reprints = append(meta.Reprints, NamedResource{Name: r.Value, SourceID: r.ID})
	}

	// Story arcs
	for _, a := range mi.Arcs.Arcs {
		meta.Arcs = append(meta.Arcs, Arc{Name: a.Name, Number: a.Number, SourceID: a.ID})
	}

	// Universes
	for _, u := range mi.Universes.Universes {
		meta.Universes = append(meta.Universes, UniverseResource{
			Name:        u.Name,
			Designation: u.Designation,
			SourceID:    u.ID,
		})
	}

	// Stories within issue
	for _, st := range mi.Stories.Stories {
		meta.Stories = append(meta.Stories, NamedResource{Name: st.Value, SourceID: st.ID})
	}

	// Prices
	for _, p := range mi.Prices.Prices {
		meta.Prices = append(meta.Prices, Price{Country: p.Country, Amount: p.Value})
	}

	// URLs
	for _, u := range mi.URLs.URLs {
		meta.URLs = append(meta.URLs, BookURL{URL: u.Value, IsPrimary: u.Primary})
	}

	// Credits
	for _, c := range mi.Credits.Credits {
		if c.Creator.Value == "" {
			continue
		}
		credit := Credit{
			CreatorName:     c.Creator.Value,
			CreatorSourceID: c.Creator.ID,
		}
		for _, r := range c.Roles.Roles {
			if r.Value != "" {
				credit.Roles = append(credit.Roles, r.Value)
			}
		}
		meta.Credits = append(meta.Credits, credit)
	}

	// Last modified
	if mi.LastModified != "" {
		for _, layout := range []string{time.RFC3339, "2006-01-02T15:04:05"} {
			if t, err := time.Parse(layout, mi.LastModified); err == nil {
				meta.LastModified = &t
				break
			}
		}
	}
}

// ParseFilename extracts best-effort metadata from a filename.
func ParseFilename(path string) *BookMeta {
	name := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	meta := &BookMeta{}

	if m := reVolChap.FindStringSubmatch(name); m != nil {
		meta.Series = strings.TrimSpace(m[1])
		v, _ := strconv.Atoi(m[2])
		meta.Volume = v
		meta.IssueNumber = stripLeadingZeros(m[3])
		meta.Title = meta.Series
		return meta
	}

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
func ParseSeriesDir(name string) *BookMeta {
	meta := &BookMeta{}
	if m := reDirYear.FindStringSubmatch(name); m != nil {
		meta.Series = strings.TrimSpace(reDirYear.ReplaceAllString(name, ""))
		y, _ := strconv.Atoi(m[1])
		meta.Year = y
		if m[2] != "" {
			if m[3] != "" {
				ey, _ := strconv.Atoi(m[3])
				meta.EndYear = ey
			} else {
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
	switch strings.ToLower(strings.TrimSpace(r)) {
	case "everyone", "g", "all ages":
		return "everyone"
	case "teen", "pg", "pg-13":
		return "teen"
	case "teen plus", "teen+":
		return "teen_plus"
	case "mature", "r":
		return "mature"
	case "explicit", "x", "nc-17":
		return "explicit"
	case "adult":
		return "adult"
	default:
		return "unknown"
	}
}
