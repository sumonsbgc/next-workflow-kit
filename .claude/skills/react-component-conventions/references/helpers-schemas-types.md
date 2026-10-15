# Helpers, schemas, types and constants

The small layers. They have no state, no I/O, and no framework — which is exactly why everything else can depend on them.

## Helpers (`lib/utils/`)

A helper is a **pure function**: same input, same output, no side effects, no clock, no network, no `document`.

```ts
// lib/utils/format.ts
export function formatCurrency(cents: number, currency = 'USD') {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(cents / 100)
}
```

- Group by topic in named files — `format.ts`, `dates.ts`, `slug.ts`, `array.ts`. **Never a `utils.ts` junk drawer**: a file named after nothing collects everything and is never deleted from.
- Verb-first names that say what comes back: `formatCurrency`, `groupByDay`, `isOverdue`, `toSlug`.
- No React import. No `window`. If it needs either, it's a hook or a component, not a helper.
- **Grep before you write one.** Date formatting already exists in most codebases, twice.
- Reach for the standard library and the framework first: `Intl` for dates/numbers/currency/lists, `URLSearchParams` for query strings, `structuredClone` for deep copies. Don't add a dependency for a five-line function, and don't hand-roll what `Intl` already does correctly in every locale.
- Anything reading the current time takes it as an argument (`isOverdue(task, now)`) — otherwise it can't be tested and it will differ between server render and hydration.
- Pure means trivially testable: no mocks, no setup, one line per case. If a helper needs a mock, it isn't pure.

## Schemas (`lib/validation/`)

**zod is the validation library for this codebase.** One schema per shape, defined once and imported by **the form, the Server Action, and any route handler** so the client and server cannot disagree. Form wiring and `useActionState` are in `references/state-and-forms.md`.

```ts
// lib/validation/project.ts
import { z } from 'zod'

export const CreateProjectInput = z.object({
  name: z.string().trim().min(1, 'Name is required').max(80),
  tags: z.array(z.string()).max(10).default([]),
})
export type CreateProjectInput = z.infer<typeof CreateProjectInput>
```

- **Infer the type from the schema** — never hand-write a type next to a schema that describes the same shape; they drift within a month.
- Schema files import nothing but the validation library. No DB, no React, no server-only code — both sides of the boundary import them.
- The error messages in the schema are the ones the user reads. Write them as messages, not as `'invalid'`.
- Validate **at the boundary, once**: the action parses `FormData`/JSON into a domain object, and everything downstream receives trusted, typed values. Don't re-validate in three layers.
- Client-side validation is a convenience. The server parses the same schema again, always — the client can be bypassed.
- Coerce explicitly where input is stringly-typed (`searchParams`, `FormData`): `z.coerce.number().int().positive()`.
- Never derive a database schema from a form schema or vice versa. They describe different things and diverge on purpose.

## Types (`types/` or beside the owner)

- A type lives next to what it describes. Export `Project` from the module that owns projects. A global `types.ts` that everything imports becomes a dependency cycle with extra steps.
- `types/` at the root is for genuinely cross-cutting shapes and third-party module augmentation only.
- Derive rather than restate: `z.infer<typeof Schema>`, `Awaited<ReturnType<typeof listProjects>>`, `Pick<Project, 'id' | 'name'>`.
- Props types are exported from the component file, not from a shared types file.

## Constants (`lib/constants.ts` or beside the owner)

- Anything a reader would otherwise have to decode: page sizes, limits, retry counts, feature keys, route paths, external URLs.
- `SCREAMING_SNAKE` for module-level literals; `as const` for object and array literals so their members stay narrow types.
- Domain values that a union type already covers (`'admin' | 'member'`) don't also need constants.
- Config that varies by environment is **not** a constant — it's parsed `process.env`, in one module, with a schema, exported typed. Read `process.env` in exactly one place and import the result everywhere else; a typo'd env var should fail at startup, not at midnight.
