export interface AuthTokens {
  access_token: string
  refresh_token: string
}

const NAME = 'auth_tokens'
const MAX_AGE = 60 * 60 * 24 * 30

export function getAuthTokens(): AuthTokens | null {
  try {
    const match = document.cookie.split('; ').find((r) => r.startsWith(NAME + '='))
    if (!match) return null
    return JSON.parse(decodeURIComponent(match.slice(NAME.length + 1))) as AuthTokens
  } catch {
    return null
  }
}

export function setAuthTokens(tokens: AuthTokens) {
  document.cookie = `${NAME}=${encodeURIComponent(JSON.stringify(tokens))}; path=/; SameSite=Lax; max-age=${MAX_AGE}`
}

export function clearAuthTokens() {
  document.cookie = `${NAME}=; path=/; max-age=0`
}
