import { useEffect, useState } from 'react'
import { Routes, Route, Navigate, useNavigate } from 'react-router-dom'
import { useAuthStore } from './store/auth'
import LoginPage from './pages/LoginPage'
import SetupPage from './pages/SetupPage'
import LibrariesPage from './pages/LibrariesPage'
import LibraryPage from './pages/LibraryPage'
import ReaderPage from './pages/ReaderPage'
import SearchPage from './pages/SearchPage'

function RequireAuth({ children }: { children: React.ReactNode }) {
  const token = useAuthStore((s) => s.token)
  if (!token) return <Navigate to="/login" replace />
  return <>{children}</>
}

function AppRoutes() {
  const [checking, setChecking] = useState(true)
  const [needsSetup, setNeedsSetup] = useState(false)
  const restore = useAuthStore((s) => s.restore)
  const navigate = useNavigate()

  useEffect(() => {
    fetch('/api/setup/status')
      .then((r) => r.json())
      .then((data: { needs_setup: boolean }) => {
        if (data.needs_setup) {
          setNeedsSetup(true)
          navigate('/setup', { replace: true })
        } else {
          restore()
        }
      })
      .catch(() => restore())
      .finally(() => setChecking(false))
  }, [navigate, restore])

  if (checking) return null

  return (
    <Routes>
      <Route path="/setup" element={needsSetup ? <SetupPage /> : <Navigate to="/" replace />} />
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/"
        element={
          <RequireAuth>
            <LibrariesPage />
          </RequireAuth>
        }
      />
      <Route
        path="/library/:id"
        element={
          <RequireAuth>
            <LibraryPage />
          </RequireAuth>
        }
      />
      <Route
        path="/read/:id"
        element={
          <RequireAuth>
            <ReaderPage />
          </RequireAuth>
        }
      />
      <Route
        path="/search"
        element={
          <RequireAuth>
            <SearchPage />
          </RequireAuth>
        }
      />
    </Routes>
  )
}

export default function App() {
  return <AppRoutes />
}
