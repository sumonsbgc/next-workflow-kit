# Next.js 16+: what changes from the Next 15 rules

> **Verified** against the official docs on 2026-10-15: the [v16 upgrade guide](https://nextjs.org/docs/app/guides/upgrading/version-16) (updated 2026-10-02), [Migrating to Cache Components](https://nextjs.org/docs/app/guides/migrating-to-cache-components) (2026-10-06), and the API references linked in each section. Every rule here is from those pages; nothing is from memory.
> **The installed version wins.** On Next 16.2+, version-matched docs ship in `node_modules/next/dist/docs/`. When a rule here and those docs disagree, follow the bundled docs and tell the user this file is stale.

Read this when the session report says Next 16 or later. Where it conflicts with the other references, **this file wins**. Everything not mentioned here (Server Components first, the island pattern, Server Action security, Suspense around `useSearchParams`) is unchanged.

## Requirements

Node.js **20.9+**, TypeScript **5.1+**, React 19.2 (via the App Router's React canary). Browsers: Chrome/Edge/Firefox 111+, Safari 16.4+.

## Breaking changes: build errors or wrong behaviour on 16

| Next 15 | Next 16 |
|---|---|
| Sync access to `cookies()`, `headers()`, `draftMode()`, `params`, `searchParams` (temporary compatibility on 15) | **Removed.** Always `await` them. Also async now: `params` and `id` in `opengraph-image`/`twitter-image`/`icon`/`apple-icon`, and `id` in `sitemap` (from `generateSitemaps`). `generateImageMetadata` still gets sync `params`. |
| `middleware.ts` exporting `middleware()` | **Deprecated, renamed** to `proxy.ts` (project root, or `src/`) exporting `proxy` (named or default). Proxy runs on **Node.js only** and `runtime` can't be set (setting it throws). **Edge middleware stays `middleware.ts`**: don't blindly rename it. Flags renamed too (`skipMiddlewareUrlNormalize` → `skipProxyUrlNormalize`). [ref](https://nextjs.org/docs/app/api-reference/file-conventions/proxy) |
| `revalidateTag(tag)` | `revalidateTag(tag, 'max')`. The profile is **required** (single-arg is deprecated, a TypeScript error, and behaves like `{ expire: 0 }`). `'max'` gives stale-while-revalidate. A webhook or Route Handler that needs data gone immediately uses `revalidateTag(tag, { expire: 0 })`. Can't be called in Proxy or Client Components. [ref](https://nextjs.org/docs/app/api-reference/functions/revalidateTag) |
| `experimental.ppr`, the `experimental_ppr` segment export, `experimental.dynamicIO`, `experimental.useCache` | **Removed.** Use top-level `cacheComponents: true`, but only as a deliberate adoption, not a rename (it can surface new build errors). |
| `unstable_cacheLife`, `unstable_cacheTag` | Stable: `import { cacheLife, cacheTag } from 'next/cache'` |
| `next lint` | **Removed**, and `next build` no longer lints. The `eslint` option in `next.config` is removed. Use the ESLint CLI via the project's `lint` script. |
| `serverRuntimeConfig` / `publicRuntimeConfig` | **Removed.** Server: `process.env`. Client: `NEXT_PUBLIC_*`. To read env at runtime rather than inline it at build: `await connection()` (from `next/server`) first. |
| Parallel-route slot without `default.js` | **Build error.** Every `@slot` needs a `default.tsx` returning `null` or calling `notFound()`. |
| `experimental.turbopack` | Top-level `turbopack`. Turbopack is the default for `next dev` and `next build`. A custom `webpack()` config (yours or a plugin's) **fails the build** unless the script passes `--webpack` (keep webpack) or `--turbopack` (ignore it). Don't add webpack config; if one exists, raise it before touching the build. |
| AMP, `next/amp`, `unstable_rootParams` | **Removed** (`next/root-params` replaces the latter). |
| `next build` printing `size` / `First Load JS` per route | **Removed from the output.** Measure with Lighthouse or real-user analytics, not the build table. |

### `next/image` defaults that changed (all breaking)

- `images.qualities` defaults to `[75]`. Other `quality` values are coerced to the closest allowed one, and `/_next/image` returns 400 for unlisted `q`.
- `images.minimumCacheTTL` is 4 hours (was 60 s). `images.imageSizes` no longer includes `16`. `images.maximumRedirects` is 3 (was unlimited).
- Local images with a query string (`/a.png?v=1`) need `images.localPatterns[].search`.
- Local-IP upstreams are blocked unless `images.dangerouslyAllowLocalIP: true` (SSRF risk; private networks only).
- `next/legacy/image` and `images.domains` are deprecated: use `next/image` and `images.remotePatterns`.

### Other behaviour changes

- `next dev` writes to `.next/dev`, so `dev` and `build` can run at the same time; a lockfile stops two `next dev` instances on one project.
- Next no longer overrides a global `scroll-behavior: smooth` during navigation. Add `data-scroll-behavior="smooth"` on `<html>` to get the old behaviour.
- `reactCompiler: true` is stable but **off by default**. Don't enable it unasked (it needs `babel-plugin-react-compiler` and slows builds).

## Caching when `cacheComponents: true` (the session report says so)

Nothing is cached unless you opt in, and uncached data runs at request time. [ref](https://nextjs.org/docs/app/api-reference/directives/use-cache)

```ts
// lib/projects.ts
import { cacheLife, cacheTag } from 'next/cache'

export async function listProjects(orgId: string) {
  'use cache'
  cacheLife('hours')   // set one explicitly in every cached scope
  cacheTag(`projects:${orgId}`)
  return db.project.findMany({ where: { orgId } })
}
```

```ts
// app/projects/actions.ts
'use server'
import { updateTag } from 'next/cache'

export async function archiveProject(id: string) {
  // authenticate → authorize → validate → mutate (unchanged)
  updateTag(`projects:${orgId}`)   // read-your-own-writes: the next request waits for fresh data
}
```

- **`'use cache'`** goes at the top of an async function, a component, or a file (every export must then be async). The cache key is the build ID, the function, its serializable arguments, and any closed-over variables. Arguments and return values must be serializable: no class instances, no functions (except passed through untouched), no URL instances.
- **`cacheLife` profiles**: `seconds`, `minutes`, `hours`, `days`, `weeks`, `max` (plus `default`: 5 min stale, 15 min revalidate, never expires). Call it inside the cached scope, not at module level. `seconds` (and anything with `expire` under 5 min or `revalidate: 0`) is excluded from the prerender and becomes a request-time hole. Nesting such a cache inside a `'use cache'` that has no explicit `cacheLife` **fails the build**.
- **Request data**: `cookies()`, `headers()` and `searchParams` **can't** be read inside `'use cache'`, or in any helper it calls (error `next-request-in-use-cache`, which can pass `next build` and fail at runtime). Read them outside and pass the values in as arguments. That's the preferred pattern. `'use cache: private'` (allows `cookies`/`headers`/`searchParams`; results aren't stored server-side across requests) is for when that refactor isn't practical or for compliance. `connection()` is banned in both.
- **Storage**: `'use cache'` is in-memory by default. It doesn't survive a new deployment, and on serverless it usually isn't shared between requests. `'use cache: remote'` uses a platform cache handler.
- **Invalidation**:
  - `updateTag(tag)`: **Server Actions only** (throws elsewhere). Read-your-own-writes.
  - `revalidateTag(tag, 'max')`: Server Actions and Route Handlers. Stale-while-revalidate.
  - `refresh()` (from `next/cache`): **Server Actions only**. It refreshes the client router; it does not invalidate cached data.
  - `revalidatePath`: unchanged.

### What errors or changes under `cacheComponents`

- **Route segment config `dynamic`, `revalidate`, `fetchCache` → error.** Replace them, don't leave them:
  - `force-dynamic` or `revalidate = 0`: delete the export (uncached is already request-time).
  - `revalidate = N`: `'use cache'` + `cacheLife(...)`.
  - `force-static` or `fetchCache: 'force-cache'`: `'use cache'` around the data.
- **`dynamicParams` → build error.** Use `notFound()` for unknown params instead.
- **`runtime = 'edge'` → not supported.** Cache Components needs Node.js.
- **`generateStaticParams` must return at least one param** (an empty array errors).
- **Request-time data outside `<Suspense>`** (cookies, headers, searchParams, uncached fetches): move it into a child component wrapped in `<Suspense>`, so the rest prerenders as the static shell. Pass the `params`/`searchParams` promise down and `await` it inside the boundary.
- **Synchronous IO during prerender is a build error**: `new Date()`, `Date.now()`, `Math.random()`, `crypto.randomUUID()`. Move it under `<Suspense>` after `await connection()`, or into a Client Component.
- **Client hooks** `usePathname`, `useParams`, `useSelectedLayoutSegment(s)` in a shared layout above dynamic params suspend: wrap the reading component in `<Suspense>`. `useSearchParams` always needs one.
- **UI state now survives navigation** (routes are kept in React `<Activity mode="hidden">`). Open menus, form inputs and `useActionState` results persist when the user navigates back, so reset them explicitly where that matters.
- **Still fine:** `unstable_cache` and `fetch` caching keep working, and migrating them is optional. Unlike `'use cache'`, they persist across deployments. Don't rewrite them as part of an unrelated task.

## Checks before closing a task on Next 16

- [ ] No synchronous request-API access; image and sitemap functions `await` their `params`/`id`.
- [ ] New request interception goes in `proxy.ts` (Node.js). Edge middleware wasn't renamed. Server Actions still check auth themselves, without relying on Proxy.
- [ ] Every `revalidateTag` has a profile; Server Actions that must show their own write use `updateTag`.
- [ ] Every parallel-route slot has `default.tsx`; no webpack config added; nothing calls `next lint`.
- [ ] With `cacheComponents`: no `dynamic`/`revalidate`/`fetchCache`/`dynamicParams` exports, no request data inside `'use cache'`, request-time reads and sync IO are under `<Suspense>`, and every cached scope sets `cacheLife`.
