export const queryKeys = {
  libraries: () => ['libraries'] as const,
  tasks: () => ['tasks'] as const,
  libraryBooks: (id: string) => ['library', id, 'books'] as const,
  libraryRecentStandalone: (id: string) => ['library', id, 'recent-standalone'] as const,
  librarySeries: (id: string) => ['library', id, 'series'] as const,
  libraryRecentIssues: (id: string) => ['library', id, 'recent-issues'] as const,
  libraryPreview: (id: string) => ['library', id, 'preview'] as const,
  libraryDeleted: (id: string) => ['library', id, 'deleted'] as const,
  book: (id: string) => ['book', id] as const,
  series: (id: string) => ['series', id] as const,
  search: (q: string) => ['search', q] as const,
}
