#!/usr/bin/env bash
# PreToolUse(Bash): a shell edit of a task's `status:` is blocked — statuses move only through
# tasks.sh, so the log and verdict stay in step. Like guard-secrets this is a speed bump, not a
# boundary.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/_lib.sh"
INPUT="$(cat)"
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"
else
  CMD="$(printf '%s' "$INPUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).tool_input?.command||"")}catch{}})')"
fi
[ -n "$CMD" ] || exit 0

block() { echo "Blocked by next-workflow: $1" >&2; exit 2; }

FIRST="${CMD%%$'\n'*}"
TQ="'"
if [[ "$FIRST" =~ ^[[:space:]]*bash[[:space:]]+[A-Za-z0-9_./~-]*tasks\.sh[[:space:]]+new[[:space:]]+[0-9]{3,}-[a-z0-9-]+[[:space:]]*\<\<[[:space:]]*($TQ([A-Za-z_]+)$TQ|\"([A-Za-z_]+)\")[[:space:]]*$ ]]; then
  TAG="${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
  BODY="${CMD#*$'\n'}"; BODY="${BODY%"${BODY##*[![:space:]]}"}"
  if [ "$BODY" != "$CMD" ] && [ "${BODY##*$'\n'}" = "$TAG" ] && [ "$(grep -cxF -- "$TAG" <<<"$BODY")" = 1 ]; then CMD="$FIRST"; fi
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

HELPERS="$(wf_helpers "$SELF_DIR")"
set -f
while IFS= read -r SEG; do
  read -ra W <<<"$SEG"
  n=${#W[@]}; CP=1; WRAP=0
  for ((i = 0; i < n && CP == 1; i++)); do
    w="${W[$i]}"
    case "$w" in
      git|*/git)
        j=$((i + 1))
        while [ "$j" -lt "$n" ]; do
          case "${W[$j]}" in
            -C|-c|--git-dir|--work-tree|--namespace|--exec-path) j=$((j + 2)) ;;
            -*) j=$((j + 1)) ;;
            *) break ;;
          esac
        done
        if [ "${W[$j]:-}" = push ]; then
          block "plain git push skips the stage-branch pull. Push only when the user asks, and only through bash $HELPERS/git-sync.sh push (it refuses until the branch contains the stage branch; run git-sync.sh sync first). /next:sync does the whole sequence."
        fi
        CP=0 ;;
      sudo|env|xargs|nice|timeout|nohup|*/env) WRAP=1 ;;
      command|exec|time|builtin|then|do|else|if|while|until|!|source|.) ;;
      bash|sh|zsh|dash|ksh|*/bash|*/sh|*/zsh) ;;
      -*|[0-9]*|*=*) ;;
      *) [ "$WRAP" = 1 ] || CP=0 ;;
    esac
  done
done < <(printf '%s\n' "$NORM" | sed 's/[;&|()]/\n/g')
set +f
exit 0
