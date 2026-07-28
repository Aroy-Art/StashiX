package media

import (
	"archive/zip"
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"path/filepath"
	"sort"
	"strings"

	"github.com/bodgit/sevenzip"
	"github.com/nwaples/rardecode/v2"
)

type Format string

const (
	FormatCBZ  Format = "cbz"
	FormatCBR  Format = "cbr"
	FormatCB7  Format = "cb7"
	FormatEPUB Format = "epub"
	FormatPDF  Format = "pdf"
)

func DetectFormat(path string) (Format, error) {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".cbz":
		return FormatCBZ, nil
	case ".cbr":
		return FormatCBR, nil
	case ".cb7":
		return FormatCB7, nil
	case ".epub":
		return FormatEPUB, nil
	case ".pdf":
		return FormatPDF, nil
	default:
		return "", fmt.Errorf("unsupported format: %s", filepath.Ext(path))
	}
}

// PageList returns sorted image filenames inside a comic archive.
func PageList(path string, format Format) ([]string, error) {
	switch format {
	case FormatCBZ, FormatEPUB:
		return zipPages(path)
	case FormatCBR:
		return rarPages(path)
	case FormatCB7:
		return sevenzipPages(path)
	default:
		return nil, fmt.Errorf("PageList: unsupported format %s", format)
	}
}

// PageReader opens a single page by index from an archive.
func PageReader(path string, format Format, index int) (io.ReadCloser, string, error) {
	pages, err := PageList(path, format)
	if err != nil {
		return nil, "", err
	}
	if index < 0 || index >= len(pages) {
		return nil, "", fmt.Errorf("page index %d out of range (0-%d)", index, len(pages)-1)
	}
	target := pages[index]

	switch format {
	case FormatCBZ, FormatEPUB:
		return zipPageReader(path, target)
	case FormatCBR:
		return rarPageReader(path, target)
	case FormatCB7:
		return sevenzipPageReader(path, target)
	default:
		return nil, "", fmt.Errorf("unsupported format %s", format)
	}
}

// CoverReader returns a reader for the first page (cover).
func CoverReader(path string, format Format) (io.ReadCloser, string, error) {
	return PageReader(path, format, 0)
}

func isImage(name string) bool {
	ext := strings.ToLower(filepath.Ext(name))
	switch ext {
	case ".jpg", ".jpeg", ".png", ".webp", ".gif", ".avif":
		return true
	}
	return false
}

func sortedImages(names []string) []string {
	imgs := make([]string, 0, len(names))
	for _, n := range names {
		if isImage(n) {
			imgs = append(imgs, n)
		}
	}
	sort.Strings(imgs)
	return imgs
}

// --- ZIP (CBZ / EPUB) ---

func zipPages(path string) ([]string, error) {
	r, err := zip.OpenReader(path)
	if err != nil {
		return nil, err
	}
	defer r.Close()

	names := make([]string, 0, len(r.File))
	for _, f := range r.File {
		names = append(names, f.Name)
	}
	return sortedImages(names), nil
}

func zipPageReader(path, target string) (io.ReadCloser, string, error) {
	r, err := zip.OpenReader(path)
	if err != nil {
		return nil, "", err
	}
	for _, f := range r.File {
		if f.Name == target {
			rc, err := f.Open()
			if err != nil {
				r.Close()
				return nil, "", err
			}
			// wrap so closing rc also closes the zip reader
			return &multiCloser{rc, r}, mimeFromExt(target), nil
		}
	}
	r.Close()
	return nil, "", fmt.Errorf("page %s not found in archive", target)
}

// --- RAR (CBR) ---

func rarPages(path string) ([]string, error) {
	r, err := rardecode.OpenReader(path)
	if err != nil {
		return nil, err
	}
	defer r.Close()

	var names []string
	for {
		hdr, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		names = append(names, hdr.Name)
	}
	return sortedImages(names), nil
}

func rarPageReader(path, target string) (io.ReadCloser, string, error) {
	r, err := rardecode.OpenReader(path)
	if err != nil {
		return nil, "", err
	}
	for {
		hdr, err := r.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			r.Close()
			return nil, "", err
		}
		if hdr.Name == target {
			return &multiCloser{io.NopCloser(r), r}, mimeFromExt(target), nil
		}
	}
	r.Close()
	return nil, "", fmt.Errorf("page %s not found in RAR", target)
}

// --- 7-zip (CB7) ---

func sevenzipPages(path string) ([]string, error) {
	r, err := sevenzip.OpenReader(path)
	if err != nil {
		return nil, err
	}
	defer r.Close()

	names := make([]string, 0, len(r.File))
	for _, f := range r.File {
		names = append(names, f.Name)
	}
	return sortedImages(names), nil
}

func sevenzipPageReader(path, target string) (io.ReadCloser, string, error) {
	r, err := sevenzip.OpenReader(path)
	if err != nil {
		return nil, "", err
	}
	for _, f := range r.File {
		if f.Name == target {
			rc, err := f.Open()
			if err != nil {
				r.Close()
				return nil, "", err
			}
			return &multiCloser{rc, r}, mimeFromExt(target), nil
		}
	}
	r.Close()
	return nil, "", fmt.Errorf("page %s not found in 7z", target)
}

func mimeFromExt(name string) string {
	switch strings.ToLower(filepath.Ext(name)) {
	case ".png":
		return "image/png"
	case ".webp":
		return "image/webp"
	case ".gif":
		return "image/gif"
	case ".avif":
		return "image/avif"
	default:
		return "image/jpeg"
	}
}

type multiCloser struct {
	io.ReadCloser
	extra io.Closer
}

func (m *multiCloser) Close() error {
	err1 := m.ReadCloser.Close()
	err2 := m.extra.Close()
	if err1 != nil {
		return err1
	}
	return err2
}

// ImageDimensions decodes just the image header to get width/height without
// loading the full image into memory.
func ImageDimensions(r io.Reader) (int, int, error) {
	cfg, _, err := image.DecodeConfig(r)
	if err != nil {
		return 0, 0, err
	}
	return cfg.Width, cfg.Height, nil
}
