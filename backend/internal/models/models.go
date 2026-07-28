package models

import "time"

type Library struct {
	ID        string    `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Name      string    `json:"name"`
	RootPath  string    `json:"root_path"`
	CreatedAt time.Time `json:"created_at"`
}

type BookSummary struct {
	ID          string  `json:"id"`
	Title       string  `json:"title"`
	Series      *string `json:"series,omitempty"`
	IssueNumber *string `json:"issue_number,omitempty"`
	Year        *int    `json:"year,omitempty"`
	Format      string  `json:"format"`
	PageCount   int     `json:"page_count"`
	AgeRating   string  `json:"age_rating"`
}

type Series struct {
	ID        string         `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	LibraryID string         `json:"library_id" gorm:"type:uuid;not null"`
	Name      string         `json:"name"`
	Publisher *string        `json:"publisher,omitempty"`
	CreatedAt time.Time      `json:"created_at"`
	Volumes   []SeriesVolume `json:"volumes,omitempty" gorm:"foreignKey:SeriesID"`
}

type SeriesVolume struct {
	ID           string    `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	SeriesID     string    `json:"series_id" gorm:"type:uuid;not null"`
	VolumeNumber int       `json:"volume_number"`
	Title        *string   `json:"title,omitempty"`
	Year         *int      `json:"year,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}

type Book struct {
	ID          string    `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	LibraryID   string    `json:"library_id" gorm:"type:uuid"`
	SeriesID    *string   `json:"series_id,omitempty" gorm:"type:uuid"`
	VolumeID    *string   `json:"volume_id,omitempty" gorm:"type:uuid"`
	Path        string    `json:"path"`
	Title       string    `json:"title"`
	Series      *string   `json:"series,omitempty"`
	IssueNumber *string   `json:"issue_number,omitempty"`
	Volume      *int      `json:"volume,omitempty"`
	Year        *int      `json:"year,omitempty"`
	Publisher   *string   `json:"publisher,omitempty"`
	Format      string    `json:"format"`
	PageCount   int       `json:"page_count"`
	FileSize    int64     `json:"file_size"`
	AgeRating   string    `json:"age_rating"`
	Language    *string   `json:"language,omitempty"`
	Summary     *string   `json:"summary,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
}

type User struct {
	ID        string     `json:"id" gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Email     string     `json:"email"`
	Username  string     `json:"username"`
	Role      string     `json:"role"`
	BirthDate *time.Time `json:"birth_date,omitempty"`
	CreatedAt time.Time  `json:"created_at"`
}
