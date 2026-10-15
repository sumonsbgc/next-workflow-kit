# Changelog

## 2.1.6 — 2026-10-15
- guard-secrets: brace expansion (`.{e,x}nv`) and ANSI-C quoting (`$'.e\156v'`, `$'\x2eenv'`) are decoded with bash's own rules (plain-character words only, globbing off, nothing executed) and checked like any other name (automated commit review). Names built at runtime remain the documented limit.

## 2.1.5 — 2026-10-15
Security fixes from the automated commit reviews (all reproduced first, then fixed and regression-tested):
- verify.sh: a tampered `.claude/.cache/stack.env` could inject a command through `CMD_*` values (a redirect passed the old charset and was `eval`d). Commands now use a strict charset (letters, digits, space, `._/:=-`), the cache check rejects any `CMD_` line outside it, and verify.sh refuses to eval one.
- stack.sh: the cache is accepted only if every line is one of the exact keys the script writes; a cache that sets `PATH`, `IFS`, `BASH_ENV` or anything else is rejected whole.
- tasks.sh diff: secret files (`.env*`, keys, `auth.json`) are never printed (the diff is read by an agent); their names are listed as changed.
- guard-secrets: the `cp .env.example …` exemption no longer applies to commands with quotes or backslashes (a quoted target could overwrite an existing `.env.local`); the backslash filter now matches a single backslash.

## 2.1.4 — 2026-10-15
- evals/run.sh: a run with no metrics file (e.g. `--reference`) no longer breaks the summary (jq printed a value and failed, so the fallback added a second one).
- guard-secrets: the block message in 2.1.3 contained backticks inside a double-quoted string, so bash ran `cat .env.example` and pasted the file into the message (found by the automated commit review). The message is plain text again; a scan confirms no hook has an unescaped backtick inside double quotes, and a regression test covers it.

## 2.1.3 — 2026-10-15
Fix for a control regression in 2.1.2, found by the automated commit review:
- Upgrades no longer remove deny rules. 2.1.2 applied the retired-rules list to deny as well as allow, which deleted `Read(./.env.*)` (exposing `.env.backup`, `.env.prod`, …) and could delete a user's own deny rules. Deny rules only add protection, so they are never removed.
- `Read(./.env.*)` and `Read(./**/.env.*)` are back in the deny list. `.env.example` is read with `cat` (the secrets guard allows it); the guard message says so.

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
