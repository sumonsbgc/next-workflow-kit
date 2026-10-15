# Data fetching, caching, revalidation

> This is the **Next 15** caching model. On Next 16, read `references/next16.md` first: `revalidateTag` needs a profile argument, and with `cacheComponents: true` route segment config (`dynamic`/`revalidate`/`fetchCache`) errors and new caching uses `'use cache'`. Existing `unstable_cache` and `fetch` caching keep working there.

## Where data is fetched

Fetch in the Server Component that needs it. Sibling components can each fetch the same thing — React `cache()`/request memoization dedupes identical `fetch` calls within one request. Do **not** lift everything to a parent and prop-drill just to avoid duplicate calls.

```tsx
// app/posts/[id]/page.tsx
async function getPost(id: string) {
  const res = await fetch(`${process.env.API_URL}/posts/${id}`, {
    next: { revalidate: 60, tags: [`post:${id}`] },
  })
  if (!res.ok) throw new Error(`post ${id}: ${res.status}`)
  return res.json() as Promise<Post>
}
```

For a DB/ORM call (no `fetch` involved), wrap it in `unstable_cache` when you want it cached across requests:

```ts
import { unstable_cache } from 'next/cache'
export const getPosts = unstable_cache(
  async (userId: string) => db.post.findMany({ where: { userId } }),
  ['posts-by-user'],            // key parts
  { revalidate: 300, tags: ['posts'] },
)
```

## Caching defaults (Next.js 15 — changed from 14)

- `fetch` is **not cached by default** (`cache: 'no-store'`). Opt in with `cache: 'force-cache'` or `next: { revalidate: n }`.
- `GET` route handlers are **not cached by default**. Opt in with `export const dynamic = 'force-static'`.
- The client Router Cache no longer reuses page segments by default; tune with `experimental.staleTimes`.
- Full Route Cache still applies to statically rendered routes at build time.

A route becomes **dynamic** the moment it awaits `cookies()`, `headers()`, `searchParams`, or uses `no-store`. Everything above it can still be static — that is what `<Suspense>` buys you.

## Revalidation

```ts
'use server'
import { revalidateTag, revalidatePath } from 'next/cache'
export async function publish(id: string) {
  await db.post.update({ where: { id }, data: { published: true } })
  revalidateTag(`post:${id}`)   // precise; prefer this
  revalidatePath('/posts')      // whole route; use when the list shape changed
}
```

Tags are the maintainable option: tag at the fetch site, invalidate at the mutation site.

## Streaming

`loading.tsx` streams the whole segment. `<Suspense>` streams a part of it — use it to keep the shell static while a slow widget resolves:

```tsx
export default function Page() {
  return (
    <>
      <Header />                        {/* static, sent immediately */}
      <Suspense fallback={<FeedSkeleton />}>
        <Feed />                        {/* async Server Component */}
      </Suspense>
    </>
  )
}
```

Rules of thumb:
- Two independent async calls in one component → `Promise.all`, not sequential `await`s (a request waterfall).
- A slow call that isn't needed for first paint → its own `<Suspense>` boundary.
- Start the promise in the Server Component and pass it to a Client Component that unwraps it with React 19's `use()` when you need interactivity around streamed data.

## Static generation

```tsx
export async function generateStaticParams() {
  const posts = await db.post.findMany({ select: { slug: true } })
  return posts.map((p) => ({ slug: p.slug }))
}
export const dynamicParams = true   // render unknown slugs on demand (default)
```

## Route segment config

`export const dynamic = 'auto' | 'force-dynamic' | 'error' | 'force-static'`, `revalidate = number | false`, `fetchCache`, `runtime = 'nodejs' | 'edge'`, `preferredRegion`. Reach for these only when the default inference is wrong — `force-dynamic` sprinkled everywhere is a performance bug, not a fix.

## Post-response work

```ts
import { after } from 'next/server'
after(() => analytics.track('page_view'))   // runs after the response is sent
```
