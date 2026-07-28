export type Role = 'admin' | 'user'
export type BookFormat = 'cbz' | 'cbr' | 'cb7' | 'epub' | 'pdf'
export type AgeRating = 'unknown' | 'everyone' | 'teen' | 'mature' | 'explicit'

export interface User {
  id: string
  email: string
  username: string
  role: Role
  birth_date?: string
  created_at: string
}

export interface Library {
  id: string
  name: string
  root_path: string
  created_at: string
}

export interface Book {
  id: string
  library_id: string
  title: string
  series?: string
  issue_number?: string
  volume?: number
  year?: number
  publisher?: string
  format: BookFormat
  page_count: number
  file_size: number
  age_rating: AgeRating
  language?: string
  summary?: string
  created_at: string
}

export interface ReadingProgress {
  book_id: string
  current_page: number
  updated_at: string
}

export interface TokenPair {
  access_token: string
  refresh_token: string
}

export interface SearchResult extends Omit<Book, 'file_size' | 'language' | 'summary' | 'created_at'> {
  rank: number
}
