# Tasks

One file per task. Write them with `/next:write-task`, run them with `/next:task`.

```
/next:write-task <what you want>   plan it: the planner (Opus) writes task files, ready to run
/next:task            build the next runnable task (Sonnet)
/next:task 003        build a specific task
/next:feature 003     force the full phased build on task 003
/next:task list       status of everything (cheap)
bash .claude/hooks/run-tasks.sh --checkpoint   many tasks, fresh context each, one commit per task
bash .claude/hooks/tasks.sh undo 003           revert task 003's checkpoint commit
bash .claude/hooks/tasks.sh stats              time, cost and guard hits so far
```

## Writing a task

Easiest: `/next:write-task <description>` — it asks what it needs, splits the work, and sets
`size` and `depends` for you. By hand: copy `TEMPLATE.md` to `NNN-short-name.md` and fill it in.
The runner reads **only** the task it is working on, plus `.claude/project-context.md` — so
each task should stand on its own.

- **Goal** — the outcome, not the implementation. "Users can archive a project from the list",
  not "add an onClick to ProjectCard that calls prisma".
- **Acceptance** — things someone else could verify. These become the definition of done, and
  the runner will not mark the task complete until each one holds.
- **Notes** — anything that would otherwise be guessed: constraints, decisions already made,
  what is explicitly out of scope.
- **size** — `small` (most tasks) or `large` (spans data + route + UI + tests). Large tasks get the
  full phased build with specialist agents; it costs more, so use it only when true.
- **depends** — ids that must finish first. The runner honours them and skips tasks whose
  dependencies aren't done.

Keep one task to one coherent change. A task that touches the data layer, three routes and
six components is really four tasks, and it will be implemented better as four.

## What the runner does

1. Reads the task and the project context (not the whole codebase).
2. Routes by size — a small change is made directly; a multi-layer one is split across the
   specialist agents.
3. Implements, then verifies with the project's own typecheck/lint/test/build. Only *new* type
   errors fail it; errors that were already there are baselined.
4. Hands the task and its diff to an independent verifier, which checks every acceptance
   criterion without seeing the builder's reasoning. A failing criterion goes back for fixing.
5. Marks the task `done`, appends a one-line log (naming any criteria only you can check), and
   records anything newly learned about the codebase in `.claude/project-context.md` so the next
   task doesn't rediscover it.

It stops and asks only when a task is ambiguous in a way that would change the design.
Anything else it decides, states in the log, and keeps moving.

## Acceptance tags

Each criterion says how it will be proven, because an independent verifier checks it before the
task can close:

- `[test]`: a test must assert it (validation, authorization, a helper's output)
- `[browser]`: only visible in the running app; checked in a browser when `NEXT_WF_DEV_URL` is set.
  Without it they come back UNVERIFIED, and the log line names them for you to check.
- `[review]`: provable by reading the code

## Status

`todo` → `doing` → `done`, or `blocked` with a reason in the log. A task cannot close without a
verifier verdict. Claude pushes or opens a pull request only when you ask; commits, if any, stay
local. You can edit statuses by hand at any time.
