import { dehydrate, HydrationBoundary, QueryClient } from '@tanstack/react-query'
import { queryKeys } from '@/lib/query-keys'
import { serverFetch } from '@/api/server'
import BookPageContent from '@/components/pages/BookPageContent'
import type { Book } from '@/types'

export default async function BookPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const queryClient = new QueryClient()
  await queryClient.prefetchQuery({
    queryKey: queryKeys.book(id),
    queryFn: async () => {
      const res = await serverFetch(`/api/books/${id}`)
      if (!res.ok) throw new Error('not found')
      return res.json() as Promise<Book>
    },
  }).catch(() => {})
  return (
    <HydrationBoundary state={dehydrate(queryClient)}>
      <BookPageContent />
    </HydrationBoundary>
  )
}
