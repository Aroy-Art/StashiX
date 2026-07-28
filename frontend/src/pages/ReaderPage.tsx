import { useEffect, useState, useCallback, useRef } from 'react'
import { useParams, Link } from 'react-router-dom'
import { books as booksApi } from '../api/client'
import type { Book } from '../types'

export default function ReaderPage() {
  const { id } = useParams<{ id: string }>()
  const [book, setBook] = useState<Book | null>(null)
  const [pages, setPages] = useState<string[]>([])
  const [currentPage, setCurrentPage] = useState(0)
  const progressTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    if (!id) return
    booksApi.get(id).then(setBook)
    booksApi.pages(id).then(({ pages }) => setPages(pages))
  }, [id])

  const savePage = useCallback((page: number) => {
    if (!id) return
    if (progressTimer.current) clearTimeout(progressTimer.current)
    progressTimer.current = setTimeout(() => {
      booksApi.updateProgress(id, page)
    }, 1000)
  }, [id])

  const goTo = useCallback((page: number) => {
    setCurrentPage(page)
    savePage(page)
  }, [savePage])

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

  if (!book) return <div style={{ padding: '2rem', color: 'var(--text-muted)' }}>Loading…</div>

  if (book.format === 'epub' || book.format === 'pdf') {
    return (
      <div style={{ height: '100vh', display: 'flex', flexDirection: 'column' }}>
        <ReaderBar book={book} page={0} total={0} />
        <iframe
          src={booksApi.fileUrl(book.id)}
          style={{ flex: 1, border: 'none', width: '100%' }}
          title={book.title}
        />
      </div>
    )
  }

  return (
    <div
      style={{ height: '100vh', display: 'flex', flexDirection: 'column', background: '#000', userSelect: 'none' }}
      onClick={(e) => {
        const x = e.clientX / window.innerWidth
        if (x > 0.5) goTo(Math.min(currentPage + 1, pages.length - 1))
        else goTo(Math.max(currentPage - 1, 0))
      }}
    >
      <ReaderBar book={book} page={currentPage} total={pages.length} />
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
        {pages[currentPage] && (
          <img
            key={pages[currentPage]}
            src={pages[currentPage]}
            alt={`Page ${currentPage + 1}`}
            style={{ maxHeight: '100%', maxWidth: '100%', objectFit: 'contain', display: 'block' }}
          />
        )}
      </div>
    </div>
  )
}

function ReaderBar({ book, page, total }: { book: Book; page: number; total: number }) {
  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '0.5rem 1rem',
      background: 'rgba(0,0,0,0.85)',
      backdropFilter: 'blur(8px)',
      borderBottom: '1px solid var(--border)',
      zIndex: 10,
    }}>
      <Link to={`/library/${book.library_id}`} style={{ color: 'var(--text-muted)', fontSize: 13 }}>← Back</Link>
      <span style={{ fontSize: 13 }}>{book.title}</span>
      {total > 0 && (
        <span style={{ fontSize: 13, color: 'var(--text-muted)' }}>{page + 1} / {total}</span>
      )}
    </div>
  )
}
