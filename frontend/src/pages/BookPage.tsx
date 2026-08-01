import { useEffect, useState } from 'react'
import { useParams, Link, useNavigate } from 'react-router-dom'
import { books as booksApi } from '@/api/client'
import { thumbnailSize } from '@/lib/thumbnail'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { ChevronLeft, BookOpen, FileText, Globe, Layers } from 'lucide-react'
import type { Book } from '@/types'

const FORMAT_LABELS: Record<string, string> = {
  cbz: 'CBZ', cbr: 'CBR', cb7: 'CB7', epub: 'EPUB', pdf: 'PDF',
}

const AGE_RATING_LABELS: Record<string, string> = {
  unknown: 'N/A',
  everyone: 'Everyone',
  teen: 'Teen',
  mature: 'Mature',
  explicit: 'Explicit',
}

function formatFileSize(bytes: number): string {
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function MetaField({ label, value }: { label: string; value?: string }) {
  return (
    <div>
      <p className="text-[11px] uppercase tracking-wider text-muted-foreground font-semibold mb-1">
        {label}
      </p>
      <p className="text-sm text-foreground">{value ?? '—'}</p>
    </div>
  )
}

export default function BookPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [book, setBook] = useState<Book | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!id) return
    booksApi.get(id)
      .then(setBook)
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [id])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="w-7 h-7 rounded-full border-2 border-volt-2 border-t-transparent animate-spin" />
      </div>
    )
  }

  if (!book) {
    return (
      <div className="flex flex-col items-center justify-center h-64 gap-3 text-center px-6">
        <p className="text-sm text-muted-foreground">Book not found.</p>
        <Button variant="ghost" onClick={() => navigate(-1)}>Go back</Button>
      </div>
    )
  }

  const progress = book.current_page != null && book.page_count > 0
    ? Math.min(100, Math.round((book.current_page / book.page_count) * 100))
    : 0
  const readLabel = progress > 0 ? 'Continue' : 'Read'
  const typeLabel = book.type === 'issue'
    ? book.issue_number ? `Issue #${book.issue_number}` : 'Issue'
    : 'Standalone'

  return (
    <div className="min-h-full">
      <div className="px-6 pt-6 pb-8">
        <button
          onClick={() => navigate(-1)}
          className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition-colors mb-6"
        >
          <ChevronLeft className="w-3.5 h-3.5" />
          Back
        </button>

        <div className="flex gap-6 mb-8">
          {/* Cover */}
          <div className="shrink-0 w-36 sm:w-44">
            <div className="relative aspect-[2/3] rounded-lg overflow-hidden border border-border bg-muted shadow-xl">
              <img
                src={booksApi.coverUrl(book.id, thumbnailSize(180))}
                alt={book.title}
                className="w-full h-full object-cover"
                onError={(e) => {
                  const img = e.target as HTMLImageElement
                  img.style.display = 'none'
                  const fb = img.nextElementSibling as HTMLElement | null
                  if (fb) fb.style.display = 'flex'
                }}
              />
              <div
                className="absolute inset-0 flex items-center justify-center"
                style={{ display: 'none' }}
              >
                <Layers className="w-10 h-10 text-muted-foreground/40" />
              </div>
              {progress > 0 && (
                <div className="absolute bottom-0 left-0 right-0 h-1 bg-black/40">
                  <div className="h-full bg-volt-2" style={{ width: `${progress}%` }} />
                </div>
              )}
            </div>
          </div>

          {/* Metadata */}
          <div className="flex-1 min-w-0 py-1">
            {book.series_id && book.series && (
              <Link
                to={`/series/${book.series_id}`}
                className="text-sm text-volt-3 hover:text-volt-2 transition-colors font-medium mb-1 block"
              >
                {book.series}
              </Link>
            )}

            <h1 className="font-display font-bold text-2xl sm:text-3xl text-foreground tracking-tight leading-tight mb-2">
              {book.title}
            </h1>

            <p className="text-sm text-muted-foreground mb-4">{typeLabel}</p>

            {/* Stats row */}
            <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 mb-4 text-sm text-muted-foreground">
              <span className="flex items-center gap-1">
                <BookOpen className="w-3.5 h-3.5" />
                {book.page_count.toLocaleString()} pages
              </span>
              <span className="flex items-center gap-1">
                <FileText className="w-3.5 h-3.5" />
                {FORMAT_LABELS[book.format] ?? book.format.toUpperCase()}
              </span>
              {book.language && (
                <span className="flex items-center gap-1">
                  <Globe className="w-3.5 h-3.5" />
                  {book.language}
                </span>
              )}
            </div>

            {/* Age rating badge */}
            <div className="mb-5">
              <Badge variant="aqua" className="text-xs">
                {AGE_RATING_LABELS[book.age_rating] ?? book.age_rating}
              </Badge>
            </div>

            {/* Actions */}
            <div className="flex items-center gap-2 mb-6">
              <Link to={`/read/${book.id}`}>
                <Button className="gap-1.5">
                  <BookOpen className="w-4 h-4" />
                  {readLabel}
                </Button>
              </Link>
            </div>

            {/* Summary */}
            {book.summary && (
              <p className="text-sm text-muted-foreground leading-relaxed mb-6 max-w-prose">
                {book.summary}
              </p>
            )}

            {/* Metadata grid */}
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-x-8 gap-y-4">
              <MetaField label="Publisher" value={book.publisher} />
              <MetaField label="Year" value={book.year?.toString()} />
              <MetaField label="Age Rating" value={AGE_RATING_LABELS[book.age_rating]} />
              <MetaField label="Format" value={FORMAT_LABELS[book.format] ?? book.format} />
              <MetaField label="File Size" value={book.file_size > 0 ? formatFileSize(book.file_size) : undefined} />
              {book.language && <MetaField label="Language" value={book.language} />}
              {book.path && <MetaField label="File Path" value={book.path} />}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
