'use client'

import { useEffect } from 'react'
import { useAuthStore } from '@/store/auth'

export function TransportProvider({ children }: { children: React.ReactNode }) {
  const restore = useAuthStore((s) => s.restore)

  useEffect(() => {
    restore().catch(() => {})
  }, [restore])

  return <>{children}</>
}
