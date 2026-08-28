'use client'

import { useState, useRef, useEffect } from 'react'
import { useRouter, usePathname } from 'next/navigation'
import Link from 'next/link'
import {
  Home,
  Search,
  BookOpen,
  Library,
  Zap,
  ScanLine,
  LogOut,
  ChevronRight,
  MoreVertical,
  RefreshCw,
  RotateCcw,
  Settings,
  X,
  Plus,
} from 'lucide-react'
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuAction,
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarSeparator,
} from '@/components/ui/sidebar'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useAuthStore } from '@/store/auth'
import { libraries as librariesApi } from '@/api/client'
import { cn } from '@/lib/utils'
import type { Library as LibraryType, ScanTask } from '@/types'

interface AppSidebarProps {
  libraries: LibraryType[]
  activeTasks: Record<string, ScanTask>
}

const NAV_ITEMS = [
  { to: '/', label: 'Home', icon: Home, end: true },
  { to: '/search', label: 'Search', icon: Search, end: false },
  { to: '/books', label: 'All Books', icon: BookOpen, end: false },
]

export function AppSidebar({ libraries, activeTasks }: AppSidebarProps) {
  const pathname = usePathname() ?? ''
  const router = useRouter()
  const logout = useAuthStore((s) => s.logout)
  const isAdmin = useAuthStore((s) => s.isAdmin)
  const totalTasks = Object.values(activeTasks)

  const [scanning, setScanning] = useState<Set<string>>(new Set())
  const [settingsLib, setSettingsLib] = useState<LibraryType | null>(null)
  const [sfFolders, setSfFolders] = useState<string[]>([])
  const [sfInput, setSfInput] = useState('')
  const [sfSaving, setSfSaving] = useState(false)
  const sfInputRef = useRef<HTMLInputElement>(null)

  const openSettings = (lib: LibraryType) => {
    setSettingsLib(lib)
    setSfFolders(lib.standalone_folders ?? [])
    setSfInput('')
  }

  const addFolder = () => {
    const val = sfInput.trim()
    if (!val || sfFolders.includes(val)) return
    setSfFolders((f) => [...f, val])
    setSfInput('')
    sfInputRef.current?.focus()
  }

  const removeFolder = (folder: string) => setSfFolders((f) => f.filter((x) => x !== folder))

  const handleSaveFolders = async () => {
    if (!settingsLib) return
    setSfSaving(true)
    try {
      await librariesApi.update(settingsLib.id, { standalone_folders: sfFolders })
      setSettingsLib(null)
    } finally {
      setSfSaving(false)
    }
  }

  useEffect(() => {
    setScanning((s) => {
      if (s.size === 0) return s
      const next = new Set(s)
      let changed = false
      for (const libId of s) {
        if (activeTasks[libId]) { next.delete(libId); changed = true }
      }
      return changed ? next : s
    })
  }, [activeTasks])

  const handleScan = async (libId: string, force = false) => {
    setScanning((s) => new Set(s).add(libId))
    try {
      await librariesApi.scan(libId, force)
    } catch {
      setScanning((s) => { const next = new Set(s); next.delete(libId); return next })
    }
  }

  function handleLogout() {
    logout().catch(() => {}).finally(() => router.push('/login'))
  }

  function isNavActive(to: string, end: boolean) {
    if (end) return pathname === to
    return pathname.startsWith(to)
  }

  function isLibraryActive(id: string) {
    return pathname === `/library/${id}`
  }

  return (
    <Sidebar collapsible="offcanvas">
      {/* ── Logo ────────────────────────────────────────────────────────── */}
      <SidebarHeader>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              size="lg"
              className="cursor-default hover:bg-transparent active:bg-transparent"
            >
              <div className="flex items-center justify-center w-7 h-7 rounded-lg bg-volt/20 border border-volt/40 glow-volt shrink-0">
                <Zap className="w-3.5 h-3.5 text-volt-3" />
              </div>
              <span className="font-display font-bold text-base tracking-tight text-prose">
                Stashix
              </span>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>

      <SidebarContent>
        {/* ── Main navigation ─────────────────────────────────────────────── */}
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu>
              {NAV_ITEMS.map(({ to, label, icon: Icon, end }) => (
                <SidebarMenuItem key={to}>
                  <SidebarMenuButton
                    asChild
                    isActive={isNavActive(to, end)}
                    className={cn(
                      isNavActive(to, end) && 'sidebar-active-glow'
                    )}
                  >
                    <Link href={to}>
                      <Icon />
                      <span>{label}</span>
                    </Link>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>

        {/* ── Libraries ────────────────────────────────────────────────────── */}
        {libraries.length > 0 && (
          <>
            <SidebarSeparator />
            <SidebarGroup>
              <SidebarGroupLabel className="flex items-center gap-1.5">
                <Library className="w-3 h-3" />
                Libraries
              </SidebarGroupLabel>
              <SidebarGroupContent>
                <SidebarMenu>
                  {libraries.map((lib) => {
                    const task = activeTasks[lib.id]
                    const pct =
                      task && task.total > 0
                        ? Math.round((task.scanned / task.total) * 100)
                        : null
                    const active = isLibraryActive(lib.id)

                    const isScanning = !!task || scanning.has(lib.id)

                    return (
                      <SidebarMenuItem key={lib.id}>
                        <SidebarMenuButton
                          asChild
                          isActive={active}
                          className={cn(active && 'sidebar-active-glow')}
                        >
                          <Link href={`/library/${lib.id}`}>
                            <ChevronRight className="w-3 h-3 opacity-50" />
                            <span>{lib.name}</span>
                          </Link>
                        </SidebarMenuButton>
                        {(scanning.has(lib.id) && !task) || (task && task.total === 0) ? (
                          <SidebarMenuBadge className={cn('text-volt-3', isAdmin && 'right-7')}>
                            <div className="w-2.5 h-2.5 rounded-full border border-volt-3 border-t-transparent animate-spin" />
                          </SidebarMenuBadge>
                        ) : pct !== null ? (
                          <SidebarMenuBadge className={cn('text-volt-3 font-mono text-[10px]', isAdmin && 'right-7')}>
                            {pct}%
                          </SidebarMenuBadge>
                        ) : null}
                        {isAdmin && (
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <SidebarMenuAction aria-label="Library actions">
                                <MoreVertical className="w-3.5 h-3.5" />
                              </SidebarMenuAction>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent side="right" align="start">
                              <DropdownMenuItem
                                onClick={() => handleScan(lib.id)}
                                disabled={isScanning}
                              >
                                <RefreshCw className="w-3.5 h-3.5 mr-2" />
                                Scan for new files
                              </DropdownMenuItem>
                              <DropdownMenuItem
                                onClick={() => handleScan(lib.id, true)}
                                disabled={isScanning}
                              >
                                <RotateCcw className="w-3.5 h-3.5 mr-2" />
                                Force rescan
                              </DropdownMenuItem>
                              <DropdownMenuItem onClick={() => openSettings(lib)}>
                                <Settings className="w-3.5 h-3.5 mr-2" />
                                Settings
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>
                        )}
                      </SidebarMenuItem>
                    )
                  })}
                </SidebarMenu>
              </SidebarGroupContent>
            </SidebarGroup>
          </>
        )}

        {/* ── Active scans ─────────────────────────────────────────────────── */}
        {(totalTasks.length > 0 || scanning.size > 0) && (
          <>
            <SidebarSeparator />
            <SidebarGroup>
              <SidebarGroupLabel className="flex items-center gap-1.5 text-plasma/80">
                <ScanLine className="w-3 h-3" />
                Scanning
              </SidebarGroupLabel>
              <SidebarGroupContent>
                <div className="px-2 space-y-2">
                  {[...scanning].filter((id) => !activeTasks[id]).map((libId) => {
                    const lib = libraries.find((l) => l.id === libId)
                    return (
                      <div key={libId} className="flex items-center gap-2">
                        <span className="text-[11px] text-muted-foreground truncate flex-1">
                          {lib?.name ?? 'Library'}
                        </span>
                        <div className="w-3 h-3 rounded-full border border-volt-3 border-t-transparent animate-spin shrink-0" />
                      </div>
                    )
                  })}
                  {totalTasks.map((t) => {
                    const lib = libraries.find((l) => l.id === t.library_id)
                    if (t.total === 0) {
                      return (
                        <div key={t.library_id} className="flex items-center gap-2">
                          <span className="text-[11px] text-muted-foreground truncate flex-1">
                            {lib?.name ?? 'Library'}
                          </span>
                          <div className="w-3 h-3 rounded-full border border-volt-3 border-t-transparent animate-spin shrink-0" />
                        </div>
                      )
                    }
                    const pct = Math.round((t.scanned / t.total) * 100)
                    return (
                      <div key={t.library_id}>
                        <div className="flex justify-between text-[11px] mb-1">
                          <span className="text-muted-foreground truncate">
                            {lib?.name ?? 'Library'}
                          </span>
                          <span className="text-volt-3 font-mono ml-2 shrink-0">{pct}%</span>
                        </div>
                        <div className="h-1 rounded-full bg-border overflow-hidden">
                          <div
                            className="h-full rounded-full shimmer-bar transition-all duration-300"
                            style={{ width: `${pct}%` }}
                          />
                        </div>
                      </div>
                    )
                  })}
                </div>
              </SidebarGroupContent>
            </SidebarGroup>
          </>
        )}
      </SidebarContent>

      {/* ── Footer ──────────────────────────────────────────────────────────── */}
      <SidebarFooter>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              onClick={handleLogout}
              className="text-muted-foreground hover:text-foreground"
            >
              <LogOut />
              <span>Sign out</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarFooter>
      <Sheet open={!!settingsLib} onOpenChange={(open) => !open && setSettingsLib(null)}>
        <SheetContent side="right" className="w-full sm:max-w-md flex flex-col gap-0">
          <SheetHeader className="px-6 pt-6 pb-4 border-b border-border">
            <SheetTitle className="font-display text-base">
              {settingsLib?.name} — Settings
            </SheetTitle>
          </SheetHeader>

          <div className="flex-1 overflow-y-auto px-6 py-5 space-y-6">
            <div>
              <p className="text-sm font-medium text-foreground mb-1">Standalone book folders</p>
              <p className="text-xs text-muted-foreground mb-3">
                Files whose immediate parent folder matches one of these names are always treated as standalone books, regardless of directory structure.
              </p>

              <div className="flex gap-2 mb-3">
                <Input
                  ref={sfInputRef}
                  placeholder="e.g. One-Shot"
                  value={sfInput}
                  onChange={(e) => setSfInput(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && addFolder()}
                  className="text-sm h-8"
                />
                <Button size="sm" variant="outline" onClick={addFolder} className="shrink-0 h-8 px-2">
                  <Plus className="w-3.5 h-3.5" />
                </Button>
              </div>

              {sfFolders.length > 0 ? (
                <div className="flex flex-wrap gap-1.5">
                  {sfFolders.map((f) => (
                    <span
                      key={f}
                      className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-muted text-xs text-foreground"
                    >
                      {f}
                      <button
                        onClick={() => removeFolder(f)}
                        className="text-muted-foreground hover:text-foreground transition-colors"
                        aria-label={`Remove ${f}`}
                      >
                        <X className="w-3 h-3" />
                      </button>
                    </span>
                  ))}
                </div>
              ) : (
                <p className="text-xs text-muted-foreground italic">No standalone folders configured.</p>
              )}
            </div>
          </div>

          <div className="px-6 py-4 border-t border-border flex justify-end gap-2">
            <Button variant="ghost" size="sm" onClick={() => setSettingsLib(null)}>
              Cancel
            </Button>
            <Button size="sm" onClick={handleSaveFolders} disabled={sfSaving}>
              {sfSaving ? 'Saving…' : 'Save'}
            </Button>
          </div>
        </SheetContent>
      </Sheet>
    </Sidebar>
  )
}
