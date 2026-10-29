# Changelog

## 2.6.1 — 2026-10-30
Fixes from automated security review.
- guard-owner reads a heredoc delimiter the way bash does: the whole word with its quotes removed (`<<"E"OF` is `EOF`), ended only by an exact terminator line (leading tabs only for `<<-`). With more than one heredoc, an odd delimiter, or no terminator, the whole command is scanned. Before, `cat <<"E"OF … EOF` followed by `git push` hid the push.
- allow-helpers no longer builds its auto-approve list from the stack cache, which a shell command could rewrite. It approves only the fixed verify commands the kit can detect (`<pm> run typecheck|type-check|types|lint|test|build`, `npx --no-install tsc …`, `npx --no-install vitest run`, `npx --no-install next build`), optionally followed by plain paths.

## 2.6.0 — 2026-10-30
**No comments — pure code.** Code written for a task carries no comments.
- New PreToolUse(Edit|Write|MultiEdit) hook `guard-comments.sh` blocks an edit that adds a `//`, `/* */`, JSDoc prose, `{/* */}` or `<!-- -->` line to TS/JS, CSS, Vue/HTML or shell files, before the file is written, and names the lines. Only comments the edit adds count: ones already in the file (or in `old_string`) are left alone. Allowed: `'use client'`/`'use server'`, shebangs, tooling directives (`@ts-expect-error`, `eslint-disable-next-line`, `prettier-ignore`) and type-only JSDoc tags. `node_modules/`, `.next/`, `dist/`, `build/`, `out/`, `coverage/`, `next-env.d.ts` and `.claude/` are skipped. `NEXT_WF_COMMENT_GUARD=off` turns it off. It always runs in a plugin install. Works without jq (Node fallback).
- The rule is in `code-conventions` (replacing "comment why, not what"), the builder agents, the test writer, `/next:task`, `/next:feature`, `/next:test`, the reviewer's checklist and the session report.
- Plugin build: `allow-helpers` is attached only to the Bash matcher (it has nothing to approve on Edit/Write).

**Git: commit, pull the stage branch, push.**
- One command, `/next:sync` (user-only, `disable-model-invocation`), does the whole round: commit, pull the stage branch in, re-run the checks if anything came in, push. New helper `git-sync.sh` (`stage [<branch>]`, `candidates`, `status`, `check-staged`, `sync`, `push`): `sync` fetches and brings in this branch's own remote commits and then the stage branch (merge by default, `SYNC_MODE=rebase` to rebase; a conflict stops with exit 3 and the file list); `push` refuses until the branch contains the stage branch's latest commit and never forces.
- The stage branch lives in `.claude/workflow.conf` (`STAGE_BRANCH=…`, committed). Set it with `./install.sh /path/to/app --stage-branch stage`, or `/next:setup` and the first `/next:sync` ask, suggesting `stage`/`staging`/`develop` from the remote. `NEXT_WF_STAGE_BRANCH`, `NEXT_WF_SYNC_MODE` and `NEXT_WF_REMOTE` override it.
- The owner guard blocks a plain `git push` (command position, through wrappers and `git -C`) and points at `git-sync.sh push`, so no push skips the stage pull. Claude still pushes only when asked.
- The session report names the stage branch and the push rule.
- Guide PDF updated for 2.6; its source is now `docs/guide.html`.

## 2.5.2 — 2026-10-23
- The browser-check switch is now `NEXT_WF_VERIFY_BROWSER=off`. 2.5.0 called it `NEXT_WF_VERIFY=no-browser`, but `NEXT_WF_VERIFY` already selects what the Stop hook runs (`typecheck`, `typecheck,lint`, `off`). Setting it to `no-browser` silently meant typecheck-only, and browser-off couldn't be combined with lint or off. The owner guard covers the new name.
- Guide PDF updated for 2.5.

## 2.5.1 — 2026-10-23
Plugin hardening, from automated security review of 2.5.0.
- allow-helpers approves only the plugin's own helpers, by absolute path. The relative `.claude/hooks/tasks.sh` form would have auto-approved whatever script the project keeps at that path.
- allow-helpers approves verify commands only with plain path arguments after them. Flags and `key=value` (`--config x`, `--reporter=./x.js`) go to the normal prompt.
- plugin-dispatch: the guards (secrets, owner, read, bash-guard, allow-helpers) always run, so a file in the project can't switch one off. Context, format and Stop hooks step aside only when the project's settings really register them.

