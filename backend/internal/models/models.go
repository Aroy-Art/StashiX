package models

import (
	"database/sql/driver"
	"encoding/json"
	"fmt"
	"time"
)

// StringSlice is a []string that serializes as JSON for JSONB columns.
type StringSlice []string

func (s *StringSlice) Scan(value interface{}) error {
	if value == nil {
		*s = nil
		return nil
	}
	var b []byte
	switch v := value.(type) {
	case []byte:
		b = v
	case string:
		b = []byte(v)
	default:
		return fmt.Errorf("StringSlice: unsupported type %T", value)
	}
	return json.Unmarshal(b, s)
}

func (s StringSlice) Value() (driver.Value, error) {
	if s == nil {
		return "[]", nil
	}
	b, err := json.Marshal(s)
	return string(b), err
}

type Library struct {
	ID                string      `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Name              string      `json:"name"`
	RootPath          string      `json:"root_path"`
	CreatedAt         time.Time   `json:"created_at"`
	BookCount         int         `json:"book_count"`
	IssueCount        int         `json:"issue_count"`
	SeriesCount       int         `json:"series_count"`
	StandaloneFolders StringSlice `json:"standalone_folders" gorm:"column:standalone_folders"`
}

type BookSummary struct {
	ID          string  `json:"id"`
	Title       string  `json:"title"`
	Type        string  `json:"type"`
	Series      *string `json:"series,omitempty"`
	IssueNumber *string `json:"issue_number,omitempty"`
	Volume      *int    `json:"volume,omitempty"`
	Year        *int    `json:"year,omitempty"`
	Format      string  `json:"format"`
	PageCount   int     `json:"page_count"`
	FileSize    int64   `json:"file_size"`
	AgeRating   string  `json:"age_rating"`
	Adult       bool    `json:"adult"`
	CurrentPage *int    `json:"current_page,omitempty"`
}

type Publisher struct {
	ID        string    `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Name      string    `json:"name"`
	Source    *string   `json:"source,omitempty"`
	SourceID  *string   `json:"source_id,omitempty"`
	CreatedAt time.Time `json:"created_at"`
	Imprints  []Imprint `json:"imprints,omitempty" gorm:"foreignKey:PublisherID"`
}

type Imprint struct {
	ID          string    `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	PublisherID string    `json:"publisher_id" gorm:"type:uuid;not null"`
	Name        string    `json:"name"`
	SourceID    *string   `json:"source_id,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
}

type Series struct {
	ID               string                  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	LibraryID        string                  `json:"library_id" gorm:"type:uuid;not null"`
	Path             string                  `json:"path" gorm:"not null;default:''"`
	Name             string                  `json:"name"`
	SortName         *string                 `json:"sort_name,omitempty"`
	Volume           *int                    `json:"volume,omitempty"`
	Language         string                  `json:"language" gorm:"default:en"`
	Format           *string                 `json:"format,omitempty"`
	StartYear        *int                    `json:"start_year,omitempty"`
	EndYear          *int                    `json:"end_year,omitempty"`
	Ongoing          bool                    `json:"ongoing"`
	Adult            bool                    `json:"adult"`
	AgeRating        string                  `json:"age_rating,omitempty"`
	IssueCount       *int                    `json:"issue_count,omitempty"`
	VolumeCount      *int                    `json:"volume_count,omitempty"`
	Publisher        *string                 `json:"publisher,omitempty"`
	PublisherID      *string                 `json:"publisher_id,omitempty" gorm:"type:uuid"`
	ImprintID        *string                 `json:"imprint_id,omitempty" gorm:"type:uuid"`
	CreatedAt        time.Time               `json:"created_at"`
	Volumes          []SeriesVolume          `json:"volumes,omitempty" gorm:"foreignKey:SeriesID"`
	AlternativeNames []SeriesAlternativeName `json:"alternative_names,omitempty" gorm:"foreignKey:SeriesID"`
	ExternalIDs      []SeriesExternalID      `json:"external_ids,omitempty" gorm:"foreignKey:SeriesID"`
	CoverBookID      *string                 `json:"cover_book_id,omitempty" gorm:"-:migration"`
	BookCount        int                     `json:"book_count,omitempty" gorm:"-:migration"`
}

