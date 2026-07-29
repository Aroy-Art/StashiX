import { Link } from 'react-router-dom'
import { series as seriesApi } from '@/api/client'
import { cn } from '@/lib/utils'
import { formatYears } from '@/lib/series'
import { Card, CardContent, CardTitle, CardDescription } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Layers } from 'lucide-react'
import type { Series } from '@/types'

interface SeriesCardProps {
  series: Series
  className?: string
}

export function SeriesCard({ series, className }: SeriesCardProps) {
  return (
    <Link to={`/series/${series.id}`} className={cn('group block', className)}>
      <Card className="card-hover p-0 gap-0">
        <div className="relative aspect-[2/3] overflow-hidden bg-muted">
          <img
            src={seriesApi.coverUrl(series.id)}
            alt={series.name}
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
              <Layers className="w-5 h-5 text-volt-3" />
            </div>
            <span className="text-[10px] text-muted-foreground px-2 text-center leading-tight line-clamp-2">
              {series.name}
            </span>
          </div>
          {/* Issue count badge */}
          {series.book_count != null && series.book_count > 0 && (
            <div className="absolute bottom-1.5 left-1.5">
              <Badge variant="aqua" className="text-[9px] backdrop-blur-sm">
                {series.book_count} {series.book_count === 1 ? 'issue' : 'issues'}
              </Badge>
            </div>
          )}
          <div className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-300 bg-gradient-to-t from-volt/12 to-transparent pointer-events-none" />
        </div>

        <CardContent className="p-2">
          <CardTitle className="text-[13px] font-semibold leading-tight line-clamp-2">
            {series.name}
          </CardTitle>
          {series.publisher && (
            <CardDescription className="mt-0.5">{series.publisher}</CardDescription>
          )}
          {series.start_year && (
            <CardDescription className="mt-0.5 opacity-70">
              {formatYears(series.start_year, series.end_year, series.ongoing)}
            </CardDescription>
          )}
        </CardContent>
      </Card>
    </Link>
  )
}
