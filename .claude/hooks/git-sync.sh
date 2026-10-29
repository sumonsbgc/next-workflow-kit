#!/usr/bin/env bash
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/_lib.sh"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
CONF="$ROOT/.claude/workflow.conf"
REMOTE="${NEXT_WF_REMOTE:-origin}"
SUGGESTED_RE='^(stage|staging|develop|development|dev)$'

die() { echo "git-sync: $1" >&2; exit "${2:-1}"; }
cd "$ROOT" 2>/dev/null || die "no project folder: $ROOT"
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
[[ "$REMOTE" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid remote name: $REMOTE"

conf_get() { [ -f "$CONF" ] && sed -n "s/^$1=//p" "$CONF" | tail -n 1; }
conf_set() {
  mkdir -p "$(dirname "$CONF")"
  if [ -f "$CONF" ] && grep -q "^$1=" "$CONF"; then
    local tmp; tmp="$(mktemp)"
    awk -v k="$1" -v v="$2" 'index($0, k "=") == 1 { print k "=" v; next } { print }' "$CONF" > "$tmp" && mv "$tmp" "$CONF"
  else
    printf '%s=%s\n' "$1" "$2" >> "$CONF"
  fi
}
valid_branch() { [[ "$1" =~ ^[A-Za-z0-9._/-]+$ ]] && git check-ref-format --branch "$1" >/dev/null 2>&1; }
stage_branch() {
  local b="${NEXT_WF_STAGE_BRANCH:-$(conf_get STAGE_BRANCH)}"
  [ -n "$b" ] && valid_branch "$b" && printf '%s' "$b"
}
sync_mode() {
  local m="${NEXT_WF_SYNC_MODE:-$(conf_get SYNC_MODE)}"
  if [ "$m" = rebase ]; then echo rebase; else echo merge; fi
}
remote_has() { git rev-parse --verify --quiet "refs/remotes/$REMOTE/$1" >/dev/null; }
fetch() { git fetch --quiet --prune "$REMOTE" 2>/dev/null || die "git fetch $REMOTE failed (offline, or no such remote?)"; }
current_branch() { git symbolic-ref --quiet --short HEAD || die "detached HEAD: check out a branch first"; }
dirty_files() { git status --porcelain --untracked-files=normal -- . ':(exclude).claude/.cache'; }
is_clean() { [ -z "$(dirty_files)" ]; }
in_progress() {
  [ -f "$(git rev-parse --git-path MERGE_HEAD)" ] || [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]
}
list_candidates() {
  git for-each-ref --format='%(refname:lstrip=3)' "refs/remotes/$REMOTE" | grep -vx HEAD | grep -E "$SUGGESTED_RE"
}
no_stage() {
  echo "no stage branch configured. Ask the user which branch to pull from before every push, then run: git-sync.sh stage <branch>"
  git fetch --quiet --prune "$REMOTE" 2>/dev/null
  local c; c="$(list_candidates | paste -sd, - | sed 's/,/, /g')"
  [ -n "$c" ] && echo "likely candidates on $REMOTE: $c"
  exit 2
}
need_stage() { STAGE="$(stage_branch)" || no_stage; [ -n "$STAGE" ] || no_stage; }
conflicts() { git diff --name-only --diff-filter=U; }

integrate() {
  local ref="$1" label="$2" mode
  git merge-base --is-ancestor "$ref" HEAD && return 0
  if git merge --ff-only --quiet "$ref" >/dev/null 2>&1; then echo "  fast-forwarded to $label"; return 0; fi
  mode="$(sync_mode)"
  if [ "$mode" = rebase ]; then
    git rebase --quiet "$ref" >/dev/null 2>&1 && { echo "  rebased onto $label"; return 0; }
  else
    git merge --no-edit --quiet "$ref" >/dev/null 2>&1 && { echo "  merged $label"; return 0; }
  fi
  echo "CONFLICT while bringing in $label ($mode). Conflicted files:"
  conflicts | sed 's/^/  /'
  echo "Resolve them, git add them, then: git $mode --continue. Or give up with: git $mode --abort"
  exit 3
}

cmd_stage() {
  if [ $# -eq 0 ]; then need_stage; echo "$STAGE"; return; fi
  valid_branch "$1" || die "not a valid branch name: $1"
  conf_set STAGE_BRANCH "$1"
  [ -z "$(conf_get SYNC_MODE)" ] && conf_set SYNC_MODE merge
  git fetch --quiet --prune "$REMOTE" 2>/dev/null
  remote_has "$1" || echo "warning: $REMOTE/$1 does not exist (yet)"
  echo "stage branch: $1 (saved in .claude/workflow.conf — commit it so the team shares it)"
}

cmd_candidates() {
  git fetch --quiet --prune "$REMOTE" 2>/dev/null
  local c; c="$(list_candidates)"
  if [ -n "$c" ]; then echo "suggested:"; printf '  %s\n' $c; fi
  echo "all branches on $REMOTE:"
  git for-each-ref --format='  %(refname:lstrip=3)' "refs/remotes/$REMOTE" | grep -vx '  HEAD' | head -n 30
}

cmd_status() {
  local b; b="$(current_branch)"
  echo "branch: $b"
  echo "uncommitted files: $(dirty_files | wc -l | tr -d ' ')"
  STAGE="$(stage_branch)" || STAGE=""
  if [ -z "$STAGE" ]; then echo "stage: not configured"; return; fi
  echo "stage: $REMOTE/$STAGE (sync: $(sync_mode))"
  fetch
  remote_has "$STAGE" || { echo "  $REMOTE/$STAGE does not exist"; return; }
  read -r ahead behind < <(git rev-list --left-right --count "HEAD...$REMOTE/$STAGE")
  echo "  $ahead commit(s) not in stage, $behind commit(s) from stage not in this branch"
  if remote_has "$b"; then
    read -r ahead behind < <(git rev-list --left-right --count "HEAD...$REMOTE/$b")
    echo "upstream: $REMOTE/$b — $ahead to push, $behind to pull"
  else
    echo "upstream: none yet ($b has never been pushed)"
  fi
}

cmd_check_staged() {
  local hits
  hits="$(git diff --cached --name-only | grep -E '(^|/)(\.env(\..*)?|auth\.json|id_(rsa|ed25519|ecdsa)(\..*)?|[^/]*\.(pem|key))$' | grep -vE '(^|/)\.env\.(example|sample|template|dist)$')"
  [ -z "$hits" ] && { echo "no secret files staged"; return 0; }
  echo "secret files are staged — unstage them (git restore --staged <file>) and add them to .gitignore:"
  printf '%s\n' "$hits" | sed 's/^/  /'
  exit 1
}

cmd_sync() {
  need_stage
  local b before; b="$(current_branch)"
  in_progress && die "a merge or rebase is already in progress: finish it (git add + git merge/rebase --continue) or abort it" 6
  is_clean || die "uncommitted changes: commit them first (/next:sync commits them)" 4
  fetch
  remote_has "$STAGE" || die "$REMOTE/$STAGE does not exist" 2
  before="$(git rev-parse HEAD)"
  echo "syncing $b with $REMOTE/$STAGE ($(sync_mode))"
  if [ "$b" != "$STAGE" ] && remote_has "$b"; then integrate "$REMOTE/$b" "$REMOTE/$b"; fi
  integrate "$REMOTE/$STAGE" "$REMOTE/$STAGE"
  local n; n="$(git rev-list --count "$before..HEAD")"
  if [ "$n" = 0 ]; then
    echo "already up to date with $REMOTE/$STAGE"
  else
    echo "brought in $n commit(s): $(git diff --shortstat "$before" HEAD | sed 's/^ //')"
  fi
  wf_metric git action sync commits "$n"
}

cmd_push() {
  need_stage
  local b; b="$(current_branch)"
  in_progress && die "a merge or rebase is in progress: finish it first" 6
  is_clean || die "uncommitted changes: commit them first (/next:sync commits them)" 4
  fetch
  remote_has "$STAGE" || die "$REMOTE/$STAGE does not exist" 2
  git merge-base --is-ancestor "$REMOTE/$STAGE" HEAD ||
    die "not synced: $REMOTE/$STAGE has commits this branch doesn't. Run git-sync.sh sync first (it pulls them in), check the result, then push." 5
  if remote_has "$b" && ! git merge-base --is-ancestor "$REMOTE/$b" HEAD; then
    die "$REMOTE/$b has commits this branch doesn't. Run git-sync.sh sync first." 5
  fi
  git push --quiet -u "$REMOTE" "$b" 2>&1 || die "git push failed" 7
  wf_metric git action push
  echo "pushed $b to $REMOTE (includes $REMOTE/$STAGE at $(git rev-parse --short "$REMOTE/$STAGE"))"
}

case "${1:-}" in
  stage) shift; cmd_stage "$@" ;;
  candidates) cmd_candidates ;;
  status) cmd_status ;;
  check-staged) cmd_check_staged ;;
  sync|pull) cmd_sync ;;
  push) cmd_push ;;
  *) echo "usage: git-sync.sh stage [<branch>] | candidates | status | check-staged | sync | push" >&2; exit 64 ;;
esac
