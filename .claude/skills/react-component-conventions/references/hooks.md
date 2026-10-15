# Custom hooks

A hook is where a component's *behaviour* lives once it stops being trivial. It owns state, effects, subscriptions and event choreography — and returns data and callbacks. Never JSX.

## When to write one

Write a hook when any of these is true:

- The component has more than ~4 pieces of related state, or state whose transitions have rules.
- The same stateful behaviour is needed by a second component.
- There's an effect with a subscription, a listener, a timer, or cleanup.
- The component's body has become "compute, coordinate, then render" instead of "render".

Do **not** write a hook for a single `useState` that only one component uses, or to wrap one call in a new name. Indirection with no behaviour is a cost with no benefit.

## Shape

```ts
// hooks/use-project-filters.ts
export function useProjectFilters(projects: Project[], initial: Filters) {
  const [filters, setFilters] = useState(initial)

  const toggleTag = useCallback((tag: string) => {
    setFilters(f => ({ ...f, tags: xor(f.tags, tag) }))    // updater form — no stale closure
  }, [])

  const visible = useMemo(() => applyFilters(projects, filters), [projects, filters])

  return { filters, visible, toggleTag }
}
```

Rules:

- **`use` prefix, one file, named export.** File `hooks/use-project-filters.ts` exports `useProjectFilters` — no default exports, no two hooks per file unless one is private to the other.
- **Return an object, not a positional tuple**, once there are more than two values. `const { visible, toggleTag } = …` survives adding a third value; `const [a, b, c] = …` does not.
- **Take data, don't fetch it.** A hook receives server-fetched data as an argument. It does not call the database, and it does not `fetch` in an effect (see `nextjs-app-router/references/client-boundary.md`).
- **Keep the pure part pure.** `applyFilters` above is a helper in `lib/utils/` — testable with no React at all. The hook only wires state to it.
- Hooks live in `hooks/` when shared, or beside the component when it's the only consumer. Colocate first; promote when a second consumer appears.
- A hook that returns JSX is a component wearing a costume. Return data; let the component render.

## Rules of hooks, non-negotiable

- Top level only — never inside a condition, loop, or nested function. The lint rule is not advisory; the bug it prevents is a state mix-up between renders.
- Every hook you call is a dependency of your hook. If yours calls `useSearchParams`, yours is client-only too, and so is every component that calls it.
- A custom hook may only be called from a component or another hook — never from a service, an event handler defined outside a component, or module scope.

## Effects

Most `useEffect` calls should not exist. Before writing one, check:

| You wrote an effect to… | Do this instead |
|---|---|
| fetch data on mount | fetch in a Server Component, pass it as a prop |
| derive state from props | compute it during render; `useMemo` only if it's actually expensive |
| reset state when a prop changes | give the component a `key` so React remounts it |
| respond to a user action | do it in the event handler |
| sync to an external store | `useSyncExternalStore` |

What effects are legitimately for: **synchronising with something outside React** — the DOM, the browser, a websocket, a third-party widget, an analytics SDK.

- Every effect that subscribes returns a cleanup that unsubscribes. No exceptions; StrictMode will run it twice in development precisely to expose the ones that don't.
- The dependency array is not a tuning knob. Never remove a dependency to stop a loop — that hides a stale closure. Fix the cause: move the function inside the effect, wrap it in `useCallback`, or use a `useRef` for a value the effect reads but shouldn't re-run on.
- One effect per concern. Two unrelated subscriptions in one effect re-run each other for no reason.
- Effects don't run on the server. Anything inside one is, by definition, client-only and post-hydration — never put something the first paint depends on in an effect.

## Memoisation

- `useMemo`/`useCallback` are for two things: a genuinely expensive computation, and preserving referential identity for a dependency array or a `memo`'d child. Everywhere else they cost more than they save.
- Measure before optimising. Wrapping every function in `useCallback` makes code harder to read and does not make it faster.
- If a value is expensive *and* pure, it probably belongs on the server anyway.

## State

- Keep state as local as possible, then lift only as far as the nearest common parent that needs it.
- Don't mirror props into state — the copy goes stale. Derive during render.
- Don't store what you can compute. One source of truth, everything else derived.
- URL state (filters, tabs, pagination, the open item) belongs in `searchParams`, not `useState` — it survives reload, it's shareable, and the server can read it.
- Reach for a global store only when several distant subtrees genuinely share mutable state — that's zustand, with a per-request store and selectors (`references/state-and-forms.md`). Context is for stable, rarely-changing values; putting fast-changing state in context re-renders everything below the provider.
