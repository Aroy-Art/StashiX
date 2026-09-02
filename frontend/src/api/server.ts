import { cookies } from 'next/headers'

export const GO = process.env.GO_API_URL ?? 'http://localhost:8080'

export async function getServerToken(): Promise<string | null> {
  try {
    const store = await cookies()
    const raw = store.get('auth_tokens')?.value
    if (!raw) return null
    const tokens = JSON.parse(decodeURIComponent(raw)) as { access_token: string }
    return tokens.access_token ?? null
  } catch {
    return null
  }
}

export async function serverFetch(path: string, init: RequestInit = {}): Promise<Response> {
  const token = await getServerToken()
  return fetch(`${GO}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(init.headers as Record<string, string> | undefined ?? {}),
    },
  })
}
