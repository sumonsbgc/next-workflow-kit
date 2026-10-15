#!/usr/bin/env bash
# Run tasks one per fresh Claude session, so no task inherits the previous one's context.
# Each run is `claude -p "/next:task <id> headless"`; what a task learns reaches the next one
# through .claude/project-context.md, exactly as across normal sessions.
#
#   bash .claude/hooks/run-tasks.sh                     every runnable task, in dependency order
#   bash .claude/hooks/run-tasks.sh 003 004             just these, in this order
#   options:
#     --checkpoint            one local git commit per closed task, on a new branch nw/batch-<time>
#                             (undo with: tasks.sh undo <id>; merge the branch when you're happy)
#     --no-branch             with --checkpoint, commit on the current branch instead
#     --max N                 stop after N tasks (default: no limit)
#     --budget USD            spending cap per task (claude --max-budget-usd)
#     --permission-mode M     default acceptEdits. bypassPermissions only inside a container/VM.
#     --dry-run               print what would run, run nothing
#
# Stops at the first task that does not end `done` (blocked, failed, or out of budget), so a
# rerun picks up where it left off. Cost, turns and time per task go to metrics.jsonl.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
export CLAUDE_PROJECT_DIR="$ROOT"
. "$SELF_DIR/_lib.sh"
T="$SELF_DIR/tasks.sh"

CHECKPOINT=0; NOBRANCH=0; MAX=0; BUDGET=""; PMODE="acceptEdits"; DRY=0; IDS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --checkpoint) CHECKPOINT=1 ;;
    --no-branch) NOBRANCH=1 ;;
    --max) MAX="$2"; shift ;;
    --budget) BUDGET="$2"; shift ;;
    --permission-mode) PMODE="$2"; shift ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) IDS+=("$1") ;;
  esac
  shift
done
command -v claude >/dev/null 2>&1 || { echo "claude CLI not found on PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to read run results" >&2; exit 1; }
[ "$CHECKPOINT" = 1 ] && export NEXT_WF_CHECKPOINT=commit
export NEXT_WF_RUNNER=1   # tasks.sh tags these starts, so stats can tell runner from in-session work
# Checkpoints go on their own branch, so a batch never commits straight onto main.
if [ "$CHECKPOINT" = 1 ] && [ "$NOBRANCH" = 0 ] && [ "$DRY" = 0 ] && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  CUR="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
  case "$CUR" in
    nw/batch-*) echo "continuing on $CUR" ;;
    *) BR="nw/batch-$(date +%Y%m%d-%H%M)"
       git -C "$ROOT" switch -c "$BR" >/dev/null 2>&1 || { echo "could not create branch $BR" >&2; exit 1; }
       echo "checkpoints go on new branch $BR (from $CUR). When done: git switch $CUR && git merge $BR" ;;
  esac
fi
# A dry run changes no statuses, so `tasks.sh next` would keep returning the same task:
# plan the whole todo list up front instead.
if [ "$DRY" = 1 ] && [ "${#IDS[@]}" -eq 0 ]; then
  while read -r id st _; do [ "$st" = todo ] && IDS+=("$id"); done < <(bash "$T" list 2>/dev/null)
fi

task_field() { sed -n '2,/^---[[:space:]]*$/p' "$1" | sed -nE "s/^$2:[[:space:]]*//p" | sed -E 's/[[:space:]]+#.*$//' | head -1; }

pick() { # next id to run, or empty
  if [ "${#IDS[@]}" -gt 0 ]; then
    [ "$N" -lt "${#IDS[@]}" ] && printf '%s' "${IDS[$N]}"
    return
  fi
  local p; p="$(bash "$T" next 2>/dev/null)" || return 0
  task_field "$p" id
}

N=0; TOTAL=0; SUMMARY=""; LAST=""
trap 'echo; echo "interrupted"; printf "%b" "$SUMMARY"; exit 130' INT
while :; do
  [ "$MAX" -gt 0 ] && [ "$N" -ge "$MAX" ] && break
  ID="$(pick)"; [ -n "$ID" ] || break
  P="$(bash "$T" path "$ID" 2>/dev/null)" || { echo "no task $ID" >&2; break; }
  ST="$(task_field "$P" status)"
  case "$ST" in
    done) N=$((N+1)); continue ;;
    draft) echo "task $ID is a draft — approve it first: bash .claude/hooks/tasks.sh approve $ID"; break ;;
  esac
  [ "$ID" = "$LAST" ] && { echo "task $ID did not finish on the previous run — stopping to avoid a loop"; break; }
  LAST="$ID"

  printf '\n▶ task %s — %s\n' "$ID" "$(task_field "$P" title)"
  ARGS=(-p "/next:task $ID headless" --output-format json --permission-mode "$PMODE")
  [ -n "$BUDGET" ] && ARGS+=(--max-budget-usd "$BUDGET")
  if [ "$DRY" = 1 ]; then echo "  [dry-run] claude ${ARGS[*]}"; N=$((N+1)); continue; fi

  START=$(date +%s)
  OUT="$(cd "$ROOT" && claude "${ARGS[@]}" 2>/dev/null)"
  SECS=$(( $(date +%s) - START ))
  COST="$(printf '%s' "$OUT" | jq -r '.total_cost_usd // 0' 2>/dev/null || echo 0)"
  TURNS="$(printf '%s' "$OUT" | jq -r '.num_turns // 0' 2>/dev/null || echo 0)"
  ERRFLAG="$(printf '%s' "$OUT" | jq -r '.is_error // false' 2>/dev/null || echo true)"
  ST="$(task_field "$P" status)"
  wf_metric run id "$ID" result "$ST" cost_usd "$COST" turns "$TURNS" seconds "$SECS"
  TOTAL="$(awk -v a="$TOTAL" -v b="$COST" 'BEGIN{printf "%.4f", a+b}')"
  LINE="$(printf '  %-6s %-8s %4ss  %3s turns  $%s' "$ID" "$ST" "$SECS" "$TURNS" "$COST")"
  echo "$LINE"; SUMMARY="$SUMMARY$LINE\n"
  N=$((N+1))
  if [ "$ST" != "done" ]; then
    [ "$ERRFLAG" = true ] && echo "  the session ended with an error (budget or turn limit?)"
    echo "  stopping: task $ID is '$ST'. Its log says why: bash .claude/hooks/tasks.sh show $ID"
    break
  fi
done

printf '\nran %s task(s), total $%s\n' "$N" "$TOTAL"
