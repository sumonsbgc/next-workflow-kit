---
description: Detect this Next.js project's stack and wire the workflow into it (CLAUDE.md stack section, missing scripts, gitignore)
argument-hint: (no arguments)
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

Wire this Next.js agentic workflow into the current project. Run once per project.

## Steps

1. Run `bash <Kit helpers>/stack.sh` and read the detected stack. **Kit helpers** is the path in the session-start report: `.claude/hooks` for a project install, `~/.claude/hooks` for `--global`, or the plugin's own folder when the kit is installed as a plugin. Use it wherever this file says `<Kit helpers>`.
2. Read `package.json`, `tsconfig.json`, `next.config.*`, and list the top two levels of the app directory. Read any existing `CLAUDE.md`.
3. Write or update `CLAUDE.md` in the project root, between the markers `<!-- next-workflow:start -->` and `<!-- next-workflow:end -->` (replace that block if it exists, leave everything outside it untouched). The block is a **pointer, not a copy**. The stack and verify commands come fresh from the session-start report every session, and repo conventions live in `.claude/project-context.md`; duplicating either here only creates a copy that goes stale. Exactly:
   ```
   <!-- next-workflow:start -->
   This project uses next-workflow. The stack and verify commands are reported at session start;
   repo conventions are in .claude/project-context.md. Plan with /next:write-task, build with
   /next:task (batches: run-tasks.sh in the kit helpers folder).
   <!-- next-workflow:end -->
   ```
4. If `package.json` has no `typecheck` script and the project is TypeScript, add `"typecheck": "tsc --noEmit --incremental --tsBuildInfoFile .claude/.cache/tsbuildinfo"`. Do not touch other scripts.
5. Ensure `.gitignore` contains `.claude/.cache/`.
6. Run `bash <Kit helpers>/tasks.sh init` to create `.claude/tasks/` and `.claude/project-context.md`, then **seed the context file** from what you just learned: where components, routes, services, hooks, schemas and stores live in this repo; the import alias; the class-composition helper; the auth helper; the test setup. One line per fact, under the existing headings, no narrative.
   This file is injected at the start of every session — it is what stops every future task from re-deriving the same facts. Keep it under ~60 lines and delete anything the stack report already covers.
7. Check the type-error baseline: if `.claude/.cache/tsc-baseline` doesn't exist and the typecheck currently fails, tell the user to record the existing errors by typing `! bash <Kit helpers>/verify.sh --baseline` (with the real path filled in). You are not allowed to run it yourself: an agent must never baseline errors it might have caused.
8. Report: the detected stack, what you changed, and anything the workflow's hooks will *not* be able to do here (no Prettier, no test runner, no git, which means no task diffs or checkpoints, and no Playwright, which means `[browser]` criteria stay unverified).

Do not install dependencies. Do not restructure the project.
