#!/usr/bin/env bash
# PreToolUse(Bash), plugin installs only: pre-approve the kit's own bookkeeping commands.
# A project install allows these with permission rules in settings.json. A plugin can't ship
# permission rules, so without this every `tasks.sh` call would prompt. Per the docs a hook's
# "allow" never overrides the user's deny or ask rules; it only skips the default prompt.
#
# Approved, and nothing else (anything that doesn't match falls through to the normal prompt):
#   bash <plugin helpers, absolute>/tasks.sh|stack.sh|repo-map.sh|verify-browser.sh <plain args>
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
# Only the plugin's own copies, by absolute path. A relative `.claude/hooks/…` would run whatever
# the project has at that path; when the project really has its own install, plugin-dispatch.sh
# skips this hook and the project's settings.json allow rules apply instead.
HELPER_RE="^bash $H/(tasks|stack|repo-map|verify-browser|git-sync)\\.sh( .*)?$"

# The task-writing heredoc: exactly one command line, a quoted delimiter, nothing after it.
FIRST="${CMD%%$'\n'*}"
TQ="'"
if [ "$FIRST" != "$CMD" ] &&
   [[ "$FIRST" =~ ^bash\ $H/tasks\.sh\ new\ [0-9]{3,}-[a-z0-9]+(-[a-z0-9]+)*\ \<\<\ ?($TQ([A-Za-z_]+)$TQ|\"([A-Za-z_]+)\")$ ]]; then
  TAG="${BASH_REMATCH[3]}${BASH_REMATCH[4]}"
  BODY="${CMD#*$'\n'}"; BODY="${BODY%"${BODY##*[![:space:]]}"}"
  [ "${BODY##*$'\n'}" = "$TAG" ] && [ "$(grep -cxF -- "$TAG" <<<"$BODY")" = 1 ] && allow "tasks.sh new"
  exit 0
fi

plain "$CMD" || exit 0

[[ "$CMD" =~ $HELPER_RE ]] && allow "${BASH_REMATCH[1]}.sh"

case "$CMD" in
  'printenv NEXT_WF_DEV_URL'|'git status'|'node --version') allow "$CMD" ;;
esac

# The verify commands detected for this project (values already restricted to a strict charset),
# optionally followed by file paths: `npm run test -- src/x.test.ts`. Paths only: no flags and no
# `=`, so nothing like `--config evil.ts` or `--reporter=./x.js` rides along (those prompt).
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
eval "$(CLAUDE_PROJECT_DIR="$ROOT" bash "$SELF_DIR/stack.sh" 2>/dev/null | grep -E '^CMD_(TYPECHECK|LINT|TEST|BUILD)=')"
for c in "${CMD_TYPECHECK:-}" "${CMD_LINT:-}" "${CMD_TEST:-}" "${CMD_BUILD:-}"; do
  [ -n "$c" ] || continue
  [ "$CMD" = "$c" ] && allow "verify command"
  if [[ "$CMD" == "$c "* ]]; then
    REST="${CMD#"$c "}"; REST="${REST#-- }"
    read -ra ARGS <<<"$REST"
    OK=1
    for a in "${ARGS[@]}"; do [[ "$a" =~ ^[A-Za-z0-9_./@][A-Za-z0-9_./@:-]*$ ]] || OK=0; done
    [ "${#ARGS[@]}" -gt 0 ] && [ "$OK" = 1 ] && allow "verify command"
  fi
done
exit 0
