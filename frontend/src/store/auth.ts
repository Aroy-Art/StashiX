import { create } from 'zustand'
import { auth as authApi } from '../api/client'

interface AuthState {
  token: string | null
  isAdmin: boolean
  login: (email: string, password: string) => Promise<void>
  logout: () => void
  restore: () => void
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

  async login(email, password) {
    const pair = await authApi.login(email, password)
    const role = parseRole(pair.access_token)
    set({ token: pair.access_token, isAdmin: role === 'admin' })
  },

  logout() {
    authApi.logout()
    set({ token: null, isAdmin: false })
  },

  restore() {
    const token = authApi.restoreSession()
    if (token) {
      const role = parseRole(token)
      set({ token, isAdmin: role === 'admin' })
    }
  },
}))
