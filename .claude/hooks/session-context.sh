#!/usr/bin/env bash
# SessionStart: tell Claude what this particular Next.js project actually is,
# so agents/commands stop guessing (Tailwind v3 vs v4, App vs Pages, ORM, test runners).
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$ROOT/package.json" ] || exit 0
. "$SELF_DIR/_lib.sh"
eval "$(bash "$SELF_DIR/stack.sh")"
[ -n "$NEXT_VERSION" ] || exit 0   # not a Next.js project; stay quiet
bash "$SELF_DIR/bash-guard.sh" --snapshot >/dev/null 2>&1   # baseline for shell-change detection
# Where the kit's helpers live: the project for a project install, ~/.claude for --global.
# shellcheck disable=SC2088  # a literal "~" for display, not a path to expand
if [ "$SELF_DIR" = "$ROOT/.claude/hooks" ]; then HELPERS=".claude/hooks"; else HELPERS="~/.claude/hooks"; fi
KIT_VERSION="$(cat "$ROOT/.claude/next-workflow.version" 2>/dev/null || cat "$SELF_DIR/../next-workflow.version" 2>/dev/null || echo unknown)"

# Version-specific guidance: the skill's references are split by Next major.
if [ "${NEXT_MAJOR:-0}" -ge 16 ] 2>/dev/null; then
  NEXTREF="Next $NEXT_MAJOR: read \`nextjs-app-router/references/next16.md\` before any caching, middleware/proxy or config work — it overrides the Next 15 caching notes.${CACHE_COMPONENTS:+ cacheComponents is ON: new caching uses 'use cache' + cacheLife/cacheTag; route segment config (dynamic/revalidate/fetchCache) errors.}"
else
  NEXTREF="Next ${NEXT_MAJOR:-15}: the Next 15 rules in \`nextjs-app-router\` apply as written."
fi
[ -n "${NEXT_DOCS:-}" ] && NEXTREF="$NEXTREF Version-matched Next.js docs are installed at \`$NEXT_DOCS/\` — grep them before relying on memory for any Next.js API; they override the skill if the two disagree."

TW="none"
[ -n "$TAILWIND_VERSION" ] && TW="$TAILWIND_VERSION"
[ -n "$TAILWIND_INSTALLED" ] && TW="$TAILWIND_INSTALLED (installed)"
ROUTER="app router"
[ -n "$PAGES_DIR" ] && [ -n "$APP_DIR" ] && ROUTER="app router (+ legacy $PAGES_DIR)"
[ -z "$APP_DIR" ] && ROUTER="pages router"

# Accumulated project knowledge, written by the task runner. Injected so no session has to
# rediscover it. Comments and empty sections are stripped; hard-capped so it can never dominate.
CONTEXT=""
CTX_FILE="$ROOT/.claude/project-context.md"
if [ -f "$CTX_FILE" ]; then
  # Strip single-line comments first: a sed range never ends on the line it starts,
  # so '/<!--/,/-->/d' alone would swallow everything up to the *next* comment.
  # Then drop headings that have no content under them.
  CTX_FULL="$(sed -E 's/<!--.*-->//' "$CTX_FILE" | sed -E '/<!--/,/-->/d' \
    | awk '/^#/ { hdr=$0; next } NF { if (hdr != "") { print hdr; hdr="" } print }')"
  CTX_BODY="$(printf '%s' "$CTX_FULL" | head -c 4000)"
  # Cut at a line boundary, and say so: a silently dropped Gotchas section is worse than a warning.
  if [ "${#CTX_FULL}" -gt 4000 ]; then
    CTX_BODY="$(printf '%s' "$CTX_BODY" | sed '$d')
[project-context.md is ${#CTX_FULL} characters; only the first 4000 were loaded — merge and prune it to under ~60 lines so nothing is dropped]"
  fi
  # Only worth injecting if it has content beyond its own headings.
  if [ "$(printf '%s' "$CTX_BODY" | grep -vcE '^#|^$')" -gt 0 ] 2>/dev/null; then
    CONTEXT="

Known about this codebase (.claude/project-context.md — keep it current, it is why you do not have to rediscover this):
$CTX_BODY"
  fi
fi

TASKS=""
if [ -d "$ROOT/tasks" ] && [ -x "$SELF_DIR/tasks.sh" ]; then
  TODO="$(CLAUDE_PROJECT_DIR="$ROOT" "$SELF_DIR/tasks.sh" count todo 2>/dev/null || echo 0)"
  DOING="$(CLAUDE_PROJECT_DIR="$ROOT" "$SELF_DIR/tasks.sh" count doing 2>/dev/null || echo 0)"
  BLOCKED="$(CLAUDE_PROJECT_DIR="$ROOT" "$SELF_DIR/tasks.sh" count blocked 2>/dev/null || echo 0)"
  DRAFT="$(CLAUDE_PROJECT_DIR="$ROOT" "$SELF_DIR/tasks.sh" count draft 2>/dev/null || echo 0)"
  PARTS=""
  [ "${DRAFT:-0}" -gt 0 ] 2>/dev/null   && PARTS="$DRAFT draft (awaiting approval)"
  [ "${TODO:-0}" -gt 0 ] 2>/dev/null    && PARTS="${PARTS:+$PARTS, }$TODO todo"
  [ "${DOING:-0}" -gt 0 ] 2>/dev/null   && PARTS="${PARTS:+$PARTS, }$DOING in progress"
  [ "${BLOCKED:-0}" -gt 0 ] 2>/dev/null && PARTS="${PARTS:+$PARTS, }$BLOCKED blocked"
  [ -n "$PARTS" ] && TASKS="
- Tasks: $PARTS — \`/next:task\` runs the next one, \`/next:task list\` shows them all."
fi

TEXT="Detected stack (next-workflow $KIT_VERSION, auto-detected at session start — this report is the source of truth for the stack):
- Kit helpers: \`$HELPERS\` — run \`bash $HELPERS/tasks.sh …\` (and run-tasks.sh, verify.sh) from there.
- Next.js: ${NEXT_INSTALLED:-$NEXT_VERSION} — $ROUTER, routes live in ${APP_DIR:-$PAGES_DIR}. $NEXTREF
- Package manager: $PM
- Tailwind: $TW${SHADCN:+ | shadcn/ui: configured (components.json)}${SHADCN:+}
- Database/ORM: ${ORM:-none detected}
- Validation: ${VALIDATION:-none detected} | Client store: ${STORE:-none detected}${FORMS:+ | Forms: $FORMS}${DESIGN_SKILL:+
- Design: the \`frontend-design\` skill is available — load it when building new UI or restyling, and not for refactors, fixes, or components that must match existing siblings.}
- Unit tests: ${TEST_UNIT:-none} | E2E: ${TEST_E2E:-none}
- Verify commands: typecheck=\`${CMD_TYPECHECK:-n/a}\` lint=\`${CMD_LINT:-n/a}\` test=\`${CMD_TEST:-n/a}\` build=\`$CMD_BUILD\`$TASKS

Use these exact commands rather than inventing them. If Tailwind is absent do not add Tailwind classes; if shadcn/ui is not configured, write plain components instead of importing @/components/ui/*. Write classes for the installed Tailwind version only — a utility from a newer minor silently emits no CSS.$CONTEXT"

wf_context SessionStart "$TEXT"
