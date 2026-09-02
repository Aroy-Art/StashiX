import { NextRequest, NextResponse } from 'next/server'
import { GO, getServerToken } from '@/api/server'

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ bookId: string }> }
) {
  const token = await getServerToken()
  if (!token) return new NextResponse(null, { status: 401 })

  const { bookId } = await params
  const thumbnail = req.nextUrl.searchParams.get('thumbnail')
  const url = new URL(`${GO}/api/books/${bookId}/cover`)
  if (thumbnail) url.searchParams.set('thumbnail', thumbnail)

  const upstream = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!upstream.ok) return new NextResponse(null, { status: upstream.status })

  return new NextResponse(upstream.body, {
    headers: {
      'Content-Type': upstream.headers.get('Content-Type') ?? 'image/jpeg',
      'Cache-Control': 'private, max-age=3600',
    },
  })
}
