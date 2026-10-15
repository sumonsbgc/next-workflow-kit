#!/usr/bin/env bash
# Stop: before handing the turn back, make sure the TypeScript the agent just wrote
# actually compiles. Failing types are reported back so Claude fixes them in-turn
# instead of leaving a broken tree behind.
#
# Only NEW type errors fail the turn. Errors that were already in the codebase are recorded
# in a baseline (by /next:setup, or `verify.sh --baseline` run by the user), so an agent is
# never bounced for — or tempted into "fixing" — problems it didn't cause. The baseline only
# shrinks on its own: when errors disappear they are dropped from it.
#
#   verify.sh --baseline          record the current type errors as pre-existing
#   NEXT_WF_VERIFY=off            -> disable
#   NEXT_WF_VERIFY=typecheck,lint -> also run the project's lint script
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
MODE="${NEXT_WF_VERIFY:-typecheck}"
CACHE="$ROOT/.claude/.cache"
BASELINE="$CACHE/tsc-baseline"
grep -qE '"next"[[:space:]]*:' "$ROOT/package.json" 2>/dev/null || exit 0   # not a Next.js project
. "$SELF_DIR/_lib.sh"

# "file(12,5): error TS2322: msg" -> "file: TS2322: msg" — line numbers move as code is edited
# (greedy path match: route groups like app/(shop)/page.tsx contain parentheses)
normalize() { sed -nE 's/^[[:space:]]*(.+)\([0-9]+,[0-9]+\): error (TS[0-9]+): (.*)$/\1: \2: \3/p' | sort -u; }

# Last line of defence: only ever eval a command made of plain words.
cmd_ok() { [[ "$1" =~ ^[A-Za-z0-9\ ._/:=-]*$ ]]; }
typecheck() { eval "$(bash "$SELF_DIR/stack.sh")"; cmd_ok "$CMD_TYPECHECK" || return 0; [ -n "$CMD_TYPECHECK" ] || return 0; (cd "$ROOT" && eval "$CMD_TYPECHECK" 2>&1); }

if [ "${1:-}" = --baseline ]; then
  mkdir -p "$CACHE"
  typecheck | normalize > "$BASELINE"
  N="$(grep -c . "$BASELINE" || true)"
  wf_metric baseline errors "$N"
  echo "baseline: $N pre-existing type error(s) recorded in .claude/.cache/tsc-baseline"
  exit 0
fi

[ "$MODE" = off ] && exit 0
INPUT="$(cat)"
if command -v jq >/dev/null 2>&1; then
  ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')"
else
  ACTIVE="$(printf '%s' "$INPUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).stop_hook_active===true))}catch{process.stdout.write("false")}})' 2>/dev/null || echo false)"
fi
[ "$ACTIVE" = true ] && exit 0   # already looped once; never trap the agent in a Stop loop
MARK="$CACHE/dirty"
[ -f "$MARK" ] || exit 0
[ -d "$ROOT/node_modules" ] || { rm -f "$MARK"; exit 0; }
eval "$(bash "$SELF_DIR/stack.sh")"
cmd_ok "$CMD_TYPECHECK" || CMD_TYPECHECK=""
cmd_ok "$CMD_LINT" || CMD_LINT=""

FAIL=""
if [ -n "$CMD_TYPECHECK" ]; then
  if OUT="$(cd "$ROOT" && eval "$CMD_TYPECHECK" 2>&1)"; then
    : > "$BASELINE" 2>/dev/null || true          # clean tree: nothing is pre-existing any more
  else
    NOW="$(printf '%s\n' "$OUT" | normalize)"
    if [ -z "$NOW" ]; then
      # failed without parseable errors (crash, config error): report it whole
      FAIL="$FAIL
--- typecheck failed ($CMD_TYPECHECK) ---
$(printf '%s' "$OUT" | tail -n 40)"
    elif [ -f "$BASELINE" ]; then
      NEW="$(comm -13 "$BASELINE" <(printf '%s\n' "$NOW"))"
      if [ -n "$NEW" ]; then
        SHOW="$(printf '%s\n' "$OUT" | while IFS= read -r l; do
          n="$(printf '%s\n' "$l" | normalize)"; [ -n "$n" ] && grep -qxF "$n" <<<"$NEW" && printf '%s\n' "$l"
        done | head -n 40)"
        FAIL="$FAIL
--- typecheck: $(grep -c . <<<"$NEW") new error(s) introduced by this change ($CMD_TYPECHECK) ---
$SHOW
(Pre-existing errors are baselined and not shown. Fix only the ones above.)"
      else
        # no new errors; drop any baseline entries that have since been fixed
        comm -12 "$BASELINE" <(printf '%s\n' "$NOW") > "$BASELINE.tmp" && mv "$BASELINE.tmp" "$BASELINE"
      fi
    else
      FAIL="$FAIL
--- typecheck failed ($CMD_TYPECHECK) ---
$(printf '%s' "$OUT" | tail -n 40)
(No baseline exists. If these errors were already in the codebase before this session, tell the user — they can record them with: bash .claude/hooks/verify.sh --baseline. Do not run that yourself.)"
    fi
  fi
fi
if [[ "$MODE" == *lint* ]] && [ -n "$CMD_LINT" ]; then
  OUT="$(cd "$ROOT" && eval "$CMD_LINT" 2>&1)" || FAIL="$FAIL
--- lint failed ($CMD_LINT) ---
$(printf '%s' "$OUT" | tail -n 40)"
fi

rm -f "$MARK"
if [ -n "$FAIL" ]; then
  wf_metric verify result fail
  { echo "Verification of your changes failed. Fix these, then stop:"; printf '%s\n' "$FAIL"; } >&2
  exit 2
fi
wf_metric verify result pass
exit 0
