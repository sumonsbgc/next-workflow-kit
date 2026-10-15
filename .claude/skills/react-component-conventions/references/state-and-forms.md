# Client state and forms

Two decisions this codebase has already made: **zod** for every validation boundary, and **zustand** when state genuinely has to be shared.

## The state ladder — climb only as far as you must

Each rung costs more than the one before it. Stop at the first that works.

1. **Derive it.** If it can be computed from props or existing state during render, it isn't state.
2. **`useState` in the component** that owns it.
3. **Lift** to the nearest common parent when a sibling needs it.
4. **URL `searchParams`** for anything a user would expect to survive a reload or share in a link — filters, tabs, pagination, the open record. The server can read it, so the page can render correctly on first paint.
5. **`children` / slots** instead of drilling a prop through wrappers that don't use it.
6. **Context** for values that are stable and rarely change — theme, locale, the current user, a form's `id`.
7. **zustand** when several distant subtrees read *and write* the same fast-changing state.

Skipping to rung 7 because prop drilling is annoying is how a codebase ends up with a store nobody can reason about. Two levels of drilling is fine. Rungs 4 and 5 solve most of what people reach for a store to fix.

## zustand

Use it for **client UI state that is shared across the tree**: a multi-step wizard, a cart drawer, canvas/editor state, selection across panels, a command palette.

Do **not** put server data in it. Data fetched by a Server Component arrives as props; mirroring it into a store gives you two sources of truth that drift, and it re-renders on the client what the server already rendered.

### In the App Router, create the store per request — not as a module singleton

A module-level `create()` store is created once per *server process*. On the server that object is shared by every user hitting that process: one request's state leaks into another's. Create a vanilla store inside a provider instead.

```ts
// stores/cart-store.ts
import { createStore } from 'zustand/vanilla'

export type CartState = { items: Item[] }
export type CartActions = { add: (item: Item) => void; clear: () => void }
export type CartStore = CartState & CartActions

export const createCartStore = (init: CartState = { items: [] }) =>
  createStore<CartStore>()(set => ({
    ...init,
    add: item => set(s => ({ items: [...s.items, item] })),
    clear: () => set({ items: [] }),
  }))
```

```tsx
// stores/cart-provider.tsx
'use client'
import { createContext, useContext, useRef } from 'react'
import { useStore } from 'zustand'
import { createCartStore, type CartStore } from './cart-store'

const CartStoreContext = createContext<ReturnType<typeof createCartStore> | null>(null)

export function CartStoreProvider({ children }: { children: React.ReactNode }) {
  const storeRef = useRef<ReturnType<typeof createCartStore>>(null)
  storeRef.current ??= createCartStore()            // one store per mount, not per module
  return <CartStoreContext.Provider value={storeRef.current}>{children}</CartStoreContext.Provider>
}

export function useCartStore<T>(selector: (s: CartStore) => T): T {
  const store = useContext(CartStoreContext)
  if (!store) throw new Error('useCartStore must be used within CartStoreProvider')
  return useStore(store, selector)
}
```

The provider is a client component rendering `{children}` as a slot, so the subtree below it stays server-rendered — see `nextjs-app-router/references/client-boundary.md`.

### Rules

- **Always select.** `useCartStore(s => s.items)` — never `const store = useCartStore()` destructured, which re-renders the component on every unrelated change.
- Selecting several values at once needs `useShallow`, or the new object identity re-renders every time:
  ```ts
  const { items, total } = useCartStore(useShallow(s => ({ items: s.items, total: s.total })))
  ```
- **Actions live in the store**, next to the state they change. A component calls `add(item)`; it does not `set` state from outside.
- Keep stores small and per-domain (`cart-store.ts`, `editor-store.ts`). One `app-store.ts` holding everything is a global variable with extra ceremony.
- Split large stores into slices, composed in one `createStore` call.
- Business rules do **not** go in the store. A store holds UI state and calls a Server Action for anything that must be true on the server.
- `persist` middleware rehydrates from `localStorage` *after* mount, so the first client render differs from the server HTML. Use `skipHydration: true` and rehydrate in an effect, or render the persisted part only once mounted.
- `subscribeWithSelector` for imperative side effects; `devtools` in development only.
- Seed from server data by passing the initial value into the provider — `createCartStore(initialFromServer)` — not by writing into the store from an effect.

## Forms and validation — zod, once, shared

**Every validation boundary is a zod schema in `lib/validation/`, and the same schema is used by the form and the Server Action.** One definition means client and server cannot disagree about what is valid.

```ts
// lib/validation/project.ts
import { z } from 'zod'

export const CreateProjectInput = z.object({
  name: z.string().trim().min(1, 'Name is required').max(80, 'Keep it under 80 characters'),
  visibility: z.enum(['private', 'team']),
  tags: z.array(z.string()).max(10).default([]),
})
export type CreateProjectInput = z.infer<typeof CreateProjectInput>
```

- The messages in the schema are what the user reads. Write them as sentences, not `'invalid'`.
- `z.infer` the type — never hand-write a type beside the schema that says the same thing.
- The schema file imports zod and nothing else: no DB, no React, no `server-only`. Both sides import it.
- Coerce explicitly where the input is stringly-typed — `FormData` and `searchParams` are always strings:
  `z.coerce.number().int().positive()`, `z.coerce.boolean()`.
- Reuse by derivation: `CreateProjectInput.partial()` for a patch, `.omit({ id: true })`, `.extend({ … })`.

### The server side is the one that counts

```ts
'use server'
export async function createProject(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const session = await requireSession()                                   // authenticate
  const parsed = CreateProjectInput.safeParse(Object.fromEntries(formData)) // validate
  if (!parsed.success) return { errors: parsed.error.flatten().fieldErrors }
  await projectService.create(session.userId, parsed.data)                  // authorize + act
  revalidatePath('/projects')
  return { ok: true }
}
```

Client-side validation is a convenience for the user; the server parses the same schema again, always. A form that only validates in the browser is not validated.

### The form component

- Prefer a plain `<form action={action}>` with `useActionState` — it works before hydration, needs no form library, and keeps the page a Server Component apart from the fields that need interactivity.
- Render field errors from the action's returned state, keyed by field name, and wire them with `aria-describedby` + `aria-invalid` so screen readers announce them.
- `useFormStatus` must be called by a component **inside** the `<form>`, not the one rendering it — that's what the submit button uses for its pending state.
- If the project already uses react-hook-form, keep it, and wire the same schema through `@hookform/resolvers/zod`. Don't introduce a second form library, and don't add one where `useActionState` is doing the job.
- Never disable the submit button as the only error handling — say what's wrong.
