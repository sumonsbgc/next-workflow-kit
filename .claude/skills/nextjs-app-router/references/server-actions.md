# Server Actions

A Server Action is a **public HTTP endpoint**. Anyone can call it with any payload. Treat every action as an untrusted entry point: authenticate, authorize, and validate — every time, inside the action itself.

## Shape

```ts
// app/posts/actions.ts
'use server'

import { revalidateTag } from 'next/cache'
import { redirect } from 'next/navigation'
import { z } from 'zod'
import { auth } from '@/lib/auth'

const CreatePost = z.object({
  title: z.string().min(1).max(200),
  body: z.string().min(1),
})

export type ActionState = { error?: string; fieldErrors?: Record<string, string[]> }

export async function createPost(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const session = await auth()
  if (!session) return { error: 'Not signed in' }          // authn

  const parsed = CreatePost.safeParse(Object.fromEntries(formData))
  if (!parsed.success) {
    return { fieldErrors: parsed.error.flatten().fieldErrors }
  }

  const post = await db.post.create({
    data: { ...parsed.data, authorId: session.user.id },     // never trust an id from the client
  })

  revalidateTag('posts')
  redirect(`/posts/${post.id}`)                              // throws; must be outside try/catch
}
```

Hard rules:
- Every export from a `'use server'` file must be an `async function`.
- `redirect()` and `notFound()` work by throwing — never wrap them in a `try`, and never `catch` around them.
- Return serializable values only. Return errors as data; don't throw raw errors at the client.
- Never accept an `authorId`, `role`, `price`, or `isAdmin` from `formData`. Derive it server-side.

## Wiring it to a form (progressive enhancement, works without JS)

```tsx
'use client'
import { useActionState } from 'react'
import { useFormStatus } from 'react-dom'
import { createPost, type ActionState } from './actions'

function Submit() {
  const { pending } = useFormStatus()
  return <button disabled={pending}>{pending ? 'Saving…' : 'Save'}</button>
}

export function NewPostForm() {
  const [state, action] = useActionState<ActionState, FormData>(createPost, {})
  return (
    <form action={action}>
      <input name="title" required aria-describedby="title-error" />
      <p id="title-error" role="alert">{state.fieldErrors?.title?.[0]}</p>
      <Submit />
    </form>
  )
}
```

`useActionState` is React 19 (it replaced `useFormState` from `react-dom`). `useFormStatus` must be called in a component *inside* the `<form>`, not the one that renders it.

## Inline actions

Small mutations can be defined inside a Server Component:

```tsx
export default function Page() {
  async function remove(formData: FormData) {
    'use server'
    await db.post.delete({ where: { id: String(formData.get('id')) } })
    revalidateTag('posts')
  }
  return <form action={remove}><input type="hidden" name="id" value={id} /><button>Delete</button></form>
}
```
Closed-over values are encrypted and sent to the client — keep secrets out of the closure.

## Optimistic UI

```tsx
const [optimistic, addOptimistic] = useOptimistic(items, (s, next: Item) => [...s, next])
```
Pair with `revalidateTag` in the action so the server state converges.

## When *not* to use an action

Webhooks, file downloads, third-party callbacks, anything needing custom status codes or streaming → use a `route.ts` handler instead.
