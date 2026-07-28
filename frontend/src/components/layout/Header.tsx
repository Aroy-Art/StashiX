import { useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { Search, Settings } from 'lucide-react'
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

export function Header() {
  const navigate = useNavigate()
  const logout = useAuthStore((s) => s.logout)
  const isAdmin = useAuthStore((s) => s.isAdmin)
  const searchRef = useRef<HTMLInputElement>(null)

  function handleSearchSubmit(e: React.FormEvent) {
    e.preventDefault()
    const q = searchRef.current?.value.trim()
    if (q) navigate(`/search?q=${encodeURIComponent(q)}`)
  }

  function handleLogout() {
    logout()
    navigate('/login')
  }

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
            onClick={() => navigate('/settings')}
          >
            <Settings />
          </Button>
        )}

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button className="focus:outline-none rounded-full focus:ring-2 focus:ring-ring/50 ml-1">
              <Avatar className="h-6 w-6 cursor-pointer ring-1 ring-border hover:ring-ring transition-all duration-200">
                <AvatarFallback className="text-[10px]">U</AvatarFallback>
              </Avatar>
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-40">
            <DropdownMenuLabel>My account</DropdownMenuLabel>
            <DropdownMenuSeparator />
            <DropdownMenuItem
              className="text-destructive focus:text-destructive"
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
