#!/usr/bin/env bash
# Shared stack detection for the Next.js agentic workflow.
# Usage:  eval "$("$CLAUDE_PROJECT_DIR/.claude/hooks/stack.sh")"
# Emits KEY="value" lines. Never fails: unknown values come back empty.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
PKG="$ROOT/package.json"

# Cache: detection costs ~15 subprocesses and only changes when the manifest or the
# installed tree does. NEXT_WF_NO_CACHE=1 forces a fresh probe.
CACHE="$ROOT/.claude/.cache/stack.env"
# frontend-design is a user- or project-level skill. It depends on $HOME, which is not part
# of the cache key, and costs one -d test — so it is computed fresh on every call, never cached.
design_skill() {
  local d
  for d in "$ROOT/.claude/skills/frontend-design" "$HOME/.claude/skills/frontend-design"; do
    [ -d "$d" ] && { printf 'DESIGN_SKILL="yes"\n'; return; }
  done
  printf 'DESIGN_SKILL=""\n'
}

# Every consumer `eval`s this output, and values come from package.json — repo content, not
# ours. Reduce each value to a charset that cannot carry shell syntax ($, `, ", \, ;, newline).
safe() { printf '%s' "$1" | tr -cd 'A-Za-z0-9 ._~^<>=|@/:+,*-'; }
# A cache line is trusted only if it has exactly the shape this script writes.
cache_ok() { ! grep -qvE '^[A-Z_]+="[A-Za-z0-9 ._~^<>=|@/:+,*-]*"$' "$1"; }

if [ "${NEXT_WF_NO_CACHE:-0}" != 1 ] && [ -f "$CACHE" ] && [ -f "$PKG" ] &&
   [ "$CACHE" -nt "$PKG" ] && { [ ! -d "$ROOT/node_modules" ] || [ "$CACHE" -nt "$ROOT/node_modules" ]; } &&
   cache_ok "$CACHE"; then
  cat "$CACHE"; design_skill; exit 0
fi

