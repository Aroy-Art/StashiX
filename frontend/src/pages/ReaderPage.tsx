import { useEffect, useState, useCallback, useRef } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { books as booksApi } from '@/api/client'
import { Button } from '@/components/ui/button'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip'
import type { Book } from '@/types'
import { Square, Columns2, Minimize2, ArrowLeftRight, ArrowUpDown } from 'lucide-react'

type Layout = 'single' | 'double'
type ZoomMode = 'fit-page' | 'fit-width' | 'fit-height'
type Direction = 'ltr' | 'rtl'

function pref<T extends string>(key: string, fallback: T): T {
  return (localStorage.getItem(key) as T) ?? fallback
}

export default function ReaderPage() {
  const { id } = useParams<{ id: string }>()
  const [book, setBook] = useState<Book | null>(null)
  const [pages, setPages] = useState<string[]>([])
  const [currentPage, setCurrentPage] = useState(0)
  const [error, setError] = useState(false)
  const [layout, setLayout] = useState<Layout>(() => pref('reader_layout', 'single'))
  const [zoom, setZoom] = useState<ZoomMode>(() => pref('reader_zoom', 'fit-page'))
  const [direction, setDirection] = useState<Direction>(() => pref('reader_direction', 'ltr'))
  const [showControls, setShowControls] = useState(true)
  const controlsTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const progressTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    if (!id) return
    Promise.all([booksApi.get(id), booksApi.pages(id)])
      .then(([bookData, { pages: p }]) => {
        setBook(bookData)
        setPages(p)
        if (bookData.current_page != null) setCurrentPage(bookData.current_page)
      })
      .catch(() => setError(true))
  }, [id])

  // Preload adjacent pages
  useEffect(() => {
    if (!pages.length) return
    ;[currentPage + 1, currentPage + 2, currentPage - 1]
      .filter(p => p >= 0 && p < pages.length)
      .forEach(p => { const img = new Image(); img.src = pages[p] })
  }, [currentPage, pages])

  const savePage = useCallback((page: number) => {
    if (!id) return
    if (progressTimer.current) clearTimeout(progressTimer.current)
    progressTimer.current = setTimeout(() => booksApi.updateProgress(id, page), 1000)
  }, [id])

  const advance = useCallback((delta: 1 | -1) => {
    setCurrentPage(prev => {
      let next: number
      if (layout === 'double') {
        next = delta > 0
          ? (prev === 0 ? 1 : prev + 2)
          : (prev <= 1 ? 0 : prev - 2)
      } else {
        next = prev + delta
      }
      next = Math.max(0, Math.min(next, pages.length - 1))
      savePage(next)
      return next
    })
  }, [layout, pages.length, savePage])

  const bumpControls = useCallback(() => {
    setShowControls(true)
    if (controlsTimer.current) clearTimeout(controlsTimer.current)
    controlsTimer.current = setTimeout(() => setShowControls(false), 3000)
  }, [])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const fwd: 1 | -1 = direction === 'ltr' ? 1 : -1
      const bwd: 1 | -1 = direction === 'ltr' ? -1 : 1
      if (e.key === 'ArrowRight' || e.key === 'ArrowDown') advance(fwd)
      else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') advance(bwd)
      bumpControls()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [advance, direction, bumpControls])

  const setLayoutPersist = (l: Layout) => {
    if (l === 'double') {
      setCurrentPage(p => (p > 0 && p % 2 === 0 ? p - 1 : p))
    }
    setLayout(l)
    localStorage.setItem('reader_layout', l)
  }
  const setZoomPersist = (z: ZoomMode) => { setZoom(z); localStorage.setItem('reader_zoom', z) }
  const setDirectionPersist = (d: Direction) => { setDirection(d); localStorage.setItem('reader_direction', d) }

  if (error) return (
    <div className="min-h-screen flex items-center justify-center bg-background">
      <p className="text-sm text-muted-foreground">Failed to load book.</p>
    </div>
  )

  if (!book) return (
    <div className="min-h-screen flex items-center justify-center bg-background">
      <div className="w-7 h-7 rounded-full border-2 border-volt-2 border-t-transparent animate-spin" />
    </div>
  )

  if (book.format === 'epub' || book.format === 'pdf') {
    return (
      <div className="h-screen flex flex-col bg-background">
        <ReaderBar book={book} page={0} total={0} />
        <iframe src={booksApi.fileUrl(book.id)} className="flex-1 border-0 w-full" title={book.title} />
      </div>
    )
  }

  const isDoubleMode = layout === 'double' && pages.length > 1
  const showDouble = isDoubleMode && currentPage > 0 && currentPage + 1 < pages.length
  const leftIdx = direction === 'rtl' ? currentPage + 1 : currentPage
  const rightIdx = direction === 'rtl' ? currentPage : currentPage + 1

  const containerCls =
    zoom === 'fit-width' ? 'overflow-y-auto overflow-x-hidden' :
    zoom === 'fit-height' ? 'overflow-x-auto overflow-y-hidden' :
    'overflow-hidden'

  const imgCls = (half: boolean) => {
    if (zoom === 'fit-page') return half ? 'max-h-full max-w-[50%] object-contain block' : 'max-h-full max-w-full object-contain block'
    if (zoom === 'fit-width') return half ? 'w-1/2 object-contain block' : 'w-full object-contain block'
    return 'h-full object-contain block'
  }

  return (
    <TooltipProvider>
      <div
        className="h-screen flex flex-col bg-black select-none"
        onMouseMove={bumpControls}
        onClick={(e) => {
          if ((e.target as HTMLElement).closest('[data-controls]')) return
          bumpControls()
          const x = e.clientX / window.innerWidth
          const fwd: 1 | -1 = direction === 'ltr' ? 1 : -1
          const bwd: 1 | -1 = direction === 'ltr' ? -1 : 1
          if (x > 0.6) advance(fwd)
          else if (x < 0.4) advance(bwd)
        }}
      >
        <div
          data-controls
          className={`transition-opacity duration-300 ${showControls ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
          onClick={e => e.stopPropagation()}
        >
          <ReaderBar
            book={book}
            page={currentPage}
            total={pages.length}
            layout={layout}
            zoom={zoom}
            direction={direction}
            onLayoutChange={setLayoutPersist}
            onZoomChange={setZoomPersist}
            onDirectionChange={setDirectionPersist}
          />
        </div>

        <div className={`flex-1 flex items-center justify-center ${containerCls}`}>
          {showDouble ? (
            <div className="flex items-center justify-center h-full">
              {pages[leftIdx] && (
                <img
                  key={`l-${pages[leftIdx]}`}
                  src={pages[leftIdx]}
                  alt={`Page ${leftIdx + 1}`}
                  className={imgCls(true)}
                />
              )}
              {pages[rightIdx] && (
                <img
                  key={`r-${pages[rightIdx]}`}
                  src={pages[rightIdx]}
                  alt={`Page ${rightIdx + 1}`}
                  className={imgCls(true)}
                />
              )}
            </div>
          ) : (
            pages[currentPage] && (
              <img
                key={pages[currentPage]}
                src={pages[currentPage]}
                alt={`Page ${currentPage + 1}`}
                className={imgCls(false)}
              />
            )
          )}
        </div>
      </div>
    </TooltipProvider>
  )
}

function ReaderBar({
  book, page, total, layout, zoom, direction, onLayoutChange, onZoomChange, onDirectionChange,
}: {
  book: Book
  page: number
  total: number
  layout?: Layout
  zoom?: ZoomMode
  direction?: Direction
  onLayoutChange?: (l: Layout) => void
  onZoomChange?: (z: ZoomMode) => void
  onDirectionChange?: (d: Direction) => void
}) {
  const navigate = useNavigate()
  const isComicArchive = book.format === 'cbz' || book.format === 'cbr' || book.format === 'cb7'

  return (
    <div className="flex items-center justify-between px-4 py-2 bg-background/90 backdrop-blur-md border-b border-border z-10 gap-4">
      <button
        onClick={() => window.history.length > 1 ? navigate(-1) : navigate(`/library/${book.library_id}`)}
        className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition-colors shrink-0"
      >
        ← Back
      </button>

      <span className="text-sm font-medium text-foreground truncate">{book.title}</span>

      {isComicArchive && layout && zoom && direction && onLayoutChange && onZoomChange && onDirectionChange && (
        <div className="flex items-center gap-2 shrink-0">
          {/* Layout */}
          <div className="flex items-center gap-0.5 rounded-md border border-border p-0.5">
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant={layout === 'single' ? 'secondary' : 'ghost'}
                  size="icon"
                  className="h-7 w-7"
                  onClick={() => onLayoutChange('single')}
                >
                  <Square className="h-3.5 w-3.5" />
                </Button>
              </TooltipTrigger>
              <TooltipContent side="bottom">Single page</TooltipContent>
            </Tooltip>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant={layout === 'double' ? 'secondary' : 'ghost'}
                  size="icon"
                  className="h-7 w-7"
                  onClick={() => onLayoutChange('double')}
                >
                  <Columns2 className="h-3.5 w-3.5" />
                </Button>
              </TooltipTrigger>
              <TooltipContent side="bottom">Double page</TooltipContent>
            </Tooltip>
          </div>

          {/* Zoom */}
          <div className="flex items-center gap-0.5 rounded-md border border-border p-0.5">
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant={zoom === 'fit-page' ? 'secondary' : 'ghost'}
                  size="icon"
                  className="h-7 w-7"
                  onClick={() => onZoomChange('fit-page')}
                >
                  <Minimize2 className="h-3.5 w-3.5" />
                </Button>
              </TooltipTrigger>
              <TooltipContent side="bottom">Fit page</TooltipContent>
            </Tooltip>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant={zoom === 'fit-width' ? 'secondary' : 'ghost'}
                  size="icon"
                  className="h-7 w-7"
                  onClick={() => onZoomChange('fit-width')}
                >
                  <ArrowLeftRight className="h-3.5 w-3.5" />
                </Button>
              </TooltipTrigger>
              <TooltipContent side="bottom">Fit width</TooltipContent>
            </Tooltip>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant={zoom === 'fit-height' ? 'secondary' : 'ghost'}
                  size="icon"
                  className="h-7 w-7"
                  onClick={() => onZoomChange('fit-height')}
                >
                  <ArrowUpDown className="h-3.5 w-3.5" />
                </Button>
              </TooltipTrigger>
              <TooltipContent side="bottom">Fit height</TooltipContent>
            </Tooltip>
          </div>

          {/* Direction */}
          <Tooltip>
            <TooltipTrigger asChild>
              <Button
                variant={direction === 'rtl' ? 'secondary' : 'ghost'}
                size="sm"
                className="h-7 px-2 text-xs font-mono"
                onClick={() => onDirectionChange(direction === 'ltr' ? 'rtl' : 'ltr')}
              >
                {direction === 'ltr' ? 'LTR' : 'RTL'}
              </Button>
            </TooltipTrigger>
            <TooltipContent side="bottom">Reading direction (manga: RTL)</TooltipContent>
          </Tooltip>
        </div>
      )}

      {total > 0 && (
        <span className="text-sm text-muted-foreground font-mono shrink-0">
          {page + 1} / {total}
        </span>
      )}
    </div>
  )
}
