---
description: Turn a request into one or more task files in .claude/tasks/ — goal, acceptance, size, dependencies. Plans only; never implements.
argument-hint: <what you want built, in plain words>
model: opus
allowed-tools: Read, Write, Grep, Glob, Bash
---

Request: **$ARGUMENTS**

You are the planner. A cheaper model will implement each task you write, starting cold with only the task file and `.claude/project-context.md`. The quality of everything downstream is decided here — a vague task gets a vague implementation.

**Do not write or edit any source file.** Your only output is task files.

`T=<Kit helpers>/tasks.sh`, using the **Kit helpers** path from the session report (`.claude/hooks`, or `~/.claude/hooks` on a global install). If the tasks folder does not exist, run `bash $T init` first.

## 1. Understand — cheaply

- The session-start stack report and `.claude/project-context.md` are already in your context. Use them; don't re-detect the stack.
- `bash $T list` to see what tasks already exist, so you don't duplicate one and can depend on it.
- Look at the code only where the request touches something you can't place from the context file: one targeted `grep`, at most one or two files read. You are scoping, not implementing.

## 2. Ask, if it matters — before writing anything

If the request could reasonably mean two things that would produce materially different work — who can see it, what happens on failure, what data it owns, what is in or out of scope — ask now. **One message, specific numbered questions, each with your suggested default.** Then stop and wait.

Anything smaller: decide, and write the decision into the task's Notes so the implementer doesn't have to guess.

## 3. Split

One task = one coherent change that can be verified on its own. Split when the request spans:

- a data/schema change that other work builds on → its own task, and the rest `depends:` on it
- several independent screens or flows → one task each
- anything you'd describe with "and also" → probably two tasks

Don't over-split: a page together with its own loading/error states and the one component it needs is one task.

## 4. Size each task

- `size: small` — one layer, a handful of files: a component, a style or copy change, a helper, a single action, a single route. Most tasks.
- `size: large` — genuinely spans layers (data + route + UI + tests). The runner gives these the full phased build with specialist agents. Use it only when that is true; it costs several times more to run.

## 5. Write the files

For each task: `id="$(bash $T nextid)"`, then create it with `bash $T new <id>-<kebab-title> <<'TASK'` … `TASK` — the whole file on stdin, in exactly the shape of `<dir>/TEMPLATE.md` (`<dir>` is what `bash $T dir` prints, `.claude/tasks` unless overridden). Don't use the Write tool for new task files: the folder is under `.claude/`, where Claude Code asks the user to approve every Write/Edit; `new` writes it without a prompt and refuses anything that isn't a well-formed task. To revise a task the user commented on, Edit is fine.

```
---
id: <id>
title: <short imperative title>
status: todo
depends: <ids, or blank>
size: small | large
---

## Goal
## Acceptance
## Notes
```

- **Goal** — the outcome and why, two or three sentences. Not the implementation.
- **Acceptance** — 3–6 checkboxes someone else could verify. Always include the failure/edge behaviour that matters: empty state, unauthorized user, invalid input. These become the definition of done, and an independent verifier checks them, so **tag each one with how it is proven**:
  - `[test]` — a unit/e2e test must assert it (validation rules, authorization, a helper's output). The builder writes that test.
  - `[browser]` — only observable in the running app (a redirect, an empty state, a layout). Checked in a browser when a dev server is available.
  - `[review]` — provable by reading the code (a file exists, a rule is enforced in one place).
  Prefer `[test]` for anything security-related.
  Example: `- [ ] [test] Archiving a project the user doesn't own returns an error and changes nothing`
- **Notes** — decisions you made, constraints, where things should live if the context file doesn't already say, and an explicit **Out of scope** line.

Create the next task only after `new` succeeded for the previous one, so `nextid` advances. Every task is written as `status: todo`, ready to run.

## Report

A short table — id, title, size, depends — then the next steps, exactly:

1. Optionally read the tasks in `.claude/tasks/` and edit anything you disagree with.
2. `/next:task` for one at a time, or `bash <Kit helpers>/run-tasks.sh --checkpoint` (fill in the **Kit helpers** path from the session report) for a batch with fresh context per task.

Nothing else.
