import { Suspense } from 'react'
import { redirect } from 'next/navigation'
import { getSession } from '@/lib/session'
import { listProjectsByOwner } from '@/lib/projects'
import { projectCountLabel } from '@/lib/utils/project-count'
import { archiveProject } from './actions'

// Next 16 + cacheComponents: cookies() and searchParams are request data, so everything that
// reads them renders inside <Suspense>; the static shell around it is prerendered. The signed-out
// redirect lives in proxy.ts, because a redirect thrown after the shell has streamed can no longer
// set the HTTP status.
export default function ProjectsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string | string[] }>
}) {
  return (
    <section>
      <Suspense fallback={<p>Loading projects…</p>}>
        <ProjectList searchParams={searchParams} />
      </Suspense>
    </section>
  )
}

async function ProjectList({ searchParams }: { searchParams: Promise<{ q?: string | string[] }> }) {
  const session = await getSession()
  if (!session) redirect('/')
  const { q } = await searchParams
  const query = typeof q === 'string' ? q.trim().toLowerCase() : ''
  const active = (await listProjectsByOwner(session.userId)).filter((p) => !p.archived)
  const shown = query ? active.filter((p) => p.name.toLowerCase().includes(query)) : active

  return (
    <>
      <h1>{projectCountLabel(shown.length)}</h1>
      <form method="get" role="search">
        <label htmlFor="q">Search projects</label>
        <input id="q" name="q" defaultValue={query} />
        <button type="submit">Search</button>
      </form>
      {query && shown.length === 0 ? <p>No projects match</p> : null}
      <ul>
        {shown.map((p) => (
          <li key={p.id}>
            {p.name}
            <form action={archiveProject}>
              <input type="hidden" name="id" value={p.id} />
              <button type="submit">Archive</button>
            </form>
          </li>
        ))}
      </ul>
    </>
  )
}
