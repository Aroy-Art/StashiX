import { useState, useEffect } from 'react'
import { SidebarInset, SidebarProvider } from '@/components/ui/sidebar'
import { AppSidebar } from './AppSidebar'
import { Header } from './Header'
import { libraries as librariesApi, tasks as tasksApi } from '@/api/client'
import { transport } from '@/api/transport'
import type { Library, ScanTask } from '@/types'

interface AppLayoutProps {
  children: React.ReactNode
}

export function AppLayout({ children }: AppLayoutProps) {
  const [libraries, setLibraries] = useState<Library[]>([])
  const [activeTasks, setActiveTasks] = useState<Record<string, ScanTask>>({})

  useEffect(() => {
    librariesApi.list().then((libs) => setLibraries(libs ?? []))
    tasksApi.list().then((ts) => {
      const map: Record<string, ScanTask> = {}
      for (const t of ts) map[t.library_id] = t
      setActiveTasks(map)
    }).catch(() => {})
  }, [])

  useEffect(() => {
    return transport.on('scan_progress', (payload) => {
      const t = payload as ScanTask
      setActiveTasks((prev) => {
        const next = { ...prev }
        if (t.done) delete next[t.library_id]
        else next[t.library_id] = t
        return next
      })
    })
  }, [])

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
