---
name: nextjs-app-router
description: Next.js 15/16 App Router conventions (version-aware) — Server vs Client Components, the client boundary, caching and revalidation, Server Actions, route handlers, metadata, streaming, and the pitfalls that only surface at `next build`. Load before writing or reviewing any file under app/, any Server Action, any data-fetching code, or any next.config change.
---

# Next.js App Router

Assume **Next.js 15 + React 19 + TypeScript, App Router, Server Components by default** unless the session-start stack report says otherwise. **On Next 16 or later, read `references/next16.md` first.** It overrides the Next 15 caching and middleware rules below and in the other references. The stack report is authoritative — check it before assuming Tailwind, shadcn/ui, an ORM, or a test runner exists.

## The one rule everything else follows from

Every file under `app/` is a **Server Component** until someone writes `'use client'`. `'use client'` is not a per-file setting — it is a **boundary**: that file *and everything it imports* becomes browser code. So:

- Fetch data in Server Components. Never build an internal `/api` route just so a Client Component can fetch its own data.
- Push `'use client'` to the smallest interactive leaf, **in its own file**. A `'use client'` on `page.tsx` or `layout.tsx` ships the entire subtree. Server Component unless proven otherwise — see `references/client-boundary.md`.
- Server Components can render Client Components and pass serializable props (no functions, no class instances, no `Date` methods — plain data). Client Components can render Server Components only as `children`/props passed from a server parent.
- Secrets, DB clients, and `next/headers` live on the server side of the boundary. Only `NEXT_PUBLIC_*` env vars reach the browser.

## File conventions under `app/`

| File | Purpose | Notes |
|---|---|---|
| `page.tsx` | route UI | receives `params`, `searchParams` |
| `layout.tsx` | shared shell, persists across navigation | receives `params`, `children`; cannot receive `searchParams` |
| `loading.tsx` | Suspense fallback for the segment | enables streaming |
| `error.tsx` | error boundary | **must** be `'use client'`; gets `{ error, reset }` |
| `not-found.tsx` | 404 UI | paired with `notFound()` |
| `route.ts` | HTTP handler | export `GET`/`POST`/…; cannot coexist with `page.tsx` in the same segment |
| `template.tsx` | like layout but remounts per navigation | rarely needed |
| `default.tsx` | fallback for parallel-route slots | needed with `@slot` routes |

Dynamic segments: `[id]`, `[...slug]`, `[[...slug]]`. Groups `(marketing)` don't affect the URL. Private folders `_lib` are never routable. Parallel routes `@modal`, intercepting routes `(.)photo`.

## Async request APIs (Next 15+, mandatory on 16) — the most common breakage

`params`, `searchParams`, `cookies()`, `headers()`, and `draftMode()` are **Promises**:

```tsx
export default async function Page({
  params, searchParams,
}: {
  params: Promise<{ id: string }>
  searchParams: Promise<{ [k: string]: string | string[] | undefined }>
}) {
  const { id } = await params
  const { q } = await searchParams
  const store = await cookies()
}
```

Route handlers too: `export async function GET(req: Request, ctx: { params: Promise<{ id: string }> })`.

## References

Read the one that matches the task — don't read all of them:

- `references/client-boundary.md` — server-first policy, the client-island pattern, serializable props, hydration mismatches, and the boundary errors that only appear at `next build`.
- `references/next16.md` — **Next 16+ only**: `proxy.ts`, `cacheComponents` + `'use cache'`/`cacheLife`/`cacheTag`/`updateTag`, removed APIs. Wins over the others where they differ.
- `references/data-and-caching.md` — (Next 15 model) fetching, the four caches, `revalidateTag`/`revalidatePath`, `unstable_cache`, streaming, dynamic vs static rendering.
- `references/server-actions.md` — writing mutations safely, `useActionState`, validation, authorization, forms.
- `references/pitfalls.md` — the errors that only appear at build/runtime, and their fixes. Check this before declaring a task done.
- `references/testing.md` — Vitest + React Testing Library for components, Playwright for routes and async Server Components.
- `references/styling.md` — Tailwind v3 vs v4 setup differences, shadcn/ui conventions, and what to do when neither is present.

## Related

- `react-component-conventions` — what may live in a `.tsx` file, and where logic goes instead (hooks, services, helpers, schemas). Load it alongside this one when writing or reviewing components or hooks.
- `code-conventions` — naming, functions, types, errors and async for every file regardless of layer.

## Verification

A Next.js change is not done until `typecheck` passes, and is not trustworthy until `build` passes — many App Router mistakes (missing Suspense around `useSearchParams`, server-only imports pulled into client bundles, invalid metadata exports) are **build-time-only** errors. Use the exact commands from the session-start stack report.
