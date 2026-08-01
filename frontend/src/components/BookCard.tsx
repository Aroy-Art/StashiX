import { Link } from 'react-router-dom'
import { books as booksApi } from '@/api/client'
import { cn } from '@/lib/utils'
import { thumbnailSize } from '@/lib/thumbnail'
import { Card, CardContent, CardTitle, CardDescription } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'

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
      <Card className="card-hover p-0 gap-0">
        {/* Cover */}
        <div className="relative aspect-[2/3] overflow-hidden bg-muted">
          <img
            src={booksApi.coverUrl(book.id, thumbnailSize(160))}
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
            <Badge variant="outline" className="text-[9px] bg-background/80 backdrop-blur-sm">
              {FORMAT_LABELS[book.format] ?? book.format}
            </Badge>
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
        <CardContent className="p-2">
          <CardTitle className="text-[13px] font-semibold leading-tight line-clamp-2">
            {book.title ?? book.series}
          </CardTitle>
          {book.issue_number && (
            <CardDescription className="mt-0.5">#{book.issue_number}</CardDescription>
          )}
          {!book.series && book.year && (
            <CardDescription className="mt-0.5">{book.year}</CardDescription>
          )}
        </CardContent>
      </Card>
    </Link>
  )
}
