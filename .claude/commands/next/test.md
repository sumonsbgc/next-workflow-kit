---
description: Write or repair tests for a file, feature, or failing suite
argument-hint: [file/feature, or blank for the current diff]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, Skill
---

Target: **$ARGUMENTS** (if empty, test whatever the current uncommitted diff changed — check `git status`/`git diff` first).

Delegate to `next-test-writer`. Pass it: the target, the existing test conventions (read a neighbouring test file first), and the project's test commands from the stack report.

Require:
- The right level per target — Vitest + RTL for logic and client components, Playwright for routes, redirects, middleware, and async Server Components.
- Branch coverage that matters: happy path, validation failure, unauthorized, empty, error.
- Queries by role/label/text; no class-name or implementation-detail assertions.
- The suite actually run, with output reported.
- No comments in test code: the test name says what it proves.

If a test fails, it must decide whether the test or the code is wrong and say which. Weakening assertions or skipping tests to get green is not an acceptable outcome.
