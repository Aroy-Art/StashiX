export type Role = 'admin' | 'user'
export type BookFormat = 'cbz' | 'cbr' | 'cb7' | 'epub' | 'pdf'
export type AgeRating = 'unknown' | 'everyone' | 'teen' | 'teen_plus' | 'mature' | 'explicit' | 'adult'

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
  book_count?: number
  issue_count?: number
  series_count?: number
  standalone_folders?: string[]
}

export interface Book {
  id: string
  library_id: string
  title: string
  type?: 'issue' | 'standalone'
  series?: string
  series_id?: string
  issue_number?: string
  volume?: number
  year?: number
  publisher?: string
  format: BookFormat
  page_count: number
  file_size: number
  age_rating: AgeRating
  language?: string
  path?: string
  folder_path?: string
  summary?: string
  created_at: string
  deleted_at?: string
  current_page?: number
}

export interface DeletedBook {
  id: string
  title: string
  path: string
  format: BookFormat
  deleted_at: string
}

export interface Series {
  id: string
  library_id: string
  name: string
  publisher?: string
  start_year?: number
  end_year?: number
  ongoing?: boolean
  adult?: boolean
  age_rating?: AgeRating
  created_at: string
  cover_book_id?: string
  book_count?: number
}

export interface SeriesBook {
  id: string
  title: string
  type?: 'issue' | 'standalone'
  series?: string
  series_id?: string
  issue_number?: string
  volume?: number
  year?: number
  format: BookFormat
  page_count: number
  file_size: number
  age_rating: AgeRating
  adult?: boolean
  current_page?: number
}

export interface SeriesDetail extends Series {
  books: SeriesBook[]
  folder_path?: string
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

export interface ScanTask {
  library_id: string
  scanned: number
  total: number
  done: boolean
  phase?: 'collecting' | 'parsing' | 'importing' | 'thumbnails' | 'scan' | 'file'
}