## 2.5.0 — 2026-10-23
Fits existing stacks, installs as a plugin, verification you can afford, and a Next 16 baseline.
- **Match the existing stack.** `stack.sh` now detects Redux Toolkit (and RTK Query, from `createApi`), redux, jotai, react-query, SWR, Apollo, formik, TanStack Form, yup, valibot, antd, MUI, Chakra and Mantine (new keys `DATA_CLIENT`, `UI_KIT`, `STACK_MODE`). A project built on any of them runs in `match` mode: the session report says so and points to the new `react-component-conventions/references/existing-stacks.md`, which replaces the zustand/zod/react-hook-form defaults (per-request Redux store, RTK Query endpoints, the same yup schema on the server, AntdRegistry…). The useEffect-fetch guard advises instead of blocking there. `NEXT_WF_STACK_MODE=kit|match` overrides it; the override is never cached.
- **Plugin install.** `.claude-plugin/plugin.json` and a local marketplace: `claude plugin marketplace add <kit>` then `claude plugin install next@next-workflow`. Commands stay `/next:*`. Plugins can't ship permission rules, so the plugin adds two hooks: `allow-helpers.sh` (pre-approves exactly the helper and verify commands; anything chained or expanded still prompts, and the user's deny/ask rules always win) and `guard-read.sh` (blocks Read on env files and keys). `hooks/hooks.json` is generated from settings.json by `hooks/build-hooks.jq` (a test keeps them in sync). Every plugin hook runs through `plugin-dispatch.sh`, which steps aside when the project also has the kit's files and says so at session start. `claude plugin validate .` passes.
- **Verifier cost, still never skipped.** `NEXT_WF_VERIFY=no-browser` stops the verifier writing Playwright specs; `[browser]` criteria are recorded UNVERIFIED for the user. `NEXT_WF_SKIP_VERIFY_LINES` raises the `[review]`-only skip size (default 20, capped at 60). The owner guard blocks Claude from setting these, `NEXT_WF_REQUIRE_VERDICT`, or running `verify.sh --baseline` itself.
- **Track record.** `tasks.sh verdict <id> FAIL <round> "<what failed>"` records the reason; `tasks.sh stats --brief` and the session report show the verifier's first-pass rate and the last three failures, so later tasks don't repeat them.
- **`tasks.sh compact-context`** tidies `.claude/project-context.md`: exact duplicate facts, repeated headings and empty sections. The runner calls it before pruning by hand; the over-4000-characters warning points to it.
- **Next 16 reference solution** (`evals/reference-next16/`): request data under `<Suspense>`, signed-out redirect in `proxy.ts`. `evals/run.sh --reference --next 16` scores 5/5 against a real 16.4.1 build; CI runs it. The Next 15 page fails that build, so the variant really tests Next 16 knowledge.
- next16.md: `redirect()` inside a streamed `<Suspense>` boundary answers HTTP 200 with a meta refresh, not a 307 (checked on a 16.4.1 production build). Auth gates belong in `proxy.ts`.
- Permissions cover `pnpm run`, `yarn`, `yarn run` and `bun run`. The detected commands are `<pm> run <script>`, so `pnpm run typecheck` used to prompt. `bun.lock` (bun 1.2+ text lockfile) is detected.
- Fix: the stack cache never hit. `TEST_E2E` was missing from the cache allow-list, so every hook re-ran the full detection (~19 jq calls per edit); the test that should have caught it skipped keys containing a digit. The cache is now also invalidated by lockfiles, installed next/tailwind manifests, install records and `next.config.*`.
- Fix: the secrets guard's message glob-expanded a matched pattern, listing every file in the folder as a "secret file".
- Fix: `run-tasks.sh` still told the user to run `tasks.sh accept`, which 2.4.0 removed.
- Prompts no longer hard-code `.claude/hooks/`; they use the **Kit helpers** path from the session report (project, `--global` or plugin).
- guard-secrets is **frozen**: false positives and message bugs only, no more bypass hardening. For a real boundary, keep secrets out of the project folder or use the sandbox.
- Removed `todo.yml` (an obsolete plan).

## 2.4.0 — 2026-10-23
Verification can't be skipped, and tasks run as soon as they are planned.
- `tasks.sh close` refuses until a verdict is recorded for the task: PASS, UNVERIFIED, or a SKIPPED that `can-skip-verify` allowed. A FAIL must be fixed and re-verified first. `NEXT_WF_REQUIRE_VERDICT=off` turns the gate off. A task closed on UNVERIFIED is `done`, and its log line names the criteria the user should check.
- `/next:write-task` writes tasks as `todo`, ready to run. The `draft` status and the `approve`/`accept` steps are gone; `tasks.sh new` takes `status: todo`.
- New PreToolUse(Bash) hook `guard-owner.sh` blocks shell edits of a task's `status:`, so statuses move only through `tasks.sh` and stay in step with the log and verdict. Pushing and opening pull requests are not blocked: Claude does them when the user asks.

