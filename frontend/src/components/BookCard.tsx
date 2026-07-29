import { Link } from 'react-router-dom'
import { books as booksApi } from '@/api/client'
import { cn } from '@/lib/utils'

interface BookLike {
  id: string
  title: string
  type?: string
  series?: string
  series_id?: string
  issue_number?: string
  year?: number
  format: string
  page_count: number
  age_rating: string
  current_page?: number
}

interface BookCardProps {
  book: BookLike
  className?: string
  to?: string
}

const FORMAT_LABELS: Record<string, string> = {
  cbz: 'CBZ', cbr: 'CBR', cb7: 'CB7', epub: 'EPUB', pdf: 'PDF',
}

export function BookCard({ book, className, to }: BookCardProps) {
  const href = to ?? (book.series_id ? `/series/${book.series_id}` : `/book/${book.id}`)
  return (
    <Link to={href} className={cn('group block', className)}>
      <div className="card-hover rounded-lg overflow-hidden border border-border bg-card">
        {/* Cover */}
        <div className="relative aspect-[2/3] overflow-hidden bg-muted">
          <img
            src={booksApi.coverUrl(book.id)}
            alt={book.title}
            className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
            loading="lazy"
            onError={(e) => {
              const img = e.target as HTMLImageElement
              img.style.display = 'none'
              const fb = img.nextElementSibling as HTMLElement | null
              if (fb) fb.style.display = 'flex'
            }}
          />
          {/* Fallback */}
          <div
            className="absolute inset-0 flex-col items-center justify-center gap-1.5 bg-muted"
            style={{ display: 'none' }}
          >
            <div className="w-10 h-10 rounded-lg bg-volt/15 border border-volt/25 flex items-center justify-center">
              <span className="text-volt-3 text-[10px] font-mono font-bold">
                {FORMAT_LABELS[book.format] ?? book.format.toUpperCase()}
              </span>
            </div>
            <span className="text-[10px] text-muted-foreground px-2 text-center leading-tight line-clamp-2">
              {book.series ?? book.title}
            </span>
          </div>
          {/* Format badge — visible on hover */}
          <div className="absolute bottom-1.5 left-1.5 opacity-0 group-hover:opacity-100 transition-opacity duration-200">
            <span className="inline-flex items-center rounded px-1.5 py-0.5 text-[9px] font-semibold uppercase tracking-wider bg-background/80 border border-border text-muted-foreground backdrop-blur-sm">
              {FORMAT_LABELS[book.format] ?? book.format}
            </span>
          </div>
          {/* Purple glow on hover */}
          <div className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-300 bg-gradient-to-t from-volt/12 to-transparent pointer-events-none" />
          {/* Reading progress bar */}
          {book.current_page != null && book.current_page > 0 && book.page_count > 0 && (
            <div className="absolute bottom-0 left-0 right-0 h-1 bg-black/40">
              <div
                className="h-full bg-volt-2"
                style={{ width: `${Math.min(100, Math.round((book.current_page / book.page_count) * 100))}%` }}
              />
            </div>
          )}
        </div>

        {/* Info */}
        <div className="p-2">
          <p className="text-[13px] font-semibold text-card-foreground leading-tight line-clamp-2">
            {book.title ?? book.series}
          </p>
          {book.issue_number && (
            <p className="text-[11px] text-muted-foreground mt-0.5">#{book.issue_number}</p>
          )}
          {!book.series && book.year && (
            <p className="text-[11px] text-muted-foreground mt-0.5">{book.year}</p>
          )}
        </div>
      </div>
    </Link>
  )
}
