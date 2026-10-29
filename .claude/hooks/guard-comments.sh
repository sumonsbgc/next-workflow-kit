#!/usr/bin/env bash
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/_lib.sh"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
INPUT="$(cat)"
[ "${NEXT_WF_COMMENT_GUARD:-on}" = off ] && exit 0
FILE="$(wf_file_from_input "$INPUT")"
[ -n "$FILE" ] || exit 0

case "$FILE" in
  */.claude/*|.claude/*|*/node_modules/*|node_modules/*|*/.next/*|.next/*|*/dist/*|*/build/*|*/out/*|*/coverage/*|*/next-env.d.ts|next-env.d.ts) exit 0 ;;
esac
case "$FILE" in
  *.blade.php) LANG_KIND=blade ;;
  *.php) LANG_KIND=php ;;
  *.js|*.mjs|*.cjs|*.jsx|*.ts|*.mts|*.cts|*.tsx) LANG_KIND=js ;;
  *.vue|*.svelte) LANG_KIND=vue ;;
  *.css|*.scss|*.sass|*.less) LANG_KIND=css ;;
  *.html|*.htm) LANG_KIND=html ;;
  *.sh|*.bash) LANG_KIND="sh" ;;
  *) exit 0 ;;
esac

COMMENT_LINES_AWK=$(cat <<'AWK'
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }

function is_prose(text,    x) {
  x = text
  sub(/^(\{\/\*+|\/\*+|\/\/+|\*+\/?|#+|\{\{--|<!--)/, "", x)
  sub(/(\*+\/\}?|--\}\}|-->)$/, "", x)
  x = trim(x)
  if (x == "") return 0
  if (x ~ /^(@ts-|eslint-|eslint |prettier-ignore|biome-ignore|stylelint-|@phpstan-|@psalm-|phpcs:|@codeCoverageIgnore|istanbul |c8 |v8 |@vite-ignore|webpack|@jsx|@license|@preserve|SPDX-|shellcheck |@var( |$)|@param |@returns? |@property|@method |@mixin |@template|@extends |@implements |@use |@throws |@see |@noinspection|@deprecated|@internal|@test( |$)|@dataProvider|@covers|@group|wp:|\/wp:|global |exported |@type |@typedef|@satisfies|#?region|#?endregion|@[A-Za-z-]+-ignore)/) return 0
  return 1
}

function slash_lang() { return kind == "php" || kind == "blade" || kind == "js" || kind == "vue" || kind == "css" }
function hash_lang() { return kind == "php" || kind == "sh" }
function markup_lang() { return kind == "blade" || kind == "vue" || kind == "html" }

function opens_block(t) {
  if (slash_lang() && (t ~ /^\/\*/ || t ~ /^\{\/\*/)) { closer = "*/"; return 1 }
  if (kind == "blade" && t ~ /^\{\{--/) { closer = "--}}"; return 1 }
  if (markup_lang() && t ~ /^<!--/) { closer = "-->"; return 1 }
  return 0
}

function report(t) { if (!(t in old) && !(t in seen)) { seen[t] = 1; print t } }

NR == FNR { old[trim($0)] = 1; next }

{
  t = trim($0)
  if (t == "") next
  if (inblock) {
    if (index(t, closer)) inblock = 0
    if (is_prose(t)) report(t)
    next
  }
  if (opens_block(t)) {
    if (!index(substr(t, 3), closer)) inblock = 1
    if (is_prose(t)) report(t)
    next
  }
  if (slash_lang() && kind != "css" && t ~ /^\/\//) { if (is_prose(t)) report(t); next }
  if (hash_lang() && t ~ /^#/ && t !~ /^#\[/ && t !~ /^#!/) { if (is_prose(t)) report(t); next }
  if (slash_lang() && kind != "css" && match(t, /[;{},)][ \t]+\/\/[ \t]/)) {
    if (is_prose(substr(t, RSTART + RLENGTH - 1))) report(t)
    next
  }
  if (kind == "php" && match(t, /;[ \t]+#[ \t]/)) {
    if (is_prose(substr(t, RSTART + RLENGTH - 1))) report(t)
  }
}
AWK
)

tool_texts() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null
  else
    printf '%s' "$INPUT" | node -e '
      let s = "";
      process.stdin.on("data", d => s += d).on("end", () => {
        let t = {};
        try { t = JSON.parse(s).tool_input || {}; } catch {}
        const want = process.argv[1];
        const keys = want === "new" ? ["new_string", "content"] : ["old_string"];
        const out = keys.filter(k => typeof t[k] === "string").map(k => t[k]);
        for (const e of t.edits || []) { const k = want === "new" ? "new_string" : "old_string"; if (typeof e[k] === "string") out.push(e[k]); }
        process.stdout.write(out.join("\n"));
      });' "$2" 2>/dev/null
  fi
}

NEW_TXT="$(mktemp)"; OLD_TXT="$(mktemp)"
trap 'rm -f "$NEW_TXT" "$OLD_TXT"' EXIT
tool_texts '[.tool_input.new_string, .tool_input.content, (.tool_input.edits // [] | .[].new_string)] | map(select(. != null)) | join("\n")' new > "$NEW_TXT"
tool_texts '[.tool_input.old_string, (.tool_input.edits // [] | .[].old_string)] | map(select(. != null)) | join("\n")' old > "$OLD_TXT"
case "$FILE" in /*) ABS="$FILE" ;; *) ABS="$ROOT/$FILE" ;; esac
[ -f "$ABS" ] && cat "$ABS" >> "$OLD_TXT"
[ -s "$NEW_TXT" ] || exit 0

ADDED="$(awk -v kind="$LANG_KIND" "$COMMENT_LINES_AWK" "$OLD_TXT" "$NEW_TXT")"
[ -n "$ADDED" ] || exit 0

wf_metric guard guard comments level block file "${FILE#"$ROOT"/}"
{
  echo "Blocked by next-workflow: this project's code carries no comments — pure code only. Remove these comment lines and say the intent through names, types and small functions instead:"
  printf '%s\n' "$ADDED" | head -n 5 | sed 's/^/  /'
  echo "Comments that were already in the file are fine to keep. Tooling directives are allowed (@ts-expect-error, eslint-disable, prettier-ignore, type-only JSDoc tags such as @type/@param/@returns in .js files); 'use client' and 'use server' are not comments."
} >&2
exit 2
