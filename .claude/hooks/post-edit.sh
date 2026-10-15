#!/usr/bin/env bash
# PostToolUse(Edit|Write|MultiEdit): one entry point for every per-edit check.
# Parses the hook input once, then runs the guards and the formatter against that file and
# merges their output into a single block (exit 2) or a single advisory.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
grep -qE '"next"[[:space:]]*:' "$ROOT/package.json" 2>/dev/null || exit 0   # not a Next.js project
. "$SELF_DIR/_lib.sh"
FILE="$(wf_file_from_input "$(cat)")"
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
T0="${EPOCHREALTIME:-}"   # bash 5+; latency is simply not recorded on older shells

ERR=""; ADV=""
for g in guard-rsc.sh guard-component.sh guard-styles.sh; do
  E="$(mktemp)"
  O="$(NEXT_WF_FILE="$FILE" NEXT_WF_RAW=1 bash "$SELF_DIR/$g" 2>"$E" </dev/null)"; RC=$?
  [ "$RC" = 2 ] && ERR="$ERR$(cat "$E")"$'\n'
  [ -n "$O" ] && ADV="$ADV$O"$'\n'
  rm -f "$E"
done
NEXT_WF_FILE="$FILE" bash "$SELF_DIR/format.sh" </dev/null >/dev/null 2>&1

# Keep the shell-change snapshot current, so bash-guard.sh doesn't re-check this edit.
bash "$SELF_DIR/bash-guard.sh" --snapshot >/dev/null 2>&1

[ -n "$T0" ] && [ -n "${EPOCHREALTIME:-}" ] &&
  wf_metric edit_hook ms "$(T1="$EPOCHREALTIME"; awk -v a="${T0/,/.}" -v b="${T1/,/.}" 'BEGIN{printf "%d", (b-a)*1000}')"   # some locales use a decimal comma

if [ -n "$ERR" ]; then
  { printf '%s' "$ERR"; [ -n "$ADV" ] && printf '%s' "$ADV"; } >&2
  exit 2
fi
[ -n "$ADV" ] && wf_context PostToolUse "$ADV"
exit 0
