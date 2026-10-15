'use server'

import { revalidatePath } from 'next/cache'
import { getSession } from '@/lib/session'
import { findProject, setArchived } from '@/lib/projects'
import { archiveProjectSchema } from '@/lib/validation/project'

export async function archiveProject(formData: FormData): Promise<void> {
  const session = await getSession()
  if (!session) return
  const parsed = archiveProjectSchema.safeParse({ id: formData.get('id') })
  if (!parsed.success) return
  const project = await findProject(parsed.data.id)
  if (!project || project.ownerId !== session.userId) return
  await setArchived(project.id, true)
  revalidatePath('/projects')
}
