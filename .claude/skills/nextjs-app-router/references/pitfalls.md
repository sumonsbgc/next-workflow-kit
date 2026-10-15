# Pitfalls that only surface at build or runtime

Check this list before declaring a Next.js task done.

### `useSearchParams() should be wrapped in a suspense boundary`
Build-time failure. Any component calling `useSearchParams`, and by extension the route, bails out to client rendering. Wrap the component in `<Suspense>` in its parent — the boundary must be in a *different* component than the hook call.

### `You're importing a component that needs useState` / `next/headers`
The client boundary leaked. Either the file needs `'use client'`, or a Client Component is importing a server-only module. Fix by moving the import, not by adding `'use client'` higher up. Mark true server modules with `import 'server-only'` so the failure lands at build time in the right file.

### `Functions cannot be passed directly to Client Components`
You passed a callback across the boundary. Pass a Server Action (allowed) or restructure so the handler is defined in the Client Component.

### `Error: Dynamic server usage: cookies`
A route you expected to be static awaited `cookies()`/`headers()`. Either accept dynamic rendering, or move the dynamic part into a child inside `<Suspense>`.

### Hydration mismatch
Caused by `Date.now()`, `Math.random()`, `localStorage`, `window`, or locale-dependent formatting during render. Move it into `useEffect`, or render it only on the client. `suppressHydrationWarning` is for text you *know* differs (timestamps), not a fix.

### `params.id` is undefined in Next.js 15
`params`/`searchParams` are Promises now — `await` them.

### `next/dynamic` with `ssr: false` in a Server Component
Not allowed (Next 15+). Move the dynamic import into a Client Component, or drop `ssr: false`.

### Metadata is ignored
`export const metadata` / `generateMetadata` only work in Server Components (`page.tsx`/`layout.tsx` without `'use client'`). `viewport` and `themeColor` are a separate `export const viewport`.

### Environment variables are `undefined` in the browser
Only `NEXT_PUBLIC_*` is inlined at build time. `NEXT_PUBLIC_*` values are baked into the bundle — never put a secret behind that prefix. Rebuild after changing them.

### The whole page went client-side
Someone put `'use client'` on `layout.tsx` or `page.tsx`. Move it down to the interactive leaf.

### Route handler and page in the same segment
`app/x/page.tsx` + `app/x/route.ts` conflict. Move the handler to `app/api/x/route.ts`.

### `revalidatePath`/`revalidateTag` did nothing
They only work in Server Actions and route handlers, and only affect the server cache. Calling them during render is a no-op. Also check that the fetch actually carries the tag you're invalidating.

### Middleware (Next 15) / proxy (Next 16)
On Next 16 this file is `proxy.ts` exporting `proxy()` (Node.js runtime only; Edge middleware stays `middleware.ts`); see `next16.md`. Never rely on it alone for auth: Server Actions are POSTs to their route, so a matcher change can silently skip them. Same rules either way:
Runs on every matched request before rendering — keep it to redirects/rewrites/header work. No DB clients, no Node-only APIs unless `runtime: 'nodejs'` is configured. Always set `config.matcher`; without it you run on static assets too.

### Images
`next/image` needs `width`/`height` (or `fill` on a positioned parent) and an `alt`. Remote hosts must be listed in `next.config` `images.remotePatterns`. `priority` on the LCP image only.

### Server Actions used as GET endpoints
They're POST-only. For anything a browser navigates to, use a route handler.

### `use client` file importing a `.server.ts` module or a DB client
Ships (or fails to ship) your database driver to the browser. Keep DB access in `lib/*` modules imported only from Server Components and actions, guarded with `import 'server-only'`.
