import { create } from 'zustand'

export type Theme = 'dark' | 'light'

function getStored(): Theme {
  try { return (localStorage.getItem('theme') as Theme) || 'dark' } catch { return 'dark' }
}

function apply(t: Theme) {
  document.documentElement.classList.toggle('dark', t === 'dark')
  try {
    localStorage.setItem('theme', t)
    document.cookie = `theme=${t}; path=/; SameSite=Lax; max-age=31536000`
  } catch {}
}

interface ThemeState {
  theme: Theme
  setTheme: (t: Theme) => void
  toggleTheme: () => void
}

export const useThemeStore = create<ThemeState>((set, get) => ({
  theme: getStored(),
  setTheme(t) { apply(t); set({ theme: t }) },
  toggleTheme() { get().setTheme(get().theme === 'dark' ? 'light' : 'dark') },
}))
