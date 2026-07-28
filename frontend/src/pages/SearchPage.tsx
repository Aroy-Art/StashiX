import { useState, FormEvent, useEffect } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { search as searchApi, books as booksApi } from '../api/client'
import type { SearchResult } from '../types'

export default function SearchPage() {
  const [params, setParams] = useSearchParams()
  const [query, setQuery] = useState(params.get('q') ?? '')
  const [results, setResults] = useState<SearchResult[]>([])
  const [loading, setLoading] = useState(false)

  async function doSearch(q: string) {
    if (!q.trim()) return
    setLoading(true)
    try {
      const data = await searchApi.query(q)
      setResults(data.results)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    const q = params.get('q')
    if (q) doSearch(q)
  }, [])

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setParams({ q: query })
    doSearch(query)
  }

  return (
    <div style={{ maxWidth: 900, margin: '0 auto', padding: '2rem 1rem' }}>
      <div style={{ marginBottom: '1rem' }}>
        <Link to="/" style={{ color: 'var(--text-muted)', fontSize: 13 }}>← Libraries</Link>
      </div>
      <form onSubmit={handleSubmit} style={{ display: 'flex', gap: 8, marginBottom: '1.5rem' }}>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search titles, series, publisher…"
          autoFocus
        />
        <button type="submit" disabled={loading} style={{ whiteSpace: 'nowrap' }}>
          {loading ? '…' : 'Search'}
        </button>
      </form>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))', gap: 16 }}>
        {results.map((book) => (
          <Link key={book.id} to={`/read/${book.id}`} style={{ color: 'var(--text)' }}>
            <div style={{
              background: 'var(--surface)',
              border: '1px solid var(--border)',
              borderRadius: 6,
              overflow: 'hidden',
            }}>
              <img
                src={booksApi.coverUrl(book.id)}
                alt={book.title}
                style={{ width: '100%', aspectRatio: '2/3', objectFit: 'cover', display: 'block' }}
                loading="lazy"
                onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
              />
              <div style={{ padding: '0.6rem' }}>
                <div style={{ fontSize: 13, fontWeight: 600 }}>{book.series ?? book.title}</div>
                {book.issue_number && (
                  <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>#{book.issue_number}</div>
                )}
              </div>
            </div>
          </Link>
        ))}
      </div>

      {!loading && results.length === 0 && params.get('q') && (
        <p style={{ color: 'var(--text-muted)' }}>No results for "{params.get('q')}"</p>
      )}
    </div>
  )
}
