import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { libraries } from '../api/client'
import { useAuthStore } from '../store/auth'
import type { Library } from '../types'

export default function LibrariesPage() {
  const [libs, setLibs] = useState<Library[]>([])
  const [loading, setLoading] = useState(true)
  const logout = useAuthStore((s) => s.logout)
  const navigate = useNavigate()

  useEffect(() => {
    libraries.list().then((data) => setLibs(data ?? [])).finally(() => setLoading(false))
  }, [])

  return (
    <div style={{ maxWidth: 900, margin: '0 auto', padding: '2rem 1rem' }}>
      <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '2rem' }}>
        <h1 style={{ fontSize: 22 }}>Libraries</h1>
        <div style={{ display: 'flex', gap: 12 }}>
          <button onClick={() => navigate('/search')} style={{ background: 'var(--surface)', color: 'var(--text)', border: '1px solid var(--border)' }}>
            Search
          </button>
          <button onClick={logout} style={{ background: 'transparent', color: 'var(--text-muted)', border: '1px solid var(--border)' }}>
            Sign out
          </button>
        </div>
      </header>

      {loading && <p style={{ color: 'var(--text-muted)' }}>Loading…</p>}

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))', gap: 16 }}>
        {libs.map((lib) => (
          <Link
            key={lib.id}
            to={`/library/${lib.id}`}
            style={{
              display: 'block',
              background: 'var(--surface)',
              border: '1px solid var(--border)',
              borderRadius: 8,
              padding: '1.25rem',
              color: 'var(--text)',
              transition: 'border-color 0.15s',
            }}
          >
            <div style={{ fontSize: 16, fontWeight: 600, marginBottom: 4 }}>{lib.name}</div>
            <div style={{ fontSize: 12, color: 'var(--text-muted)', wordBreak: 'break-all' }}>{lib.root_path}</div>
          </Link>
        ))}
      </div>
    </div>
  )
}
