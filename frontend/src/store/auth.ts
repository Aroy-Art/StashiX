import { create } from 'zustand'
import { auth as authApi, user as userApi } from '../api/client'

interface UserProfile {
  username: string
  email: string
  firstName: string
  lastName: string
  isAdmin: boolean
  isStaff: boolean
}

interface AuthState {
  token: string | null
  isAdmin: boolean
  profile: UserProfile | null
  login: (email: string, password: string) => Promise<void>
  logout: () => void
  restore: () => void
  fetchProfile: () => Promise<void>
}

function parseRole(token: string): string {
  try {
    const payload = JSON.parse(atob(token.split('.')[1]))
    return payload.role ?? 'user'
  } catch {
    return 'user'
  }
}

export const useAuthStore = create<AuthState>((set) => ({
  token: null,
  isAdmin: false,
  profile: null,

  async fetchProfile() {
    try {
      const p = await userApi.profile()
      set({
        isAdmin: p.is_admin,
        profile: {
          username: p.username,
          email: p.email,
          firstName: p.first_name,
          lastName: p.last_name,
          isAdmin: p.is_admin,
          isStaff: p.is_staff,
        },
      })
    } catch {
      // profile fetch is best-effort
    }
  },

  async login(email, password) {
    const pair = await authApi.login(email, password)
    const role = parseRole(pair.access_token)
    set({ token: pair.access_token, isAdmin: role === 'admin' })
    try {
      const p = await userApi.profile()
      set({
        isAdmin: p.is_admin,
        profile: {
          username: p.username,
          email: p.email,
          firstName: p.first_name,
          lastName: p.last_name,
          isAdmin: p.is_admin,
          isStaff: p.is_staff,
        },
      })
    } catch {
      // profile fetch is best-effort
    }
  },

  logout() {
    authApi.logout()
    set({ token: null, isAdmin: false, profile: null })
  },

  restore() {
    const token = authApi.restoreSession()
    if (token) {
      const role = parseRole(token)
      set({ token, isAdmin: role === 'admin' })
    }
  },
}))
