#!/usr/bin/env bash
# Task-file helper for the next-workflow task runner.
# Deterministic bookkeeping so the model never reads a task file it isn't working on.
#
#   tasks.sh init                 scaffold the tasks folder (.claude/tasks) from the templates
#   tasks.sh new <id>-<slug>      write a draft task from stdin (no .claude/ write prompt)
#   tasks.sh dir                  print the tasks folder, relative to the project
#   tasks.sh migrate              move a pre-2.3 ./tasks folder to .claude/tasks
#   tasks.sh list [status]        one line per task: id, status, title [size]
#   tasks.sh next                 path of the first runnable task (todo, deps done)
#   tasks.sh nextid               the next free id, zero-padded (for /next:write-task)
#   tasks.sh show <id>            print one task file
#   tasks.sh context <id>         the task plus what its dependencies did (log lines, files changed):
#                                 read this instead of re-exploring code a dependency just wrote
#   tasks.sh map                  the cached repo map (routes, modules, models…), see repo-map.sh
#   tasks.sh path <id>            print its path
#   tasks.sh approve <id|all>     draft -> todo (the planner writes drafts; you approve them)
#   tasks.sh start <id>           -> doing; records the git base so the task's diff can be shown
#   tasks.sh diff <id>            everything this task changed since it started (needs git)
#   tasks.sh close <id> <text>    -> done + log line; with NEXT_WF_CHECKPOINT=commit, one local commit
#                                 holding only this task's files (never secrets, never pre-existing edits)
#   tasks.sh block <id> <reason>  -> blocked, reason logged
#   tasks.sh undo <id> [--cascade]  revert the task's checkpoint; refuses while done tasks depend on it
#                                 unless --cascade, which undoes those dependents first (newest first)
#   tasks.sh verdict <id> <PASS|FAIL|UNVERIFIED|SKIPPED> [round]   record a verifier result
#   tasks.sh can-skip-verify <id> exit 0 only if every criterion is [review] and the diff is <= 20 lines
#   tasks.sh log <id> <text>      append a line under ## Log
#   tasks.sh count [status]       number of tasks, for cheap status checks
#   tasks.sh stats                cost/time/guard summary from .claude/.cache/metrics.jsonl
#
# Statuses: draft -> todo -> doing -> done | blocked.
# A task is a .md file whose FIRST LINE is `---` (YAML frontmatter). Plans, notes and scratch
# files that happen to live in the tasks folder are ignored, not run.
# Tasks live in .claude/tasks (override with NEXT_WF_TASKS_DIR, relative to the project).
# A project still on the pre-2.3 layout — ./tasks with the kit's TEMPLATE.md and no
# .claude/tasks — keeps working from ./tasks until `tasks.sh migrate` moves it.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
if [ -n "${NEXT_WF_TASKS_DIR:-}" ]; then
  DIR="$ROOT/${NEXT_WF_TASKS_DIR%/}"
elif [ ! -d "$ROOT/.claude/tasks" ] && [ -f "$ROOT/tasks/TEMPLATE.md" ]; then
  DIR="$ROOT/tasks"
else
  DIR="$ROOT/.claude/tasks"
fi
TASKS_REL="${DIR#"$ROOT"/}"   # for git pathspecs: task files are bookkeeping, not the task's change
STATE="$ROOT/.claude/.cache/tasks"
# shellcheck source=_lib.sh
. "$SELF_DIR/_lib.sh"

die() { printf '%s\n' "$*" >&2; exit 1; }

field() { # field <file> <key> — read one frontmatter value
  sed -n '2,/^---[[:space:]]*$/p' "$1" 2>/dev/null \
    | grep -m1 -E "^$2:" | sed -E "s/^$2:[[:space:]]*//" | sed -E 's/^["'"'"']|["'"'"']$//g' | sed -E 's/[[:space:]]+#.*$//'
}

is_task() { # a real task file: YAML frontmatter, not a doc, template, plan or note
  case "$(basename "$1")" in README.md|TEMPLATE.md|_*) return 1 ;; esac
  [ -f "$1" ] || return 1
  [ "$(head -n1 "$1" 2>/dev/null | tr -d '[:space:]')" = "---" ]
}

