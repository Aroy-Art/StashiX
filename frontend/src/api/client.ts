import axios from 'axios'
import { transport } from './transport'
import type { Book, Library, SearchResult, TokenPair } from '../types'

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
}

export const books = {
  listByLibrary(libraryId: string, offset = 0, limit = 50): Promise<Book[]> {
    return transport.send('get_books', { library_id: libraryId, offset, limit })
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
    return `/api/books/${bookId}/cover`
  },
  fileUrl(bookId: string) {
    return `/api/books/${bookId}/file`
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
