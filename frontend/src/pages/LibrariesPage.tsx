import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { libraries as librariesApi, tasks as tasksApi, books as booksApi, series as seriesApi } from '@/api/client'
import { thumbnailSize } from '@/lib/thumbnail'
import { transport } from '@/api/transport'
import { useAuthStore } from '@/store/auth'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { SectionCarousel } from '@/components/SectionCarousel'
import { BookCard } from '@/components/BookCard'
import { SeriesCard } from '@/components/SeriesCard'
import { ScanLine, Library, FolderPlus, RefreshCw, RotateCcw } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { Library as LibraryType, ScanTask, Book, Series } from '@/types'

interface LibraryWithContent extends LibraryType {
  recentBooks: Book[]
  recentSeries: Series[]
  recentIssues: Book[]
  previewBooks: Book[]
  loading: boolean
}

export default function LibrariesPage() {
  const [libs, setLibs] = useState<LibraryWithContent[]>([])
  const [loading, setLoading] = useState(true)
  const [activeTasks, setActiveTasks] = useState<Record<string, ScanTask>>({})
  const [scanning, setScanning] = useState<Set<string>>(new Set())
  const isAdmin = useAuthStore((s) => s.isAdmin)

  useEffect(() => {
    async function init() {
      try {
        const [libsData, tasksData] = await Promise.all([
          librariesApi.list(),
          tasksApi.list().catch(() => [] as ScanTask[]),
        ])

        const taskMap: Record<string, ScanTask> = {}
        for (const t of tasksData) taskMap[t.library_id] = t
        setActiveTasks(taskMap)

        const withPlaceholders = (libsData ?? []).map((l) => ({
          ...l,
          recentBooks: [],
          recentSeries: [],
          recentIssues: [],
          previewBooks: [],
          loading: true,
        }))
        setLibs(withPlaceholders)
        setLoading(false)

        for (const lib of withPlaceholders) {
          Promise.all([
            booksApi.listByLibrary(lib.id, 0, 20, { sort: 'recent', type: 'standalone' }),
            seriesApi.listByLibrary(lib.id),
            booksApi.listByLibrary(lib.id, 0, 20, { sort: 'recent', type: 'issues' }),
            booksApi.listByLibrary(lib.id, 0, 5, { sort: 'recent' }),
          ])
            .then(([recentBooks, recentSeries, recentIssues, previewBooks]) => {
              setLibs((prev) =>
                prev.map((l) =>
                  l.id === lib.id
                    ? { ...l, recentBooks, recentSeries, recentIssues, previewBooks, loading: false }
                    : l
                )
              )
            })
            .catch(() => {
              setLibs((prev) =>
                prev.map((l) => (l.id === lib.id ? { ...l, loading: false } : l))
              )
            })
        }
      } catch {
        setLoading(false)
      }
    }
    init()
  }, [])

  useEffect(() => {
    return transport.on('scan_progress', (payload) => {
      const t = payload as ScanTask
      setActiveTasks((prev) => {
        if (t.done) {
          const next = { ...prev }
          delete next[t.library_id]
          return next
        }
        return { ...prev, [t.library_id]: t }
      })
    })
  }, [])

  const handleScan = async (libId: string, force = false) => {
    setScanning((s) => new Set(s).add(libId))
    try {
      await librariesApi.scan(libId, force)
    } catch {
      // progress via WS
    } finally {
      setScanning((s) => {
        const next = new Set(s)
        next.delete(libId)
        return next
      })
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 rounded-full border-2 border-volt-2 border-t-transparent animate-spin" />
          <p className="text-sm text-muted-foreground">Loading libraries…</p>
        </div>
      </div>
    )
  }

  if (libs.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-64 gap-4 px-6 text-center">
        <div className="w-16 h-16 rounded-2xl bg-volt/10 border border-volt/20 flex items-center justify-center glow-volt">
          <Library className="w-8 h-8 text-volt-3" />
        </div>
        <div>
          <h2 className="font-display font-bold text-xl text-foreground mb-1">No libraries yet</h2>
          <p className="text-sm text-muted-foreground">Add a library to start scanning your collection.</p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-full">
      {/* Library cards grid */}
      <div className="px-6 pt-6 pb-2">
        <div className="flex items-center gap-2.5 mb-5">
          <div className="w-1.5 h-5 rounded-full bg-volt-2 shadow-[0_0_8px_rgba(139,92,246,0.6)]" />
          <h2 className="font-display font-bold text-lg text-foreground tracking-tight">Libraries</h2>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-4">
          {libs.map((lib) => {
            const task = activeTasks[lib.id]
            const isScanning = !!task || scanning.has(lib.id)
            const pct = task && task.total > 0
              ? Math.round((task.scanned / task.total) * 100)
              : null

            return (
              <div
                key={lib.id}
                className="relative group rounded-xl bg-card border border-border hover:border-ring/50 transition-all duration-200 overflow-hidden"
              >
                {lib.previewBooks.length > 0 && (
                  <div className="relative flex h-20 overflow-hidden border-b border-border">
                    {lib.previewBooks.slice(0, 5).map((book) => (
                      <img
                        key={book.id}
                        src={booksApi.coverUrl(book.id, thumbnailSize(55))}
                        alt=""
                        className="flex-1 min-w-0 object-cover"
                        loading="lazy"
                        onError={(e) => {
                          ;(e.target as HTMLImageElement).style.display = 'none'
                        }}
                      />
                    ))}
                    <div className="absolute inset-0 bg-gradient-to-b from-transparent via-transparent to-card pointer-events-none" />
                  </div>
                )}

                <div className="p-4">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                      <h3 className="font-display font-bold text-base text-foreground truncate">
                        {lib.name}
                      </h3>
                      <p className="text-xs text-muted-foreground truncate mt-0.5">{lib.root_path}</p>
                    </div>
                    <div className="flex items-center gap-1.5 shrink-0">
                      {(lib.book_count ?? 0) > 0 && (
                        <Badge variant="aqua" className="text-[10px]">
                          {lib.book_count} {lib.book_count === 1 ? 'book' : 'books'}
                        </Badge>
                      )}
                      {(lib.issue_count ?? 0) > 0 && (
                        <Badge variant="plasma" className="text-[10px]">
                          {lib.issue_count} {lib.issue_count === 1 ? 'issue' : 'issues'}
                        </Badge>
                      )}
                      {(lib.series_count ?? 0) > 0 && (
                        <Badge variant="default" className="text-[10px]">
                          {lib.series_count} {lib.series_count === 1 ? 'series' : 'series'}
                        </Badge>
                      )}
                      {isAdmin && (
                        <>
                          <Button
                            variant="ghost"
                            size="icon-sm"
                            onClick={() => handleScan(lib.id)}
                            disabled={isScanning}
                            aria-label="Scan library"
                            title="Scan for new files"
                            className={cn(isScanning && 'animate-pulse')}
                          >
                            {isScanning ? (
                              <ScanLine className="w-3.5 h-3.5 text-plasma" />
                            ) : (
                              <RefreshCw className="w-3.5 h-3.5" />
                            )}
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon-sm"
                            onClick={() => handleScan(lib.id, true)}
                            disabled={isScanning}
                            aria-label="Force rescan library"
                            title="Force rescan (re-imports all files)"
                          >
                            <RotateCcw className="w-3.5 h-3.5" />
                          </Button>
                        </>
                      )}
                    </div>
                  </div>

                  {pct !== null && (
                    <div className="mt-3">
                      <div className="flex justify-between text-[11px] text-muted-foreground mb-1">
                        <span>Scanning…</span>
                        <span className="text-volt-3 font-mono">{pct}%</span>
                      </div>
                      <div className="h-1 rounded-full bg-border overflow-hidden">
                        <div
                          className="h-full rounded-full shimmer-bar transition-all duration-300"
                          style={{ width: `${pct}%` }}
                        />
                      </div>
                    </div>
                  )}

                  <Link
                    to={`/library/${lib.id}`}
                    className="mt-3 flex items-center gap-1.5 text-xs text-volt-3 hover:text-volt-4 transition-colors group/link"
                  >
                    <span>Browse collection</span>
                    <FolderPlus className="w-3 h-3 transition-transform group-hover/link:translate-x-0.5" />
                  </Link>
                </div>
              </div>
            )
          })}
        </div>
      </div>

      {/* Per-library carousels */}
      {libs.map((lib) => (
        <div key={lib.id}>
          {/* Recent Books */}
          <SectionCarousel
            title={`${lib.name} — Recent Books`}
            accentColor="volt"
            isEmpty={!lib.loading && lib.recentBooks.length === 0}
          >
            {lib.recentBooks.map((book) => (
              <div key={book.id} className="shrink-0 w-[140px]">
                <BookCard book={book} />
              </div>
            ))}
          </SectionCarousel>

          {/* Recent Series */}
          {(lib.loading || lib.recentSeries.length > 0) && (
            <SectionCarousel
              title={`${lib.name} — Recent Series`}
              accentColor="plasma"
              isEmpty={!lib.loading && lib.recentSeries.length === 0}
            >
              {lib.recentSeries.map((s) => (
                <div key={s.id} className="shrink-0 w-[140px]">
                  <SeriesCard series={s} />
                </div>
              ))}
            </SectionCarousel>
          )}

          {/* Recent Issues */}
          {(lib.loading || lib.recentIssues.length > 0) && (
            <SectionCarousel
              title={`${lib.name} — Recent Issues`}
              accentColor="volt"
              isEmpty={!lib.loading && lib.recentIssues.length === 0}
            >
              {lib.recentIssues.map((book) => (
                <div key={book.id} className="shrink-0 w-[140px]">
                  <BookCard book={book} to={`/issue/${book.id}`} />
                </div>
              ))}
            </SectionCarousel>
          )}
        </div>
      ))}
    </div>
  )
}
