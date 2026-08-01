import { useState, useRef, FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuthStore } from '@/store/auth'
import { transport } from '@/api/transport'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Zap, CheckCircle2, Plus, X } from 'lucide-react'
import { cn } from '@/lib/utils'

type Step = 'account' | 'library'

export default function SetupPage() {
  const [step, setStep] = useState<Step>('account')
  const [token, setToken] = useState('')

  return (
    <div
      style={{
        background: 'radial-gradient(ellipse 80% 60% at 50% 0%, rgba(124,58,237,0.12) 0%, transparent 70%)',
      }}
      className="min-h-screen flex items-center justify-center p-6 bg-background relative overflow-hidden"
    >
      <div
        className="absolute inset-0 opacity-[0.04] dark:opacity-[0.03]"
        style={{
          backgroundImage: 'linear-gradient(var(--border) 1px, transparent 1px), linear-gradient(90deg, var(--border) 1px, transparent 1px)',
          backgroundSize: '48px 48px',
        }}
      />

      <div className="relative w-full max-w-md animate-fade-in-up">
        <div className="rounded-2xl border border-border bg-card/80 backdrop-blur-xl p-8 shadow-xl">
          {/* Header */}
          <div className="flex items-center gap-3 mb-2">
            <div className="flex items-center justify-center w-10 h-10 rounded-xl bg-volt/20 border border-volt/40 glow-volt">
              <Zap className="w-5 h-5 text-volt-3" />
            </div>
            <div>
              <h1 className="font-display font-bold text-xl text-foreground tracking-tight">Stashix</h1>
              <p className="text-xs text-muted-foreground">Initial setup</p>
            </div>
          </div>

          <p className="text-sm text-muted-foreground mt-1 mb-6">
            {step === 'account'
              ? 'Create your admin account to get started.'
              : 'Add your first library folder.'}
          </p>

          {/* Step indicator */}
          <StepIndicator current={step} />

          {step === 'account'
            ? <AccountStep onDone={(t) => { setToken(t); setStep('library') }} />
            : <LibraryStep token={token} />}
        </div>
      </div>
    </div>
  )
}

function StepIndicator({ current }: { current: Step }) {
  const steps: { key: Step; label: string }[] = [
    { key: 'account', label: 'Admin account' },
    { key: 'library', label: 'First library' },
  ]
  const currentIndex = steps.findIndex((s) => s.key === current)

  return (
    <div className="flex items-center gap-3 mb-6">
      {steps.map((s, i) => {
        const done = i < currentIndex
        const active = i === currentIndex
        return (
          <div key={s.key} className="flex items-center gap-2">
            {i > 0 && (
              <div className={cn('flex-1 h-px w-8', done ? 'bg-volt-3' : 'bg-border')} />
            )}
            <div className="flex items-center gap-1.5">
              <div
                className={cn(
                  'w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold shrink-0 transition-all duration-300',
                  done && 'bg-volt-3 text-background',
                  active && 'bg-volt text-white shadow-[0_0_10px_rgba(124,58,237,0.5)]',
                  !done && !active && 'bg-muted text-muted-foreground border border-border'
                )}
              >
                {done ? <CheckCircle2 className="w-3 h-3" /> : i + 1}
              </div>
              <span
                className={cn(
                  'text-xs',
                  active ? 'text-foreground font-medium' : 'text-muted-foreground'
                )}
              >
                {s.label}
              </span>
            </div>
          </div>
        )
      })}
    </div>
  )
}

