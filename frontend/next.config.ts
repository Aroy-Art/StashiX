import type { NextConfig } from 'next'

const config: NextConfig = {
  allowedDevOrigins: ['192.168.22.68', 'jail-arch.lan'],
  async rewrites() {
    const apiUrl = process.env.GO_API_URL ?? 'http://localhost:8080'
    return {
      // fallback = tried only after all Route Handlers and pages are checked
      fallback: [
        {
          source: '/api/:path*',
          destination: `${apiUrl}/api/:path*`,
        },
      ],
    }
  },
}

export default config