dep() { # dep <name> -> version string or empty
  [ -f "$PKG" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg d "$1" '((.dependencies//{}) + (.devDependencies//{}))[$d] // ""' "$PKG" 2>/dev/null
  else
    node -e 'const p=require(process.argv[1]);const d={...p.dependencies,...p.devDependencies};process.stdout.write(d[process.argv[2]]||"")' "$PKG" "$1" 2>/dev/null
  fi
}
has_script() {
  [ -f "$PKG" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    [ "$(jq -r --arg s "$1" '.scripts[$s] // ""' "$PKG" 2>/dev/null)" != "" ]
  else
    node -e 'const p=require(process.argv[1]);process.exit((p.scripts||{})[process.argv[2]]?0:1)' "$PKG" "$1" 2>/dev/null
  fi
}

PM=npm
[ -f "$ROOT/pnpm-lock.yaml" ] && PM=pnpm
[ -f "$ROOT/yarn.lock" ] && PM=yarn
[ -f "$ROOT/bun.lockb" ] && PM=bun

SRC=""
[ -d "$ROOT/src" ] && SRC="src/"
APP_DIR=""
[ -d "$ROOT/app" ] && APP_DIR="app"
[ -d "$ROOT/src/app" ] && APP_DIR="src/app"
PAGES_DIR=""
[ -d "$ROOT/pages" ] && PAGES_DIR="pages"
[ -d "$ROOT/src/pages" ] && PAGES_DIR="src/pages"

NEXT_V="$(dep next)"
TW_V="$(dep tailwindcss)"
# The declared range is not what is installed; read the resolved version when present.
TW_INSTALLED="$(node -p 'require(process.argv[1]).version' "$ROOT/node_modules/tailwindcss/package.json" 2>/dev/null || true)"
# Next major drives which version-specific references apply (15 vs 16+).
NEXT_MAJOR="$(printf '%s' "$NEXT_V" | grep -oE '[0-9]+' | head -1)"
NEXT_INSTALLED="$(node -p 'require(process.argv[1]).version' "$ROOT/node_modules/next/package.json" 2>/dev/null || true)"
[ -n "$NEXT_INSTALLED" ] && NEXT_MAJOR="${NEXT_INSTALLED%%.*}"
# Next 16.2+ ships version-matched docs inside the package: the authoritative reference.
NEXT_DOCS=""
[ -d "$ROOT/node_modules/next/dist/docs" ] && NEXT_DOCS="node_modules/next/dist/docs"
CACHE_COMPONENTS=""
for c in "$ROOT"/next.config.*; do
  [ -f "$c" ] && grep -qE 'cacheComponents[[:space:]]*:[[:space:]]*true' "$c" && CACHE_COMPONENTS="yes"
done
ORM=""
[ -n "$(dep prisma)$(dep @prisma/client)" ] && ORM="prisma"
[ -n "$(dep drizzle-orm)" ] && ORM="drizzle"
[ -n "$(dep mongoose)" ] && ORM="mongoose"
[ -n "$(dep @supabase/supabase-js)" ] && ORM="${ORM:+$ORM+}supabase"

VALIDATION=""
[ -n "$(dep zod)" ] && VALIDATION="zod"
STORE=""
[ -n "$(dep zustand)" ] && STORE="zustand"
FORMS=""
[ -n "$(dep react-hook-form)" ] && FORMS="react-hook-form"

SHADCN=""
[ -f "$ROOT/components.json" ] && SHADCN="yes"


TEST_UNIT=""
[ -n "$(dep vitest)" ] && TEST_UNIT="vitest"
[ -z "$TEST_UNIT" ] && [ -n "$(dep jest)" ] && TEST_UNIT="jest"
TEST_E2E=""
[ -n "$(dep @playwright/test)" ] && TEST_E2E="playwright"
[ -z "$TEST_E2E" ] && [ -n "$(dep cypress)" ] && TEST_E2E="cypress"

# Preferred verification commands, in order of what the repo actually defines.
if has_script typecheck; then TYPECHECK="$PM run typecheck"
elif has_script type-check; then TYPECHECK="$PM run type-check"
elif has_script types; then TYPECHECK="$PM run types"
elif [ -f "$ROOT/tsconfig.json" ]; then TYPECHECK="npx --no-install tsc --noEmit --incremental --tsBuildInfoFile .claude/.cache/tsbuildinfo"
else TYPECHECK=""; fi
if has_script lint; then LINT="$PM run lint"; else LINT=""; fi
if has_script test; then TEST="$PM run test"
elif [ "$TEST_UNIT" = vitest ]; then TEST="npx --no-install vitest run"
else TEST=""; fi
if has_script build; then BUILD="$PM run build"; else BUILD="npx --no-install next build"; fi

# Only cache a detection that actually found Next.js. Caching an empty result — node
# missing, a broken jq, an install mid-flight — would silently disable the whole
# workflow until package.json next changed.
if [ -n "$NEXT_V" ] && [ "${NEXT_WF_NO_CACHE:-0}" != 1 ]; then
  mkdir -p "$(dirname "$CACHE")" 2>/dev/null || true
else
  CACHE="/dev/null"        # failed detection, or an explicit fresh probe: never persist it
fi
{ for kv in \
    "PM=$PM" "SRC_PREFIX=$SRC" "APP_DIR=$APP_DIR" "PAGES_DIR=$PAGES_DIR" \
    "NEXT_VERSION=$NEXT_V" "NEXT_INSTALLED=$NEXT_INSTALLED" "NEXT_MAJOR=$NEXT_MAJOR" "NEXT_DOCS=$NEXT_DOCS" "CACHE_COMPONENTS=$CACHE_COMPONENTS" \
    "TAILWIND_VERSION=$TW_V" "TAILWIND_INSTALLED=$TW_INSTALLED" "SHADCN=$SHADCN" \
    "VALIDATION=$VALIDATION" "STORE=$STORE" "FORMS=$FORMS" "ORM=$ORM" \
    "TEST_UNIT=$TEST_UNIT" "TEST_E2E=$TEST_E2E" \
    "CMD_TYPECHECK=$TYPECHECK" "CMD_LINT=$LINT" "CMD_TEST=$TEST" "CMD_BUILD=$BUILD"; do
    printf '%s="%s"\n' "${kv%%=*}" "$(safe "${kv#*=}")"
  done
} | tee "$CACHE" 2>/dev/null
design_skill
exit 0
