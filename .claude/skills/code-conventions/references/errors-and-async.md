# Errors and async

## The rule

**An error must change something.** It is handled, it is turned into a value the caller acts on, or it propagates. What it must never do is disappear.

```ts
try { await save() } catch {}                       // banned
try { await save() } catch (e) { console.log(e) }   // banned — the user still thinks it saved
```

## Throw vs return

| Situation | Do this |
|---|---|
| Programmer error (bad argument, impossible state) | throw — it should crash loudly in development |
| Infrastructure failure (DB down, network) | let it propagate to a boundary that can log and show an error UI |
| Expected domain outcome (invalid input, not found, forbidden) | return it as a value the caller must handle |

Expected outcomes are not exceptions. A Server Action returning `{ ok: false, error: 'Email already taken' }` is control flow the type system can enforce; a thrown string is not. Reserve `throw` for the genuinely exceptional, and use typed error classes so a handler can tell them apart:

```ts
export class NotFoundError extends Error {}
export class ForbiddenError extends Error {}
```

## Error boundaries own the message

Catch where you can actually do something. A `catch` in the middle of a call stack that logs and rethrows adds noise, not information. Add context when you rethrow, don't replace it:

```ts
catch (cause) {
  throw new Error(`Failed to archive project ${id}`, { cause })   // keeps the stack
}
```

- Never leak internals to the user. Log the real error server-side with an id; show "Something went wrong (ref: a1b2c3)".
- `catch (e)` binds `unknown`. Narrow with `e instanceof Error` before touching `.message`.
- One place decides the user-facing copy — the action or the error boundary, not both.

## Async

- **Every promise is awaited or explicitly handled.** A floating promise is an unhandled rejection and a race. If you truly want fire-and-forget, say so: `void track(...)` with a `.catch()` inside.
- **Independent awaits run in parallel.** Sequential `await`s that don't depend on each other are a self-inflicted waterfall:
  ```ts
  const [user, projects] = await Promise.all([getUser(id), listProjects(id)])
  ```
  Use `Promise.allSettled` when one failure shouldn't sink the rest, and handle every rejected entry.
- No `await` inside a `for` loop over independent items — build the array and `Promise.all` it. Keep the loop only when the calls genuinely depend on each other or you're deliberately rate-limiting.
- `async` functions return promises: don't wrap one in `new Promise`, and don't `.then()` inside an `async` function.
- Anything that can hang gets a timeout and an `AbortSignal`. Pass the signal down; don't invent a second cancellation mechanism.
- Don't mix `await` and `.then()` in the same function.

## Cleanup

Whatever you start, you stop — timers, subscriptions, listeners, controllers. In React that's the effect's cleanup function; everywhere else it's `try/finally`. An effect that subscribes without unsubscribing leaks on every re-render, and the leak shows up as a bug somewhere else entirely.

## Logging

- Log at the boundary, once, with structure: an event name and fields, not an interpolated sentence.
- Never log secrets, tokens, full request bodies, or personal data.
- `console.log` is a debugging tool, not an output channel — remove it before you finish, or use the project's logger.
