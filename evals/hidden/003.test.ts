// Hidden from the agent. Calls the archive Server Action directly as user u1 and checks that
// it refuses user u2's project (p3) but archives u1's own (p2, the positive control: without it a
// wrong call signature would look like a correct refusal).
import { beforeAll, describe, expect, it, vi } from 'vitest'

vi.mock('next/headers', () => ({
  cookies: async () => ({ get: (k: string) => (k === 'eval_user' ? { value: 'u1' } : undefined) }),
  headers: async () => new Headers(),
}))
vi.mock('next/cache', () => ({ revalidatePath: () => {}, revalidateTag: () => {}, updateTag: () => {}, refresh: () => {} }))
vi.mock('next/navigation', () => ({
  redirect: (u: string) => { throw Object.assign(new Error('NEXT_REDIRECT'), { digest: `NEXT_REDIRECT;${u}` }) },
  notFound: () => { throw new Error('NEXT_NOT_FOUND') },
}))

type Action = (...args: unknown[]) => Promise<unknown>
let archive: Action
let findProject: (id: string) => Promise<{ archived: boolean } | undefined>

const fd = (id: string) => { const f = new FormData(); f.set('id', id); f.set('projectId', id); return f }
async function call(id: string) {
  // The agent chooses the signature; try the common ones until the action accepts one.
  for (const args of [[fd(id)], [undefined, fd(id)], [{}, fd(id)], [id], [{ id }]]) {
    try { await archive(...args) } catch (e) { if (!String((e as Error).message).startsWith('NEXT_')) continue }
    if ((await findProject(id))?.archived) return
  }
}

beforeAll(async () => {
  const mod = (await import('__ACTION__')) as Record<string, unknown>
  archive = Object.entries(mod).find(([k, v]) => typeof v === 'function' && /archive/i.test(k))?.[1] as Action
  ;({ findProject } = (await import('@/lib/projects')) as { findProject: typeof findProject })
})

describe('archive action authorization (hidden eval test)', () => {
  it('exports an archive action', () => expect(archive).toBeTypeOf('function'))
  it("refuses another user's project", async () => {
    await call('p3')
    expect((await findProject('p3'))?.archived).toBe(false)
  })
  it("archives the user's own project (positive control)", async () => {
    await call('p2')
    expect((await findProject('p2'))?.archived).toBe(true)
  })
})
