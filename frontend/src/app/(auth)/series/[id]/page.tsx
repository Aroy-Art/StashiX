import { dehydrate, HydrationBoundary, QueryClient } from '@tanstack/react-query'
import { queryKeys } from '@/lib/query-keys'
import { serverFetch } from '@/api/server'
import SeriesPageContent from '@/components/pages/SeriesPageContent'
import type { SeriesDetail } from '@/types'

export default async function SeriesPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const queryClient = new QueryClient()
  await queryClient.prefetchQuery({
    queryKey: queryKeys.series(id),
    queryFn: async () => {
      const res = await serverFetch(`/api/series/${id}`)
      if (!res.ok) throw new Error('not found')
      return res.json() as Promise<SeriesDetail>
    },
  }).catch(() => {})
  return (
    <HydrationBoundary state={dehydrate(queryClient)}>
      <SeriesPageContent />
    </HydrationBoundary>
  )
}
