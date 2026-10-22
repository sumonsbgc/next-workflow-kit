import { NextResponse, type NextRequest } from 'next/server'

// Signed-out visitors never reach /projects. Done here rather than in the page: with
// cacheComponents the page streams, and a redirect from inside the stream can't set a 307.
export function proxy(request: NextRequest) {
  if (!request.cookies.get('eval_user')?.value) return NextResponse.redirect(new URL('/', request.url))
  return NextResponse.next()
}

export const config = { matcher: ['/projects/:path*'] }
