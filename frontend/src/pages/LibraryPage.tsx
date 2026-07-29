import { useEffect, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { books as booksApi, libraries as librariesApi } from '@/api/client'
import { transport } from '@/api/transport'
import { BookCard } from '@/components/BookCard'
import { Badge } from '@/components/ui/badge'
import { ChevronLeft } from 'lucide-react'
import type { Book, Library } from '@/types'

export default function LibraryPage() {
  const { id } = useParams<{ id: string }>()
  const [library, setLibrary] = useState<Library | null>(null)
  const [bookList, setBookList] = useState<Book[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(false)

  useEffect(() => {
    if (!id) return

    Promise.all([
      librariesApi.list().then((libs) => libs?.find((l) => l.id === id) ?? null),
      booksApi.listByLibrary(id),
    ])
      .then(([lib, books]) => {
        setLibrary(lib)
        setBookList(books)
      })
      .catch(() => setError(true))
      .finally(() => setLoading(false))

    const off = transport.on('book_added', (payload) => {
      const p = payload as { book_id: string; library_id: string }
      if (p.library_id !== id) return
      booksApi.get(p.book_id).then((book) => {
        setBookList((prev) => [book, ...prev])
      })
    })
    return off
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
      <div className="flex items-end gap-4 mb-8">
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
            >
              <BookCard book={book} />
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
