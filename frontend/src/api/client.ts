import axios from 'axios'
import { transport } from './transport'
import type { Book, DeletedBook, Library, ScanTask, SearchResult, Series, SeriesDetail } from '../types'

const http = axios.create({ baseURL: '/api' })

http.interceptors.request.use((config) => {
  const token = transport.getToken()
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

http.interceptors.response.use(
  (res) => res,
  async (error) => {
    const original = error.config
    const status = error.response?.status
    if ((status === 401 || status === 403) && !original._retry) {
      original._retry = true
      const refreshed = await transport.tryRefresh()
      if (refreshed) {
        original.headers.Authorization = `Bearer ${transport.getToken()}`
        return http(original)
      }
    }
    return Promise.reject(error)
  }
)

export const auth = {
  async login(email: string, password: string): Promise<{ access_token: string; profile: unknown }> {
    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    })
    if (!res.ok) throw new Error('Invalid credentials')
    return res.json()
  },
  async logout(): Promise<void> {
    await fetch('/api/auth/logout', { method: 'POST' })
    transport.clearToken()
  },
  async restore(): Promise<{ token: string } | null> {
    try {
      const res = await fetch('/api/ws-token')
      if (!res.ok) return null
      return res.json()
    } catch {
      return null
    }
  },
}

export const libraries = {
  list(): Promise<Library[]> {
    return transport.send('get_libraries')
  },
  async scan(libraryId: string, force = false): Promise<void> {
    const params = force ? '?force=true' : ''
    await http.post(`/libraries/${libraryId}/scan${params}`)
  },
  async update(libraryId: string, data: { standalone_folders: string[] }): Promise<void> {
    await http.patch(`/libraries/${libraryId}`, data)
  },
  async create(data: { name: string; root_path: string; standalone_folders?: string[] }): Promise<Library> {
    const { data: lib } = await http.post<Library>('/libraries', data)
    return lib
  },
}

export const tasks = {
  async list(): Promise<ScanTask[]> {
    const { data } = await http.get<ScanTask[]>('/tasks')
    return data
  },
}

export const books = {
  listByLibrary(
    libraryId: string,
    offset = 0,
    limit = 50,
    opts: { sort?: 'series' | 'recent'; type?: 'all' | 'standalone' | 'issues' } = {}
  ): Promise<Book[]> {
    return transport.send('get_books', {
      library_id: libraryId,
      offset,
      limit,
      sort: opts.sort ?? 'series',
      type: opts.type ?? 'all',
    })
  },
  get(bookId: string): Promise<Book> {
    return transport.send('get_book', { book_id: bookId })
  },
  async pages(bookId: string): Promise<{ count: number; pages: string[] }> {
    const result = await transport.send<{ count: number; pages: string[] }>('get_pages', { book_id: bookId })
    result.pages = result.pages.map((_, i) => `/api/pages/${bookId}/${i}`)
    return result
  },
  updateProgress(bookId: string, page: number): Promise<void> {
    return transport.send('update_progress', { book_id: bookId, page })
  },
  coverUrl(bookId: string, thumbnail?: 'sx' | 's' | 'm' | 'l' | 'lx') {
    const params = thumbnail ? `?thumbnail=${thumbnail}` : ''
    return `/api/covers/books/${bookId}${params}`
  },
  fileUrl(bookId: string) {
    return `/api/books/${bookId}/file`
  },
  async listDeleted(libraryId: string): Promise<DeletedBook[]> {
    const { data } = await http.get<DeletedBook[]>(`/libraries/${libraryId}/deleted-books`)
    return data
  },
  async delete(bookId: string): Promise<void> {
    await http.delete(`/books/${bookId}`)
  },
}

export const series = {
  async get(id: string): Promise<SeriesDetail> {
    const { data } = await http.get<SeriesDetail>(`/series/${id}`)
    return data
  },
  async listByLibrary(libraryId: string): Promise<Series[]> {
    const { data } = await http.get<Series[]>(`/libraries/${libraryId}/series`)
    return data
  },
  coverUrl(seriesId: string, thumbnail?: 'sx' | 's' | 'm' | 'l' | 'lx') {
    const params = thumbnail ? `?thumbnail=${thumbnail}` : ''
    return `/api/covers/series/${seriesId}${params}`
  },
}

export const user = {
  async profile(): Promise<{ username: string; email: string; first_name: string; last_name: string; is_staff: boolean; is_admin: boolean }> {
    const { data } = await http.get('/user/profile')
    return data
  },
}

export const search = {
  query(
    q: string,
    opts: { libraryId?: string; ageRating?: string; limit?: number; offset?: number } = {}
  ): Promise<{ results: SearchResult[]; total: number; offset: number; limit: number }> {
    return transport.send('search', {
      q,
      library_id: opts.libraryId,
      age_rating: opts.ageRating,
      limit: opts.limit ?? 50,
      offset: opts.offset ?? 0,
    })
  },
}
