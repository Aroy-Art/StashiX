'use client'

import { useEffect } from 'react'
import { useThemeStore } from '@/store/theme'

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const theme = useThemeStore((s) => s.theme)

  useEffect(() => {
    document.documentElement.classList.toggle('dark', theme === 'dark')
  }, [theme])

  return <>{children}</>
}
