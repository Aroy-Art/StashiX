import { useEffect, useState, useCallback, useRef } from 'react'
import { useParams, Link } from 'react-router-dom'
import { books as booksApi } from '@/api/client'
import type { Book } from '@/types'

export default function ReaderPage() {
  const { id } = useParams<{ id: string }>()
  const [book, setBook] = useState<Book | null>(null)
  const [pages, setPages] = useState<string[]>([])
  const [currentPage, setCurrentPage] = useState(0)
  const progressTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    if (!id) return
    booksApi.get(id).then(setBook)
    booksApi.pages(id).then(({ pages: p }) => setPages(p))
  }, [id])

  const savePage = useCallback(
    (page: number) => {
      if (!id) return
      if (progressTimer.current) clearTimeout(progressTimer.current)
      progressTimer.current = setTimeout(() => {
        booksApi.updateProgress(id, page)
      }, 1000)
    },
    [id]
  )

  const goTo = useCallback(
    (page: number) => {
      setCurrentPage(page)
      savePage(page)
    },
    [savePage]
  )

  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
        goTo(Math.min(currentPage + 1, pages.length - 1))
      } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
        goTo(Math.max(currentPage - 1, 0))
      }
    }
    window.addEventListener('keydown', handleKey)
    return () => window.removeEventListener('keydown', handleKey)
  }, [currentPage, pages.length, goTo])

  if (!book) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-void">
        <div className="w-7 h-7 rounded-full border-2 border-volt-2 border-t-transparent animate-spin" />
      </div>
    )
  }

  if (book.format === 'epub' || book.format === 'pdf') {
    return (
      <div className="h-screen flex flex-col bg-void">
        <ReaderBar book={book} page={0} total={0} />
        <iframe
          src={booksApi.fileUrl(book.id)}
          className="flex-1 border-0 w-full"
          title={book.title}
        />
      </div>
    )
  }

  return (
    <div
      className="h-screen flex flex-col bg-black select-none"
      onClick={(e) => {
        const x = e.clientX / window.innerWidth
        if (x > 0.5) goTo(Math.min(currentPage + 1, pages.length - 1))
        else goTo(Math.max(currentPage - 1, 0))
      }}
    >
      <ReaderBar book={book} page={currentPage} total={pages.length} />
      <div className="flex-1 flex items-center justify-center overflow-hidden">
        {pages[currentPage] && (
          <img
            key={pages[currentPage]}
            src={pages[currentPage]}
            alt={`Page ${currentPage + 1}`}
            className="max-h-full max-w-full object-contain block"
          />
        )}
      </div>
    </div>
  )
}

function ReaderBar({ book, page, total }: { book: Book; page: number; total: number }) {
  return (
    <div className="flex items-center justify-between px-4 py-2.5 bg-void/90 backdrop-blur-md border-b border-rim z-10">
      <Link
        to={`/library/${book.library_id}`}
        className="flex items-center gap-1 text-sm text-muted hover:text-prose transition-colors"
      >
        ← Back
      </Link>
      <span className="text-sm font-medium text-prose truncate max-w-xs">{book.title}</span>
      {total > 0 && (
        <span className="text-sm text-muted font-mono shrink-0">
          {page + 1} / {total}
        </span>
      )}
    </div>
  )
}
