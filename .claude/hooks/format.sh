#!/usr/bin/env bash
# PostToolUse(Edit|Write): format/lint-fix the touched file with the project's own
# toolchain (never installs anything), and remember that TS sources changed so the
# Stop hook knows it needs to typecheck.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
grep -qE '"next"[[:space:]]*:' "$ROOT/package.json" 2>/dev/null || exit 0   # not a Next.js project
. "$SELF_DIR/_lib.sh"
# Run standalone (hook JSON on stdin) or from post-edit.sh, which parses once and sets NEXT_WF_FILE.
if [ -n "${NEXT_WF_FILE:-}" ]; then FILE="$NEXT_WF_FILE"; else FILE="$(wf_file_from_input "$(cat)")"; fi
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.css|*.json|*.md) ;;
  *) exit 0 ;;
esac

mkdir -p "$ROOT/.claude/.cache"
case "$FILE" in *.ts|*.tsx) touch "$ROOT/.claude/.cache/dirty" ;; esac

[ -d "$ROOT/node_modules" ] || exit 0
if [ -x "$ROOT/node_modules/.bin/prettier" ]; then
  "$ROOT/node_modules/.bin/prettier" --write --log-level error "$FILE" >/dev/null 2>&1 || true
fi
case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs)
    # NEXT_WF_FORMAT=prettier skips the per-edit eslint --fix (slow on large repos);
    # lint still runs in /next:ship and, with NEXT_WF_VERIFY=typecheck,lint, at Stop.
    if [ "${NEXT_WF_FORMAT:-all}" != prettier ] && [ -x "$ROOT/node_modules/.bin/eslint" ]; then
      "$ROOT/node_modules/.bin/eslint" --fix --no-warn-ignored "$FILE" >/dev/null 2>&1 || true
    fi ;;
esac
exit 0
