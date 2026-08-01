import { useEffect, useRef, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { books as booksApi, libraries as librariesApi } from '@/api/client'
import { transport } from '@/api/transport'
import { BookCard } from '@/components/BookCard'
import { Badge } from '@/components/ui/badge'
import { ChevronLeft, Trash2 } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { Book, DeletedBook, Library, ScanTask } from '@/types'

export default function LibraryPage() {
  const { id } = useParams<{ id: string }>()
  const [library, setLibrary] = useState<Library | null>(null)
  const [bookList, setBookList] = useState<Book[]>([])
  const [deletedBooks, setDeletedBooks] = useState<DeletedBook[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(false)
  const [scanTask, setScanTask] = useState<ScanTask | null>(null)
  const [newBookIds, setNewBookIds] = useState<Set<string>>(new Set())
  const [removingIds, setRemovingIds] = useState<Set<string>>(new Set())
  const newBookTimers = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map())
  const pendingBookIds = useRef<string[]>([])
  const flushTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const removeDeletedBook = async (bookId: string) => {
    setRemovingIds((prev) => new Set(prev).add(bookId))
    try {
      await booksApi.delete(bookId)
      setDeletedBooks((prev) => prev.filter((b) => b.id !== bookId))
    } finally {
      setRemovingIds((prev) => { const n = new Set(prev); n.delete(bookId); return n })
    }
  }

  useEffect(() => {
    if (!id) return

    Promise.all([
      librariesApi.list().then((libs) => libs?.find((l) => l.id === id) ?? null),
      booksApi.listByLibrary(id),
      booksApi.listDeleted(id),
    ])
      .then(([lib, books, deleted]) => {
        setLibrary(lib)
        setBookList(books)
        setDeletedBooks(deleted)
      })
      .catch(() => setError(true))
      .finally(() => setLoading(false))

    function preloadCover(url: string): Promise<void> {
      return new Promise((resolve) => {
        const img = new Image()
        const t = setTimeout(resolve, 5000)
        img.onload = () => { clearTimeout(t); resolve() }
        img.onerror = () => { clearTimeout(t); resolve() }
        img.src = url
      })
    }

    function scheduleFlush() {
      if (flushTimer.current !== null) return
      flushTimer.current = setTimeout(async () => {
        flushTimer.current = null
        const batch = pendingBookIds.current.splice(0, 5)
        if (batch.length === 0) return
        const books = await Promise.all(batch.map((bid) => booksApi.get(bid)))
        await Promise.all(books.map((b) => preloadCover(booksApi.coverUrl(b.id, 'm'))))
        setBookList((prev) => {
          const existingIds = new Set(prev.map((b) => b.id))
          const fresh = books.filter((b) => !existingIds.has(b.id))
          return fresh.length > 0 ? [...fresh, ...prev] : prev
        })
        setNewBookIds((prev) => {
          const next = new Set(prev)
          for (const book of books) {
            next.add(book.id)
            const timer = setTimeout(() => {
              setNewBookIds((s) => { const n = new Set(s); n.delete(book.id); return n })
              newBookTimers.current.delete(book.id)
            }, 3000)
            newBookTimers.current.set(book.id, timer)
          }
          return next
        })
        if (pendingBookIds.current.length > 0) scheduleFlush()
      }, 800 + Math.random() * 600)
    }

    const offAdded = transport.on('book_added', (payload) => {
      const p = payload as { book_id: string; library_id: string }
      if (p.library_id !== id) return
      pendingBookIds.current.push(p.book_id)
      scheduleFlush()
    })

    const offProgress = transport.on('scan_progress', (payload) => {
      const t = payload as ScanTask
      if (t.library_id !== id) return
      setScanTask(t.done ? null : t)
    })

    return () => {
      offAdded()
      offProgress()
      if (flushTimer.current !== null) clearTimeout(flushTimer.current)
      pendingBookIds.current = []
      for (const timer of newBookTimers.current.values()) clearTimeout(timer)
      newBookTimers.current.clear()
    }
  }, [id])

  return (
    <div className="min-h-full px-6 py-6">
      {/* Breadcrumb */}
      <div className="flex items-center gap-2 mb-6">
        <Link
          to="/"
          className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition-colors"
        >
          <ChevronLeft className="w-3.5 h-3.5" />
          Libraries
        </Link>
        {library && (
          <>
            <span className="text-border">/</span>
            <span className="text-sm font-medium text-foreground">{library.name}</span>
          </>
        )}
      </div>

      {/* Header */}
      <div className="flex items-end gap-4 mb-4">
        <div>
          <h1 className="font-display font-bold text-2xl text-foreground tracking-tight">
            {library?.name ?? 'Library'}
          </h1>
          {library && (
            <p className="text-xs text-muted-foreground mt-1 font-mono">{library.root_path}</p>
          )}
        </div>
        {bookList.length > 0 && (
          <Badge variant="aqua" className="mb-0.5">
            {bookList.length} books
          </Badge>
        )}
      </div>

      {/* Scan progress */}
      {scanTask && (
        <div className="mb-6">
          <div className="flex justify-between text-[11px] text-muted-foreground mb-1">
            <span className="text-volt-3 animate-pulse">Scanning…</span>
            <span className="font-mono">
              {scanTask.scanned} / {scanTask.total}
              {scanTask.total > 0 && (
                <> · {Math.round((scanTask.scanned / scanTask.total) * 100)}%</>
              )}
            </span>
          </div>
          <div className="h-0.5 rounded-full bg-border overflow-hidden">
            <div
              className="h-full rounded-full shimmer-bar transition-all duration-300"
              style={{ width: scanTask.total > 0 ? `${Math.round((scanTask.scanned / scanTask.total) * 100)}%` : '0%' }}
            />
          </div>
        </div>
      )}

      {/* Loading */}
      {loading && (
        <div className="flex items-center justify-center h-48">
          <div className="w-7 h-7 rounded-full border-2 border-volt-2 border-t-transparent animate-spin" />
        </div>
      )}

      {/* Error */}
      {!loading && error && (
        <div className="flex flex-col items-center justify-center h-48 gap-3 text-center">
          <p className="text-sm text-muted-foreground">Failed to load library.</p>
        </div>
      )}

      {/* Empty */}
      {!loading && !error && bookList.length === 0 && (
        <div className="flex flex-col items-center justify-center h-48 gap-3 text-center">
          <div className="w-12 h-12 rounded-xl bg-muted border border-border flex items-center justify-center">
            <span className="text-2xl">📚</span>
          </div>
          <p className="text-sm text-muted-foreground">No books scanned yet. Trigger a scan from the home page.</p>
        </div>
      )}

      {/* Grid */}
      {!loading && !error && bookList.length > 0 && (
        <div className="grid grid-cols-[repeat(auto-fill,minmax(130px,1fr))] gap-4">
          {bookList.map((book, i) => (
            <div
              key={book.id}
              style={{ animationDelay: `${Math.min(i * 30, 300)}ms` }}
              className={cn(newBookIds.has(book.id) && 'animate-book-arrive')}
            >
              <BookCard book={book} />
            </div>
          ))}
        </div>
      )}

      {/* Deleted books */}
      {!loading && !error && deletedBooks.length > 0 && (
        <div className="mt-10">
          <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide mb-3">
            Deleted from disk
            <Badge variant="outline" className="ml-2 text-xs">{deletedBooks.length}</Badge>
          </h2>
          <div className="flex flex-col gap-1">
            {deletedBooks.map((book) => (
              <div
                key={book.id}
                className="flex items-center justify-between gap-3 px-3 py-2 rounded-md bg-muted/40 border border-border/50"
              >
                <div className="min-w-0">
                  <p className="text-sm font-medium text-foreground truncate">{book.title}</p>
                  <p className="text-xs text-muted-foreground font-mono truncate">{book.path}</p>
                </div>
                <button
                  onClick={() => removeDeletedBook(book.id)}
                  disabled={removingIds.has(book.id)}
                  className="shrink-0 p-1.5 rounded hover:bg-destructive/10 hover:text-destructive text-muted-foreground transition-colors disabled:opacity-40"
                  title="Remove from library"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