task_id()     { local v; v="$(field "$1" id)";     [ -n "$v" ] && printf '%s' "$v" || basename "$1" .md; }
task_status() { local v; v="$(field "$1" status)"; [ -n "$v" ] && printf '%s' "$v" || printf 'todo'; }
task_title()  { local v; v="$(field "$1" title)";  [ -n "$v" ] && printf '%s' "$v" || basename "$1" .md; }
task_size()   { field "$1" size; }

find_task() { # find_task <id> -> path
  local want="$1" f
  for f in "$DIR"/*.md; do
    is_task "$f" || continue
    [ "$(task_id "$f")" = "$want" ] && { printf '%s' "$f"; return 0; }
  done
  for f in "$DIR/$want".md "$DIR/$want"-*.md "$DIR"/"$want"_*.md; do
    [ -f "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

deps_done() { # every id in `depends:` has status done
  local d dep p
  d="$(field "$1" depends | tr -d '[]' | tr ',' ' ')"
  [ -n "$d" ] || return 0
  for dep in $d; do
    p="$(find_task "$dep")" || return 1
    [ "$(task_status "$p")" = "done" ] || return 1
  done
  return 0
}

set_status() { # set_status <file> <status>
  local f="$1" st="$2"
  if sed -n '2,/^---[[:space:]]*$/p' "$f" | grep -qE '^status:'; then
    awk -v st="$st" '
      NR==1 { print; next }
      !done_fm && /^---[[:space:]]*$/ { done_fm=1; print; next }
      !done_fm && /^status:/ { print "status: " st; next }
      { print }
    ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  else
    awk -v st="$st" 'NR==1 { print; print "status: " st; next } { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  fi
}

in_git() { git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; }

state_get() { # state_get <id> <key>
  [ -f "$STATE/$1.env" ] && sed -n "s/^$2=//p" "$STATE/$1.env" | head -1
}

# Paths that must never be committed by a checkpoint, whatever .gitignore says.
is_secret_path() {
  case "$(basename "$1")" in
    .env.example|.env.sample|.env.template|.env.dist) return 1 ;;
    .env|.env.*|*.pem|*.key|id_rsa|id_rsa.*|id_ed25519|id_ed25519.*|id_ecdsa|id_ecdsa.*) return 0 ;;
  esac
  return 1
}

# Blob hash of a working-tree file, or "-" if it is gone.
wt_hash() { [ -f "$ROOT/$1" ] && git -C "$ROOT" hash-object -- "$1" 2>/dev/null || echo -; }

# Paths this task touched: changed since its base commit or untracked, minus files that were
# already dirty at `start` and haven't changed since (those are someone else's work).
task_paths() { # task_paths <id>
  local base p h was
  base="$(state_get "$1" base)"; [ -n "$base" ] && [ "$base" != none ] || base="HEAD"
  { git -C "$ROOT" diff --name-only "$base" -- . ":!$TASKS_REL"
    git -C "$ROOT" ls-files --others --exclude-standard -- . ":!$TASKS_REL"; } | sort -u |
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    was="$( [ -f "$STATE/$1.dirty" ] && awk -v p="$p" '{h=$1; $1=""; sub(/^ /,""); if ($0==p) print h}' "$STATE/$1.dirty" | head -1)"
    if [ -n "$was" ]; then h="$(wt_hash "$p")"; [ "$h" = "$was" ] && continue; fi
    printf '%s\n' "$p"
  done
}

# Tasks (transitively) depending on <id> that are done, newest checkpoint first.
done_dependents() { # done_dependents <id>
  local want="$1" f id deps found=1 seen=" $1 "
  while [ "$found" = 1 ]; do
    found=0
    for f in "$DIR"/*.md; do
      is_task "$f" || continue
      id="$(task_id "$f")"; case "$seen" in *" $id "*) continue ;; esac
      deps=" $(field "$f" depends | tr -d '[]' | tr ',' ' ') "
      for d in $seen; do
        case "$deps" in *" $d "*) seen="$seen$id "; found=1; break ;; esac
      done
    done
  done
  for id in $seen; do
    [ "$id" = "$want" ] && continue
    f="$(find_task "$id")" || continue
    [ "$(task_status "$f")" = "done" ] || continue
    printf '%s %s\n' "$(git -C "$ROOT" log -1 --format=%ct --grep="^task $id: " 2>/dev/null || echo 0)" "$id"
  done | sort -rn | awk '{print $2}'
}

append_log() { # append_log <file> <text>
  local f="$1"; shift
  grep -qE '^## Log[[:space:]]*$' "$f" || printf '\n## Log\n' >> "$f"
  printf -- '- %s\n' "$*" >> "$f"
}

CMD="${1:-list}"; shift || true

case "$CMD" in
  init)
    mkdir -p "$DIR"
    TPL="$SELF_DIR/../templates"
    [ -d "$TPL" ] || TPL="$SELF_DIR/../../templates"
    [ -f "$DIR/README.md" ]   || { [ -f "$TPL/tasks-readme.md" ] && cp "$TPL/tasks-readme.md" "$DIR/README.md"; }
    [ -f "$DIR/TEMPLATE.md" ] || { [ -f "$TPL/task.md" ]         && cp "$TPL/task.md" "$DIR/TEMPLATE.md"; }
    CTX="$ROOT/.claude/project-context.md"
    [ -f "$CTX" ] || { [ -f "$TPL/project-context.md" ] && mkdir -p "$ROOT/.claude" && cp "$TPL/project-context.md" "$CTX"; }
    echo "tasks ready: $TASKS_REL/ (README.md, TEMPLATE.md)"
    [ -f "$CTX" ] && echo "context: .claude/project-context.md"
    ;;

  dir) echo "$TASKS_REL" ;;

  new) # new <id>-<kebab-title>, task text on stdin: writes a DRAFT task file. Claude Code
       # prompts on every Write/Edit under .claude/, so planners write drafts through here.
    NAME="${1:?usage: tasks.sh new <id>-<kebab-title> < task.md}"
    [[ "$NAME" =~ ^([0-9]{3,})-[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "bad name '$NAME' — want <id>-<kebab-title>, e.g. 004-add-footer"
    NID="${BASH_REMATCH[1]}"
    [ -z "$(find_task "$NID" 2>/dev/null)" ] || die "task $NID already exists — run: tasks.sh nextid"
    BODY="$(head -c 200000)"
    [ "$(printf '%s\n' "$BODY" | head -n1 | tr -d '[:space:]')" = "---" ] || die "the task must start with a --- frontmatter line"
    FM="$(printf '%s\n' "$BODY" | sed -n '2,/^---[[:space:]]*$/p')"
    printf '%s\n' "$FM" | grep -qE "^id:[[:space:]]*['\"]?$NID['\"]?[[:space:]]*$" || die "frontmatter id must be $NID"
    printf '%s\n' "$FM" | grep -qE '^status:[[:space:]]*draft[[:space:]]*$' || die "new tasks are drafts: set status: draft"
    mkdir -p "$DIR" || die "cannot create $TASKS_REL"
    OUT="$DIR/$NAME.md"
    printf '%s\n' "$BODY" > "$OUT.tmp.$$" && mv "$OUT.tmp.$$" "$OUT" || { rm -f "$OUT.tmp.$$"; die "could not write $OUT"; }
    echo "wrote $TASKS_REL/$NAME.md (draft)"
    ;;

  migrate)
    [ -z "${NEXT_WF_TASKS_DIR:-}" ] || die "NEXT_WF_TASKS_DIR is set ($NEXT_WF_TASKS_DIR) — unset it to use .claude/tasks"
    [ -d "$ROOT/.claude/tasks" ] && die "already on .claude/tasks — nothing to move"
    [ -d "$ROOT/tasks" ] || die "no ./tasks folder to move"
    mkdir -p "$ROOT/.claude" && mv "$ROOT/tasks" "$ROOT/.claude/tasks" || die "could not move ./tasks"
    echo "moved ./tasks -> .claude/tasks"
    if [ -f "$ROOT/.gitignore" ] && grep -qxE '/?tasks/?' "$ROOT/.gitignore"; then
      echo "note: .gitignore ignores /tasks; .claude/tasks is not ignored, so task files will now show up in git"
    fi
    ;;

  list)
    WANT="${1:-}"
    [ -d "$DIR" ] || die "No tasks directory at $DIR — run: tasks.sh init"
    FOUND=0
    for f in "$DIR"/*.md; do
      is_task "$f" || continue
      st="$(task_status "$f")"
      [ -n "$WANT" ] && [ "$st" != "$WANT" ] && continue
      MARK=""
      [ "$st" = todo ] && ! deps_done "$f" && MARK=" [blocked by deps]"
      [ "$(task_size "$f")" = large ] && MARK=" [large]$MARK"
      printf '%-6s %-7s %s%s\n' "$(task_id "$f")" "$st" "$(task_title "$f")" "$MARK"
      FOUND=1
    done
    [ "$FOUND" = 0 ] && echo "(no tasks${WANT:+ with status $WANT})"
    ;;

  count)
    WANT="${1:-}"; N=0
    for f in "$DIR"/*.md; do
      is_task "$f" || continue
      [ -n "$WANT" ] && [ "$(task_status "$f")" != "$WANT" ] && continue
      N=$((N+1))
    done
    echo "$N"
    ;;

  next)
    for f in "$DIR"/*.md; do
      is_task "$f" || continue
      [ "$(task_status "$f")" = doing ] && { printf '%s\n' "$f"; exit 0; }
    done
    for f in "$DIR"/*.md; do
      is_task "$f" || continue
      [ "$(task_status "$f")" = todo ] || continue
      deps_done "$f" || continue
      printf '%s\n' "$f"; exit 0
    done
    echo "(no runnable task)"; exit 1
    ;;

  nextid)
    MAX=0
    for f in "$DIR"/*.md; do
      is_task "$f" || continue
      n="$(task_id "$f" | grep -oE '^[0-9]+')" || continue
      n=$((10#$n)); [ "$n" -gt "$MAX" ] && MAX=$n
    done
    printf '%03d\n' $((MAX+1))
    ;;

  map) exec bash "$SELF_DIR/repo-map.sh" "$@" ;;

  context)
    f="$(find_task "${1:?id}")" || die "no task with id $1"
    cat "$f"
    DEPS="$(field "$f" depends | tr -d '[]' | tr ',' ' ')"
    for d in $DEPS; do
      df="$(find_task "$d")" || continue
      printf '\n---\n## Dependency %s: %s (%s)\n' "$d" "$(task_title "$df")" "$(task_status "$df")"
      sed -n '/^## Log/,$p' "$df" | tail -n +2 | tail -5
      [ -s "$STATE/$d.files" ] && printf 'Files it changed: %s\n' "$(tr '\n' ' ' < "$STATE/$d.files")"
    done
    exit 0 ;;

  path)  [ $# -ge 1 ] || die "usage: tasks.sh path <id>"; find_task "$1" || die "no task with id $1"; echo ;;
  show)  [ $# -ge 1 ] || die "usage: tasks.sh show <id>"; f="$(find_task "$1")" || die "no task with id $1"; cat "$f" ;;

  approve)
    [ $# -ge 1 ] || die "usage: tasks.sh approve <id|all>"
    if [ "$1" = all ]; then
      N=0
      for f in "$DIR"/*.md; do
        is_task "$f" || continue
        [ "$(task_status "$f")" = draft ] && { set_status "$f" todo; N=$((N+1)); }
      done
      echo "approved $N"
    else
      f="$(find_task "$1")" || die "no task with id $1"
      [ "$(task_status "$f")" = draft ] || die "task $1 is $(task_status "$f"), not draft"
      set_status "$f" todo; echo "approved $1"
    fi ;;

  start)
    f="$(find_task "${1:?id}")" || die "no task with id $1"
    [ "$(task_status "$f")" = draft ] && die "task $1 is still a draft — review it, then: tasks.sh approve $1"
    set_status "$f" doing
    mkdir -p "$STATE"
    BASE="none"
    if in_git; then
      BASE="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none)"
      # Remember what was already dirty, so the checkpoint can leave it out.
      : > "$STATE/$1.dirty"
      { git -C "$ROOT" diff --name-only HEAD -- . ":!$TASKS_REL"
        git -C "$ROOT" ls-files --others --exclude-standard -- . ":!$TASKS_REL"; } 2>/dev/null | sort -u |
        while IFS= read -r p; do [ -n "$p" ] && printf '%s %s\n' "$(wt_hash "$p")" "$p"; done >> "$STATE/$1.dirty"
    fi
    printf 'base=%s\nstarted=%s\n' "$BASE" "$(date +%s)" > "$STATE/$1.env"
    VIA=session; [ "${NEXT_WF_RUNNER:-0}" = 1 ] && VIA=runner
    wf_metric task_start id "$1" size "$(task_size "$f")" via "$VIA"
    # Soft limit, measured: in-session batches degrade after ~3 tasks (context build-up).
    if [ "$VIA" = session ] && [ -f "$ROOT/.claude/.cache/metrics.jsonl" ]; then
      SINCE=$(( $(date +%s) - 10800 ))
      N="$(grep '"event":"task_start"' "$ROOT/.claude/.cache/metrics.jsonl" | grep '"via":"session"' |
           sed -nE 's/^\{"ts":([0-9]+).*/\1/p' | awk -v s="$SINCE" '$1 >= s' | wc -l | tr -d ' ')"
      [ "${N:-0}" -gt 3 ] && echo "note: task #$N started in-session within 3h — for longer batches use run-tasks.sh (fresh context per task)" >&2
    fi
    echo "started $1" ;;

  diff)
    f="$(find_task "${1:?id}")" || die "no task with id $1"
    in_git || die "not a git repository — no diff available; review the files named in the task log instead"
    BASE="$(state_get "$1" base)"; [ -n "$BASE" ] && [ "$BASE" != none ] || BASE="HEAD"
    # Secret files are never printed: the diff is read by an agent, and printing it would bypass
    # the Read deny rules. Their names are listed so nobody thinks they were untouched.
    SECRET_PS=(":(exclude,glob)**/.env" ":(exclude,glob)**/.env.*" ":(exclude,glob)**/*.pem" ":(exclude,glob)**/*.key"
               ":(exclude,glob)**/auth.json" ":(exclude,glob)**/id_rsa*" ":(exclude,glob)**/id_ed25519*" ":(exclude,glob)**/id_ecdsa*")
    git -C "$ROOT" diff "$BASE" -- . ":!$TASKS_REL" "${SECRET_PS[@]}"
    UNTRACKED="$(git -C "$ROOT" ls-files --others --exclude-standard -- . ":!$TASKS_REL" "${SECRET_PS[@]}")"
    [ -n "$UNTRACKED" ] && printf '\n# new files (untracked):\n%s\n' "$UNTRACKED"
    HIDDEN="$({ git -C "$ROOT" diff --name-only "$BASE" -- . ":!$TASKS_REL"; git -C "$ROOT" ls-files --others --exclude-standard -- . ":!$TASKS_REL"; } |
              while IFS= read -r p; do [ -n "$p" ] && is_secret_path "$p" && printf '%s\n' "$p"; done | sort -u)"
    [ -n "$HIDDEN" ] && printf '\n# secret files changed (content not shown): %s\n' "$(tr '\n' ' ' <<<"$HIDDEN")"
    exit 0 ;;

  done)  f="$(find_task "${1:?id}")" || die "no task with id $1"; set_status "$f" "done"; echo "done $1" ;;

  close)
    f="$(find_task "${1:?id}")" || die "no task with id $1"; ID="$1"; shift
    [ $# -gt 0 ] || die "usage: tasks.sh close <id> <log line>"
    STARTED="$(state_get "$ID" started)"; SECS=0
    [ -n "$STARTED" ] && SECS=$(( $(date +%s) - STARTED ))
    FILES=0; PATHS=""
    if in_git; then
      PATHS="$(task_paths "$ID")"
      FILES="$(printf '%s' "$PATHS" | grep -c . || true)"
    fi
    set_status "$f" "done"; append_log "$f" "$*"
    # Remember what this task touched, so dependent tasks get it from `context` instead of re-reading.
    [ -n "$PATHS" ] && printf '%s\n' "$PATHS" > "$STATE/$ID.files"
    wf_metric task_close id "$ID" size "$(task_size "$f")" seconds "$SECS" files "$FILES"
    echo "closed $ID (${SECS}s, $FILES files)"
    if [ "${NEXT_WF_CHECKPOINT:-off}" = commit ] && in_git; then
      SECRETS=""; ADD=()
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        if is_secret_path "$p"; then SECRETS="$SECRETS $p"; else ADD+=("$p"); fi
      done <<<"$PATHS"
      if [ -n "$SECRETS" ]; then
        echo "checkpoint: SKIPPED — secret files changed during this task:$SECRETS. Nothing was committed; add them to .gitignore, then commit the task's files yourself." >&2
        wf_metric checkpoint id "$ID" result refused_secret
      else
        # Stage exactly this task's files (adds, edits and deletions) plus the task file itself.
        [ "${#ADD[@]}" -gt 0 ] && git -C "$ROOT" add -A -- "${ADD[@]}" >/dev/null 2>&1
        git -C "$ROOT" add -- "${f#$ROOT/}" >/dev/null 2>&1
        if git -C "$ROOT" diff --cached --quiet; then echo "checkpoint: nothing to commit"
        elif git -C "$ROOT" commit -q -m "task $ID: $(task_title "$f")" -m "$*" 2>/dev/null; then
          echo "checkpoint: $(git -C "$ROOT" rev-parse --short HEAD) task $ID (${#ADD[@]} files)"
        else
          echo "checkpoint: commit failed (a pre-commit hook?) — this task's files are staged, nothing lost" >&2
        fi
      fi
    fi ;;

  undo)
    f="$(find_task "${1:?id}")" || die "no task with id $1"
    in_git || die "not a git repository — nothing to undo with"
    DEPS="$(done_dependents "$1")"
    if [ -n "$DEPS" ]; then
      if [ "${2:-}" = --cascade ]; then
        for d in $DEPS; do bash "$0" undo "$d" || die "cascade stopped at task $d — nothing after it was undone"; done
      else
        die "task $1 has done dependents ($(echo $DEPS)) — their code builds on it. Undo them first, or: tasks.sh undo $1 --cascade"
      fi
    fi
    C="$(git -C "$ROOT" log --format=%H -n1 --grep="^task $1: ")"
    [ -n "$C" ] || die "no checkpoint commit for task $1 (was NEXT_WF_CHECKPOINT=commit set when it closed?)"
    # The checkpoint also holds this task file (status: done). Revert the code, but keep the
    # task file — with its history — and put it back to todo.
    KEEP="$(mktemp)"; cp "$f" "$KEEP"
    git -C "$ROOT" revert --no-commit "$C" >/dev/null 2>&1 || { git -C "$ROOT" revert --abort >/dev/null 2>&1; rm -f "$KEEP"; die "revert of $C hit conflicts (later work touches the same lines) — revert it by hand: git revert $C"; }
    mkdir -p "$(dirname "$f")"; cp "$KEEP" "$f"; rm -f "$KEEP"
    set_status "$f" todo; append_log "$f" "reverted checkpoint $(git -C "$ROOT" rev-parse --short "$C")"
    git -C "$ROOT" add -- "${f#$ROOT/}" >/dev/null 2>&1   # revert --no-commit already staged the code
    git -C "$ROOT" commit -q -m "revert task $1: $(task_title "$f")" >/dev/null 2>&1 || die "revert staged but commit failed (a pre-commit hook?) — commit it yourself"
    wf_metric task_undo id "$1"
    echo "reverted task $1 ($C); status back to todo" ;;

  verdict)
    f="$(find_task "${1:?id}")" || die "no task with id $1"
    case "${2:-}" in PASS|FAIL|UNVERIFIED|SKIPPED) ;; *) die "usage: tasks.sh verdict <id> PASS|FAIL|UNVERIFIED|SKIPPED [round]" ;; esac
    wf_metric verdict id "$1" result "$2" round "${3:-1}"
    echo "verdict $1: $2 (round ${3:-1})" ;;

  can-skip-verify)
    f="$(find_task "${1:?id}")" || die "no task with id $1"
    CRIT="$(sed -n '/^## Acceptance/,/^## /p' "$f" | grep -E '^[[:space:]]*- \[[ x]\]')"
    [ -n "$CRIT" ] || { echo "no: no acceptance criteria"; exit 1; }
    grep -qvE '\[review\]' <<<"$CRIT" && { echo "no: has [test]/[browser]/untagged criteria"; exit 1; }
    in_git || { echo "no: no git, so the diff size can't be measured"; exit 1; }
    BASE="$(state_get "$1" base)"; [ -n "$BASE" ] && [ "$BASE" != none ] || BASE="HEAD"
    # Size of the task's own change: kit bookkeeping (.claude/, the tasks folder) doesn't count.
    LINES="$(git -C "$ROOT" diff --numstat "$BASE" -- . ":!$TASKS_REL" ':!.claude' | awk '{a+=$1+$2} END{print a+0}')"
    NEW="$(git -C "$ROOT" ls-files --others --exclude-standard -- . ":!$TASKS_REL" ':!.claude' | while IFS= read -r p; do wc -l < "$ROOT/$p"; done | awk '{a+=$1} END{print a+0}')"
    T=$((LINES + NEW))
    [ "$T" -le 20 ] || { echo "no: diff is $T lines (> 20)"; exit 1; }
    echo "yes: all criteria [review], diff $T lines" ;;

  block) f="$(find_task "${1:?id}")" || die "no task with id $1"; set_status "$f" blocked
         ID="$1"; shift; [ $# -gt 0 ] && append_log "$f" "blocked: $*"
         wf_metric task_block id "$ID"; echo "blocked $ID" ;;

  log)   f="$(find_task "${1:?id}")" || die "no task with id $1"; shift; [ $# -gt 0 ] || die "nothing to log"
         append_log "$f" "$*"; echo "logged" ;;

  stats)
    M="$ROOT/.claude/.cache/metrics.jsonl"
    [ -f "$M" ] || { echo "(no metrics yet)"; exit 0; }
    node - "$M" <<'JS'
