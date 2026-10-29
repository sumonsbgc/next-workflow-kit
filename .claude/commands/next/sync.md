---
description: Commit, pull the stage branch in, check, then push — the whole git round in one command, and the only way this kit pushes
argument-hint: [commit message] (optional — written from the diff when left out)
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, Grep, Glob, AskUserQuestion
---

Commit the work, pull the stage branch in, check it, push. `G=<Kit helpers>/git-sync.sh`, using the **Kit helpers** path from the session report. A plain `git push` is blocked, so every push goes through this path.

## 1. Stage branch

`bash $G stage`. If it exits 2 (not configured), run `bash $G candidates`, ask the user which branch is the stage branch (suggested ones first), and record it: `bash $G stage <branch>`. Never guess it.

## 2. Commit

Skip this step if `git status --short` is empty. If a merge or rebase is already in progress, stop and say so.

1. Read the change: `git diff --stat` first, then only the hunks you need to describe it.
2. Stage with `git add -A` (it respects `.gitignore`), then `bash $G check-staged`. If it lists secret files, unstage them (`git restore --staged <file>`), leave them out, and tell the user to add them to `.gitignore`.
3. Message: `$ARGUMENTS` when given. Otherwise write one in the style of `git log --oneline -10`: an imperative subject of at most 72 characters saying what changed, and a body only when the reason isn't obvious. No tool or AI attribution lines. If the changes are clearly unrelated, commit them separately, staging by path.
4. `git commit -m "<subject>"` (add `-m "<body>"` for a body). If a pre-commit hook fails, fix what it reports, stage again and commit again. Never `--no-verify`, never `--amend` a pushed commit.

## 3. Pull the stage branch in

`bash $G sync`. It fetches, brings in this branch's own remote commits, then the stage branch (merge by default; `SYNC_MODE=rebase` in `.claude/workflow.conf` rebases).

- Exit 0: note how many commits came in.
- Exit 3 (conflict): read each conflicted file it lists. Resolve a conflict yourself only when the intent of both sides is clear (independent additions, an import list, a renamed variable), keeping both sides' behaviour. If both sides changed the same logic in different ways, or you are unsure, run `git merge --abort` (or `git rebase --abort`), tell the user which files conflict and why, and stop: nothing is pushed. After resolving: `git add <files>`, then `GIT_EDITOR=true git merge --continue` (or `git rebase --continue`).
- Exit 4 (uncommitted changes): go back to step 2.
- Any other exit: report its message and stop.

## 4. Check

If the sync brought commits in or you resolved conflicts, run the project's typecheck and test commands from the session report (and lint if configured). If anything fails, stop and report: don't push a branch that doesn't pass with the stage branch merged in.

## 5. Push

`bash $G push`. Never `git push` directly, never force.

- Exit 5 (the stage branch or this branch's remote moved meanwhile): go back to step 3 once.
- Exit 4: go back to step 2.
- Any other failure: report its message.

## Report

A few lines: the commit(s) made, what came in from the stage branch (and any conflicts resolved), the test result, the branch pushed and the stage commit it includes. If the team uses pull requests, the next step is a PR from this branch into the stage branch; open it if the user asks.
