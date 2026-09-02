import { create } from 'zustand'
import { transport } from '@/api/transport'
import { getAuthTokens, setAuthTokens, clearAuthTokens } from '@/lib/auth-cookie'

interface UserProfile {
  username: string
  email: string
  firstName: string
  lastName: string
  isAdmin: boolean
  isStaff: boolean
}

interface AuthState {
  isAuthenticated: boolean
  isLoading: boolean
  isAdmin: boolean
  profile: UserProfile | null
  login: (email: string, password: string) => Promise<void>
  logout: () => Promise<void>
  restore: () => Promise<void>
}

async function fetchProfile(): Promise<UserProfile | null> {
  try {
    const { user } = await import('@/api/client')
    const p = await user.profile()
    return {
      username: p.username,
      email: p.email,
      firstName: p.first_name,
      lastName: p.last_name,
      isAdmin: p.is_admin,
      isStaff: p.is_staff,
    }
  } catch {
    return null
  }
}

export const useAuthStore = create<AuthState>((set) => ({
  isAuthenticated: false,
  isLoading: true,
  isAdmin: false,
  profile: null,

  async login(email, password) {
    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    })
    if (!res.ok) throw new Error('Invalid credentials')
    const { access_token, refresh_token } = await res.json() as { access_token: string; refresh_token: string }
    setAuthTokens({ access_token, refresh_token })
    transport.setToken(access_token)
    set({ isAuthenticated: true, isLoading: false })
    fetchProfile().then((profile) => {
      if (profile) set({ isAdmin: profile.isAdmin, profile })
    })
  },

  async logout() {
    clearAuthTokens()
    transport.clearToken()
    set({ isAuthenticated: false, isLoading: false, isAdmin: false, profile: null })
    fetch('/api/auth/logout', { method: 'POST' }).catch(() => {})
  },

  async restore() {
    try {
      const tokens = getAuthTokens()
      if (!tokens?.access_token) {
        set({ isAuthenticated: false, isLoading: false })
        return
      }
      transport.setToken(tokens.access_token)
      set({ isAuthenticated: true })
      fetchProfile().then((profile) => {
        if (profile) set({ isAdmin: profile.isAdmin, profile })
      })
    } catch {
      set({ isAuthenticated: false })
    } finally {
      set({ isLoading: false })
    }
  },
}))
