---
name: react-component-conventions
description: Component architecture rules for this codebase — single responsibility, UI-only components, and where logic actually belongs (hooks, services, helpers, schemas). Load before writing, reviewing, or refactoring any React component, hook, or the module a component imports logic from.
---

# Component conventions

## The rule

**A component renders. It does not decide.** Anything that is not "turn these props into markup" belongs in a layer below it.

| Layer | Lives in | Owns | Never |
|---|---|---|---|
| **Component** `.tsx` | `components/`, `app/**/_components/` | markup, layout, styling, wiring props to elements | fetching, business rules, validation, persistence |
| **Hook** `use-*.ts` | `hooks/` or beside the component | client state, effects, event orchestration, subscriptions | JSX, direct DB access |
| **Service** `*.ts` | `lib/services/`, `server/` | business operations, orchestration, authorization | JSX, React imports |
| **Data access** | `lib/db/`, `lib/repositories/` | queries, the ORM, the only place the schema is known | business rules |
| **Helpers** | `lib/utils/`, `lib/format/` | pure functions — format, transform, derive, compare | side effects, I/O |
| **Schemas** | `lib/validation/` | **zod** shapes shared by forms, actions, and API | UI concerns |
| **Client store** | `stores/*-store.ts` | **zustand** — client UI state shared across distant subtrees | server data, business rules, anything a URL param could hold |

A component may still: map over a list, branch on a prop, compose classNames, and call a helper to format a value. That's rendering. It may not: fetch, validate, compute prices, apply permissions, or reach for the database.

**Existing stack.** When the session report says *match the existing stack* (Redux Toolkit, RTK Query, react-query, formik, yup, antd…), read `references/existing-stacks.md` first. The project's libraries replace the **zod** and **zustand** rows above, and the rest of this file applies unchanged.

## Single responsibility

- **One component, one job.** If the name needs an "and" — `UserCardAndEditModal` — it's two components.
- **One exported component per file.** Small subcomponents used only by that file may live alongside it, unexported.
- **~150 lines** is the point to stop and extract. Past ~200 you are almost certainly rendering two things.
- Extract when: a block of JSX has its own conditional state; a `map` callback grows past a few lines; the same markup appears twice.
- Don't extract a component that takes 9 props to avoid 20 lines of markup — that's worse than the duplication.

## Getting logic out of a component

**State machines, effects, event choreography → a hook.**

```ts
// hooks/use-project-filters.ts
export function useProjectFilters(initial: Filters) {
  const [filters, setFilters] = useState(initial)
  const toggle = useCallback((tag: string) => { … }, [])
  const visible = useMemo(() => applyFilters(items, filters), [items, filters])
  return { filters, toggle, visible }
}
```
The component becomes `const { visible, toggle } = useProjectFilters(initial)` and a list. A hook returns data and callbacks — never JSX.

**Business operations → a service**, called from a Server Component or a Server Action, never from a component's `useEffect`:

```ts
// lib/services/projects.ts
import 'server-only'
export async function archiveProject(userId: string, projectId: string) {
  const project = await projectRepo.byId(projectId)
  if (project.ownerId !== userId) throw new ForbiddenError()   // rule lives here
  return projectRepo.archive(projectId)
}
```

**Pure transformations → a helper.** `formatCurrency`, `slugify`, `isOverdue`, `groupByDay`. Testable without React, reusable outside the one component that first needed them.

**Shapes → a schema** in `lib/validation/`, imported by both the form and the Server Action so the client and server agree by construction.

## Data flow

- Server Components fetch (via a service) and pass plain data down.
- **Never fetch in `useEffect`.** If a Client Component needs data, the server parent passes it as a prop, or it's genuinely user-triggered and goes through a Server Action or a data-fetching library the project already uses.
- **Server Component by default; a Client Component is the last option, never the first.** Before adding `'use client'`, check whether a form action, a `<Link>`, CSS, or streaming does the job.
- When interactivity is genuinely needed, **split it into its own file** containing only the interactive part, and render it from the Server Component that owns the data. Don't mark the parent `'use client'` to reach one button. The `nextjs-app-router` skill's `references/client-boundary.md` has the pattern in full.
- Props are the contract: explicit exported type, minimal, no `any`, no `data: any[]`. Prefer `React.ComponentProps<'button'> & { … }` when wrapping a native element.
- More than two levels of prop drilling → compose with `children`/slots, or URL `searchParams`, or a context beside its provider. A zustand store is the last rung, for state several distant subtrees read *and* write — see `references/state-and-forms.md`.

## Naming and layout

```
components/project-card.tsx        one component, exported as ProjectCard
components/archive-button.client.tsx  the client island — 'use client', interactivity only
components/project-card.test.tsx   its test, colocated
hooks/use-project-filters.ts       exports useProjectFilters
lib/services/projects.ts           archiveProject, listProjects
lib/validation/project.ts          ProjectSchema, CreateProjectInput
lib/utils/format.ts                formatCurrency, formatRelativeDate
```
Follow whatever the repo already does for casing and directory names — read two files first. Consistency with the codebase beats consistency with this document.

## Consequences worth knowing

Components this thin are testable without mocking a network, hooks are testable without rendering a tree, services are testable without React, and moving a component from server to client stops being a rewrite. That's the payoff — the rule isn't aesthetic.

## References

Read the one that matches the layer you're touching:

- `references/hooks.md` — when a hook is warranted, its shape, the rules of hooks, and why most `useEffect` calls shouldn't exist.
- `references/services-and-data.md` — services vs data access, `server-only`, authorization, and where each rule belongs.
- `references/existing-stacks.md` — working inside a Redux / RTK Query / react-query / formik + yup / antd codebase: what replaces the kit's defaults and what doesn't.
- `references/state-and-forms.md` — the state ladder, zustand in the App Router (per-request stores, selectors), and zod forms wired to Server Actions.
- `references/helpers-schemas-types.md` — pure helpers, validation schemas shared by form and action, types, constants and env config.
- `references/refactor-examples.md` — a fat component pulled apart step by step.
- `references/checklist.md` — the pre-commit pass.

General TypeScript and clean-code rules that apply to every layer are the `code-conventions` skill. The client/server split and hydration are `nextjs-app-router/references/client-boundary.md`.
