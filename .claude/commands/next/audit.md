---
description: Run performance, accessibility and correctness audits over the app (or a path)
argument-hint: [path or route to audit, blank = whole app]
allowed-tools: Read, Grep, Glob, Bash, Task, TodoWrite, Skill
---

Audit scope: **$ARGUMENTS** (blank = the whole app directory).

Launch these three read-only agents **in parallel, in a single message**:

1. `next-perf-auditor` — rendering, bundle, waterfalls, caching, assets.
2. `next-a11y-auditor` — WCAG 2.2 AA over the UI in scope.
3. `next-reviewer` — correctness, Server Action security, the client/server boundary and hydration hazards, and component/language conventions over the same scope (tell it to review the files in scope, not a diff).

When all three return, do **not** just concatenate their reports. Produce one merged list:

- Deduplicate findings the agents both raised.
- Drop anything you can verify is a false positive by reading the code — say what you dropped and why.
- Rank by user impact × effort: security holes first, then things that break for real users, then bytes and milliseconds, then hygiene.
- For each surviving finding: `file:line`, the concrete failure, the fix in one sentence.

End with the three fixes worth doing first, and ask whether to apply them. Do not start editing without an answer.
