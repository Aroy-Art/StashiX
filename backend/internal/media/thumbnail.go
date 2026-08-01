package media

import (
	"image"
	_ "image/gif"
	"image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"os"
	"path/filepath"

	"github.com/gin-gonic/gin"
	"golang.org/x/image/draw"
	_ "golang.org/x/image/webp"
)

var thumbnailWidths = map[string]int{
	"sx": 64,
	"s":  128,
	"m":  256,
	"l":  512,
	"lx": 1024,
}

func IsValidThumbnailSize(s string) bool {
	_, ok := thumbnailWidths[s]
	return ok
}

// ServeThumbnail generates (or serves cached) a resized JPEG from getImage.
// Cache path: cacheDir/entityType/entityID_size.jpg
func ServeThumbnail(c *gin.Context, cacheDir, entityType, entityID, size string, getImage func() (io.ReadCloser, error)) {
	width, ok := thumbnailWidths[size]
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid thumbnail size; valid: sx,s,m,l,lx"})
		return
	}

	cacheFile := filepath.Join(cacheDir, entityType, entityID+"_"+size+".jpg")

	if _, err := os.Stat(cacheFile); err == nil {
		c.Header("Cache-Control", "public, max-age=604800")
		c.File(cacheFile)
		return
	}

	rc, err := getImage()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not read cover"})
		return
	}
	defer rc.Close()

	src, _, err := image.Decode(rc)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not decode image"})
		return
	}

	srcW := src.Bounds().Dx()
	srcH := src.Bounds().Dy()

	if width > srcW {
		width = srcW
	}
	height := width * srcH / srcW
	if height < 1 {
		height = 1
	}

	dst := image.NewRGBA(image.Rect(0, 0, width, height))
	draw.CatmullRom.Scale(dst, dst.Bounds(), src, src.Bounds(), draw.Over, nil)

	if err := os.MkdirAll(filepath.Dir(cacheFile), 0o755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "cache dir error"})
		return
	}

	f, err := os.Create(cacheFile)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "cache write error"})
		return
	}

	if err := jpeg.Encode(f, dst, &jpeg.Options{Quality: 85}); err != nil {
		f.Close()
		os.Remove(cacheFile)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "encode error"})
		return
	}
	f.Close()

	c.Header("Cache-Control", "public, max-age=604800")
	c.File(cacheFile)
}
