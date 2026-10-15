# The client boundary: server first, client last

## The policy

**Server Component unless proven otherwise.** `'use client'` is a last resort, and when it is needed it goes in its own file containing only the interactive part — never on a page, a layout, or a component that also renders the rest of the screen.

Ask, in order:

1. Can this render on the server with data it already has? → Server Component. Done.
2. Does it need interactivity? → **which element** needs it? Only that element becomes a client island.
3. Does the island need data? → the server parent fetches it and passes it as a prop. It does not fetch its own.

A `'use client'` directive is not a per-file setting — it is a **boundary**. That file and its entire import graph become browser code. A `'use client'` at the top of `page.tsx` ships the page, its children, its helpers, its date library, and everything they import to every visitor.

## What actually requires a client component

Only these:

- `useState`, `useReducer`, `useEffect`, `useLayoutEffect`, `useRef` on a DOM node, `useContext`
- event handlers — `onClick`, `onChange`, `onSubmit`, `onScroll`
- browser APIs — `window`, `document`, `localStorage`, `IntersectionObserver`, `matchMedia`
- a third-party library that uses any of the above (most animation, chart, map, editor, and carousel libraries)
- `useRouter().push()` from `next/navigation`, `usePathname`, `useSearchParams`

Everything else — layout, text, lists, conditionals, formatting, `<Link>`, `<Image>`, server-rendered forms — is a Server Component. Note in particular that **navigation via `<Link>` needs no client component**, and a `<form action={serverAction}>` submits without one.

## The island pattern

Split by *responsibility*, not by convenience: the server file owns data and markup, the client file owns behaviour.

```
app/projects/page.tsx              server — fetches, renders the shell and the list
app/projects/_components/
  project-list.tsx                 server — maps data to markup
  archive-button.client.tsx        client — one button, one onClick
```

```tsx
// app/projects/page.tsx  — Server Component, no 'use client' anywhere in sight
import { listProjects } from '@/lib/services/projects'
import { ArchiveButton } from './_components/archive-button.client'

export default async function ProjectsPage() {
  const projects = await listProjects()          // runs on the server, never ships
  return (
    <ul>
      {projects.map(p => (
        <li key={p.id}>
          {p.name}
          <ArchiveButton projectId={p.id} />     {/* the only JS the browser gets */}
        </li>
      ))}
    </ul>
  )
}
```

```tsx
// app/projects/_components/archive-button.client.tsx
'use client'
import { useTransition } from 'react'
import { archiveProjectAction } from '../actions'

export function ArchiveButton({ projectId }: { projectId: string }) {
  const [pending, start] = useTransition()
  return (
    <button disabled={pending} onClick={() => start(() => archiveProjectAction(projectId))}>
      {pending ? 'Archiving…' : 'Archive'}
    </button>
  )
}
```

Conventions:

- **One island per file**, named for the behaviour it adds. Use the `*.client.tsx` suffix when the repo has no existing convention — it makes the boundary greppable and obvious in review. Follow the repo's existing pattern if it has one.
- `'use client'` is the **first line** of the file, above the imports.
- The island receives plain serializable props: strings, numbers, booleans, plain objects/arrays, `Date`, `Map`, `Set`. **Not** functions, class instances, ORM model objects, or anything with methods. If you need to pass behaviour, pass a Server Action — those cross the boundary by design.
- Keep the island small enough that its whole job fits in its name. A 300-line `'use client'` file is a page that lost the argument.

## Wrapping the other way: `children` as a slot

A client component may *render* server-rendered content, as long as that content was created by a server parent and passed through as `children`. This is how you keep a subtree on the server underneath a client wrapper — tabs, accordions, modals, drag containers, providers:

```tsx
// tabs.client.tsx  — 'use client', owns which tab is open
export function Tabs({ children }: { children: React.ReactNode }) { … }

// page.tsx — Server Component
<Tabs>
  <ExpensiveServerRenderedPanel />   {/* stays on the server; Tabs never imports it */}
</Tabs>
```

The rule: a client component **cannot import** a Server Component, but it can **receive** one. Anything imported across `'use client'` becomes client code, no matter how it's used.

## Providers

Theme, session, query-client and similar providers are client components, and putting them in `app/layout.tsx` is fine — as long as the provider file itself is the only `'use client'` and it renders `{children}` as a slot. The layout stays a Server Component; the tree inside stays server-rendered.

```tsx
// app/layout.tsx — still a Server Component
export default function RootLayout({ children }) {
  return <html><body><Providers>{children}</Providers></body></html>
}
```

