import { redirect } from 'next/navigation'
import { getSession } from '@/lib/session'
import { listProjectsByOwner } from '@/lib/projects'
import { projectCountLabel } from '@/lib/utils/project-count'
import { archiveProject } from './actions'

export default async function ProjectsPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string | string[] }>
}) {
  const session = await getSession()
  if (!session) redirect('/')
  const { q } = await searchParams
  const query = typeof q === 'string' ? q.trim().toLowerCase() : ''
  const active = (await listProjectsByOwner(session.userId)).filter((p) => !p.archived)
  const shown = query ? active.filter((p) => p.name.toLowerCase().includes(query)) : active

  return (
    <section>
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
    </section>
  )
}
