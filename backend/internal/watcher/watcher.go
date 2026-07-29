package watcher

import (
	"context"
	"log"
	"path/filepath"
	"strings"
	"time"

	"github.com/fsnotify/fsnotify"
	"github.com/aroy/stashix/internal/library"
)

type Watcher struct {
	fw      *fsnotify.Watcher
	scanner *library.Scanner
}

func New(scanner *library.Scanner) (*Watcher, error) {
	fw, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, err
	}
	return &Watcher{fw: fw, scanner: scanner}, nil
}

func (w *Watcher) Add(libraryID, path string) error {
	return w.fw.Add(path)
}

func (w *Watcher) Remove(path string) error {
	return w.fw.Remove(path)
}

func (w *Watcher) Close() error {
	return w.fw.Close()
}

// Run processes fsnotify events. libraryMap maps root path → libraryID.
func (w *Watcher) Run(ctx context.Context, libraryMap map[string]string) {
	// debounce: collect events and flush after quiet period
	pending := make(map[string]string) // path → libraryID
	timer := time.NewTimer(0)
	if !timer.Stop() {
		<-timer.C
	}

	flush := func() {
		for path, libID := range pending {
			go w.scanner.Scan(ctx, libID, filepath.Dir(path), false)
		}
		pending = make(map[string]string)
	}

	for {
		select {
		case <-ctx.Done():
			return
		case event, ok := <-w.fw.Events:
			if !ok {
				return
			}
			if event.Op&(fsnotify.Create|fsnotify.Write) == 0 {
				continue
			}
			if !isSupportedFile(event.Name) {
				continue
			}
			libID := resolveLibrary(event.Name, libraryMap)
			if libID == "" {
				continue
			}
			pending[event.Name] = libID
			timer.Reset(5 * time.Second)
		case err, ok := <-w.fw.Errors:
			if !ok {
				return
			}
			log.Printf("watcher error: %v", err)
		case <-timer.C:
			flush()
		}
	}
}

func isSupportedFile(path string) bool {
	ext := strings.ToLower(filepath.Ext(path))
	switch ext {
	case ".cbz", ".cbr", ".cb7", ".epub", ".pdf":
		return true
	}
	return false
}

func resolveLibrary(path string, libraryMap map[string]string) string {
	for root, id := range libraryMap {
		if strings.HasPrefix(path, root) {
			return id
		}
	}
	return ""
}