function Field({
  label,
  hint,
  children,
}: {
  label: string
  hint?: string
  children: React.ReactNode
}) {
  return (
    <div className="space-y-1.5">
      <label className="text-xs font-medium text-muted-foreground uppercase tracking-wider">{label}</label>
      {children}
      {hint && <p className="text-[11px] text-muted-foreground/70">{hint}</p>}
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
    <form onSubmit={handleSubmit} className="space-y-4">
      <Field label="Email">
        <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)}
          placeholder="admin@example.com" required autoFocus className="h-10" />
      </Field>
      <Field label="Username">
        <Input type="text" value={username} onChange={(e) => setUsername(e.target.value)}
          placeholder="admin" required className="h-10" />
      </Field>
      <Field label="Password">
        <Input type="password" value={password} onChange={(e) => setPassword(e.target.value)}
          placeholder="Min. 8 characters" required className="h-10" />
      </Field>
      <Field label="Confirm password">
        <Input type="password" value={confirm} onChange={(e) => setConfirm(e.target.value)}
          placeholder="Repeat password" required className="h-10" />
      </Field>

      {error && (
        <p className="text-xs text-destructive bg-destructive/10 border border-destructive/20 rounded-md px-3 py-2">
          {error}
        </p>
      )}

      <Button type="submit" disabled={loading} className="w-full h-10 mt-2">
        {loading ? (
          <span className="flex items-center gap-2">
            <span className="w-3.5 h-3.5 rounded-full border-2 border-white/30 border-t-white animate-spin" />
            Creating account…
          </span>
        ) : (
          'Next →'
        )}
      </Button>
    </form>
  )
}

function LibraryStep({ token }: { token: string }) {
  const [name, setName] = useState('Comics')
  const [path, setPath] = useState('')
  const [sfFolders, setSfFolders] = useState<string[]>([])
  const [sfInput, setSfInput] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const sfInputRef = useRef<HTMLInputElement>(null)
  const navigate = useNavigate()
  const restore = useAuthStore((s) => s.restore)

  function addFolder() {
    const val = sfInput.trim()
    if (!val || sfFolders.includes(val)) return
    setSfFolders((f) => [...f, val])
    setSfInput('')
    sfInputRef.current?.focus()
  }

  function removeFolder(folder: string) {
    setSfFolders((f) => f.filter((x) => x !== folder))
  }

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
        body: JSON.stringify({ name, root_path: path, standalone_folders: sfFolders }),
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
    <form onSubmit={handleSubmit} className="space-y-4">
      <Field label="Library name">
        <Input type="text" value={name} onChange={(e) => setName(e.target.value)}
          placeholder="Comics" required autoFocus className="h-10" />
      </Field>
      <Field
        label="Root path"
        hint="Absolute path on the server where your files live"
      >
        <Input type="text" value={path} onChange={(e) => setPath(e.target.value)}
          placeholder="/libraries/comics" required className="h-10 font-mono text-xs" />
      </Field>

      <Field
        label="Standalone book folders"
        hint="Folders whose name matches one of these are treated as standalone books, not series."
      >
        <div className="flex gap-2">
          <Input
            ref={sfInputRef}
            placeholder="e.g. One-Shot"
            value={sfInput}
            onChange={(e) => setSfInput(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addFolder() } }}
            className="h-9 text-sm"
          />
          <Button type="button" variant="outline" size="sm" onClick={addFolder} className="h-9 px-3 shrink-0">
            <Plus className="w-4 h-4" />
          </Button>
        </div>
        {sfFolders.length > 0 && (
          <div className="flex flex-wrap gap-1.5 mt-2">
            {sfFolders.map((f) => (
              <span key={f} className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-muted text-xs text-foreground">
                {f}
                <button type="button" onClick={() => removeFolder(f)} className="text-muted-foreground hover:text-foreground">
                  <X className="w-3 h-3" />
                </button>
              </span>
            ))}
          </div>
        )}
      </Field>

      {error && (
        <p className="text-xs text-destructive bg-destructive/10 border border-destructive/20 rounded-md px-3 py-2">
          {error}
        </p>
      )}

      <Button type="submit" disabled={loading} className="w-full h-10 mt-2">
        {loading ? (
          <span className="flex items-center gap-2">
            <span className="w-3.5 h-3.5 rounded-full border-2 border-white/30 border-t-white animate-spin" />
            Creating library…
          </span>
        ) : (
          'Create library & finish'
        )}
      </Button>

      <Button
        type="button"
        variant="outline"
        onClick={skip}
        className="w-full h-10"
      >
        Skip for now
      </Button>
    </form>
  )
}
