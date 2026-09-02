import { NextRequest, NextResponse } from 'next/server'

const PUBLIC_PATHS = ['/login', '/setup']

export async function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl

  if (PUBLIC_PATHS.some((p) => pathname.startsWith(p))) return NextResponse.next()

  try {
    const apiUrl = process.env.GO_API_URL ?? 'http://localhost:8080'
    const res = await fetch(`${apiUrl}/api/setup/status`, {
      next: { revalidate: 60 },
    })
    if (res.ok) {
      const { needs_setup } = (await res.json()) as { needs_setup: boolean }
      if (needs_setup) return NextResponse.redirect(new URL('/setup', req.url))
    }
  } catch {
    // Go unreachable — allow through
  }

  const raw = req.cookies.get('auth_tokens')?.value
  let token: string | null = null
  if (raw) {
    try {
      const parsed = JSON.parse(decodeURIComponent(raw)) as { access_token: string }
      token = parsed.access_token ?? null
    } catch {}
  }
  if (!token) return NextResponse.redirect(new URL('/login', req.url))

  return NextResponse.next()
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|api/).*)'],
}
