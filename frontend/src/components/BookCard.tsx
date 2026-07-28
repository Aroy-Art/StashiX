import { Link } from 'react-router-dom'
import { books as booksApi } from '@/api/client'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import type { Book, SearchResult } from '@/types'

type BookLike = Book | SearchResult

interface BookCardProps {
  book: BookLike
  className?: string
}

const FORMAT_LABELS: Record<string, string> = {
  cbz: 'CBZ',
  cbr: 'CBR',
  cb7: 'CB7',
  epub: 'EPUB',
  pdf: 'PDF',
}

export function BookCard({ book, className }: BookCardProps) {
  return (
    <Link to={`/read/${book.id}`} className={cn('group block', className)}>
      <div className="card-hover rounded-lg overflow-hidden border border-rim bg-surface-1">
        {/* Cover */}
        <div className="relative aspect-[2/3] overflow-hidden bg-surface-2">
          <img
            src={booksApi.coverUrl(book.id)}
            alt={book.title}
            className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
            loading="lazy"
            onError={(e) => {
              const img = e.target as HTMLImageElement
              img.style.display = 'none'
              const fallback = img.nextElementSibling as HTMLElement | null
              if (fallback) fallback.style.display = 'flex'
            }}
          />
          {/* Fallback placeholder */}
          <div
            className="absolute inset-0 flex-col items-center justify-center gap-1.5 bg-surface-2"
            style={{ display: 'none' }}
          >
            <div className="w-10 h-10 rounded-lg bg-volt/15 border border-volt/25 flex items-center justify-center">
              <span className="text-volt-3 text-[10px] font-mono font-bold">
                {FORMAT_LABELS[book.format] ?? book.format.toUpperCase()}
              </span>
            </div>
            <span className="text-[10px] text-muted/60 px-2 text-center leading-tight line-clamp-2">
              {book.series ?? book.title}
            </span>
          </div>
          {/* Format badge overlay (shown on top of real cover only) */}
          <div className="absolute bottom-1.5 left-1.5 opacity-0 group-hover:opacity-100 transition-opacity duration-200">
            <Badge variant="surface" className="text-[9px] bg-void/75 border-rim/50 text-muted/80 backdrop-blur-sm">
              {FORMAT_LABELS[book.format] ?? book.format}
            </Badge>
          </div>
          {/* Purple glow overlay on hover */}
          <div className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-300 bg-gradient-to-t from-volt/15 to-transparent pointer-events-none" />
        </div>

        {/* Info */}
        <div className="p-2">
          <p className="text-[13px] font-semibold text-prose leading-tight line-clamp-2">
            {book.series ?? book.title}
          </p>
          {book.issue_number && (
            <p className="text-[11px] text-muted mt-0.5">#{book.issue_number}</p>
          )}
          {!book.series && book.year && (
            <p className="text-[11px] text-muted mt-0.5">{book.year}</p>
          )}
        </div>
      </div>
    </Link>
  )
}
