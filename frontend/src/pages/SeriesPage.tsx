import { useEffect, useState } from 'react'
import { useParams, Link, useNavigate } from 'react-router-dom'
import { series as seriesApi, books as booksApi } from '@/api/client'
import { BookCard } from '@/components/BookCard'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { ChevronLeft, BookOpen, Layers, Hash } from 'lucide-react'
import { cn } from '@/lib/utils'
import { formatYears } from '@/lib/series'
import type { SeriesDetail } from '@/types'

export default function SeriesPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [data, setData] = useState<SeriesDetail | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!id) return
    seriesApi.get(id)
      .then(setData)
      .finally(() => setLoading(false))
  }, [id])

  const firstBook = data?.books[0]
  const continueBook = data?.books.find(
    (b) => b.current_page != null && b.current_page > 0 && b.current_page < b.page_count
  )
  const readBook = continueBook ?? firstBook
  const readLabel = continueBook ? 'Continue' : 'Read First Issue'

  const totalPages = data?.books.reduce((sum, b) => sum + b.page_count, 0) ?? 0
  const yearRange = formatYears(data?.start_year, data?.end_year, data?.ongoing)
  const readCount = data?.books.filter(
    (b) => b.current_page != null && b.page_count > 0 && b.current_page >= b.page_count
  ).length ?? 0

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="w-7 h-7 rounded-full border-2 border-volt-2 border-t-transparent animate-spin" />
      </div>
    )
  }

  if (!data) {
    return (
      <div className="flex flex-col items-center justify-center h-64 gap-3 text-center px-6">
        <p className="text-sm text-muted-foreground">Series not found.</p>
        <Button variant="ghost" onClick={() => navigate(-1)}>Go back</Button>
      </div>
    )
  }

  return (
    <div className="min-h-full">
      {/* Hero section */}
      <div className="px-6 pt-6 pb-0">
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
              {firstBook ? (
                <img
                  src={booksApi.coverUrl(firstBook.id)}
                  alt={data.name}
                  className="w-full h-full object-cover"
                  onError={(e) => {
                    const img = e.target as HTMLImageElement
                    img.style.display = 'none'
                    const fb = img.nextElementSibling as HTMLElement | null
                    if (fb) fb.style.display = 'flex'
                  }}
                />
              ) : null}
              <div
                className="absolute inset-0 flex items-center justify-center"
                style={{ display: firstBook ? 'none' : 'flex' }}
              >
                <Layers className="w-10 h-10 text-muted-foreground/40" />
              </div>
            </div>
          </div>

          {/* Metadata */}
          <div className="flex-1 min-w-0 py-1">
            <h1 className="font-display font-bold text-2xl sm:text-3xl text-foreground tracking-tight leading-tight mb-3">
              {data.name}
            </h1>

            {/* Pills row */}
            <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5 mb-5 text-sm text-muted-foreground">
              {data.publisher && (
                <span className="font-semibold text-foreground/90">{data.publisher}</span>
              )}
              {yearRange && <span>{yearRange}</span>}
              {totalPages > 0 && (
                <span className="flex items-center gap-1">
                  <BookOpen className="w-3.5 h-3.5" />
                  {totalPages.toLocaleString()} pages
                </span>
              )}
              <span className="flex items-center gap-1">
                <Hash className="w-3.5 h-3.5" />
                {data.books.length} {data.books.length === 1 ? 'issue' : 'issues'}
              </span>
              {readCount > 0 && (
                <Badge variant="outline" className="text-[11px] text-volt-3 border-volt/30">
                  {readCount}/{data.books.length} read
                </Badge>
              )}
            </div>

            {/* Actions */}
            <div className="flex items-center gap-2 mb-6">
              {readBook && (
                <Link to={`/read/${readBook.id}`}>
                  <Button className="gap-1.5">
                    <BookOpen className="w-4 h-4" />
                    {readLabel}
                  </Button>
                </Link>
              )}
            </div>

            {/* Metadata grid */}
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-x-8 gap-y-4">
              <div>
                <p className="text-[11px] uppercase tracking-wider text-muted-foreground font-semibold mb-1">
                  Publisher
                </p>
                <p className="text-sm text-foreground">{data.publisher ?? '—'}</p>
              </div>
              <div>
                <p className="text-[11px] uppercase tracking-wider text-muted-foreground font-semibold mb-1">
                  Issues
                </p>
                <p className="text-sm text-foreground">{data.books.length}</p>
              </div>
              {yearRange && (
                <div>
                  <p className="text-[11px] uppercase tracking-wider text-muted-foreground font-semibold mb-1">
                    Years
                  </p>
                  <p className="text-sm text-foreground">{yearRange}</p>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Tab bar */}
        <div className="flex gap-1 border-b border-border">
          <div
            className={cn(
              'px-4 py-2 text-sm font-medium border-b-2 -mb-px border-volt-2 text-foreground'
            )}
          >
            Issues
            <Badge variant="outline" className="ml-1.5 text-[10px] px-1.5 py-0">
              {data.books.length}
            </Badge>
          </div>
        </div>
      </div>

      {/* Issues grid */}
      <div className="px-6 py-6">
        {data.books.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-48 gap-3 text-center">
            <p className="text-sm text-muted-foreground">No issues found.</p>
          </div>
        ) : (
          <div className="grid grid-cols-[repeat(auto-fill,minmax(130px,1fr))] gap-4">
            {data.books.map((book, i) => (
              <div
                key={book.id}
                style={{ animationDelay: `${Math.min(i * 30, 300)}ms` }}
              >
                <BookCard book={book} to={`/issue/${book.id}`} />
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
