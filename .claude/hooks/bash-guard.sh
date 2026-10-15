#!/usr/bin/env bash
# PostToolUse(Bash): source files written by a shell command (heredoc, sed -i, a codemod)
# never pass through the Edit/Write hooks. Find the ones this command changed, run the same
# guards over them, and mark the tree dirty so the Stop hook still typechecks.
#   bash-guard.sh --snapshot   record the current state only (session start, after each edit)
# Needs git to see what changed; without it this hook does nothing.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
grep -qE '"next"[[:space:]]*:' "$ROOT/package.json" 2>/dev/null || exit 0
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
. "$SELF_DIR/_lib.sh"
[ "${1:-}" = --snapshot ] || cat >/dev/null   # drain the hook input; only the tree matters

SNAP="$ROOT/.claude/.cache/bash-snapshot"
mkdir -p "$ROOT/.claude/.cache"

TOP="$(git -C "$ROOT" rev-parse --show-toplevel)"
snapshot() { # "<mtime> <absolute path>" for every changed/untracked source file under ROOT
  # porcelain paths are relative to the repo top, even when ROOT is a monorepo package
  git -C "$ROOT" status --porcelain -uall -- . 2>/dev/null \
    | sed -E 's/^.. //; s/^.* -> //; s/^"(.*)"$/\1/' \
    | grep -E '\.(ts|tsx|js|jsx|mjs|css)$' \
    | while IFS= read -r p; do
        [ -f "$TOP/$p" ] && printf '%s %s\n' "$(date -r "$TOP/$p" +%s 2>/dev/null || echo 0)" "$TOP/$p"
      done | sort
}

NOW="$(snapshot)"
if [ "${1:-}" = --snapshot ] || [ ! -f "$SNAP" ]; then
  printf '%s\n' "$NOW" > "$SNAP"; exit 0
fi
CHANGED="$(comm -13 "$SNAP" <(printf '%s\n' "$NOW") | sed -E 's/^[0-9]+ //' | grep -v '^$' || true)"
printf '%s\n' "$NOW" > "$SNAP"
[ -n "$CHANGED" ] || exit 0

# Run one guard on a file; prints its blocking lines (✗ …) on stdout, advisories to fd 3.
guard_errors() { # guard_errors <guard> <project-root> <file>
  local e o
  e="$(mktemp)"
  o="$(CLAUDE_PROJECT_DIR="$2" NEXT_WF_FILE="$3" NEXT_WF_RAW=1 NEXT_WF_METRICS=off bash "$SELF_DIR/$1" 2>"$e" </dev/null)"
  [ -n "$o" ] && printf '%s\n' "$o" >&3
  grep -E '^[[:space:]]*✗' "$e" || true
  rm -f "$e"
}

# The committed version of a file, checked the same way, in a scratch copy of the project
# shape (package.json + same relative path), so "pre-existing" is judged by the same rules.
HEADROOT="$(mktemp -d)"; trap 'rm -rf "$HEADROOT"' EXIT
cp "$ROOT/package.json" "$HEADROOT/" 2>/dev/null; mkdir -p "$HEADROOT/app"
head_errors() { # head_errors <guard> <abs path> -> ✗ lines the HEAD version already had
  local rel="${2#$TOP/}" here="${2#$ROOT/}"
  git -C "$TOP" cat-file -e "HEAD:$rel" 2>/dev/null || return 0     # new file: nothing pre-existing
  mkdir -p "$HEADROOT/$(dirname "$here")"
  git -C "$TOP" show "HEAD:$rel" > "$HEADROOT/$here" 2>/dev/null || return 0
  guard_errors "$1" "$HEADROOT" "$HEADROOT/$here" 3>/dev/null
}

ERR=""; ADV=""; OLD=""
ADVF="$(mktemp)"
while IFS= read -r p; do
  case "$p" in *.ts|*.tsx) touch "$ROOT/.claude/.cache/dirty" ;; esac
  wf_metric guard guard bash file "${p#$ROOT/}" level warn
  for g in guard-rsc.sh guard-component.sh guard-styles.sh; do
    NOWERR="$(guard_errors "$g" "$ROOT" "$p" 3>>"$ADVF")"
    [ -n "$NOWERR" ] || continue
    # Only violations this command introduced block. Ones the committed file already had are
    # someone else's debt: a formatter or codemod touching the file must not be blocked by them.
    WASERR="$(head_errors "$g" "$p")"
    NEWERR="$(comm -23 <(sort -u <<<"$NOWERR") <(sort -u <<<"$WASERR"))"
    if [ -n "$NEWERR" ]; then ERR="$ERR${p#$ROOT/}:"$'\n'"$NEWERR"$'\n'
    else OLD="$OLD  - ${p#$ROOT/}: $(wc -l <<<"$NOWERR" | tr -d ' ') pre-existing violation(s), not blocking"$'\n'; fi
  done
done <<<"$CHANGED"
ADV="$(cat "$ADVF")${OLD:+$'\n'Already in the committed version (left alone):$'\n'$OLD}"; rm -f "$ADVF"

NOTE="Source files were changed by a shell command, which skips the edit hooks: $(sed "s|^$ROOT/||" <<<"$CHANGED" | tr '\n' ' ')— use Edit/Write for source files so they are checked and formatted as you go."
if [ -n "$ERR" ]; then
  { printf '%s\n%s' "$NOTE" "$ERR"; [ -n "$ADV" ] && printf '%s' "$ADV"; } >&2
  exit 2
fi
wf_context PostToolUse "$NOTE${ADV:+
$ADV}"
exit 0
