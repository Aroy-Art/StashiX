/**
 * WS-first transport with REST fallback.
 *
 * All operations go through send(). If WS is connected, the message is sent
 * over the socket and resolved via correlation ID. If WS is unavailable,
 * the call falls back to a matching REST endpoint.
 */

type Resolver = { resolve: (v: unknown) => void; reject: (e: Error) => void }

const WS_URL = `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws`

// Maps WS message type → REST fallback spec
interface RestFallback {
  method: string
  url: (payload: Record<string, unknown>) => string
  body?: (payload: Record<string, unknown>) => unknown
}

// Types the backend actually handles over WS — everything else goes straight to REST
const WS_TYPES = new Set(['update_progress'])

const REST_FALLBACKS: Record<string, RestFallback> = {
  get_books: {
    method: 'GET',
    url: (p) => {
      const params = new URLSearchParams()
      params.set('limit', String(p.limit ?? 50))
      params.set('offset', String(p.offset ?? 0))
      if (p.sort) params.set('sort', String(p.sort))
      if (p.type) params.set('type', String(p.type))
      return `/api/libraries/${p.library_id}/books?${params}`
    },
  },
  get_book: {
    method: 'GET',
    url: (p) => `/api/books/${p.book_id}`,
  },
  get_pages: {
    method: 'GET',
    url: (p) => `/api/books/${p.book_id}/pages`,
  },
  update_progress: {
    method: 'PUT',
    url: (p) => `/api/books/${p.book_id}/progress`,
    body: (p) => ({ page: p.page }),
  },
  search: {
    method: 'GET',
    url: (p) => {
      const params = new URLSearchParams()
      if (p.q) params.set('q', String(p.q))
      if (p.library_id) params.set('library_id', String(p.library_id))
      if (p.age_rating) params.set('age_rating', String(p.age_rating))
      if (p.limit) params.set('limit', String(p.limit))
      if (p.offset) params.set('offset', String(p.offset))
      return `/api/search?${params}`
    },
  },
  get_libraries: {
    method: 'GET',
    url: () => '/api/libraries',
  },
}

class Transport {
  private ws: WebSocket | null = null
  private pending = new Map<string, Resolver>()
  private pushHandlers = new Map<string, Set<(payload: unknown) => void>>()
  private token: string | null = null
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private connected = false

  setToken(token: string) {
    this.token = token
    this.connect()
  }

  clearToken() {
    this.token = null
    this.ws?.close()
    this.ws = null
  }

  private connect() {
    if (!this.token) return
    try {
      this.ws = new WebSocket(`${WS_URL}?token=${this.token}`)
    } catch {
      this.scheduleReconnect()
      return
    }

    this.ws.onopen = () => {
      this.connected = true
      if (this.reconnectTimer) {
        clearTimeout(this.reconnectTimer)
        this.reconnectTimer = null
      }
    }

    this.ws.onclose = () => {
      this.connected = false
      this.rejectAll(new Error('WebSocket disconnected'))
      this.scheduleReconnect()
    }

    this.ws.onerror = () => {
      // let onclose handle it
    }

    this.ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data as string) as {
          id?: string
          type: string
          payload?: unknown
          error?: string
        }

        if (msg.id) {
          const r = this.pending.get(msg.id)
          if (r) {
            this.pending.delete(msg.id)
            if (msg.error) {
              r.reject(new Error(msg.error))
            } else {
              r.resolve(msg.payload)
            }
          }
        } else {
          // push event
          const handlers = this.pushHandlers.get(msg.type)
          handlers?.forEach((h) => h(msg.payload))
        }
      } catch {
        // ignore malformed messages
      }
    }
  }

  private scheduleReconnect() {
    if (this.reconnectTimer || !this.token) return
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null
      this.connect()
    }, 3000)
  }

  private rejectAll(err: Error) {
    this.pending.forEach((r) => r.reject(err))
    this.pending.clear()
  }

  // send a request and return a promise for the response
  async send<T = unknown>(type: string, payload: Record<string, unknown> = {}): Promise<T> {
    if (WS_TYPES.has(type) && this.connected && this.ws?.readyState === WebSocket.OPEN) {
      return this.sendWS<T>(type, payload)
    }
    return this.sendREST<T>(type, payload)
  }

  private sendWS<T>(type: string, payload: Record<string, unknown>): Promise<T> {
    const id = crypto.randomUUID()
    const msg = JSON.stringify({ id, type, payload })
    return new Promise<T>((resolve, reject) => {
      this.pending.set(id, {
        resolve: resolve as (v: unknown) => void,
        reject,
      })
      this.ws!.send(msg)
      setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id)
          this.sendREST<T>(type, payload).then(resolve, reject)
        }
      }, 10_000)
    })
  }

  private async sendREST<T>(type: string, payload: Record<string, unknown>, isRetry = false): Promise<T> {
    const fallback = REST_FALLBACKS[type]
    if (!fallback) throw new Error(`No REST fallback for "${type}"`)

    const url = fallback.url(payload)
    const init: RequestInit = {
      method: fallback.method,
      headers: {
        'Content-Type': 'application/json',
        ...(this.token ? { Authorization: `Bearer ${this.token}` } : {}),
      },
    }
    if (fallback.body) {
      init.body = JSON.stringify(fallback.body(payload))
    }

    const res = await fetch(url, init)
    if (res.status === 401 && !isRetry) {
      const refreshed = await this.tryRefresh()
      if (refreshed) return this.sendREST<T>(type, payload, true)
    }
    if (!res.ok) {
      const text = await res.text()
      throw new Error(text || res.statusText)
    }
    return res.json() as Promise<T>
  }

  private async tryRefresh(): Promise<boolean> {
    const refreshToken = localStorage.getItem('refresh_token')
    if (!refreshToken) return false
    try {
      const res = await fetch('/api/auth/refresh', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh_token: refreshToken }),
      })
      if (!res.ok) {
        localStorage.removeItem('access_token')
        localStorage.removeItem('refresh_token')
        this.token = null
        return false
      }
      const data = await res.json() as { access_token: string; refresh_token: string }
      localStorage.setItem('access_token', data.access_token)
      localStorage.setItem('refresh_token', data.refresh_token)
      this.token = data.access_token
      return true
    } catch {
      return false
    }
  }

  // subscribe to push events from server
  on(type: string, handler: (payload: unknown) => void): () => void {
    if (!this.pushHandlers.has(type)) {
      this.pushHandlers.set(type, new Set())
    }
    this.pushHandlers.get(type)!.add(handler)
    return () => this.pushHandlers.get(type)?.delete(handler)
  }
}

export const transport = new Transport()
