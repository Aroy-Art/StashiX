# Next.js Migration Plan

Migrating from Vite SPA + React Router v6 → Next.js 15 App Router + TanStack Query v5.

## Decisions

- **Image auth**: Next.js proxy route (`/api/covers/[id]`) reads httpOnly cookie, streams from Go API
- **WS dev proxy**: nginx in `docker-compose.dev.yml` handles both HTTP and WS upgrade
- **Backend changes**: minimal; only if frontend-only approach is worse

---

## Phase 0 — Prep (no visible changes)

Fix SSR hazards before touching Next.js.

- [x] `transport.ts`: move `location.protocol` eval inside `getWsUrl()` method (called at connect time, not module load)
- [x] `thumbnail.ts`: guard `window.devicePixelRatio` with `typeof window !== 'undefined'`
- [x] `client.ts`: audit all `localStorage.getItem('access_token')` call sites — tag each with `// TODO: Phase 2 cookie` comment
- [x] `pages/ReaderPage.tsx`: find `localStorage` reads in `useState()` initializers — wrap with `typeof window !== 'undefined'`
- [x] `components.json`: set `"rsc": true`

---

## Phase 1 — Install Next.js, Wire Routing

All pages stay `'use client'`. No SSR yet. Routing works. Auth guard via middleware.

### Package changes
- [x] Remove: `vite`, `@vitejs/plugin-react`, `@tailwindcss/vite`, `react-router-dom`
- [x] Add: `next@^15`, `@tanstack/react-query@^5`
- [x] Add dev: `@tanstack/react-query-devtools@^5`
- [x] Swap Tailwind integration: add `postcss.config.mjs` with `@tailwindcss/postcss`

### Config files
- [x] Create `next.config.ts` with API rewrites to Go backend + env var `GO_API_URL`
- [x] Update `tsconfig.json` for Next.js (add `"jsx": "preserve"`, paths, `moduleResolution: "bundler"`)
- [x] Delete `vite.config.ts`, `index.html`
- [x] Rename `src/index.css` → `src/app/globals.css`

### App directory structure
- [x] Create `src/app/layout.tsx` — server component shell wrapping `QueryProvider`, `ThemeProvider`, `TransportProvider`
- [x] Create `src/app/(auth)/layout.tsx` — `'use client'`, renders `AppLayout`
- [x] Move `LibrariesPage` → `src/app/(auth)/page.tsx` + add `'use client'`
- [x] Move `LibraryPage` → `src/app/(auth)/library/[id]/page.tsx` + add `'use client'`
- [x] Move `BookPage` → `src/app/(auth)/book/[id]/page.tsx` + `src/components/pages/BookPageContent.tsx`
- [x] Move `BookPage` (reuse) → `src/app/(auth)/issue/[id]/page.tsx` + add `'use client'`
- [x] Move `SeriesPage` → `src/app/(auth)/series/[id]/page.tsx` + add `'use client'`
- [x] Move `SearchPage` → `src/app/(auth)/search/page.tsx` — wrap in `<Suspense>` (required by `useSearchParams`)
- [x] Move `ReaderPage` → `src/app/read/[id]/page.tsx` + add `'use client'` (no auth layout)
- [x] Move `LoginPage` → `src/app/login/page.tsx` + add `'use client'`
- [x] Move `SetupPage` → `src/app/setup/page.tsx` + add `'use client'`

### Providers
- [x] Create `src/providers/QueryProvider.tsx` — `'use client'`, creates `QueryClient` in `useState`
- [x] Create `src/providers/ThemeProvider.tsx` — `'use client'`, applies dark class on `<html>`
- [x] Create `src/providers/TransportProvider.tsx` — `'use client'`, calls `restore()` on mount

### Middleware
- [x] Create `src/middleware.ts`:
  - Check setup status (`/api/setup/status`) with `next: { revalidate: 60 }`
  - Redirect to `/setup` if `needs_setup`
  - Auth check deferred to Phase 2 (client-side guard in `(auth)/layout.tsx` for Phase 1)
  - Pass through: `/login`, `/setup`, `/_next/*`

