---
description: Run one or more tasks through the full phased build — data layer, route, UI, tests, review — with specialist agents
argument-hint: <task id> [more ids…]
model: sonnet
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, TodoWrite, Skill
---

Task id(s): **$ARGUMENTS**

`T=<Kit helpers>/tasks.sh`, using the **Kit helpers** path from the session report (`.claude/hooks`, or `~/.claude/hooks` on a global install). This command only takes task ids. If the argument is empty or is a description instead of an id, stop and tell the user to create the task first with `/next:write-task <description>`.

`/next:task` sends `size: large` tasks here on its own; running `/next:feature <id>` directly forces the full build on a task of any size. The task-running rules in `/next:task` — token discipline, skill table, verification, memory — apply here too.

For each id, in the order given, skipping any whose dependencies aren't done (`bash $T list` shows them):

1. `bash $T start <id>`, then `bash $T show <id>`. The Acceptance list is the definition of done.
2. Run the phases below.
3. Delegate to `next-verifier` with the task id for an independent verdict, and record each round: `bash $T verdict <id> PASS|FAIL|UNVERIFIED <round>`. On `FAIL`, fix exactly what it lists and re-verify; after two failed rounds, `bash $T block <id> "<failing criteria>"` and stop. Never skip this: `close` refuses without a recorded verdict. On `PASS WITH UNVERIFIED`, name the unverified criteria in the close log line so the user can check them.
4. `bash $T close <id> "<one line: what was built and any decision made>"`. Never push or open a PR — the user publishes.
5. Add anything newly learned about the codebase to `.claude/project-context.md` (one line per fact, keep it under ~60 lines).

## Phases

Each phase's output is the next phase's input. Don't run them all blindly in parallel. Skip a phase the task genuinely doesn't need (no data change → no phase 2) and say so in the report.

### 1. Understand (do this yourself, no subagent)

Use the stack report and project context already in your context. Find and read the closest existing analogue in this repo, such as a similar route, its data access, or its tests, only for what the context file doesn't already record.

Write a short plan: the URL(s), the data read and written, the rendering strategy per segment, the client boundary, and the files you'll create. The task's Notes contain decisions already made; follow them. Ask only if the task is still ambiguous in a way that changes the design: one message with specific questions, before writing code.

### 2. Data layer: delegate to `next-data-layer`

Queries, Server Actions, caching strategy, revalidation, authorization, and schema changes if genuinely required. Give it the plan and the conventions you know.

### 3. Route: delegate to `next-route-builder`

Pages, layouts, loading, error, not-found and metadata, wired to the data layer from phase 2.

### 4. UI: delegate to `next-ui-builder`

The components the route needs, using only the styling stack that's installed. If the task introduces UI with real visual latitude (a new screen rather than another instance of an existing pattern), tell the agent to load `frontend-design` and do its planning pass first. Server Components by default: each piece of interactivity becomes its own small `'use client'` island rendered from the server component that fetched the data, never a `'use client'` page or layout. Components render; they call the data layer from phase 2, with no fetching or business rules inside a `.tsx` file.

### 5. Tests: delegate to `next-test-writer`

Cover the validation and authorization branches of the actions, the interactive components, and one end-to-end path if Playwright is set up.

### 6. Verify and review

Run typecheck, then lint, then tests, then the production build, in that order, fixing as you go. Edit source files only with Edit/Write, never via shell commands, so the guards see every change. Then delegate to `next-reviewer` for a security and boundary pass over the diff, and fix anything it confirms.

## Report

Per task: the URLs added, the files created, the rendering and caching strategy, the authorization model, test coverage, and the verification results. Call out anything you stubbed, assumed, or left for the user to decide. End with the next runnable task.
