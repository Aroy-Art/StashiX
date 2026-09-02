import { NextRequest, NextResponse } from 'next/server'
import { GO, getServerToken } from '@/api/server'

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ bookId: string; page: string }> }
) {
  const token = await getServerToken()
  if (!token) return new NextResponse(null, { status: 401 })

  const { bookId, page } = await params
  const upstream = await fetch(`${GO}/api/books/${bookId}/page/${page}`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!upstream.ok) return new NextResponse(null, { status: upstream.status })

  return new NextResponse(upstream.body, {
    headers: {
      'Content-Type': upstream.headers.get('Content-Type') ?? 'image/jpeg',
      'Cache-Control': 'private, max-age=86400',
    },
  })
}
