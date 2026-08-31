'use client'

import { useParams, useRouter } from 'next/navigation'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import { books as booksApi } from '@/api/client'
import { queryKeys } from '@/lib/query-keys'
import { thumbnailSize } from '@/lib/thumbnail'
import { Button } from '@/components/ui/button'
import { ChevronLeft, BookOpen, FileText, Globe, Layers } from 'lucide-react'

const FORMAT_LABELS: Record<string, string> = {
  cbz: 'CBZ', cbr: 'CBR', cb7: 'CB7', epub: 'EPUB', pdf: 'PDF',
}

const AGE_RATING_LABELS: Record<string, string> = {
  unknown: 'N/A',
  everyone: 'Everyone',
  teen: 'Teen',
  teen_plus: 'Teen+',
  mature: 'Mature',
  explicit: 'Explicit',
  adult: 'Adult',
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
  const params = useParams<{ id: string }>()
  const id = params?.id ?? ''
  const router = useRouter()

  const { data: book, isLoading } = useQuery({
    queryKey: queryKeys.book(id),
    queryFn: () => booksApi.get(id),
    enabled: !!id,
  })

  if (isLoading) {
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
        <Button variant="ghost" onClick={() => router.back()}>Go back</Button>
      </div>
    )
  }

  const progress = book.current_page != null && book.page_count > 0
    ? Math.min(100, Math.round((book.current_page / book.page_count) * 100))
    : 0
  const readLabel = progress > 0 ? 'Continue' : 'Read'
  const typeLabel = book.type === 'issue'
    ? [
        book.volume ? `Vol. ${book.volume}` : null,
        book.issue_number ? `Issue #${book.issue_number}` : null,
      ].filter(Boolean).join(' · ') || 'Issue'
    : 'Standalone'

  return (
    <div className="min-h-full">
      <div className="px-6 pt-6 pb-8">
        <button
          onClick={() => router.back()}
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
                href={`/series/${book.series_id}`}
                className="text-sm text-volt-3 hover:text-volt-2 transition-colors font-medium mb-1 block"
              >
                {book.series}
              </Link>
            )}

            <h1 className="font-display font-bold text-2xl sm:text-3xl text-foreground tracking-tight leading-tight mb-2">
              {book.title}
            </h1>

            <p className="text-sm text-muted-foreground mb-4">{typeLabel}</p>

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

            <div className="flex items-center gap-2 mb-6">
              <Link href={`/read/${book.id}`}>
                <Button className="gap-1.5">
                  <BookOpen className="w-4 h-4" />
                  {readLabel}
                </Button>
              </Link>
            </div>

            {book.summary && (
              <p className="text-sm text-muted-foreground leading-relaxed mb-6 max-w-prose">
                {book.summary}
              </p>
            )}

            <div className="grid grid-cols-2 sm:grid-cols-3 gap-x-8 gap-y-4">
              <MetaField label="Publisher" value={book.publisher} />
              {book.volume != null && <MetaField label="Volume" value={book.volume.toString()} />}
              <MetaField label="Year" value={book.year?.toString()} />
              <MetaField label="Age Rating" value={AGE_RATING_LABELS[book.age_rating]} />
              <MetaField label="Format" value={FORMAT_LABELS[book.format] ?? book.format} />
              <MetaField label="File Size" value={book.file_size > 0 ? formatFileSize(book.file_size) : undefined} />
              {book.language && <MetaField label="Language" value={book.language} />}
              {book.folder_path && (
                <div className="col-span-2 sm:col-span-3">
                  <p className="text-[11px] uppercase tracking-wider text-muted-foreground font-semibold mb-1">
                    Path
                  </p>
                  <p className="text-sm text-foreground flex items-center gap-1.5 font-mono">
                    <FileText className="w-3.5 h-3.5 shrink-0 text-muted-foreground" />
                    <span>{book.folder_path.split('/').map((seg, i, arr) => (
                      <span key={i}>{seg}{i < arr.length - 1 && <><wbr/>/</>}</span>
                    ))}</span>
                  </p>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
