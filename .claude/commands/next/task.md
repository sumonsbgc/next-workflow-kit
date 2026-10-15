---
description: Run a task from the tasks/ folder end to end — read it, implement it, verify it, record what was learned
argument-hint: [blank = next task | <id> [headless] | all | list | init]
model: sonnet
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, TodoWrite, Skill
---

Argument: **$ARGUMENTS**

`T=<Kit helpers>/tasks.sh`, using the **Kit helpers** path from the session report (`.claude/hooks`, or `~/.claude/hooks` on a global install). Use it for all task bookkeeping. Never glob or read `tasks/*.md` yourself; that is what the helper is for and it costs a fraction of the tokens.

| Argument | Do |
|---|---|
| *blank* | `bash $T next` → run that one task |
| `<id>` | `bash $T path <id>` → run that task |
| `<id> headless` | run that task with **no user present** (started by `run-tasks.sh`). Never ask a question: where you would ask, `bash $T block <id> "<the question>"` and stop. |
| `all` | see **Batch mode**. |
| `list` | `bash $T list` and report it. Nothing else. |
| `init` | `bash $T init`, then report what to do next. Nothing else. |

## Token discipline — this is a requirement, not a preference

You are running against a task list, not a conversation. The same waste repeated across twenty tasks is the difference between finishing and running out of context.

1. **The session-start report and `.claude/project-context.md` are already in your context.** Never re-derive what they say — no re-detecting the package manager, the Tailwind version, the test runner, or where components live.
2. **Read only the task you are running.** `bash $T show <id>`. Not the other task files.
3. **Read a source file once.** If you have already read it this session, you know its contents — do not re-read to "check".
4. **Grep before you read.** `grep -rn "requireSession" --include=*.ts -l` to find the file beats reading four candidates.
5. **Load skills by need, not by habit** — see the table below. A CSS tweak does not need the data-layer conventions.
6. **Delegate only what pays for itself.** A subagent starts cold and re-reads context you already have; it is worth it when the work is genuinely a separate layer with its own conventions, and a waste for a two-file change. Route by size — see **Routing**.
7. **Edit source files only with Edit/Write**, never with `sed -i`, heredocs or scripts. The guards and the formatter run on Edit/Write; shell writes are caught after the fact and cost you a round-trip.
8. **Verify proportionally** — see **Verification**. A full production build after every one-line change is minutes of wall clock for nothing.
9. **Report in tens of lines, not hundreds.** No file dumps, no restating the diff, no narrating what you are about to do.

### Which skill for which task

| The task touches | Load |
|---|---|
| a component, hook, or its markup/styling | `react-component-conventions`; `nextjs-app-router/references/styling.md` only if styling changes |
| **building new UI, a screen, or a visual redesign** | **`frontend-design`** (user-level skill — skip if absent), in addition to the above. Not for refactors, bug fixes, copy changes, or components whose look is dictated by existing siblings. |
| the client/server split, or anything that renders differently on the client | `nextjs-app-router/references/client-boundary.md` |
| a Server Action, query, cache, or schema change | `nextjs-app-router` + `references/server-actions.md` or `references/data-and-caching.md`; `react-component-conventions/references/services-and-data.md` |
| shared client state or a form | `react-component-conventions/references/state-and-forms.md` |
| a route, layout, metadata, loading/error boundary | `nextjs-app-router` |
| tests | `nextjs-app-router/references/testing.md` |
| anything non-trivial in TypeScript | `code-conventions` |

Load the reference, not the whole skill, when the reference is what you need.

## Running one task

