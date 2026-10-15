# Changelog

## 2.1.2 — 2026-10-15
- Upgrades now remove permission rules that earlier kit versions shipped and later removed (`Read(//home/**)`, `git diff:*`, `npx playwright test:*`, …). The settings merge was a union, so an upgraded project kept them.

## 2.1.1 — 2026-10-15
Security fixes from the automated commit review of 2.1.0:
- settings.json: removed prefix rules that granted more than intended. `git diff:*` / `git log:*` (`--no-index`, `--output` read or write files outside the deny rules) are gone, and so is `npx playwright test:*` (`-c`/`--reporter` load any file). `git status` is now exact.
- Browser specs now run through `.claude/hooks/verify-browser.sh <task-id>`, which takes a validated id and a fixed config; only that script is pre-approved.
- guard-secrets.sh: the .gitignore and cp exemptions now apply only to plain commands (no newline, `$`, backticks, `;&|<>(){}`, backslashes), checked with bash's regex against the whole command, not grep line by line. Commands are normalized (quotes and backslashes stripped) before matching, and globs are tested against secret file names (`.en*`, `.e[n]v`, `.*`, `~/.ss?/id_*`).

## 2.1.0 — 2026-10-15
Fixes every finding from the v2 review (next-workflow-review-v2.pdf, N1–N15).
- N1  Checkpoints commit only the task's own files; never secrets or pre-existing edits; batches go on an nw/batch-* branch.
- N2  Eval harness proven end to end against a reference solution (5/5, real build + server). Agent runs still to be recorded.
- N3  Browser verification works: kit Playwright config (.claude/verify.playwright.config.mjs), verified with a real browser.
- N4  Shell-change guard blocks only violations the command introduced; old ones are reported, not blocking.
- N5  .env.example readable again; safe .gitignore/seed commands allowed; the guard documents it is a speed bump.
- N6  `tasks.sh undo` refuses while done tasks depend on it; `--cascade` undoes dependents first.
- N7  Verifier verdicts recorded (`tasks.sh verdict`); `stats` shows the first-pass rate.
- N8  Next 16 reference rewritten from the official docs, with sources (2.0.1).
- N9  Kit under git, this changelog, CI running shellcheck, the self-test and the reference eval.
- N10 Behaviour-based checks (HTTP against the built app, hidden tests incl. authorization), an ambiguous task, multi-run aggregation, a Next 16 + cacheComponents variant.
- N11 Verifier skip rule is mechanical: `tasks.sh can-skip-verify` (all [review], diff <= 20 lines).
- N12 Oversized project-context.md is flagged at session start instead of silently cut.
- N13 Per-edit hook latency recorded; `stats` shows p50/p95.
- N14 Global install: helper path in the session report, matching permission rules, full task cycle tested.
- N15 In-session task starts measured and nudged past 3 in 3 hours.

## 2.0.1 — 2026-10-15
- Next 16 reference verified against nextjs.org; several rules corrected (unstable_cache valid, segment config errors under cacheComponents, refresh() semantics, Edge middleware stays middleware.ts, First Load JS gone from build output).

## 2.0.0 — 2026-10-15
- Fixes all v1 review findings (next-workflow-review.pdf): security hardening, fresh-context runner, checkpoints + undo, independent verifier, type-error baseline, Next 16 coverage, shell-write guard, metrics, eval harness, draft → approve.