### React Router → Next.js navigation
- [x] Replace all `import { Link } from 'react-router-dom'` → `import Link from 'next/link'`
- [x] Replace all `useNavigate()` + `navigate('/path')` → `useRouter()` + `router.push('/path')`
- [x] Replace all `navigate(-1)` → `router.back()`
- [x] Replace all `useParams()` from react-router → `useParams<{ id: string }>()` from `next/navigation`
- [x] Replace `useSearchParams()` from react-router → `useSearchParams()` from `next/navigation`
- [x] Replace `NavLink` in `AppSidebar` → `Link` + `usePathname()` for active state
- [x] Remove `<BrowserRouter>` — deleted `src/main.tsx`, `src/App.tsx`, `src/pages/`

### Dev infrastructure
- [x] Add `nginx` service to `docker-compose.dev.yml` — proxy HTTP to Next.js dev server, WebSocket to Go backend
- [x] Create `nginx/dev.conf` with upstream blocks for both services and `location /ws` with upgrade headers

---

## Phase 2 — Auth Cookie Migration

Replace localStorage JWT with httpOnly cookies. Blocks: reader (page image URLs), cover images.

### Next.js Route Handlers
- [x] Create `app/api/auth/login/route.ts` — POST: calls Go API, sets `access_token` + `refresh_token` cookies
- [x] Create `app/api/auth/logout/route.ts` — POST: clears cookies
- [x] Create `app/api/auth/refresh/route.ts` — POST: reads refresh cookie, calls Go API, sets new cookies, returns `{ access_token }` in body (needed to update transport in-memory token)
- [x] Create `app/api/ws-token/route.ts` — GET: reads `access_token` cookie, returns `{ token }` (protected by middleware)
- [x] Create `app/api/covers/books/[bookId]/route.ts` + `app/api/covers/series/[seriesId]/route.ts` — GET: reads cookie, proxies cover images from Go API
- [x] Create `app/api/pages/[bookId]/[page]/route.ts` — GET: reads cookie, proxies page images from Go API (used by reader)
- [x] Create `app/api/auth/setup/route.ts` — POST: forwards to Go `/api/setup`, sets cookies, returns `{ access_token }`

### Store + client changes
- [x] `src/store/auth.ts`: remove token fields + localStorage reads; keep `isAdmin`, `profile`, `isAuthenticated`, `isLoading`
- [x] `src/api/client.ts`: interceptor reads `transport.getToken()` instead of localStorage; `coverUrl()` returns `/api/covers/books/{id}`; `series.coverUrl()` returns `/api/covers/series/{id}`; `pages()` returns `/api/pages/{bookId}/{n}` URLs
- [x] `src/api/transport.ts`: add `getToken()`; `tryRefresh()` POSTs to `/api/auth/refresh` (no body, reads cookie server-side), calls `this.setToken(data.access_token)`
- [x] `src/providers/TransportProvider.tsx`: `restore()` is now async, awaited on mount
- [x] `app/login/page.tsx`: auth store `login()` now POSTs to `/api/auth/login`, seeds transport from response
- [x] `app/setup/page.tsx`: AccountStep POSTs to `/api/auth/setup`, LibraryStep uses `librariesApi.create()`
- [x] `src/middleware.ts`: added `access_token` cookie check for auth guard (server-side redirect to /login)
- [x] `src/app/(auth)/layout.tsx`: checks `isAuthenticated` + `isLoading` instead of `token`

### Server-side fetch helper
- [x] Create `src/api/server.ts` — `serverFetch()` reads `access_token` cookie via `next/headers`, forwards as `Authorization` header to Go API

---

## Phase 3 — TanStack Query

Replace `useState + useEffect + fetch` pairs. One page at a time.

- [x] Create `src/lib/query-keys.ts` with typed key factories for all entities
- [x] `BookPage`: `useQuery({ queryKey: queryKeys.book(id), queryFn: () => booksApi.get(id) })`
- [x] `SeriesPage`: `useQuery` for series data
- [x] `SearchPage`: `useQuery` with `enabled: !!q` + `placeholderData: keepPreviousData`; URL drives query
- [x] `LibraryPage` initial load: `useQuery` for books list, library (via select), deleted books, tasks
- [x] `LibraryPage` WS events: `transport.on('book_added')` → `queryClient.setQueryData()` prepend to cache
- [x] `scan_progress` WS subscription centralized in `AppLayout` → `queryClient.setQueryData(queryKeys.tasks())`; on done, `invalidateQueries(queryKeys.libraries())`
- [x] `LibrariesPage`: `useQuery` for libraries + tasks (cache hits from AppLayout); `useQueries` for 4×N per-library content; WS `book_added` → `setQueryData` per-library caches
- [x] `AppLayout`: `useQuery` for libraries + tasks; centralized `scan_progress` WS subscription
- [x] Remove orphaned `useState + useEffect` data-fetch patterns across all converted pages
- [x] Add `ReactQueryDevtools` in `QueryProvider` (dev only, dynamic import with `ssr: false`)

