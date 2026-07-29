import axios from 'axios'
import { transport } from './transport'
import type { Book, Library, ScanTask, SearchResult, Series, SeriesDetail, TokenPair } from '../types'

const http = axios.create({ baseURL: '/api' })

http.interceptors.request.use((config) => {
  const token = localStorage.getItem('access_token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

export const auth = {
  async login(email: string, password: string): Promise<TokenPair> {
    const { data } = await http.post<TokenPair>('/auth/login', { email, password })
    localStorage.setItem('access_token', data.access_token)
    localStorage.setItem('refresh_token', data.refresh_token)
    transport.setToken(data.access_token)
    return data
  },
  logout() {
    localStorage.removeItem('access_token')
    localStorage.removeItem('refresh_token')
    transport.clearToken()
  },
  restoreSession() {
    const token = localStorage.getItem('access_token')
    if (token) transport.setToken(token)
    return token
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
  pages(bookId: string): Promise<{ count: number; pages: string[] }> {
    return transport.send('get_pages', { book_id: bookId })
  },
  updateProgress(bookId: string, page: number): Promise<void> {
    return transport.send('update_progress', { book_id: bookId, page })
  },
  coverUrl(bookId: string) {
    const token = localStorage.getItem('access_token')
    return `/api/books/${bookId}/cover${token ? `?token=${encodeURIComponent(token)}` : ''}`
  },
  fileUrl(bookId: string) {
    return `/api/books/${bookId}/file`
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
  coverUrl(seriesId: string) {
    const token = localStorage.getItem('access_token')
    return `/api/series/${seriesId}/cover${token ? `?token=${encodeURIComponent(token)}` : ''}`
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
  ): Promise<{ results: SearchResult[]; offset: number; limit: number }> {
    return transport.send('search', {
      q,
      library_id: opts.libraryId,
      age_rating: opts.ageRating,
      limit: opts.limit ?? 50,
      offset: opts.offset ?? 0,
    })
  },
}
