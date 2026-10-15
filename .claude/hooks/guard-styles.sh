#!/usr/bin/env bash
# PostToolUse(Edit|Write): catch Tailwind class mistakes that produce no CSS and no error —
# v3 utilities removed in v4, classes newer than the installed version, and interpolated
# class names the scanner can never see.
# See .claude/skills/nextjs-app-router/references/styling.md
#   NEXT_WF_STYLE_GUARD=off  -> disable
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[ "${NEXT_WF_STYLE_GUARD:-on}" = off ] && exit 0
grep -qE '"next"[[:space:]]*:' "$ROOT/package.json" 2>/dev/null || exit 0   # not a Next.js project
. "$SELF_DIR/_lib.sh"
# Run standalone (hook JSON on stdin) or from post-edit.sh, which parses once and sets NEXT_WF_FILE.
if [ -n "${NEXT_WF_FILE:-}" ]; then FILE="$NEXT_WF_FILE"; else FILE="$(wf_file_from_input "$(cat)")"; fi
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
case "$FILE" in *.tsx|*.jsx|*.css|*.html) ;; *) exit 0 ;; esac

# Installed Tailwind major.minor — from node_modules, not the package.json range.
# Read it from the stack cache (a `cat` on the hot path) rather than starting node per edit.
TW="$(eval "$("$SELF_DIR/stack.sh")"; printf '%s' "${TAILWIND_INSTALLED:-}")"
[ -n "$TW" ] || exit 0                      # Tailwind not installed: nothing to check
MAJOR="${TW%%.*}"; REST="${TW#*.}"; MINOR="${REST%%.*}"
[ "$MAJOR" = 4 ] || exit 0                  # v3 projects: the v4 rules don't apply

REL="${FILE#$ROOT/}"
BODY="$(cat "$FILE")"
WARNS=()
warn() { WARNS+=("$1"); }

# --- v3 utilities that emit nothing in v4 ------------------------------------
hit() { grep -qE "(^|[\"' \`])$1" <<<"$BODY"; }
hit '(bg|text|border|ring|divide|placeholder)-opacity-[0-9]+' && warn "Removed in v4: *-opacity-* utilities emit no CSS. Use the slash modifier — bg-black/50, text-white/70."
hit 'flex-(shrink|grow)(-0)?\b'                               && warn "Removed in v4: flex-shrink-*/flex-grow-* are now shrink-*/grow-*."
hit 'overflow-ellipsis'                                       && warn "Removed in v4: overflow-ellipsis is now text-ellipsis."
hit 'decoration-(slice|clone)'                                && warn "Removed in v4: decoration-slice/clone are now box-decoration-slice/clone."
hit 'outline-none'                                            && warn "In v4 outline-none means outline:none (no focus ring for forced-colors users). If you meant the v3 behaviour, use outline-hidden."
if [ "$MINOR" -ge 3 ] 2>/dev/null; then
  hit '(start|end)-(0|px|auto|[0-9]+|\[)'                      && warn "Deprecated in v4.3: start-*/end-* are now inset-s-*/inset-e-*."
fi

# --- classes newer than the installed version --------------------------------
newer() { # newer <min-minor> <regex> <message>
  [ "$MINOR" -lt "$1" ] 2>/dev/null || return 0
  grep -qE "(^|[\"' \`])$2" <<<"$BODY" && warn "$3 (tailwindcss $TW is installed — this class emits no CSS here)."
}
newer 1 '(text-shadow|mask-[a-z]|wrap-(break-word|anywhere)|items-[a-z-]+-safe|justify-[a-z-]+-safe)' "Utility added in Tailwind v4.1"
newer 3 '(scrollbar-(thin|auto|none|thumb-|track-|gutter-)|zoom-[0-9]|tab-[0-9]|font-features-|(m|p)b(s|e)-[0-9]|inset-(s|e|bs|be)-)' "Utility added in Tailwind v4.3"

# --- pointer cursor on interactive elements (v4 Preflight no longer sets it) ---
# Silent when the project has a base-layer rule, so this only fires where it matters.
BASE_RULE=0
for css in "$ROOT/app/globals.css" "$ROOT/src/app/globals.css" "$ROOT/styles/globals.css" "$ROOT/app/global.css"; do
  [ -f "$css" ] && grep -qE "cursor:[[:space:]]*pointer" "$css" && BASE_RULE=1 && break
done
if [ "$BASE_RULE" = 0 ]; then
  case "$FILE" in
    *.tsx|*.jsx)
      if grep -qE "<(button|a|Link)([[:space:]>]|$)|role=[\"']button[\"']" <<<"$BODY" && ! grep -q "cursor-pointer" <<<"$BODY"; then
        warn "Buttons/links in $REL have no pointer cursor. Tailwind v4 Preflight dropped cursor:pointer on buttons — add cursor-pointer (and disabled:cursor-not-allowed), or better, add one base-layer rule in globals.css so it is never forgotten."
      fi
    ;;
  esac
fi

# --- interpolated class names ------------------------------------------------
grep -qE '(class(Name)?=\{`[^`]*\$\{|(\bcn|clsx|twMerge)\([^)]*`[^`]*\$\{)' <<<"$BODY" &&
  warn "Interpolated class name in $REL. Tailwind scans source text and never sees \`bg-\${color}-500\` — map the value to complete class strings instead."

# --- report -------------------------------------------------------------------
for m in "${WARNS[@]:-}"; do [ -n "$m" ] && wf_metric guard guard styles file "$REL" level warn; done
if [ "${#WARNS[@]}" -gt 0 ]; then
  TEXT="Tailwind $TW — advisory for $REL:
$(printf '  - %s\n' "${WARNS[@]}")"
  if [ "${NEXT_WF_RAW:-0}" = 1 ]; then printf '%s\n' "$TEXT"; else wf_context PostToolUse "$TEXT"; fi
fi
exit 0
