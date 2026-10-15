# Pulling a fat component apart

## Before — one file doing five jobs

```tsx
'use client'
export function ProjectList({ userId }: { userId: string }) {
  const [projects, setProjects] = useState<Project[]>([])
  const [query, setQuery] = useState('')
  const [loading, setLoading] = useState(true)

  useEffect(() => {                                   // (1) fetching
    fetch(`/api/projects?user=${userId}`)
      .then((r) => r.json())
      .then((d) => { setProjects(d); setLoading(false) })
  }, [userId])

  const visible = projects
    .filter((p) => p.name.toLowerCase().includes(query.toLowerCase()))
    .filter((p) => !p.archived || p.ownerId === userId)   // (2) a business rule
    .sort((a, b) => +new Date(b.updatedAt) - +new Date(a.updatedAt))

  async function archive(id: string) {                 // (3) a mutation + rule
    const p = projects.find((x) => x.id === id)
    if (p?.ownerId !== userId) return alert('Not allowed')
    await fetch(`/api/projects/${id}/archive`, { method: 'POST' })
    setProjects((s) => s.map((x) => (x.id === id ? { ...x, archived: true } : x)))
  }

  if (loading) return <Spinner />
  return (
    <ul>
      {visible.map((p) => (
        <li key={p.id}>
          {p.name} — {new Intl.NumberFormat('en', { style: 'currency', currency: 'USD' })
            .format(p.budget / 100)}          {/* (4) formatting */}
          <button onClick={() => archive(p.id)}>Archive</button>
        </li>
      ))}
    </ul>
  )
}
```

Five responsibilities: fetching, visibility rules, authorization, formatting, markup. It can't be tested without a network, can't be reused, and the authorization check is enforced in the browser — where the user controls it.

## After

**Data access + business rules on the server:**

```ts
// lib/services/projects.ts
import 'server-only'
export async function listProjects(userId: string) {
  return projectRepo.visibleTo(userId)          // the archived/owner rule lives in one place
}

// app/projects/actions.ts
'use server'
export async function archiveProject(id: string) {
  const session = await auth()
  if (!session) return { ok: false, error: 'Not signed in' }
  await projects.archive(session.user.id, id)   // service re-checks ownership server-side
  revalidateTag('projects')
  return { ok: true }
}
```

**Pure helpers:**

```ts
// lib/utils/format.ts
const usd = new Intl.NumberFormat('en', { style: 'currency', currency: 'USD' })
export const formatCents = (cents: number) => usd.format(cents / 100)

// lib/utils/projects.ts
export const matchesQuery = (p: Project, q: string) =>
  p.name.toLowerCase().includes(q.trim().toLowerCase())
```

**Client state in a hook:**

```ts
// hooks/use-project-search.ts
export function useProjectSearch(projects: Project[]) {
  const [query, setQuery] = useState('')
  const visible = useMemo(() => projects.filter((p) => matchesQuery(p, query)), [projects, query])
  return { query, setQuery, visible }
}
```

**The route fetches; the components render:**

```tsx
// app/projects/page.tsx  — Server Component
export default async function Page() {
  const session = await auth()
  const projects = await listProjects(session.user.id)
  return (
    <Suspense fallback={<ProjectListSkeleton />}>
      <ProjectList projects={projects} />
    </Suspense>
  )
}

// components/project-list.tsx  — 'use client' only because of the search box
'use client'
export function ProjectList({ projects }: { projects: Project[] }) {
  const { query, setQuery, visible } = useProjectSearch(projects)
  return (
    <>
      <SearchInput value={query} onChange={setQuery} />
      <ul>{visible.map((p) => <ProjectRow key={p.id} project={p} />)}</ul>
    </>
  )
}

// components/project-row.tsx
export function ProjectRow({ project }: { project: Project }) {
  return (
    <li>
      <span>{project.name}</span>
      <span>{formatCents(project.budget)}</span>
      <ArchiveButton projectId={project.id} />
    </li>
  )
}
```

Loading state is now `loading.tsx`/`<Suspense>`, the authorization rule is enforced where it can't be bypassed, `formatCents` and `matchesQuery` are unit-testable, and `ProjectRow` renders without a network.

## What each piece costs to test

| Piece | Test needs |
|---|---|
| `formatCents`, `matchesQuery` | nothing — plain assertions |
| `useProjectSearch` | `renderHook`, no network |
| `ProjectRow` | `render()` with a literal object |
| `archiveProject` | call it with a mocked service; assert the unauthorized branch |
| the page | one Playwright test |
