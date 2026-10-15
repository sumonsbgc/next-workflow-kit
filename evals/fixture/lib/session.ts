import 'server-only'
import { cookies } from 'next/headers'

export type Session = { userId: string; name: string }

// Stand-in for real auth: the signed-in user is the `eval_user` cookie. No cookie = signed out.
export async function getSession(): Promise<Session | null> {
  const userId = (await cookies()).get('eval_user')?.value
  return userId ? { userId, name: userId.toUpperCase() } : null
}
