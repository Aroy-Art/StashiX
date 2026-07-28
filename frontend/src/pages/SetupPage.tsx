import { useState, FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuthStore } from '../store/auth'
import { transport } from '../api/transport'

type Step = 'account' | 'library'

export default function SetupPage() {
  const [step, setStep] = useState<Step>('account')
  const [token, setToken] = useState('')

  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      minHeight: '100vh',
      padding: '1rem',
    }}>
      <div style={{ width: '100%', maxWidth: 400 }}>
        <h1 style={{ fontSize: 28, marginBottom: 4 }}>Stashix</h1>
        <p style={{ color: 'var(--text-muted)', marginBottom: 8 }}>
          {step === 'account' ? 'First run — create your admin account.' : 'Add your first library.'}
        </p>

        <StepIndicator current={step} />

        {step === 'account'
          ? <AccountStep onDone={(t) => { setToken(t); setStep('library') }} />
          : <LibraryStep token={token} />
        }
      </div>
    </div>
  )
}

function StepIndicator({ current }: { current: Step }) {
  const steps: { key: Step; label: string }[] = [
    { key: 'account', label: 'Admin account' },
    { key: 'library', label: 'Default library' },
  ]
  return (
    <div style={{ display: 'flex', gap: 8, marginBottom: 24, marginTop: 16 }}>
      {steps.map((s, i) => (
        <div key={s.key} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          {i > 0 && <div style={{ width: 24, height: 1, background: 'var(--border)' }} />}
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <div style={{
              width: 22,
              height: 22,
              borderRadius: '50%',
              background: current === s.key ? 'var(--accent)' : 'var(--surface)',
              border: `1px solid ${current === s.key ? 'var(--accent)' : 'var(--border)'}`,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 11,
              fontWeight: 600,
              color: current === s.key ? '#fff' : 'var(--text-muted)',
              flexShrink: 0,
            }}>
              {i + 1}
            </div>
            <span style={{ fontSize: 12, color: current === s.key ? 'var(--text)' : 'var(--text-muted)' }}>
              {s.label}
            </span>
          </div>
        </div>
      ))}
    </div>
  )
}

function AccountStep({ onDone }: { onDone: (token: string) => void }) {
  const [email, setEmail] = useState('')
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setError('')
    if (password !== confirm) { setError('Passwords do not match'); return }
    if (password.length < 8) { setError('Password must be at least 8 characters'); return }

    setLoading(true)
    try {
      const res = await fetch('/api/setup', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, username, password }),
      })
      const body = await res.json()
      if (!res.ok) { setError(body.error ?? 'Setup failed'); return }
      localStorage.setItem('access_token', body.access_token)
      localStorage.setItem('refresh_token', body.refresh_token)
      transport.setToken(body.access_token)
      onDone(body.access_token)
    } catch {
      setError('Network error')
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <Field label="Email">
        <input type="email" value={email} onChange={(e) => setEmail(e.target.value)}
          placeholder="admin@example.com" required autoFocus />
      </Field>
      <Field label="Username">
        <input type="text" value={username} onChange={(e) => setUsername(e.target.value)}
          placeholder="admin" required />
      </Field>
      <Field label="Password">
        <input type="password" value={password} onChange={(e) => setPassword(e.target.value)}
          placeholder="Min. 8 characters" required />
      </Field>
      <Field label="Confirm Password">
        <input type="password" value={confirm} onChange={(e) => setConfirm(e.target.value)}
          placeholder="Repeat password" required />
      </Field>
      {error && <p style={{ color: 'var(--danger)', fontSize: 13, margin: 0 }}>{error}</p>}
      <button type="submit" disabled={loading} style={{ marginTop: 8 }}>
        {loading ? 'Creating account…' : 'Next →'}
      </button>
    </form>
  )
}

function LibraryStep({ token }: { token: string }) {
  const [name, setName] = useState('Comics')
  const [path, setPath] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const navigate = useNavigate()
  const restore = useAuthStore((s) => s.restore)

  async function handleSubmit(e: FormEvent) {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      const res = await fetch('/api/libraries', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ name, root_path: path }),
      })
      if (!res.ok) {
        const body = await res.json().catch(() => ({ error: res.statusText }))
        setError(body.error ?? 'Could not create library')
        return
      }
      restore()
      navigate('/')
    } catch {
      setError('Network error')
    } finally {
      setLoading(false)
    }
  }

  function skip() {
    restore()
    navigate('/')
  }

  return (
    <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      <Field label="Library name">
        <input type="text" value={name} onChange={(e) => setName(e.target.value)}
          placeholder="Comics" required autoFocus />
      </Field>
      <Field label="Root path" hint="Absolute path on the server where your files live">
        <input type="text" value={path} onChange={(e) => setPath(e.target.value)}
          placeholder="/libraries/comics" required />
      </Field>
      {error && <p style={{ color: 'var(--danger)', fontSize: 13, margin: 0 }}>{error}</p>}
      <button type="submit" disabled={loading} style={{ marginTop: 8 }}>
        {loading ? 'Creating library…' : 'Create library & finish'}
      </button>
      <button type="button" onClick={skip} style={{ background: 'transparent', color: 'var(--text-muted)', border: '1px solid var(--border)' }}>
        Skip for now
      </button>
    </form>
  )
}

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
      <span style={{ fontSize: 12, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
        {label}
      </span>
      {children}
      {hint && <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>{hint}</span>}
    </label>
  )
}
