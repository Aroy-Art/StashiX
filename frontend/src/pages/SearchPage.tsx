import { useState, FormEvent, useEffect, useRef } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { search as searchApi } from '@/api/client'
import { BookCard } from '@/components/BookCard'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { ChevronLeft, Search } from 'lucide-react'
import type { SearchResult } from '@/types'

export default function SearchPage() {
  const [params, setParams] = useSearchParams()
  const [query, setQuery] = useState(params.get('q') ?? '')
  const [results, setResults] = useState<SearchResult[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  async function doSearch(q: string) {
    if (!q.trim()) return
    setLoading(true)
    try {
      const data = await searchApi.query(q)
      setResults(data.results)
      setTotal(data.total)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    const q = params.get('q')
    if (q) {
      setQuery(q)
      doSearch(q)
    }
    setTimeout(() => inputRef.current?.focus(), 50)
  }, [])

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setParams({ q: query })
    doSearch(query)
  }

  const hasQuery = !!params.get('q')

  return (
    <div className="min-h-full px-6 py-6">
      {/* Breadcrumb */}
      <div className="flex items-center gap-2 mb-6">
        <Link
          to="/"
          className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition-colors"
        >
          <ChevronLeft className="w-3.5 h-3.5" />
          Home
        </Link>
        <span className="text-border">/</span>
        <span className="text-sm font-medium text-foreground">Search</span>
      </div>

      {/* Search header */}
      <div className="mb-8">
        <div className="flex items-center gap-2.5 mb-5">
          <div className="w-1.5 h-5 rounded-full bg-plasma shadow-[0_0_8px_rgba(232,121,249,0.6)]" />
          <h1 className="font-display font-bold text-2xl text-foreground tracking-tight">Search</h1>
        </div>

        <form onSubmit={handleSubmit} className="flex gap-2 max-w-xl">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground pointer-events-none" />
            <Input
              ref={inputRef}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Titles, series, publishers…"
              className="pl-9 h-10"
            />
          </div>
          <Button type="submit" disabled={loading} className="shrink-0">
            {loading ? 'Searching…' : 'Search'}
          </Button>
        </form>
      </div>

      {/* Loading */}
      {loading && (
        <div className="flex items-center justify-center h-48">
          <div className="w-7 h-7 rounded-full border-2 border-plasma border-t-transparent animate-spin" />
        </div>
      )}

      {/* Results */}
      {!loading && results.length > 0 && (
        <div>
          <p className="text-xs text-muted-foreground mb-4">
            {total} result{total !== 1 ? 's' : ''} for &ldquo;{params.get('q')}&rdquo;
          </p>
          <div className="grid grid-cols-[repeat(auto-fill,minmax(130px,1fr))] gap-4">
            {results.map((book, i) => (
              <div
                key={book.id}
                className="animate-fade-in-up"
                style={{ animationDelay: `${Math.min(i * 25, 250)}ms` }}
              >
                <BookCard book={book} />
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Empty state */}
      {!loading && results.length === 0 && hasQuery && (
        <div className="flex flex-col items-center justify-center h-48 gap-3 text-center">
          <div className="w-12 h-12 rounded-xl bg-muted border border-border flex items-center justify-center">
            <Search className="w-5 h-5 text-muted-foreground" />
          </div>
          <p className="text-sm text-muted-foreground">
            No results for &ldquo;{params.get('q')}&rdquo;
          </p>
        </div>
      )}

      {/* Idle state */}
      {!loading && !hasQuery && (
        <div className="flex flex-col items-center justify-center h-48 gap-3 text-center">
          <div className="w-12 h-12 rounded-xl bg-plasma/10 border border-plasma/20 flex items-center justify-center glow-plasma">
            <Search className="w-5 h-5 text-plasma/70" />
          </div>
          <p className="text-sm text-muted-foreground">Type something to search your collection.</p>
        </div>
      )}
    </div>
  )
}