---

## Phase 4 — Cleanup + Optimize

- [x] Delete old `src/pages/` directory (all moved to `app/`)
- [ ] Add `next/image` for cover images via proxy route (`/api/covers/[bookId]`) for CDN optimization
- [x] `BookPage`: add `HydrationBoundary` server prefetch for book metadata (faster initial paint)
- [x] `IssuePage`: same server prefetch (shares `BookPageContent`)
- [x] `SeriesPage`: same server prefetch (extracted `SeriesPageContent` client component)
- [x] `ThemeProvider`: read initial theme from cookie (set by middleware) to eliminate flash of wrong theme
- [x] `@fontsource-variable` imports → `next/font` for optimized font loading (Syne + DM Sans via `next/font/google`)
- [ ] Update `components.json` path aliases if `src/` structure changed

---

## Architecture Notes

### File structure (target)
```
frontend/
├── app/
│   ├── layout.tsx                    # Server: wraps providers
│   ├── globals.css
│   ├── middleware.ts                 # Auth + setup guard
│   ├── (auth)/
│   │   ├── layout.tsx                # 'use client': AppLayout
│   │   ├── page.tsx                  # LibrariesPage
│   │   ├── library/[id]/page.tsx
│   │   ├── book/[id]/page.tsx
│   │   ├── issue/[id]/page.tsx
│   │   ├── series/[id]/page.tsx
│   │   └── search/page.tsx
│   ├── read/[id]/page.tsx            # No auth layout (full-screen reader)
│   ├── login/page.tsx
│   ├── setup/page.tsx
│   └── api/
│       ├── auth/login/route.ts
│       ├── auth/logout/route.ts
│       ├── auth/refresh/route.ts
│       ├── ws-token/route.ts
│       ├── covers/[bookId]/route.ts
│       └── pages/[bookId]/route.ts
├── src/
│   ├── api/
│   │   ├── transport.ts              # Modified
│   │   ├── client.ts                 # Modified
│   │   └── server.ts                 # NEW
│   ├── components/                   # Unchanged structure
│   ├── lib/
│   │   └── query-keys.ts             # NEW
│   ├── providers/
│   │   ├── QueryProvider.tsx         # NEW
│   │   ├── ThemeProvider.tsx         # NEW
│   │   └── TransportProvider.tsx     # NEW
│   ├── store/
│   │   ├── auth.ts                   # Modified
│   │   └── theme.ts
│   └── types/
│       └── index.ts
├── nginx/
│   └── dev.conf                      # NEW
├── next.config.ts                    # NEW
├── postcss.config.mjs                # NEW
└── docker-compose.dev.yml            # Modified: add nginx service
```

### WS + TanStack Query pattern (LibraryPage)
```typescript
// Initial data via TanStack Query
const { data: books } = useQuery({
  queryKey: queryKeys.libraryBooks(id),
  queryFn: () => booksApi.list(id),
})

// WS push → update cache directly (no separate React state)
useEffect(() => {
  const off = transport.on('book_added', async (payload) => {
    const newBook = await booksApi.get(payload.book_id)
    queryClient.setQueryData(queryKeys.libraryBooks(id), (old) =>
      old ? [newBook, ...old] : [newBook]
    )
  })
  return off
}, [id, queryClient])
```

### Risks
1. **HIGH** — After refresh, transport in-memory token goes stale. Fix: `/api/auth/refresh` returns new token in body; caller does `transport.setToken(data.access_token)`.
2. **HIGH** — Reader page images use `?token=` query params. Blocked until `/api/pages/` proxy route is live (Phase 2).
3. **MEDIUM** — Middleware setup-check adds latency. Mitigate with `revalidate: 60` + set a cookie after setup completes so check is skipped.
4. **LOW** — Bun compatible with Next.js 15. No issue.