1. **Claim it.** `bash $T start <id>`. If it refuses because the task is a `draft`, stop and tell the user to review it and run `bash $T approve <id>`. Drafts are unreviewed plans.
2. **Read it.** `bash $T show <id>`. The Acceptance list is the definition of done — you will check each item at the end.
3. **Orient, cheaply.** From the project context you should already know where things go. If something genuinely isn't recorded there, find it with one targeted grep and read at most one existing analogue — then add what you learned to the context file at the end.
4. **Decide the shape before writing.** The files you will touch, the client/server split, what the data layer must expose. Server Components by default; interactivity becomes its own island file.
5. **Implement.** Every `[test]` criterion needs a test that asserts it, because the verifier will look for it. Follow the conventions; the PostToolUse guards will tell you immediately if you break a boundary, hydration, or Tailwind rule — fix what they report rather than arguing with them.
6. **Verify** — see below.
7. **Get an independent verdict.** First run `bash $T can-skip-verify <id>`.
   - It says `yes` (every criterion is `[review]` and the diff is 20 lines or fewer): check the list yourself, item by item, and record `bash $T verdict <id> SKIPPED`.
   - Otherwise delegate to `next-verifier` with just the task id. It reads the task and `bash $T diff <id>` itself, and never sees your reasoning. That's the point. After **every** verifier round, record it with `bash $T verdict <id> PASS|FAIL|UNVERIFIED <round>` (`PASS WITH UNVERIFIED` → `UNVERIFIED`).
   - `FAIL` → fix exactly what it lists, re-verify. After two failed rounds, `bash $T block <id> "<the failing criteria>"` and stop.
   - `PASS WITH UNVERIFIED` → close, and name the unverified `[browser]` criteria in the log line so the user can check them.
8. **Close it.** `bash $T close <id> "<one line: what you did and any decision you made>"`.
9. **Record what you learned** — see **Memory**.

### Ambiguity

Proceed under a stated assumption and log it. (Headless: never ask, block with the question instead.) Stop and ask **only** when the task could reasonably mean two different things that would produce materially different work, and getting it wrong would waste the implementation. In that case ask one specific question, and ask it before writing code rather than after.

## Routing

The task's `size:` field decides first — it was set by the planner (`/next:write-task`), which saw the whole request:

- **`size: large`** → read `.claude/commands/next/feature.md` and run its **Phases** section for this task, delegating each phase. Do the claim/close/memory steps from this file as usual. Read that file only for large tasks — it is not needed otherwise.
- **`size: small`, or no size** → judge from the task itself:
  - **One or two files, one layer** (a component, a style fix, a copy change, a helper) → **do it yourself**. No subagents. This is most tasks.
  - **One layer, but with its own conventions** (only the data layer; only tests) → delegate to that **one** agent: `next-data-layer`, `next-route-builder`, `next-ui-builder`, or `next-test-writer`.
  - **Genuinely multi-layer** (data + route + UI + tests) despite a `small` label → treat it as large (above), and say in the log that you re-sized it.

Whenever you delegate, give the agent the conventions you already know so it does not rediscover them.

- **Review** — delegate to `next-reviewer` only for security-sensitive or multi-file work: anything touching a Server Action, auth, or the client boundary. Not for a styling task.

## Verification

Run the narrowest thing that would catch a mistake in what you changed:

| Changed | Run |
|---|---|
| styling, copy, markup only | typecheck |
| a component, hook, or helper | typecheck, then its tests if they exist |
| a Server Action, route, or the client boundary | typecheck, then **build** — these fail at build time and nowhere else |
| anything, before the last task of a batch | typecheck, lint, tests, build |

Use the exact commands from the session-start report. Fix what fails before closing the task — a task that leaves the tree broken is not done, and the next task inherits the mess.

## Batch mode (`all`)

Every task in one conversation means context grows with each one, and by the fifth task details get compacted away and quality drops. So in-session batches are capped:

- Run **at most 3** runnable tasks this way: `bash $T next` → run it fully → close it → repeat.
- If more remain, stop and tell the user to run the rest with fresh context per task: `bash .claude/hooks/run-tasks.sh` (add `--checkpoint` for one local commit per task, so any single task can be undone with `bash $T undo <id>`).
- Stop early if a task ends `blocked`, verification fails in a way you cannot fix, or a task needs a decision only the user can make. Report which tasks completed and which is stuck.
- Run the **full** verification (typecheck, lint, tests, build) once at the end of the batch, not after every task.

## Memory — leave the next run cheaper than this one

Before finishing, update `.claude/project-context.md` with anything you had to discover that isn't already there: where a kind of file lives, what a helper is called, a convention you inferred, a decision you made and why, a gotcha that cost you time.

- One line per fact, under the right heading. No narrative, no history.
- **Prune while you are there.** If the file is over ~60 lines, merge duplicates and delete what is now obvious from the code. It is injected into every session, so every line costs tokens forever.
- Do not record what the stack report already detects, or what a task file already says.

## Report

Short, and in this order: the task, what changed (paths only), any decision or assumption you made, verification results, and what the next runnable task is. If you skipped or stubbed something, say so plainly.
