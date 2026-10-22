#!/usr/bin/env bash
# PreToolUse(Bash), plugin installs only: pre-approve the kit's own bookkeeping commands.
# A project install allows these with permission rules in settings.json. A plugin can't ship
# permission rules, so without this every `tasks.sh` call would prompt. Per the docs a hook's
# "allow" never overrides the user's deny or ask rules; it only skips the default prompt.
#
# Approved, and nothing else (anything that doesn't match falls through to the normal prompt):
#   bash <helpers>/tasks.sh|stack.sh|repo-map.sh|verify-browser.sh <plain args>
#   bash <helpers>/tasks.sh new <id>-<slug> <<'TAG' … TAG     (quoted heredoc: never expanded)
#   the project's detected typecheck/lint/test/build commands, plus plain path arguments
#   printenv NEXT_WF_DEV_URL · git status · node --version
# "Plain" means no $, backticks, ;, &, |, <, >, backslashes, globs, braces or parentheses: one
# command, nothing expanded, nothing chained. verify.sh and run-tasks.sh are never approved.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="$(cat)"
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"
else
  CMD="$(printf '%s' "$INPUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).tool_input?.command||"")}catch{}})')"
fi
[ -n "$CMD" ] || exit 0

allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"next-workflow helper: %s"}}\n' "$1"
  exit 0
}
plain() { [[ "$1" != *[\$\`\;\&\|\<\>\\\*\?\{\}\(\)]* ]] && [[ "$1" != *$'\n'* ]]; }

# The helpers folder as a regex literal: its dots (".claude", "2.5.0") must not match any character.
H="$(printf '%s' "$SELF_DIR" | sed 's/[]\\.^$*+?(){}|[]/\\&/g')"
HELPER_RE="^bash ($H|\\.claude/hooks)/(tasks|stack|repo-map|verify-browser)\\.sh( .*)?$"

# The task-writing heredoc: exactly one command line, a quoted delimiter, nothing after it.
FIRST="${CMD%%$'\n'*}"
TQ="'"
if [ "$FIRST" != "$CMD" ] &&
   [[ "$FIRST" =~ ^bash\ ($H|\.claude/hooks)/tasks\.sh\ new\ [0-9]{3,}-[a-z0-9]+(-[a-z0-9]+)*\ \<\<\ ?($TQ([A-Za-z_]+)$TQ|\"([A-Za-z_]+)\")$ ]]; then
  TAG="${BASH_REMATCH[4]}${BASH_REMATCH[5]}"
  BODY="${CMD#*$'\n'}"; BODY="${BODY%"${BODY##*[![:space:]]}"}"
  [ "${BODY##*$'\n'}" = "$TAG" ] && [ "$(grep -cxF -- "$TAG" <<<"$BODY")" = 1 ] && allow "tasks.sh new"
  exit 0
fi

plain "$CMD" || exit 0

[[ "$CMD" =~ $HELPER_RE ]] && allow "${BASH_REMATCH[2]}.sh"

case "$CMD" in
  'printenv NEXT_WF_DEV_URL'|'git status'|'node --version') allow "$CMD" ;;
esac

# The verify commands detected for this project (values already restricted to a strict charset),
# optionally followed by file paths or flags: `npm run test -- src/x.test.ts`.
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
eval "$(CLAUDE_PROJECT_DIR="$ROOT" bash "$SELF_DIR/stack.sh" 2>/dev/null | grep -E '^CMD_(TYPECHECK|LINT|TEST|BUILD)=')"
for c in "${CMD_TYPECHECK:-}" "${CMD_LINT:-}" "${CMD_TEST:-}" "${CMD_BUILD:-}"; do
  [ -n "$c" ] || continue
  if [ "$CMD" = "$c" ] || { [[ "$CMD" == "$c "* ]] && [[ "${CMD#"$c "}" =~ ^[A-Za-z0-9._/@:=\ -]+$ ]]; }; then
    allow "verify command"
  fi
done
exit 0
