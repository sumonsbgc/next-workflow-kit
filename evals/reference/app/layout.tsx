import type { ReactNode } from 'react'
import { SiteFooter } from '@/components/site-footer'

export const metadata = { title: 'Eval fixture', description: 'next-workflow eval app' }

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <main>{children}</main>
        <SiteFooter />
      </body>
    </html>
  )
}
