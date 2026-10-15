---
description: Review the current Next.js changes for boundary, caching, security and build-time bugs
argument-hint: [diff target — branch, path, or blank for uncommitted changes]
allowed-tools: Read, Grep, Glob, Bash, Task, Skill
---

Review target: **$ARGUMENTS** (blank = uncommitted changes; check `git status` and `git diff` first, and fall back to recently modified files if this isn't a git repo).

Delegate to `next-reviewer` with the exact target. While it works, run the project's typecheck yourself so build-level facts are in hand when its report arrives.

Then report findings ranked by severity, each with `file:line`, the failure scenario, and the fix. Verify any finding you doubt by reading the code before passing it on — a confidently wrong review costs more than a missed nit.

Do not fix anything unless asked. End by offering to apply the fixes.
