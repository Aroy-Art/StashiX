import type { Metadata } from 'next'
import { cookies } from 'next/headers'
import { Syne, DM_Sans } from 'next/font/google'

export const dynamic = 'force-dynamic'
import './globals.css'
import { QueryProvider } from '@/providers/QueryProvider'
import { ThemeProvider } from '@/providers/ThemeProvider'
import { TransportProvider } from '@/providers/TransportProvider'

const syne = Syne({
  subsets: ['latin'],
  variable: '--font-syne',
  weight: ['400', '500', '600', '700', '800'],
  display: 'swap',
})

const dmSans = DM_Sans({
  subsets: ['latin'],
  variable: '--font-dm-sans',
  weight: ['300', '400', '500', '600'],
  style: ['normal', 'italic'],
  display: 'swap',
})

export const metadata: Metadata = {
  title: 'Stashix',
  description: 'Comic & book server',
}

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const store = await cookies()
  const theme = store.get('theme')?.value ?? 'dark'

  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={`${syne.variable} ${dmSans.variable}${theme === 'dark' ? ' dark' : ''}`}
    >
      <body>
        <ThemeProvider>
          <QueryProvider>
            <TransportProvider>
              {children}
            </TransportProvider>
          </QueryProvider>
        </ThemeProvider>
      </body>
    </html>
  )
}
