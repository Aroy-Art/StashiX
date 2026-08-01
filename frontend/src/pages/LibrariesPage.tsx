import { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { libraries as librariesApi, tasks as tasksApi, books as booksApi, series as seriesApi } from '@/api/client'
import { thumbnailSize } from '@/lib/thumbnail'
import { transport } from '@/api/transport'
import { useAuthStore } from '@/store/auth'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { SectionCarousel } from '@/components/SectionCarousel'
import { BookCard } from '@/components/BookCard'
import { SeriesCard } from '@/components/SeriesCard'
import { ScanLine, Library, FolderPlus, RefreshCw, RotateCcw, Settings, X, Plus, MoreVertical } from 'lucide-react'
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
  const [settingsLib, setSettingsLib] = useState<LibraryWithContent | null>(null)
  const [sfFolders, setSfFolders] = useState<string[]>([])
  const [sfInput, setSfInput] = useState('')
  const [sfSaving, setSfSaving] = useState(false)
  const sfInputRef = useRef<HTMLInputElement>(null)
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
    const offProgress = transport.on('scan_progress', (payload) => {
      const t = payload as ScanTask
      setActiveTasks((prev) => {
        if (t.done) {
          const next = { ...prev }
          delete next[t.library_id]
          return next
        }
        return { ...prev, [t.library_id]: t }
      })
      if (t.done) {
        librariesApi.list().then((updatedLibs) => {
          const updated = updatedLibs?.find((l) => l.id === t.library_id)
          if (updated) {
            setLibs((prev) =>
              prev.map((l) =>
                l.id === updated.id
                  ? { ...l, book_count: updated.book_count, issue_count: updated.issue_count, series_count: updated.series_count }
                  : l
              )
            )
          }
        })
      }
    })

    function preloadCover(url: string): Promise<void> {
      return new Promise((resolve) => {
        const img = new Image()
        const t = setTimeout(resolve, 5000)
        img.onload = () => { clearTimeout(t); resolve() }
        img.onerror = () => { clearTimeout(t); resolve() }
        img.src = url
      })
    }

    const pendingBooks = new Map<string, string[]>() // library_id → book_ids
    let flushTimer: ReturnType<typeof setTimeout> | null = null

    function scheduleFlush() {
      if (flushTimer !== null) return
      flushTimer = setTimeout(async () => {
        flushTimer = null
        const snapshot = new Map(pendingBooks)
        pendingBooks.clear()

        for (const [libraryId, bookIds] of snapshot) {
          const batch = bookIds.splice(0, 5)
          if (batch.length === 0) continue
          const books = await Promise.all(batch.map((bid) => booksApi.get(bid)))
          await Promise.all(books.map((b) => preloadCover(booksApi.coverUrl(b.id, 'm'))))
          setLibs((prev) =>
            prev.map((lib) => {
              if (lib.id !== libraryId) return lib
              let { recentBooks, recentIssues, previewBooks } = lib
              for (const book of books) {
                const isIssue = book.type === 'issue'
                const dedup = <T extends { id: string }>(arr: T[], item: T) =>
                  arr.some((x) => x.id === item.id) ? arr : [item, ...arr]
                recentBooks = isIssue ? recentBooks : dedup(recentBooks, book).slice(0, 20)
                recentIssues = isIssue ? dedup(recentIssues, book).slice(0, 20) : recentIssues
                previewBooks = previewBooks.length < 5 ? dedup(previewBooks, book) : previewBooks
              }
              return { ...lib, recentBooks, recentIssues, previewBooks }
            })
          )
          if (bookIds.length > 0) pendingBooks.set(libraryId, bookIds)
        }
        if (pendingBooks.size > 0) scheduleFlush()
      }, 800 + Math.random() * 600)
    }

    const offAdded = transport.on('book_added', (payload) => {
      const p = payload as { book_id: string; library_id: string }
      const queue = pendingBooks.get(p.library_id) ?? []
      queue.push(p.book_id)
      pendingBooks.set(p.library_id, queue)
      scheduleFlush()
    })

    return () => {
      offProgress()
      offAdded()
      if (flushTimer !== null) clearTimeout(flushTimer)
      pendingBooks.clear()
    }
  }, [])

  const openSettings = (lib: LibraryWithContent) => {
    setSettingsLib(lib)
    setSfFolders(lib.standalone_folders ?? [])
    setSfInput('')
  }

  const addFolder = () => {
    const val = sfInput.trim()
    if (!val || sfFolders.includes(val)) return
    setSfFolders((f) => [...f, val])
    setSfInput('')
    sfInputRef.current?.focus()
  }

  const removeFolder = (folder: string) => {
    setSfFolders((f) => f.filter((x) => x !== folder))
  }

  const handleSaveFolders = async () => {
    if (!settingsLib) return
    setSfSaving(true)
    try {
      await librariesApi.update(settingsLib.id, { standalone_folders: sfFolders })
      setLibs((prev) =>
        prev.map((l) => (l.id === settingsLib.id ? { ...l, standalone_folders: sfFolders } : l))
      )
      setSettingsLib(null)
    } finally {
      setSfSaving(false)
    }
  }

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
                          ; (e.target as HTMLImageElement).style.display = 'none'
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
                    </div>
                    {isAdmin && (
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button
                            variant="ghost"
                            size="icon"
                            aria-label="Library actions"
                            className={cn('-mr-3 -mt-1', isScanning && 'animate-pulse')}
                          >
                            {isScanning
                              ? <ScanLine className="w-4 h-4 text-plasma" />
                              : <MoreVertical className="w-4 h-4" />}
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          <DropdownMenuItem
                            onClick={() => handleScan(lib.id)}
                            disabled={isScanning}
                          >
                            <RefreshCw className="w-3.5 h-3.5 mr-2" />
                            Scan for new files
                          </DropdownMenuItem>
                          <DropdownMenuItem
                            onClick={() => handleScan(lib.id, true)}
                            disabled={isScanning}
                          >
                            <RotateCcw className="w-3.5 h-3.5 mr-2" />
                            Force rescan
                          </DropdownMenuItem>
                          <DropdownMenuItem onClick={() => openSettings(lib)}>
                            <Settings className="w-3.5 h-3.5 mr-2" />
                            Settings
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    )}
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

      {/* Library settings sheet */}
      <Sheet open={!!settingsLib} onOpenChange={(open) => !open && setSettingsLib(null)}>
        <SheetContent side="right" className="w-full sm:max-w-md flex flex-col gap-0">
          <SheetHeader className="px-6 pt-6 pb-4 border-b border-border">
            <SheetTitle className="font-display text-base">
              {settingsLib?.name} — Settings
            </SheetTitle>
          </SheetHeader>

          <div className="flex-1 overflow-y-auto px-6 py-5 space-y-6">
            <div>
              <p className="text-sm font-medium text-foreground mb-1">Standalone book folders</p>
              <p className="text-xs text-muted-foreground mb-3">
                Files whose immediate parent folder matches one of these names are always treated as standalone books, regardless of directory structure.
              </p>

              <div className="flex gap-2 mb-3">
                <Input
                  ref={sfInputRef}
                  placeholder="e.g. One-Shot"
                  value={sfInput}
                  onChange={(e) => setSfInput(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && addFolder()}
                  className="text-sm h-8"
                />
                <Button size="sm" variant="outline" onClick={addFolder} className="shrink-0 h-8 px-2">
                  <Plus className="w-3.5 h-3.5" />
                </Button>
              </div>

              {sfFolders.length > 0 ? (
                <div className="flex flex-wrap gap-1.5">
                  {sfFolders.map((f) => (
                    <span
                      key={f}
                      className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-muted text-xs text-foreground"
                    >
                      {f}
                      <button
                        onClick={() => removeFolder(f)}
                        className="text-muted-foreground hover:text-foreground transition-colors"
                        aria-label={`Remove ${f}`}
                      >
                        <X className="w-3 h-3" />
                      </button>
                    </span>
                  ))}
                </div>
              ) : (
                <p className="text-xs text-muted-foreground italic">No standalone folders configured.</p>
              )}
            </div>
          </div>

          <div className="px-6 py-4 border-t border-border flex justify-end gap-2">
            <Button variant="ghost" size="sm" onClick={() => setSettingsLib(null)}>
              Cancel
            </Button>
            <Button size="sm" onClick={handleSaveFolders} disabled={sfSaving}>
              {sfSaving ? 'Saving…' : 'Save'}
            </Button>
          </div>
        </SheetContent>
      </Sheet>

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
