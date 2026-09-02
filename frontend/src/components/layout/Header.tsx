'use client'

import { useRef } from 'react'
import { useRouter } from 'next/navigation'
import { Search, Settings, Sun, Moon } from 'lucide-react'
import { SidebarTrigger } from '@/components/ui/sidebar'
import { Button } from '@/components/ui/button'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Separator } from '@/components/ui/separator'
import { useAuthStore } from '@/store/auth'
import { useThemeStore } from '@/store/theme'

function initials(firstName: string, lastName: string, username: string): string {
  if (firstName || lastName) {
    return ((firstName[0] ?? '') + (lastName[0] ?? '')).toUpperCase() || username[0]?.toUpperCase() || 'U'
  }
  return username.slice(0, 2).toUpperCase() || 'U'
}

export function Header() {
  const router = useRouter()
  const logout = useAuthStore((s) => s.logout)
  const isAdmin = useAuthStore((s) => s.isAdmin)
  const profile = useAuthStore((s) => s.profile)
  const { theme, toggleTheme } = useThemeStore()
  const searchRef = useRef<HTMLInputElement>(null)

  function handleSearchSubmit(e: React.FormEvent) {
    e.preventDefault()
    const q = searchRef.current?.value.trim()
    if (q) router.push(`/search?q=${encodeURIComponent(q)}`)
  }

  function handleLogout() {
    logout().catch(() => {}).finally(() => router.push('/login'))
  }

  const avatarInitials = profile
    ? initials(profile.firstName, profile.lastName, profile.username)
    : 'U'

  return (
    <header className="flex shrink-0 items-center gap-2 px-4 h-12 border-b border-border bg-background/80 backdrop-blur-md">
      <SidebarTrigger className="-ml-1" />
      <Separator orientation="vertical" className="h-4 mx-1" />

      {/* Search */}
      <form onSubmit={handleSearchSubmit} className="flex-1 max-w-md">
        <div className="relative">
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-muted-foreground pointer-events-none" />
          <input
            ref={searchRef}
            type="text"
            placeholder="Search titles, series, publishers…"
            className="
              w-full h-7 rounded-md bg-muted/40 border border-border px-3 pl-8 pr-14
              text-xs text-foreground placeholder:text-muted-foreground
              focus:outline-none focus:border-ring focus:ring-2 focus:ring-ring/30
              transition-colors duration-150
            "
          />
          <kbd className="absolute right-2 top-1/2 -translate-y-1/2 hidden sm:flex items-center gap-0.5 px-1.5 py-0.5 rounded text-[9px] font-mono text-muted-foreground bg-muted border border-border">
            ⌘K
          </kbd>
        </div>
      </form>

      <div className="ml-auto flex items-center gap-1">
        {isAdmin && (
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label="Settings"
            onClick={() => router.push('/settings')}
          >
            <Settings />
          </Button>
        )}

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button className="focus:outline-none rounded-full focus:ring-2 focus:ring-ring/50 ml-1">
              <Avatar className="h-6 w-6 cursor-pointer ring-1 ring-border hover:ring-ring transition-all duration-200">
                <AvatarFallback className="text-[10px]">{avatarInitials}</AvatarFallback>
              </Avatar>
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-48">
            <DropdownMenuLabel className="font-normal">
              <div className="flex items-center gap-1.5">
                <p className="text-sm font-medium leading-none">{profile?.username ?? 'Account'}</p>
                {profile?.isAdmin && (
                  <span className="inline-flex items-center rounded-sm bg-violet-500/15 px-1.5 py-0.5 text-[10px] font-medium text-violet-400 ring-1 ring-inset ring-violet-500/30">
                    Admin
                  </span>
                )}
                {!profile?.isAdmin && profile?.isStaff && (
                  <span className="inline-flex items-center rounded-sm bg-sky-500/15 px-1.5 py-0.5 text-[10px] font-medium text-sky-400 ring-1 ring-inset ring-sky-500/30">
                    Staff
                  </span>
                )}
              </div>
              {profile?.email && (
                <p className="text-xs text-muted-foreground mt-1 truncate">{profile.email}</p>
              )}
            </DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuItem onClick={toggleTheme}>
              {theme === 'dark'
                ? <><Sun className="w-3.5 h-3.5" /> Switch to light</>
                : <><Moon className="w-3.5 h-3.5" /> Switch to dark</>
              }
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem
              className="text-destructive focus:text-destructive focus:bg-destructive/10"
              onClick={handleLogout}
            >
              Sign out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  )
}
