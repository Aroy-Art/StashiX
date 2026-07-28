import { useEffect, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { books as booksApi } from '../api/client'
import { transport } from '../api/transport'
import type { Book } from '../types'

export default function LibraryPage() {
  const { id } = useParams<{ id: string }>()
  const [bookList, setBookList] = useState<Book[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!id) return
    booksApi.listByLibrary(id).then(setBookList).finally(() => setLoading(false))

    // live: append newly added books
    const off = transport.on('book_added', (payload) => {
      const p = payload as { book_id: string; library_id: string }
      if (p.library_id !== id) return
      booksApi.get(p.book_id).then((book) => {
        setBookList((prev) => [book, ...prev])
      })
    })
    return off
  }, [id])

  return (
    <div style={{ maxWidth: 1100, margin: '0 auto', padding: '2rem 1rem' }}>
      <div style={{ marginBottom: '1.5rem' }}>
        <Link to="/" style={{ color: 'var(--text-muted)', fontSize: 13 }}>← Libraries</Link>
      </div>

      {loading && <p style={{ color: 'var(--text-muted)' }}>Loading…</p>}

      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))',
        gap: 16,
      }}>
        {bookList.map((book) => (
          <Link
            key={book.id}
            to={`/read/${book.id}`}
            style={{ display: 'block', color: 'var(--text)' }}
          >
            <div style={{
              background: 'var(--surface)',
              border: '1px solid var(--border)',
              borderRadius: 6,
              overflow: 'hidden',
              transition: 'border-color 0.15s',
            }}>
              <img
                src={booksApi.coverUrl(book.id)}
                alt={book.title}
                style={{ width: '100%', aspectRatio: '2/3', objectFit: 'cover', display: 'block' }}
                loading="lazy"
                onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
              />
              <div style={{ padding: '0.6rem' }}>
                <div style={{ fontSize: 13, fontWeight: 600, lineHeight: 1.3, marginBottom: 2 }}>
                  {book.series ?? book.title}
                </div>
                {book.issue_number && (
                  <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>#{book.issue_number}</div>
                )}
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4, textTransform: 'uppercase' }}>
                  {book.format}
                </div>
              </div>
            </div>
          </Link>
        ))}
      </div>
    </div>
  )
}
