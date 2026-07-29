package metadata

import (
	"testing"
)

func TestParseFilename(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		wantTitle   string
		wantSeries  string
		wantIssue   string
		wantVolume  int
		wantYear    int
	}{
		// standalone book: name + year, no series
		{
			name:      "standalone with year",
			input:     "NOiSE (2007).cbz",
			wantTitle: "NOiSE",
			wantYear:  2007,
		},
		// standalone book: name only, no year
		{
			name:      "standalone no year",
			input:     "Akira.cbz",
			wantTitle: "Akira",
		},
		// chapter pattern: Series (Year) - Chapter N
		{
			name:       "chapter with year",
			input:      "AD Police (1994) - Chapter 1.cbz",
			wantSeries: "AD Police",
			wantIssue:  "1",
			wantYear:   1994,
			wantTitle:  "AD Police Chapter 1",
		},
		{
			name:       "chapter no year",
			input:      "Some Series - Chapter 3.cbz",
			wantSeries: "Some Series",
			wantIssue:  "3",
			wantTitle:  "Some Series Chapter 3",
		},
		// vol+chapter pattern: Series (Year) vNN cN
		{
			name:       "vol and chapter",
			input:      "Ashen Victor (1997) v01 c1.cbz",
			wantSeries: "Ashen Victor (1997)",
			wantVolume: 1,
			wantIssue:  "1",
			wantTitle:  "Ashen Victor (1997)",
		},
		{
			name:       "vol and chapter decimal",
			input:      "Ashen Victor (1997) v01 c2.cbz",
			wantSeries: "Ashen Victor (1997)",
			wantVolume: 1,
			wantIssue:  "2",
		},
		// volume-title pattern: Volume N - Title
		{
			name:      "volume with title",
			input:     "Volume 1 - Rusty Angel.cbz",
			wantTitle: "Rusty Angel",
			wantVolume: 1,
		},
		{
			name:      "volume no title",
			input:     "Volume 3.cbz",
			wantTitle: "Volume 3",
			wantVolume: 3,
		},
		// zero-padded issue without # prefix, with extra parenthetical tags
		{
			name:       "zero-padded issue with year and tags",
			input:      "The Disavowed 001 (2025) (digital) (Knight Ripper-Empire).cbz",
			wantSeries: "The Disavowed",
			wantIssue:  "001",
			wantYear:   2025,
			wantTitle:  "The Disavowed #001",
		},
		{
			name:       "zero-padded issue no tags",
			input:      "Some Comic 012 (2020).cbz",
			wantSeries: "Some Comic",
			wantIssue:  "012",
			wantYear:   2020,
			wantTitle:  "Some Comic #012",
		},
		// issue number pattern: Series #N (Year)
		{
			name:      "series issue with year",
			input:     "X-Men #12 (1995).cbz",
			wantSeries: "X-Men",
			wantIssue:  "12",
			wantYear:   1995,
			wantTitle:  "X-Men #12",
		},
		{
			name:      "series vol and issue",
			input:     "X-Men v2 #5.cbz",
			wantSeries: "X-Men",
			wantVolume: 2,
			wantIssue:  "5",
			wantTitle:  "X-Men #5",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := ParseFilename(tc.input)

			if tc.wantTitle != "" && got.Title != tc.wantTitle {
				t.Errorf("Title: got %q, want %q", got.Title, tc.wantTitle)
			}
			if got.Series != tc.wantSeries {
				t.Errorf("Series: got %q, want %q", got.Series, tc.wantSeries)
			}
			if got.IssueNumber != tc.wantIssue {
				t.Errorf("IssueNumber: got %q, want %q", got.IssueNumber, tc.wantIssue)
			}
			if got.Volume != tc.wantVolume {
				t.Errorf("Volume: got %d, want %d", got.Volume, tc.wantVolume)
			}
			if got.Year != tc.wantYear {
				t.Errorf("Year: got %d, want %d", got.Year, tc.wantYear)
			}
		})
	}
}

func TestParseSeriesDir(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		wantSeries  string
		wantYear    int
		wantEndYear int
		wantOngoing bool
	}{
		{"single year",        "AD Police (1994)",               "AD Police",           1994, 0,    false},
		{"year range",         "Battle Angel Alita (1994-1998)", "Battle Angel Alita",  1994, 1998, false},
		{"ongoing",            "Berserk (1989-)",                "Berserk",             1989, 0,    true},
		{"no year — category", "One-Shot",                       "One-Shot",            0,    0,    false},
		{"no year — plain",    "Viz Graphic Novels",             "Viz Graphic Novels",  0,    0,    false},
		{"year at end",        "Ashen Victor (1997)",            "Ashen Victor",        1997, 0,    false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := ParseSeriesDir(tc.input)
			if got.Series != tc.wantSeries {
				t.Errorf("Series: got %q, want %q", got.Series, tc.wantSeries)
			}
			if got.Year != tc.wantYear {
				t.Errorf("Year: got %d, want %d", got.Year, tc.wantYear)
			}
			if got.EndYear != tc.wantEndYear {
				t.Errorf("EndYear: got %d, want %d", got.EndYear, tc.wantEndYear)
			}
			if got.Ongoing != tc.wantOngoing {
				t.Errorf("Ongoing: got %v, want %v", got.Ongoing, tc.wantOngoing)
			}
		})
	}
}