type SeriesVolume struct {
	ID           string    `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	SeriesID     string    `json:"series_id" gorm:"type:uuid;not null"`
	VolumeNumber int       `json:"volume_number"`
	Title        *string   `json:"title,omitempty"`
	Year         *int      `json:"year,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}

type SeriesAlternativeName struct {
	ID       string  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	SeriesID string  `json:"series_id" gorm:"type:uuid;not null"`
	Name     string  `json:"name"`
	Language string  `json:"language" gorm:"default:en"`
	SourceID *string `json:"source_id,omitempty"`
}

type SeriesExternalID struct {
	SeriesID  string `json:"series_id" gorm:"type:uuid;primaryKey;not null"`
	Source    string `json:"source" gorm:"primaryKey"`
	SourceID  string `json:"source_id"`
	IsPrimary bool   `json:"is_primary"`
}

type Book struct {
	ID                   string    `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	LibraryID            string    `json:"library_id" gorm:"type:uuid"`
	Path                 string    `json:"path"`
	Title                string    `json:"title"`
	Type                 string    `json:"type"` // "issue" | "standalone"
	SeriesID             *string   `json:"series_id,omitempty" gorm:"type:uuid"`
	Series               *string   `json:"series,omitempty"`
	IssueNumber          *string   `json:"issue_number,omitempty"`
	AlternativeNumber    *string   `json:"alternative_number,omitempty"`
	Volume               *int      `json:"volume,omitempty"`
	Year                 *int      `json:"year,omitempty"`
	CoverDate            *string   `json:"cover_date,omitempty"`
	StoreDate            *string   `json:"store_date,omitempty"`
	CollectionTitle      *string   `json:"collection_title,omitempty"`
	MangaVolume          *string   `json:"manga_volume,omitempty"`
	Publisher            *string   `json:"publisher,omitempty"`
	PublisherID          *string   `json:"publisher_id,omitempty" gorm:"type:uuid"`
	ImprintID            *string   `json:"imprint_id,omitempty" gorm:"type:uuid"`
	Format               string    `json:"format"` // file format: cbz, cbr, etc.
	ComicFormat          *string   `json:"comic_format,omitempty"`
	PageCount            int       `json:"page_count"`
	FileSize             int64     `json:"file_size"`
	AgeRating            string    `json:"age_rating"`
	Adult                bool      `json:"adult"`
	Language             *string   `json:"language,omitempty"`
	Summary              *string   `json:"summary,omitempty"`
	Notes                *string   `json:"notes,omitempty"`
	ISBN                 *string   `json:"isbn,omitempty"`
	UPC                  *string   `json:"upc,omitempty"`
	CommunityRating      *float64   `json:"community_rating,omitempty"`
	CommunityRatingCount *int       `json:"community_rating_count,omitempty"`
	LastModified         *time.Time `json:"last_modified,omitempty"`
	FileHash             *string    `json:"file_hash,omitempty"`
	DeletedAt            *time.Time `json:"deleted_at,omitempty"`
	CurrentPage          *int       `json:"current_page,omitempty" gorm:"-"`
	CreatedAt            time.Time  `json:"created_at"`
}

type BookExternalID struct {
	BookID    string `json:"book_id" gorm:"type:uuid;primaryKey;not null"`
	Source    string `json:"source" gorm:"primaryKey"`
	SourceID  string `json:"source_id"`
	IsPrimary bool   `json:"is_primary"`
}

type BookURL struct {
	ID        string `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	BookID    string `json:"book_id" gorm:"type:uuid;not null"`
	URL       string `json:"url"`
	IsPrimary bool   `json:"is_primary"`
}

type Genre struct {
	ID       string  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Name     string  `json:"name"`
	SourceID *string `json:"source_id,omitempty"`
}

type Tag struct {
	ID       string  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Name     string  `json:"name"`
	SourceID *string `json:"source_id,omitempty"`
}

type StoryArc struct {
	ID       string  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Name     string  `json:"name"`
	SourceID *string `json:"source_id,omitempty"`
}

type BookStoryArc struct {
	BookID    string `json:"book_id" gorm:"type:uuid;primaryKey;not null"`
	ArcID     string `json:"arc_id" gorm:"type:uuid;primaryKey;not null"`
	ArcNumber *int   `json:"arc_number,omitempty"`
}

type Character struct {
	ID       string  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Name     string  `json:"name"`
	SourceID *string `json:"source_id,omitempty"`
}

type Team struct {
	ID       string  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Name     string  `json:"name"`
	SourceID *string `json:"source_id,omitempty"`
}

type Universe struct {
	ID          string  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Name        string  `json:"name"`
	Designation *string `json:"designation,omitempty"`
	SourceID    *string `json:"source_id,omitempty"`
}

type Location struct {
	ID       string  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Name     string  `json:"name"`
	SourceID *string `json:"source_id,omitempty"`
}

type Creator struct {
	ID       string  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Name     string  `json:"name"`
	SourceID *string `json:"source_id,omitempty"`
}

type BookCredit struct {
	ID        string `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	BookID    string `json:"book_id" gorm:"type:uuid;not null"`
	CreatorID string `json:"creator_id" gorm:"type:uuid;not null"`
	Role      string `json:"role"`
}

type BookStory struct {
	ID        string `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	BookID    string `json:"book_id" gorm:"type:uuid;not null"`
	Title     string `json:"title"`
	SourceID  *string `json:"source_id,omitempty"`
	SortOrder int    `json:"sort_order"`
}

type BookPrice struct {
	ID      string  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	BookID  string  `json:"book_id" gorm:"type:uuid;not null"`
	Country string  `json:"country"`
	Price   float64 `json:"price"`
}

type BookReprint struct {
	ID       string  `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	BookID   string  `json:"book_id" gorm:"type:uuid;not null"`
	SourceID string  `json:"source_id"`
	Name     *string `json:"name,omitempty"`
}

type User struct {
	ID        string     `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Email     string     `json:"email"`
	Username  string     `json:"username"`
	FirstName string     `json:"first_name"`
	LastName  string     `json:"last_name"`
	Role      string     `json:"role"`
	BirthDate *time.Time `json:"birth_date,omitempty"`
	CreatedAt time.Time  `json:"created_at"`
}
