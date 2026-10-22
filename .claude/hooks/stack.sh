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
# NEXT_WF_STACK_MODE=kit|match overrides the detected mode. Printed after the cached lines (the
# later assignment wins in the consumer's eval) so the override never ends up in the cache.
mode_override() {
  case "${NEXT_WF_STACK_MODE:-}" in kit|match) printf 'STACK_MODE="%s"\n' "$NEXT_WF_STACK_MODE" ;; esac
}

# Every consumer `eval`s this output, and values come from package.json — repo content, not
# ours. Reduce each value to a charset that cannot carry shell syntax ($, `, ", \, ;, newline).
safe() { printf '%s' "$1" | tr -cd 'A-Za-z0-9 ._~^<>=|@/:+,*-'; }
# Commands (CMD_*) are later `eval`'d, so they get a far stricter charset: no pipes, redirects,
# `&`, globs or quotes — nothing that can chain a second command. Versions keep the wider set.
safecmd() { printf '%s' "$1" | tr -cd 'A-Za-z0-9 ._/:=-'; }
# A cache line is trusted only if it has exactly the shape this script writes.
# Only the exact keys this script writes are accepted: a cache that sets PATH, IFS, BASH_ENV or
# any other variable is rejected whole (every hook evals this output, then runs commands).
CACHE_KEYS='APP_DIR|CACHE_COMPONENTS|CMD_BUILD|CMD_LINT|CMD_TEST|CMD_TYPECHECK|DATA_CLIENT|FORMS|NEXT_DOCS|NEXT_INSTALLED|NEXT_MAJOR|NEXT_VERSION|ORM|PAGES_DIR|PM|SHADCN|SRC_PREFIX|STACK_MODE|STORE|TAILWIND_INSTALLED|TAILWIND_VERSION|TEST_E2E|TEST_UNIT|UI_KIT|VALIDATION'
cache_ok() { ! grep -qvE "^($CACHE_KEYS)=\"[A-Za-z0-9 ._~^<>=|@/:+,*-]*\"\$" "$1" &&
             ! grep -qE '^CMD_[A-Z_]+="[^"]*[^A-Za-z0-9 ._/:="-][^"]*"$' "$1"; }

# Fresh only if nothing detection reads has changed since: the manifest and lockfiles, what an
# install writes (the installed next/tailwind manifests, npm's and pnpm's install records), the
# next config (cacheComponents), and the node_modules folder itself (a package added or removed).
cache_fresh() {
  local f
  [ -f "$CACHE" ] && [ -f "$PKG" ] || return 1
  for f in "$PKG" "$ROOT/node_modules" "$ROOT/node_modules/.package-lock.json" "$ROOT/node_modules/.modules.yaml" \
           "$ROOT/node_modules/next/package.json" "$ROOT/node_modules/tailwindcss/package.json" \
           "$ROOT/package-lock.json" "$ROOT/pnpm-lock.yaml" "$ROOT/yarn.lock" "$ROOT/bun.lock" "$ROOT/bun.lockb" \
           "$ROOT"/next.config.*; do
    [ -e "$f" ] && [ "$f" -nt "$CACHE" ] && return 1
  done
  return 0
}

if [ "${NEXT_WF_NO_CACHE:-0}" != 1 ] && cache_fresh && cache_ok "$CACHE"; then
  cat "$CACHE"; design_skill; mode_override; exit 0
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
{ [ -f "$ROOT/bun.lockb" ] || [ -f "$ROOT/bun.lock" ]; } && PM=bun   # bun.lock: text lockfile, bun 1.2+

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

# Libraries the project already uses. Several can be present at once (a migration in progress),
# so each key is a +-joined list. Agents follow these; they never swap one for the kit's default.
add() { [ -n "$(dep "$2")" ] && eval "$1=\"\${$1:+\$$1+}$3\""; return 0; }   # add <KEY> <package> <label>
VALIDATION=""; add VALIDATION zod zod; add VALIDATION yup yup; add VALIDATION valibot valibot
STORE=""; add STORE zustand zustand; add STORE @reduxjs/toolkit redux-toolkit; add STORE jotai jotai
[ -z "$STORE" ] && add STORE redux redux
FORMS=""; add FORMS react-hook-form react-hook-form; add FORMS formik formik; add FORMS @tanstack/react-form tanstack-form
DATA_CLIENT=""; add DATA_CLIENT @tanstack/react-query react-query; add DATA_CLIENT swr swr; add DATA_CLIENT @apollo/client apollo
# RTK Query ships inside @reduxjs/toolkit, so the dependency alone doesn't say it's in use.
case "$STORE" in *redux-toolkit*)
  grep -rqsE "createApi\(" --include='*.ts' --include='*.tsx' --exclude-dir=node_modules --exclude-dir=.next \
    "$ROOT/${SRC:-}" "$ROOT/lib" "$ROOT/store" "$ROOT/redux" "$ROOT/services" 2>/dev/null &&
    DATA_CLIENT="${DATA_CLIENT:+$DATA_CLIENT+}rtk-query" ;;
esac
UI_KIT=""; add UI_KIT antd antd; add UI_KIT @mui/material mui; add UI_KIT @chakra-ui/react chakra; add UI_KIT @mantine/core mantine

# kit: the kit's own line applies (server-first, zod, zustand only at the top of the ladder).
# match: the project is built on a different stack, so new code follows what is already there.
STACK_MODE="kit"
case "+$STORE+$FORMS+$DATA_CLIENT+$UI_KIT+" in
  *+redux-toolkit+*|*+redux+*|*+formik+*|*+react-query+*|*+swr+*|*+apollo+*|*+rtk-query+*|*+antd+*|*+mui+*|*+chakra+*|*+mantine+*) STACK_MODE="match" ;;
esac
[ -n "$VALIDATION" ] && [ "${VALIDATION#*zod}" = "$VALIDATION" ] && STACK_MODE="match"   # validation, but no zod

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
    "VALIDATION=$VALIDATION" "STORE=$STORE" "FORMS=$FORMS" "DATA_CLIENT=$DATA_CLIENT" "UI_KIT=$UI_KIT" "STACK_MODE=$STACK_MODE" "ORM=$ORM" \
    "TEST_UNIT=$TEST_UNIT" "TEST_E2E=$TEST_E2E" \
    "CMD_TYPECHECK=$TYPECHECK" "CMD_LINT=$LINT" "CMD_TEST=$TEST" "CMD_BUILD=$BUILD"; do
    case "$kv" in CMD_*) v="$(safecmd "${kv#*=}")" ;; *) v="$(safe "${kv#*=}")" ;; esac
    printf '%s="%s"\n' "${kv%%=*}" "$v"
  done
} | tee "$CACHE" 2>/dev/null
design_skill
mode_override
exit 0
