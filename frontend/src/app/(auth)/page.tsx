'use client'

import { useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueries, useQueryClient } from '@tanstack/react-query'
import { libraries as librariesApi, tasks as tasksApi, books as booksApi, series as seriesApi } from '@/api/client'
import { queryKeys } from '@/lib/query-keys'
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

export default function LibrariesPage() {
  const queryClient = useQueryClient()
  const isAdmin = useAuthStore((s) => s.isAdmin)
  const [scanning, setScanning] = useState<Set<string>>(new Set())
  const [settingsLib, setSettingsLib] = useState<LibraryType | null>(null)
  const [sfFolders, setSfFolders] = useState<string[]>([])
  const [sfInput, setSfInput] = useState('')
  const [sfSaving, setSfSaving] = useState(false)
  const sfInputRef = useRef<HTMLInputElement>(null)

  const { data: libraries = [], isLoading } = useQuery({
    queryKey: queryKeys.libraries(),
    queryFn: () => librariesApi.list(),
  })

  const { data: activeTasks = {} } = useQuery({
    queryKey: queryKeys.tasks(),
    queryFn: async () => {
      const ts = await tasksApi.list()
      return Object.fromEntries(ts.map((t) => [t.library_id, t])) as Record<string, ScanTask>
    },
  })

  // Per-library content: 4 queries per library via useQueries
  const contentQueries = useQueries({
    queries: libraries.flatMap((lib) => [
      {
        queryKey: queryKeys.libraryRecentStandalone(lib.id),
        queryFn: () => booksApi.listByLibrary(lib.id, 0, 20, { sort: 'recent', type: 'standalone' }),
      },
      {
        queryKey: queryKeys.librarySeries(lib.id),
        queryFn: () => seriesApi.listByLibrary(lib.id),
      },
      {
        queryKey: queryKeys.libraryRecentIssues(lib.id),
        queryFn: () => booksApi.listByLibrary(lib.id, 0, 20, { sort: 'recent', type: 'issues' }),
      },
      {
        queryKey: queryKeys.libraryPreview(lib.id),
        queryFn: () => booksApi.listByLibrary(lib.id, 0, 5, { sort: 'recent' }),
      },
    ]),
  })

  // WS book_added — batch fetch + preload + update per-library caches
  useEffect(() => {
    const pendingBooks = new Map<string, string[]>()
    let flushTimer: ReturnType<typeof setTimeout> | null = null

    function preloadCover(url: string): Promise<void> {
      return new Promise((resolve) => {
        const img = new Image()
        const t = setTimeout(resolve, 5000)
        img.onload = () => { clearTimeout(t); resolve() }
        img.onerror = () => { clearTimeout(t); resolve() }
        img.src = url
      })
    }

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

          for (const book of books) {
            const isIssue = book.type === 'issue'
            const dedup = (arr: Book[]) =>
              arr.some((x) => x.id === book.id) ? arr : [book, ...arr]

            if (!isIssue) {
              queryClient.setQueryData(queryKeys.libraryRecentStandalone(libraryId), (old: Book[] = []) =>
                dedup(old).slice(0, 20)
              )
            } else {
              queryClient.setQueryData(queryKeys.libraryRecentIssues(libraryId), (old: Book[] = []) =>
                dedup(old).slice(0, 20)
              )
            }
            queryClient.setQueryData(queryKeys.libraryPreview(libraryId), (old: Book[] = []) =>
              old.length < 5 ? dedup(old) : old
            )
          }

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
      offAdded()
      if (flushTimer !== null) clearTimeout(flushTimer)
      pendingBooks.clear()
    }
  }, [queryClient])

  const openSettings = (lib: LibraryType) => {
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

  const removeFolder = (folder: string) => setSfFolders((f) => f.filter((x) => x !== folder))

  const handleSaveFolders = async () => {
    if (!settingsLib) return
    setSfSaving(true)
    try {
      await librariesApi.update(settingsLib.id, { standalone_folders: sfFolders })
      queryClient.setQueryData(queryKeys.libraries(), (old: LibraryType[] = []) =>
        old.map((l) => l.id === settingsLib.id ? { ...l, standalone_folders: sfFolders } : l)
      )
      setSettingsLib(null)
    } finally {
      setSfSaving(false)
    }
  }

  useEffect(() => {
    setScanning((s) => {
      if (s.size === 0) return s
      const next = new Set(s)
      let changed = false
      for (const libId of s) {
        if (activeTasks[libId]) { next.delete(libId); changed = true }
      }
      return changed ? next : s
    })
  }, [activeTasks])

  const handleScan = async (libId: string, force = false) => {
    setScanning((s) => new Set(s).add(libId))
    try {
      await librariesApi.scan(libId, force)
    } catch {
      setScanning((s) => { const next = new Set(s); next.delete(libId); return next })
    }
  }

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 rounded-full border-2 border-volt-2 border-t-transparent animate-spin" />
          <p className="text-sm text-muted-foreground">Loading libraries…</p>
        </div>
      </div>
    )
  }

  if (libraries.length === 0) {
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
          {libraries.map((lib, libIdx) => {
            const task = activeTasks[lib.id]
            const isScanning = !!task || scanning.has(lib.id)
            const pct = task && task.total > 0 ? Math.round((task.scanned / task.total) * 100) : null
            const previewBooks = (contentQueries[libIdx * 4 + 3]?.data as Book[] | undefined) ?? []

            return (
              <div
                key={lib.id}
                className="relative group rounded-xl bg-card border border-border hover:border-ring/50 transition-all duration-200 overflow-hidden"
              >
                {previewBooks.length > 0 && (
                  <div className="relative flex h-20 overflow-hidden border-b border-border">
                    {previewBooks.slice(0, 5).map((book) => (
                      <img
                        key={book.id}
                        src={booksApi.coverUrl(book.id, thumbnailSize(55))}
                        alt=""
                        className="flex-1 min-w-0 object-cover"
                        loading="lazy"
                        onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
                      />
                    ))}
                    <div className="absolute inset-0 bg-gradient-to-b from-transparent via-transparent to-card pointer-events-none" />
                  </div>
                )}

                <div className="p-4">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                      <h3 className="font-display font-bold text-base text-foreground truncate">{lib.name}</h3>
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
                          <DropdownMenuItem onClick={() => handleScan(lib.id)} disabled={isScanning}>
                            <RefreshCw className="w-3.5 h-3.5 mr-2" />
                            Scan for new files
                          </DropdownMenuItem>
                          <DropdownMenuItem onClick={() => handleScan(lib.id, true)} disabled={isScanning}>
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

                  {scanning.has(lib.id) && !task && (
                    <div className="mt-3 flex items-center gap-2">
                      <div className="w-3 h-3 rounded-full border border-volt-3 border-t-transparent animate-spin shrink-0" />
                      <span className="text-[11px] text-volt-3">Starting…</span>
                    </div>
                  )}
                  {task && task.total === 0 && (
                    <div className="mt-3">
                      <div className="flex justify-between text-[11px] text-muted-foreground mb-1">
                        <span className="text-volt-3">Scanning…</span>
                        <div className="w-3 h-3 rounded-full border border-volt-3 border-t-transparent animate-spin" />
                      </div>
                      <div className="h-1 rounded-full bg-border overflow-hidden">
                        <div className="h-full rounded-full shimmer-bar" style={{ width: '100%' }} />
                      </div>
                    </div>
                  )}
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
                    href={`/library/${lib.id}`}
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
                    <span key={f} className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-muted text-xs text-foreground">
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
      {libraries.map((lib, libIdx) => {
        const recentBooks = (contentQueries[libIdx * 4 + 0]?.data as Book[] | undefined) ?? []
        const recentSeries = (contentQueries[libIdx * 4 + 1]?.data as Series[] | undefined) ?? []
        const recentIssues = (contentQueries[libIdx * 4 + 2]?.data as Book[] | undefined) ?? []
        const contentLoading = contentQueries[libIdx * 4]?.isLoading

        return (
          <div key={lib.id}>
            <SectionCarousel
              title={`${lib.name} — Recent Books`}
              accentColor="volt"
              isEmpty={!contentLoading && recentBooks.length === 0}
            >
              {recentBooks.map((book) => (
                <div key={book.id} className="shrink-0 w-[140px]">
                  <BookCard book={book} />
                </div>
              ))}
            </SectionCarousel>

            {(contentLoading || recentSeries.length > 0) && (
              <SectionCarousel
                title={`${lib.name} — Recent Series`}
                accentColor="plasma"
                isEmpty={!contentLoading && recentSeries.length === 0}
              >
                {recentSeries.map((s) => (
                  <div key={s.id} className="shrink-0 w-[140px]">
                    <SeriesCard series={s} />
                  </div>
                ))}
              </SectionCarousel>
            )}

            {(contentLoading || recentIssues.length > 0) && (
              <SectionCarousel
                title={`${lib.name} — Recent Issues`}
                accentColor="volt"
                isEmpty={!contentLoading && recentIssues.length === 0}
              >
                {recentIssues.map((book) => (
                  <div key={book.id} className="shrink-0 w-[140px]">
                    <BookCard book={book} to={`/issue/${book.id}`} />
                  </div>
                ))}
              </SectionCarousel>
            )}
          </div>
        )
      })}
    </div>
  )
}