const lines = require('fs').readFileSync(process.argv[2], 'utf8').split('\n').filter(Boolean)
const ev = lines.map(l => { try { return JSON.parse(l) } catch { return null } }).filter(Boolean)
const by = (k, xs) => xs.reduce((m, x) => ((m[x[k] ?? '-'] ??= []).push(x), m), {})
const closed = ev.filter(e => e.event === 'task_close')
const runs = ev.filter(e => e.event === 'run')
console.log(`tasks closed: ${closed.length}   blocked: ${ev.filter(e => e.event === 'task_block').length}   undone: ${ev.filter(e => e.event === 'task_undo').length}`)
for (const [size, xs] of Object.entries(by('size', closed))) {
  const avg = xs.reduce((a, x) => a + (x.seconds || 0), 0) / xs.length
  console.log(`  size ${size.padEnd(6)} ${String(xs.length).padStart(3)} tasks   avg ${Math.round(avg / 60)} min   avg ${Math.round(xs.reduce((a, x) => a + (x.files || 0), 0) / xs.length)} files`)
}
if (runs.length) {
  const cost = runs.reduce((a, r) => a + Number(r.cost_usd || 0), 0)
  console.log(`headless runs: ${runs.length}   total $${cost.toFixed(2)}   avg $${(cost / runs.length).toFixed(2)}/task   failed: ${runs.filter(r => r.result !== 'done').length}`)
}
const v = ev.filter(e => e.event === 'verdict')
if (v.length) {
  const first = Object.values(by('id', v.filter(e => String(e.round) === '1')))
  const verified = first.filter(xs => xs[0].result !== 'SKIPPED')
  const pass1 = verified.filter(xs => xs[0].result.startsWith('PASS')).length
  console.log(`verifier: first-pass ${verified.length ? Math.round(100 * pass1 / verified.length) : 0}% (${pass1}/${verified.length})   skipped ${first.length - verified.length}   FAIL rounds ${v.filter(e => e.result === 'FAIL').length}   UNVERIFIED ${v.filter(e => e.result === 'UNVERIFIED').length}`)
}
const starts = ev.filter(e => e.event === 'task_start')
if (starts.length) console.log(`task starts: ${starts.filter(e => e.via === 'runner').length} via run-tasks, ${starts.filter(e => e.via !== 'runner').length} in-session`)
const lat = ev.filter(e => e.event === 'edit_hook').map(e => e.ms).sort((a, b) => a - b)
if (lat.length) console.log(`edit hook latency: p50 ${lat[Math.floor(lat.length * 0.5)]} ms   p95 ${lat[Math.floor(lat.length * 0.95)]} ms   (${lat.length} edits)`)
const g = ev.filter(e => e.event === 'guard')
if (g.length) {
  console.log('guard hits:')
  for (const [name, xs] of Object.entries(by('guard', g)).sort((a, b) => b[1].length - a[1].length))
    console.log(`  ${name.padEnd(10)} ${String(xs.length).padStart(4)}   (${xs.filter(x => x.level === 'block').length} blocking)`)
}
JS
    ;;

  *) sed -n '2,31p' "$0"; exit 1 ;;
esac