Never stack five providers because a library's README said so. Each one is a client boundary at the root of your app.

## Hydration mismatches — the CSR/SSR trap

The server renders HTML; the browser re-renders the same tree and reuses that HTML. If the two disagree, React logs a hydration error and throws away the server HTML for that subtree — you lose the SSR benefit exactly where it mattered, and you may flash the wrong content.

**Anything that differs between the two renders causes it:**

| Cause | Why it differs | Fix |
|---|---|---|
| `new Date()`, `Date.now()` rendered directly | server time ≠ client time | format on the server and pass the string; or render the raw value in a `<time dateTime>` and localise in an effect |
| `Math.random()`, `crypto.randomUUID()`, a counter for ids | different value per render | `useId()` for ids; generate on the server and pass down |
| `toLocaleString()` with no explicit locale | server locale ≠ browser locale | pass `locale` and options explicitly, both sides |
| `localStorage` / `sessionStorage` / cookies read during render | doesn't exist on the server | read in `useEffect` after mount, or move the value to a server-readable cookie via `next/headers` |
| `typeof window !== 'undefined' ? A : B` in JSX | evaluates differently on each side | this pattern *is* the bug — see below |
| `window.matchMedia` / viewport-dependent markup | no viewport on the server | render the CSS-driven version; use container queries or `hidden`/`block` variants instead of JS |
| Invalid HTML nesting (`<div>` inside `<p>`, `<p>` inside `<p>`) | the browser silently repairs it, the server doesn't | fix the markup |
| Browser extensions injecting attributes on `<body>`/`<html>` | out of your control | `suppressHydrationWarning` on that one element only |

**The `typeof window` check is not a fix.** It guarantees the first client render differs from the server render. Legitimate approaches, in order of preference:

1. **Don't branch.** Render the same thing on both sides and let CSS handle the difference.
2. **Mount flag** when a subtree genuinely can't render on the server:
   ```tsx
   const [mounted, setMounted] = useState(false)
   useEffect(() => setMounted(true), [])
   if (!mounted) return <Skeleton />   // identical on server and first client render
   ```
3. **`useSyncExternalStore`** for reading a browser store with a server snapshot — the correct primitive for `localStorage`, media queries, and online status.
4. **`next/dynamic` with `ssr: false`** for a library that simply cannot render on the server (canvas, maps, WYSIWYG editors). Give it a `loading` fallback the same size as the real thing to avoid layout shift. This import must live in a Client Component — `ssr: false` is not allowed in a Server Component.

`suppressHydrationWarning` silences the warning for one element's *text*; it does not fix the mismatch and does not propagate to children. Use it for timestamps you deliberately localise client-side and for extension-injected attributes. Anywhere else it's hiding a real bug.

## Things that break at build, not in dev

- **`useSearchParams()` without a `<Suspense>` boundary above it** fails `next build` with "missing suspense boundary with useSearchParams". Wrap the component that calls it.
- **`export const metadata`** in a `'use client'` file is invalid. Metadata is server-only; move it to the server parent.
- **`next/dynamic` with `ssr: false`** inside a Server Component is a build error.
- **Server-only imports pulled into a client bundle** — `next/headers`, `server-only`, an ORM, a secret — fail the build (which is the good outcome; the bad outcome is a barrel file that hides it until it leaks).
- A `'use client'` component **cannot be `async`**.

`next build` catches all of these and `next dev` catches almost none. Build before declaring a boundary change done.

## Streaming instead of client-side loading

The reflex "make it a client component so it can show a spinner while it loads" is backwards in the App Router. Keep it on the server and stream:

```tsx
export default function Page() {
  return (
    <>
      <Header />                              {/* instant */}
      <Suspense fallback={<ProjectsSkeleton />}>
        <ProjectList />                       {/* async Server Component, streams in */}
      </Suspense>
    </>
  )
}
```

The user gets the shell immediately and the slow part arrives without a client bundle, without a waterfall, and without a loading state you had to write state for. `loading.tsx` does the same thing for a whole route segment.

## Checklist before you ship a client component

- [ ] Is there a server-rendered way to do this? (form action, `<Link>`, CSS, streaming)
- [ ] Is `'use client'` on the smallest file that needs it, not on the page or layout?
- [ ] Does the island receive data as props rather than fetching its own?
- [ ] Are all props serializable?
- [ ] Does anything render a date, random value, or storage read that could differ between server and client?
- [ ] If it uses `useSearchParams`, is there a `<Suspense>` above it?
- [ ] Does `next build` pass?
