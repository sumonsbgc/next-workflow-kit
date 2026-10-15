# TypeScript rules

## Strictness

`strict: true` in `tsconfig.json` is the baseline. If the project has it off, don't fight it file by file — say so and keep your own files clean.

Banned, in order of how much damage they do:

| Escape hatch | Why it's banned | Instead |
|---|---|---|
| `any` | turns off checking for everything it touches, silently and transitively | `unknown` + narrowing, or the real type |
| `as X` | asserts a lie the compiler then trusts | fix the type, or parse with a schema |
| `!` (non-null) | claims a value exists with no evidence | narrow it, or handle the `undefined` |
| `@ts-ignore` | hides the next error too | `@ts-expect-error` with a one-line reason, so it fails when the bug is fixed |
| `Function`, `object`, `{}` | mean almost nothing | a real signature or shape |

`unknown` is the honest version of `any`: it forces you to prove what the value is before using it. Use it for anything crossing a trust boundary — JSON, `catch` bindings, third-party responses.

## Model the domain, not the JSON

Make illegal states unrepresentable and half your validation disappears:

```ts
// weak — four impossible combinations exist
type Request = { loading: boolean; data?: User; error?: Error }

// strong — a discriminated union; the compiler enforces the branches
type Request =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: User }
  | { status: 'error'; error: Error }
```

- Discriminated unions over optional-everything objects.
- **Union of string literals over `enum`.** `type Role = 'admin' | 'member'` is erased at compile time, works with plain strings, and doesn't have TypeScript's `enum` runtime quirks.
- Branded/opaque ids where mixing them is plausible: `type UserId = string & { readonly __brand: 'UserId' }`. Cheap, and it makes `archiveProject(userId, projectId)` un-swappable.
- `readonly` on props and on arrays you don't intend to mutate.
- Derive, don't duplicate: `type ProjectStatus = Project['status']`, `Pick`, `Omit`, `Awaited<ReturnType<typeof getProject>>`, `z.infer<typeof Schema>`. One source of truth per shape.

## Narrowing

```ts
function assertNever(x: never): never {
  throw new Error(`Unhandled variant: ${JSON.stringify(x)}`)
}

switch (req.status) {
  case 'idle': …
  case 'loading': …
  case 'success': return req.data
  case 'error': throw req.error
  default: return assertNever(req)   // adding a variant now breaks the build
}
```

Use `switch` with an exhaustiveness check for unions. Write type guards as `function isProject(v: unknown): v is Project` rather than casting at each call site.

## Inference vs annotation

- **Annotate what you export**, infer what's local. An exported function's return type is its contract — write it down so a refactor inside can't silently change the API.
- Don't annotate what's obvious: `const count = 0`, not `const count: number = 0`.
- `satisfies` when you want a value checked against a type *and* to keep its narrow inferred literal types:
  ```ts
  const routes = { home: '/', project: '/projects/[id]' } satisfies Record<string, `/${string}`>
  // routes.home is '/' — not string
  ```

## Generics

Generics are for relating types to each other, not for looking sophisticated. If a type parameter appears exactly once in the signature, it should have been `unknown` or a concrete type. Constrain them (`<T extends { id: string }>`) so error messages point at the call site. Two type parameters is usually the limit before a caller can no longer read it.

## Parse at the boundary

Every value entering the program from outside — request bodies, `searchParams`, form data, `process.env`, `localStorage`, a third-party API — is `unknown` until a schema says otherwise. Parse it once, at the edge, into a domain type; everything inside the boundary then works with values the compiler can trust. See `react-component-conventions/references/helpers-schemas-types.md` for where those schemas live.

```ts
const parsed = CreateProjectInput.safeParse(raw)
if (!parsed.success) return { error: parsed.error.flatten().fieldErrors }
// parsed.data is typed and validated from here on
```

Typing a fetch response as `Promise<User>` is a claim, not a check. `.json()` returns `any`; the assertion just moves the crash somewhere less obvious.

## Types that don't earn their keep

- `interface` vs `type`: pick what the repo uses. Only `interface` supports declaration merging; `type` does unions. Don't churn existing files to switch.
- No type gymnastics that need a comment to read. A conditional-mapped-template type saving three lines of duplication is a net loss.
- Don't export a type nobody imports.
