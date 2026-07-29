import { useEffect, useState } from 'react'
import { Routes, Route, Navigate, useNavigate } from 'react-router-dom'
import { useAuthStore } from '@/store/auth'
import { AppLayout } from '@/components/layout/AppLayout'
import LoginPage from '@/pages/LoginPage'
import SetupPage from '@/pages/SetupPage'
import LibrariesPage from '@/pages/LibrariesPage'
import LibraryPage from '@/pages/LibraryPage'
import ReaderPage from '@/pages/ReaderPage'
import SearchPage from '@/pages/SearchPage'
import SeriesPage from '@/pages/SeriesPage'
import BookPage from '@/pages/BookPage'

function RequireAuth({ children }: { children: React.ReactNode }) {
  const token = useAuthStore((s) => s.token)
  if (!token) return <Navigate to="/login" replace />
  return <>{children}</>
}

function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <RequireAuth>
      <AppLayout>{children}</AppLayout>
    </RequireAuth>
  )
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

  if (checking) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-void">
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 rounded-full border-2 border-volt-2 border-t-transparent animate-spin" />
        </div>
      </div>
    )
  }

  return (
    <Routes>
      <Route path="/setup" element={needsSetup ? <SetupPage /> : <Navigate to="/" replace />} />
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/"
        element={
          <AuthLayout>
            <LibrariesPage />
          </AuthLayout>
        }
      />
      <Route
        path="/library/:id"
        element={
          <AuthLayout>
            <LibraryPage />
          </AuthLayout>
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
          <AuthLayout>
            <SearchPage />
          </AuthLayout>
        }
      />
      <Route
        path="/series/:id"
        element={
          <AuthLayout>
            <SeriesPage />
          </AuthLayout>
        }
      />
      <Route
        path="/book/:id"
        element={
          <AuthLayout>
            <BookPage />
          </AuthLayout>
        }
      />
      <Route
        path="/issue/:id"
        element={
          <AuthLayout>
            <BookPage />
          </AuthLayout>
        }
      />
    </Routes>
  )
}

export default function App() {
  return <AppRoutes />
}
