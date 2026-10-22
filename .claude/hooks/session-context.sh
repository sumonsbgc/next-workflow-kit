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
# Where the kit's helpers live: the project for a project install, ~/.claude for --global, the
# plugin's folder for a plugin install.
HELPERS="$(wf_helpers "$SELF_DIR")"
# A plugin carries the kit's VERSION file at its root, two levels up from the hooks.
KIT_VERSION="$(cat "$ROOT/.claude/next-workflow.version" 2>/dev/null || cat "$SELF_DIR/../next-workflow.version" 2>/dev/null || cat "$SELF_DIR/../../VERSION" 2>/dev/null || echo unknown)"

# Version-specific guidance: the skill's references are split by Next major.
if [ "${NEXT_MAJOR:-0}" -ge 16 ] 2>/dev/null; then
  NEXTREF="Next $NEXT_MAJOR: read \`nextjs-app-router/references/next16.md\` before any caching, middleware/proxy or config work — it overrides the Next 15 caching notes.${CACHE_COMPONENTS:+ cacheComponents is ON: new caching uses 'use cache' + cacheLife/cacheTag; route segment config (dynamic/revalidate/fetchCache) errors.}"
else
  NEXTREF="Next ${NEXT_MAJOR:-15}: the Next 15 rules in \`nextjs-app-router\` apply as written."
fi
[ -n "${NEXT_DOCS:-}" ] && NEXTREF="$NEXTREF Version-matched Next.js docs are installed at \`$NEXT_DOCS/\` — grep them before relying on memory for any Next.js API; they override the skill if the two disagree."

# Stack mode: a project built on Redux/antd/formik/yup/react-query… is not rewritten to the kit's
# defaults. New code follows what the project already uses; the kit's rules fill the gaps.
STACKLINE=""
if [ "${STACK_MODE:-kit}" = match ]; then
  USES="$(printf '%s' "${STORE:+$STORE+}${DATA_CLIENT:+$DATA_CLIENT+}${FORMS:+$FORMS+}${VALIDATION:+$VALIDATION+}${UI_KIT:+$UI_KIT+}" | tr '+' '\n' | grep -v '^$' | awk '!s[$0]++' | paste -sd, - | sed 's/,/, /g')"
  STACKLINE="
- **Conventions: match the existing stack** ($USES). Follow the patterns already in the codebase and read \`react-component-conventions/references/existing-stacks.md\` before state, data-fetching, form or validation work — it overrides the zustand/zod/react-hook-form defaults in the skills. Never introduce a second library for a job one of these already does, and don't move existing client code to the server unless the task asks. New routes and pure helpers still follow the kit's server-first rules where they don't fight the existing data layer. (\`NEXT_WF_STACK_MODE=kit\` turns this off.)"
fi

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
[project-context.md is ${#CTX_FULL} characters; only the first 4000 were loaded — run \`bash $HELPERS/tasks.sh compact-context\`, then merge and prune it to under ~60 lines so nothing is dropped]"
  fi
  # Only worth injecting if it has content beyond its own headings.
  if [ "$(printf '%s' "$CTX_BODY" | grep -vcE '^#|^$')" -gt 0 ] 2>/dev/null; then
    CONTEXT="

Known about this codebase (.claude/project-context.md — keep it current, it is why you do not have to rediscover this):
$CTX_BODY"
  fi
fi

TASKS=""
TDIR="$(CLAUDE_PROJECT_DIR="$ROOT" bash "$SELF_DIR/tasks.sh" dir 2>/dev/null)"
if [ -n "$TDIR" ] && [ -d "$ROOT/$TDIR" ] && [ -x "$SELF_DIR/tasks.sh" ]; then
  TODO="$(CLAUDE_PROJECT_DIR="$ROOT" "$SELF_DIR/tasks.sh" count todo 2>/dev/null || echo 0)"
  DOING="$(CLAUDE_PROJECT_DIR="$ROOT" "$SELF_DIR/tasks.sh" count doing 2>/dev/null || echo 0)"
  BLOCKED="$(CLAUDE_PROJECT_DIR="$ROOT" "$SELF_DIR/tasks.sh" count blocked 2>/dev/null || echo 0)"
  PARTS=""
  [ "${TODO:-0}" -gt 0 ] 2>/dev/null    && PARTS="$TODO todo"
  [ "${DOING:-0}" -gt 0 ] 2>/dev/null   && PARTS="${PARTS:+$PARTS, }$DOING in progress"
  [ "${BLOCKED:-0}" -gt 0 ] 2>/dev/null && PARTS="${PARTS:+$PARTS, }$BLOCKED blocked"
  [ -n "$PARTS" ] && TASKS="
- Tasks: $PARTS — \`/next:task\` runs the next one, \`/next:task list\` shows them all."
fi

# Track record: how verification has gone in this project, and what failed recently, so the
# same mistakes aren't made again. Volatile, so it sits at the end with the task counts.
RECORD=""
REC="$(CLAUDE_PROJECT_DIR="$ROOT" bash "$SELF_DIR/tasks.sh" stats --brief 2>/dev/null | head -c 700)"
[ -n "$REC" ] && RECORD="
- Track record: $REC"
VERIFYLINE=""
[ "${NEXT_WF_VERIFY_BROWSER:-on}" = off ] && VERIFYLINE="
- Verification: browser checks are OFF (NEXT_WF_VERIFY_BROWSER=off, set by the user to save tokens). The verifier marks [browser] criteria UNVERIFIED without starting Playwright; the user checks them."

TEXT="Detected stack (next-workflow $KIT_VERSION, auto-detected at session start — this report is the source of truth for the stack):
- Kit helpers: \`$HELPERS\` — run \`bash $HELPERS/tasks.sh …\` (and run-tasks.sh, verify.sh) from there.
- Next.js: ${NEXT_INSTALLED:-$NEXT_VERSION} — $ROUTER, routes live in ${APP_DIR:-$PAGES_DIR}. $NEXTREF
- Package manager: $PM
- Tailwind: $TW${SHADCN:+ | shadcn/ui: configured (components.json)}${SHADCN:+}
- Database/ORM: ${ORM:-none detected}
- Validation: ${VALIDATION:-none detected} | Client store: ${STORE:-none detected}${FORMS:+ | Forms: $FORMS}${DATA_CLIENT:+ | Data client: $DATA_CLIENT}${UI_KIT:+ | UI kit: $UI_KIT}$STACKLINE${DESIGN_SKILL:+
- Design: the \`frontend-design\` skill is available — load it when building new UI or restyling, and not for refactors, fixes, or components that must match existing siblings.}
- Unit tests: ${TEST_UNIT:-none} | E2E: ${TEST_E2E:-none}
- Verify commands: typecheck=\`${CMD_TYPECHECK:-n/a}\` lint=\`${CMD_LINT:-n/a}\` test=\`${CMD_TEST:-n/a}\` build=\`$CMD_BUILD\`
- Repo map: \`bash $HELPERS/tasks.sh map\` prints routes, components, lib modules and server actions (cached, regenerated when files change). Read it before exploring with grep/ls.

Use these exact commands rather than inventing them. If Tailwind is absent do not add Tailwind classes; if shadcn/ui is not configured, write plain components instead of importing @/components/ui/*. Write classes for the installed Tailwind version only — a utility from a newer minor silently emits no CSS.$VERIFYLINE$CONTEXT$TASKS$RECORD"

wf_context SessionStart "$TEXT"
