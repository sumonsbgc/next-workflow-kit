#!/usr/bin/env bash
# PreToolUse(Bash): steps that belong to the user, not to Claude.
#
#   git push, gh pr create, gh pr merge     publishing is the user's call; work stays local
#   a shell edit of a task's `status:`      statuses move only through tasks.sh
#
# A blocking exit (2) wins over allow rules, so a stray `Bash(git push *)` allow in
# settings.local.json doesn't reopen it. Like guard-secrets this is a speed bump, not a
# boundary: a git alias or a script can still push. The user runs these steps in a terminal.
#
#   NEXT_WF_ALLOW_PUSH=1  (in the environment Claude Code was started with) -> allow pushing
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

# Quotes and backslashes only change how the shell groups words; drop them so `"git" push`
# and `git\ push` look like what they run.
NORM="$(printf '%s' "$CMD" | tr -d "\"'\\\\")"

TASKS_DIR="${NEXT_WF_TASKS_DIR:-.claude/tasks}"
WRITES='(^|[[:space:]])(-i[^[:space:]]*|--in-place|tee|python3?|node|perl|ruby)([[:space:]]|$)|>'
if [[ "$NORM" == *status:* ]] && [[ "$NORM" == *"${TASKS_DIR%/}/"* || "$NORM" == *tasks/* ]] && [[ "$NORM" =~ $WRITES ]]; then
  block "a task's status is changed only through tasks.sh (start/close/block), so the log and verdict stay in step with it."
fi

# Only words in command position count, so `git commit -m "then push"` or an echo that mentions
# tasks.sh is left alone. Wrappers (sudo, env, xargs, timeout, bash script.sh, sh -c ...) keep the
# position open for the word after them.
set -f
while IFS= read -r SEG; do
  read -ra W <<<"$SEG"
  n=${#W[@]}; CP=1; WRAP=0
  for ((i = 0; i < n && CP == 1; i++)); do
    w="${W[$i]}"
    case "$w" in
      git|*/git)
        j=$((i + 1))
        while [ "$j" -lt "$n" ]; do       # skip git's global options to reach the subcommand
          case "${W[$j]}" in
            -C|-c|--git-dir|--work-tree|--namespace|--exec-path) j=$((j + 2)) ;;
            -*) j=$((j + 1)) ;;
            *) break ;;
          esac
        done
        if [ "${W[$j]:-}" = push ] && [ "${NEXT_WF_ALLOW_PUSH:-0}" != 1 ]; then
          block "pushing is the user's call — commits stay local. Finish the task, then tell the user it is ready to push (they push from their own terminal)."
        fi
        CP=0 ;;
      gh|*/gh)
        if [ "${W[$((i + 1))]:-}" = pr ] && [[ "${W[$((i + 2))]:-}" =~ ^(create|merge)$ ]] && [ "${NEXT_WF_ALLOW_PUSH:-0}" != 1 ]; then
          block "opening or merging a pull request publishes the branch — that is the user's call. Tell the user the work is ready instead."
        fi
        CP=0 ;;
      sudo|env|xargs|nice|timeout|nohup|*/env) WRAP=1 ;;   # their option values look like words: keep scanning
      command|exec|time|builtin|then|do|else|if|while|until|!|source|.) ;;
      bash|sh|zsh|dash|ksh|*/bash|*/sh|*/zsh) ;;
      -*|[0-9]*|*=*) ;;                   # options, timeout's duration, VAR=value
      *) [ "$WRAP" = 1 ] || CP=0 ;;
    esac
  done
done < <(printf '%s\n' "$NORM" | sed 's/[;&|()]/\n/g')
set +f
exit 0
