import { useNavigate, useLocation, NavLink } from 'react-router-dom'
import {
  Home,
  Search,
  BookOpen,
  Library,
  Zap,
  ScanLine,
  LogOut,
  ChevronRight,
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
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarSeparator,
} from '@/components/ui/sidebar'
import { useAuthStore } from '@/store/auth'
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
  const location = useLocation()
  const navigate = useNavigate()
  const logout = useAuthStore((s) => s.logout)
  const totalTasks = Object.values(activeTasks)

  function handleLogout() {
    logout()
    navigate('/login')
  }

  function isNavActive(to: string, end: boolean) {
    if (end) return location.pathname === to
    return location.pathname.startsWith(to)
  }

  function isLibraryActive(id: string) {
    return location.pathname === `/library/${id}`
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
                    <NavLink to={to} end={end}>
                      <Icon />
                      <span>{label}</span>
                    </NavLink>
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

                    return (
                      <SidebarMenuItem key={lib.id}>
                        <SidebarMenuButton
                          asChild
                          isActive={active}
                          className={cn(active && 'sidebar-active-glow')}
                        >
                          <NavLink to={`/library/${lib.id}`}>
                            <ChevronRight className="w-3 h-3 opacity-50" />
                            <span>{lib.name}</span>
                          </NavLink>
                        </SidebarMenuButton>
                        {pct !== null && (
                          <SidebarMenuBadge className="text-volt-3 font-mono text-[10px]">
                            {pct}%
                          </SidebarMenuBadge>
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
        {totalTasks.length > 0 && (
          <>
            <SidebarSeparator />
            <SidebarGroup>
              <SidebarGroupLabel className="flex items-center gap-1.5 text-plasma/80">
                <ScanLine className="w-3 h-3" />
                Scanning
              </SidebarGroupLabel>
              <SidebarGroupContent>
                <div className="px-2 space-y-2">
                  {totalTasks.map((t) => {
                    const lib = libraries.find((l) => l.id === t.library_id)
                    const pct = t.total > 0 ? Math.round((t.scanned / t.total) * 100) : 0
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
    </Sidebar>
  )
}
