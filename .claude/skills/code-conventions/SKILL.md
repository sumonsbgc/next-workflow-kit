---
name: code-conventions
description: General programming conventions for this codebase — naming, module structure, function design, control flow, types, errors, async, imports, comments and dead code. Load before writing or reviewing any TypeScript/JavaScript file, alongside the framework-specific skills.
---

# Code conventions

Rules that apply to every `.ts`/`.tsx` file regardless of layer. Component architecture is `react-component-conventions`; App Router behaviour is `nextjs-app-router`. This skill is about the code itself.

## Rule zero

**Read two neighbouring files before writing one.** Every rule here loses to an established pattern in the repo. Consistency with the codebase beats consistency with this document — a lone "correct" file among fifty that do it differently is a defect, not an improvement.

## Naming

| Thing | Convention | Example |
|---|---|---|
| Files | `kebab-case` | `project-card.tsx`, `use-project-filters.ts` |
| Components | `PascalCase`, noun | `ProjectCard` |
| Hooks | `use` + noun phrase | `useProjectFilters` |
| Functions | `camelCase`, verb first | `archiveProject`, `formatCurrency` |
| Booleans | `is`/`has`/`can`/`should` prefix | `isArchived`, `canEdit` |
| Predicates | `is`/`has` returning boolean | `isOverdue(task)` |
| Handlers | `handleX` locally, `onX` as a prop | `onSelect={handleSelect}` |
| Async that fetches | `get`/`list`/`find` | `listProjects`, `findUserByEmail` |
| Async that mutates | the actual verb | `archiveProject`, not `doArchive` |
| Types/interfaces | `PascalCase`, no `I` prefix | `Project`, `CreateProjectInput` |
| Constants | `SCREAMING_SNAKE` only for module-level literals | `MAX_UPLOAD_BYTES` |

- Name by **what it means, not what it is**: `retryDelayMs`, not `num2`; `visibleProjects`, not `filteredData`.
- Units and currency go in the name: `timeoutMs`, `priceCents`, `sizeBytes`. This prevents an entire class of bug.
- No abbreviations that aren't already in the domain (`id`, `url`, `db` are fine; `usrPrf` is not).
- No `data`, `info`, `item`, `obj`, `temp`, `handleThing` as final names. If the best name is `data`, you haven't decided what it is.
- The name says what it does, including the cost: `fetchUser` goes to the network, `getUser` doesn't.

## Functions

- **One job.** If you need "and" to describe it, split it. If it takes a boolean flag that switches behaviour, that's two functions.
- Under ~40 lines. Past that, name the parts.
- **Three arguments max.** More, or two of the same type in a row, → one options object with a named type. `createUser({ name, email, role })` cannot be called with the arguments swapped; `createUser(name, email, role)` can.
- **Early return over nesting.** Guard clauses first, happy path last and unindented. Never more than two levels of nesting in one function — a third level is a function waiting to be extracted.
- **Pure by default.** A function that takes inputs and returns output, with no I/O and no mutation of its arguments, is testable, movable, and cacheable. Push side effects to the edges (actions, services, effects) and keep the middle pure.
- Don't mutate parameters. Return a new value.
- Return early-and-typed rather than accumulating an `let result` you reassign four times.

## Control flow and data

- `const` everywhere; `let` only when a value genuinely changes; never `var`.
- Prefer `map`/`filter`/`reduce`/`find` over index loops when it reads better — but a `for…of` is clearer than a `reduce` that builds an object. Choose the one a reader understands fastest.
- No magic values. `if (status === 3)` → a named constant or a union type. Same for `'admin'`, `86400000`, `'#0ea5e9'`.
- Optional chaining and `??` over `&&` chains and `||` defaults — `count ?? 10` is not `count || 10` when `count` is `0`.
- Immutability by default: `[...items, next]`, `{ ...obj, key }`. Mutating shared state is how two components disagree about the truth.
- Comparisons are `===`. `==` only for the deliberate `x == null` null-and-undefined check, and prefer `x ?? …`.

## Modules and imports

- **One concern per file.** A file's name should predict its contents exactly.
- Import order: node builtins → external packages → internal aliases (`@/…`) → relative → styles. Let the formatter/linter enforce it; don't hand-sort against the tool.
- Use the project's path alias (`@/lib/…`) rather than `../../../lib/…`. Three or more `../` means the file is in the wrong place.
- **No barrel files** (`index.ts` re-exporting a directory) unless the repo already uses them — they defeat tree-shaking, create import cycles, and pull server code into client bundles by accident.
- Import types with `import type { … }` so the import is erased at build time and can never drag runtime code across a boundary.
- Circular imports are a design error, not a build warning. Break them by moving the shared thing down a layer.
- Never deep-import another module's internals. If two modules need the same thing, it belongs in a third.

## Comments

- Comment **why**, never **what**. `// clamp to 100 — the vendor API rejects larger pages` earns its place; `// loop over users` does not.
- A comment explaining confusing code is a bid to rewrite the code. Take the bid.
- No commented-out code. Git remembers it.
- No `// TODO` without a name or an issue reference — an anonymous TODO is never done.
- JSDoc on exported functions whose contract isn't obvious from the signature: what it throws, what it revalidates, what it costs.

## Dead code and duplication

- Delete unused exports, parameters, props, and dependencies as you find them. Unused code is read, maintained, and trusted by mistake.
- **Rule of three.** Two similar blocks are a coincidence; the third is a pattern. Abstracting on the first duplicate usually produces a worse abstraction than the duplication it removed.
- The wrong abstraction costs more than duplication. If a shared helper has grown flags to serve its callers, split it back apart.
- Before writing a helper, grep for it. This codebase probably already formats that date.

## Types

Strict TypeScript is not optional — see `references/typescript.md`. The headline: **no `any`**, no non-null `!` to silence the compiler, no `as` to make a shape fit. Model the domain so illegal states can't be constructed.

## Errors and async

See `references/errors-and-async.md`. The headline: **never swallow an error**. No empty `catch`, no `catch` that only logs and continues as if nothing happened, no floating promise.

## References

- `references/typescript.md` — the type-level rules: strictness, unions over enums, narrowing, generics, `satisfies`, parsing at the boundary.
- `references/errors-and-async.md` — error types, throw vs return, async patterns, parallelism, cancellation, logging.
