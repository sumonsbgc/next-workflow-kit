---
description: Full pre-ship gate — typecheck, lint, tests, production build — fixing what fails
argument-hint: (no arguments)
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, TodoWrite, Skill
---

Take the current changes to a shippable state. Use the exact commands from the session-start stack report (`bash .claude/hooks/stack.sh` if you need them again).

Run in this order, and **stop at the first failure, fix it, then restart from that step**:

1. **Typecheck** — fix the types properly. No `any`, no `@ts-expect-error`, no non-null assertions to silence an error you don't understand.
2. **Lint** — fix the violations. Do not add eslint-disable comments unless you can justify the specific line in your report.
3. **Tests** — fix the code, or the test if the test is genuinely wrong. Never skip, weaken, or delete a test to get green.
4. **Production build** — this is where the App Router mistakes surface (Suspense boundaries, server-only imports in client bundles, metadata from client modules). On Next 15, read the route table it prints and flag any route whose First Load JS looks out of line with its siblings. Next 16 removed those size metrics from the build output, so don't look for them there; say that bundle size needs Lighthouse or analytics.

Then a fast self-review of the diff: secrets, `console.log`, TODOs, dead code, forgotten stubs, `.env` files staged.

## Report

A short status table — step, command, pass/fail, what you fixed. Then anything still broken, and anything you changed that the user should look at before committing. Do not commit or push unless explicitly asked.
