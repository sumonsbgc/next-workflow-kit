import 'server-only'

export type Project = { id: string; ownerId: string; name: string; archived: boolean }

const projects: Project[] = [
  { id: 'p1', ownerId: 'u1', name: 'Website redesign', archived: false },
  { id: 'p2', ownerId: 'u1', name: 'Mobile app', archived: false },
  { id: 'p3', ownerId: 'u2', name: 'Someone else’s project', archived: false },
]

export async function findProject(id: string): Promise<Project | undefined> {
  return projects.find((p) => p.id === id)
}

export async function listProjectsByOwner(ownerId: string): Promise<Project[]> {
  return projects.filter((p) => p.ownerId === ownerId)
}

export async function setArchived(id: string, archived: boolean): Promise<void> {
  const p = projects.find((x) => x.id === id)
  if (p) p.archived = archived
}