## 2.3.1 — 2026-10-15
- guard-secrets: the new glob shortcuts (a `*` can't match a leading dot; a bare `*` blocks only where a key file exists) now apply only to plain shell globbing. With find/rg/grep/git/tar-style matchers, `-name`/`-path`/`-g`/`--include`, dotglob/GLOBIGNORE, or a `cd`/`pushd` in the command, every pattern match blocks as before (`find . -name '*' -exec cat {} +` would have reached .env). The filesystem check resolves against the hook input's `cwd`, not the project root. Found by automated security review.

## 2.3.0 — 2026-10-15
- Task files live in `.claude/tasks/` instead of `./tasks/`, beside the rest of the kit's project state. `tasks.sh init` scaffolds it there, and `tasks.sh dir` prints the folder in use; `/next:write-task` asks it. `NEXT_WF_TASKS_DIR` still overrides.
- Existing projects keep working: when `.claude/tasks` doesn't exist and `./tasks` holds the kit's `TEMPLATE.md`, the helpers keep using `./tasks`. `tasks.sh migrate` moves it (and warns if `.gitignore` ignores `/tasks`); the installer says so. A user's own `./tasks` folder of notes is never taken over.
- Task diffs, dirty-file snapshots and the skip-verify size check exclude whichever tasks folder is in use, not a hardcoded `tasks`.
- `tasks.sh new <id>-<kebab-title>` writes a draft task from stdin, and `/next:write-task` uses it. Claude Code asks the user to approve every Write/Edit under `.claude/`, and settings allow-rules can't pre-approve those writes (docs: permission modes, "Protected paths"), so writing drafts with the Write tool would mean one prompt per task. `new` accepts only a well-formed draft: a `<id>-<kebab>` name with no path, frontmatter whose `id` matches, `status: draft`, and an id that doesn't exist yet.
- guard-secrets: a quoted heredoc sent to `tasks.sh new` passes even when the task text mentions `.env` (exact shape only; heredocs into `bash`/`cat`, unquoted heredocs and anything after the closing delimiter are still checked).
- guard-secrets: globs no longer false-positive. `*` can't match a leading dot, so `-not -path '*/node_modules/*'` and `ls src/*` pass; `.e*`-style patterns still block. A bare `*` blocks only where a key file actually exists (`cat keys/*`).
- The session report counts tasks in the folder actually in use (it was still looking at `./tasks`).

## 2.2.1 — 2026-10-15
- tasks.sh: only files that start with YAML frontmatter are tasks. Before, a plain note in `tasks/` (found in a real project) counted as an approved `todo` task, and `/next:task` would have started building from it. The Laravel kit already had this rule.

## 2.2.0 — 2026-10-15
Context memory: the kit now remembers more, so each task pays less to rediscover the codebase.
- Repo map (`tasks.sh map`, `repo-map.sh`): a cached, script-generated map of the app (routes; components/modules or models with relations, controllers with actions, tables). Regenerated only when the files it covers change. On a real app (aark-epaper) it is ~1,100 tokens versus ~9,000 to read the models and routes it summarizes.
- Task handoff (`tasks.sh context <id>`): the task plus what each dependency did and which files it changed (recorded at close), so dependent tasks don't re-read code a dependency just wrote.
- Subagents get the context: a SubagentStart hook (scoped to kit agents) injects the stack report and project memory (~550 tokens) before their first prompt; before this every delegation started cold and re-explored. Per the docs this leaves the subagent's prompt cache intact.
- Compaction: SessionStart now matches `startup|resume|clear|compact|fork` explicitly, so the stack report and memory are re-injected after auto-compaction (docs: injected context is otherwise summarized away).
- The session report keeps the volatile task counts last, so the stable part stays a reusable prompt prefix; the report stays under the documented 10,000-character hook cap (tested).
- Runner rules: `context` instead of `show`, and map → grep → read.

## 2.1.9 — 2026-10-15
- guard-secrets: brace ranges are sized, not skipped (automated commit review). 2.x.8 judged every `{x..y}` by letters alone, so letter ranges such as `.e{n..n}v` slipped through. Ranges now count by their real size (letters at most 58, numbers by span); small ones are expanded and checked like lists; only huge numeric ranges, which can only produce digits, fall back to the letter check; a range it cannot size counts as unsure.

## 2.1.8 — 2026-10-15
- guard-secrets: bounded work (automated commit review). A hook that times out does not block, so `cat .env {1..99999999}` previously got through by exhausting the expansion step. `{x..y}` ranges are never expanded, lists are expanded only up to 256 combinations, and more than 16 brace words in one command count as unsure; over a limit, the cheap letter check decides.

## 2.1.7 — 2026-10-15
- guard-secrets now fails closed (automated commit review): more than 32 `$'…'` segments, a segment that will not decode, an unterminated `$'`, or a brace list it cannot expand safely all count as a secret reference. Brace lists are expanded from the list part of a word, so `cat $(echo .{e,x}nv)` is caught, while code with braces (`jq 'map({id})'`, `php -r`, `awk`, `node -e`) still passes.

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
