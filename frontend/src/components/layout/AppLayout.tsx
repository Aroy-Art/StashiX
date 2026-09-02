'use client'

import { useEffect } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { SidebarInset, SidebarProvider } from '@/components/ui/sidebar'
import { AppSidebar } from './AppSidebar'
import { Header } from './Header'
import { libraries as librariesApi, tasks as tasksApi } from '@/api/client'
import { transport } from '@/api/transport'
import { queryKeys } from '@/lib/query-keys'
import type { ScanTask } from '@/types'

export function AppLayout({ children }: { children: React.ReactNode }) {
  const queryClient = useQueryClient()

  const { data: libraries = [] } = useQuery({
    queryKey: queryKeys.libraries(),
    queryFn: () => librariesApi.list(),
  })

  const { data: activeTasks = {} } = useQuery({
    queryKey: queryKeys.tasks(),
    queryFn: async () => {
      const ts = await tasksApi.list()
      return Object.fromEntries(ts.map((t) => [t.library_id, t])) as Record<string, ScanTask>
    },
  })

  useEffect(() => {
    return transport.on('scan_progress', (payload) => {
      const t = payload as ScanTask
      queryClient.setQueryData(queryKeys.tasks(), (old: Record<string, ScanTask> = {}) => {
        const next = { ...old }
        if (t.done) {
          delete next[t.library_id]
          queryClient.invalidateQueries({ queryKey: queryKeys.libraries() })
        } else {
          next[t.library_id] = t
        }
        return next
      })
    })
  }, [queryClient])

  return (
    <SidebarProvider>
      <AppSidebar libraries={libraries} activeTasks={activeTasks} />
      <SidebarInset className="overflow-hidden">
        <Header />
        <div className="flex-1 overflow-y-auto">
          {children}
        </div>
      </SidebarInset>
    </SidebarProvider>
  )
}
