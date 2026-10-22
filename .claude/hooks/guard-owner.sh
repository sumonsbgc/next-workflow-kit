#!/usr/bin/env bash
# PreToolUse(Bash): a shell edit of a task's `status:` is blocked — statuses move only through
# tasks.sh, so the log and verdict stay in step. Like guard-secrets this is a speed bump, not a
# boundary.
set -uo pipefail
INPUT="$(cat)"
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"
else
  CMD="$(printf '%s' "$INPUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).tool_input?.command||"")}catch{}})')"
fi
[ -n "$CMD" ] || exit 0

block() { echo "Blocked by next-workflow: $1" >&2; exit 2; }

# A heredoc fed to anything but a shell is data (a task for `tasks.sh new`, a script for python,
# a file for cat), not commands: drop its body. Fed to a bare shell (`bash <<EOF`) it runs, so it stays.
FIRST="${CMD%%$'\n'*}"
if [[ "$FIRST" =~ \<\<-?[[:space:]]*[\"\']?([A-Za-z_][A-Za-z0-9_]*) ]] && [[ "$FIRST" != *'<<<'* ]]; then
  TAG="${BASH_REMATCH[1]}"
  read -ra F <<<"${FIRST%%<<*}"
  k=0; while [ "$k" -lt "${#F[@]}" ] && [[ "${F[$k]}" == *=* ]]; do k=$((k + 1)); done
  RUNS=0
  if [[ "${F[$k]:-}" =~ ^(.*/)?(bash|sh|zsh|dash|ksh)$ ]]; then
    RUNS=1; for x in "${F[@]:$((k + 1))}"; do [[ "$x" == -* ]] || { RUNS=0; break; }; done   # `bash script.sh <<X` feeds data
  fi
  if [ "$RUNS" = 0 ]; then
    REST="$(printf '%s\n' "$CMD" | awk -v t="$TAG" 'NR > 1 && !past { if ($0 ~ "^[[:space:]]*" t "[[:space:]]*$") past = 1; next } NR > 1 { print }')"
    CMD="$FIRST"${REST:+$'\n'"$REST"}
  fi
fi

# Quotes and backslashes only change how the shell groups words; drop them so the command
# looks like what it runs.
NORM="$(printf '%s' "$CMD" | tr -d "\"'\\\\")"

# The verification gate's switches belong to the user (settings env or their own shell). An
# agent that sets one inline, or exports it, is turning off the check on its own work.
if [[ "$NORM" =~ (^|[^A-Za-z0-9_])NEXT_WF_(REQUIRE_VERDICT|SKIP_VERIFY_LINES|VERIFY|VERIFY_BROWSER)= ]]; then
  block "NEXT_WF_REQUIRE_VERDICT, NEXT_WF_SKIP_VERIFY_LINES, NEXT_WF_VERIFY and NEXT_WF_VERIFY_BROWSER are the user's settings. Run the command without them; if the gate is in the way, tell the user."
fi

# Recording the type-error baseline is the user's job: an agent that baselines its own errors
# hides them. A project install also has a deny rule for this; a plugin install has only this hook.
if [[ "$NORM" =~ verify\.sh([^A-Za-z0-9_]|$) ]] && [[ "$NORM" == *--baseline* ]]; then
  block "verify.sh --baseline records the current type errors as accepted. Only the user runs it (in their own terminal, or with ! in the prompt)."
fi

TASKS_DIR="${NEXT_WF_TASKS_DIR:-.claude/tasks}"
WRITES='(^|[[:space:]])(-i[^[:space:]]*|--in-place|tee|python3?|node|perl|ruby)([[:space:]]|$)|>'
if [[ "$NORM" == *status:* ]] && [[ "$NORM" == *"${TASKS_DIR%/}/"* || "$NORM" == *tasks/* ]] && [[ "$NORM" =~ $WRITES ]]; then
  block "a task's status is changed only through tasks.sh (start/close/block), so the log and verdict stay in step with it."
fi
exit 0
