# Component review checklist

Run through this before calling a component done.

**Responsibility**
- [ ] The component's name describes one thing, with no "and".
- [ ] One exported component per file; helpers used only here are unexported and below it.
- [ ] Under ~150 lines. If not, what is the second thing it renders?

**No logic inside**
- [ ] No `fetch`, no ORM/DB import, no API client call.
- [ ] No `useEffect` that loads data.
- [ ] No business rule — pricing, permissions, eligibility, state transitions — inline in JSX or handlers.
- [ ] No validation logic; a schema from `lib/validation/` is used instead.
- [ ] No inline `Intl`/date arithmetic/string munging; a helper does it.
- [ ] Handlers are thin: they call a hook callback or a Server Action, they don't implement the operation.

**Boundary**
- [ ] A Server Component was tried first — a form action, `<Link>`, CSS, or streaming doesn't already solve it.
- [ ] `'use client'` is present only if the component itself needs state/effects/handlers/browser APIs.
- [ ] The island is its own file containing only the interactive part, rendered from the Server Component that owns the data — not a page, layout, or list marked `'use client'`.
- [ ] Server-fetched data arrives as props; the island fetches nothing itself.
- [ ] Nothing server-only is reachable from a client module.

**Hydration** (server and client must render the same thing)
- [ ] No `new Date()`, `Date.now()`, `Math.random()` or uuid rendered directly; `useId()` for ids.
- [ ] No `toLocaleString()` without an explicit locale.
- [ ] No `localStorage`/`sessionStorage`/`matchMedia`/`document` read during render.
- [ ] No `typeof window` branch that changes the markup.
- [ ] Valid HTML nesting (no `<div>` inside `<p>`).

**Props**
- [ ] Exported, explicit props type; no `any`; no `object`/`unknown[]` stand-ins.
- [ ] Minimal surface — no props that exist only to be passed straight through more than two levels.
- [ ] Serializable if it crosses the server→client boundary.

**States**
- [ ] Loading, empty, and error states are rendered, not assumed away.
- [ ] Disabled/pending states on anything that submits.

**Accessibility**
- [ ] Semantic element for the job; every control labelled; keyboard operable; visible focus.

**Styling** (if Tailwind)
- [ ] Classes exist in the *installed* version — no v3 leftovers (`bg-opacity-*`, `flex-shrink-0`), no utility from a newer minor.
- [ ] No interpolated class names; complete literal strings only.
- [ ] Theme tokens rather than scattered arbitrary values.
- [ ] Buttons and links show a pointer cursor (base-layer rule, or `cursor-pointer` on the element) — Tailwind v4 Preflight no longer does this for you; disabled controls get `cursor-not-allowed`.

**Tests**
- [ ] The extracted helper/hook/service has a unit test.
- [ ] The component's own test renders it from literal props, with no network mock in sight.
