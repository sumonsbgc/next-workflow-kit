#!/usr/bin/env bash
# PostToolUse(Edit|Write): enforce the component conventions — a component renders,
# it does not decide. Logic belongs in hooks / services / helpers / schemas.
# See .claude/skills/react-component-conventions/SKILL.md
#   NEXT_WF_COMPONENT_GUARD=warn  -> never block, advise only
#   NEXT_WF_COMPONENT_GUARD=off   -> disable
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
MODE="${NEXT_WF_COMPONENT_GUARD:-enforce}"
[ "$MODE" = off ] && exit 0
grep -qE '"next"[[:space:]]*:' "$ROOT/package.json" 2>/dev/null || exit 0
. "$SELF_DIR/_lib.sh"
# Run standalone (hook JSON on stdin) or from post-edit.sh, which parses once and sets NEXT_WF_FILE.
if [ -n "${NEXT_WF_FILE:-}" ]; then FILE="$NEXT_WF_FILE"; else FILE="$(wf_file_from_input "$(cat)")"; fi
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
case "$FILE" in
  *.tsx|*.jsx) ;;
  *) exit 0 ;;
esac
case "$FILE" in
  *.test.tsx|*.spec.tsx|*.test.jsx|*.spec.jsx|*.stories.tsx) exit 0 ;;
esac

REL="${FILE#$ROOT/}"
BODY="$(cat "$FILE")"
LINES="$(wc -l < "$FILE" | tr -d ' ')"
IS_CLIENT=0; head -n 5 "$FILE" | grep -qE "^[[:space:]]*['\"]use client['\"]" && IS_CLIENT=1
# Unambiguous: importing an ORM client is always a data-layer import.
DATA_RE="from ['\"](@prisma/client|drizzle-orm|drizzle-orm/.*|mongoose|@/lib/prisma.*)['\"]"
# Ambiguous: a path called db/ is often just static content (src/db/locations.ts). Only
# treat it as the data layer when the file also actually queries something.
DATA_PATH_RE="from ['\"](@/lib/db.*|@/server/db.*|@/db.*|@/lib/database.*)['\"]"
QUERY_RE="(\.findMany\(|\.findUnique\(|\.findFirst\(|prisma\.|drizzle|await db\.|db\.select\(|db\.insert\(|\.aggregate\()"

ERRORS=(); WARNS=()
err()  { ERRORS+=("$1"); }
warn() { WARNS+=("$1"); }

# --- logic that must not live in a component ---------------------------------
if grep -qE "$DATA_RE" <<<"$BODY"; then
  if [ "$IS_CLIENT" = 1 ]; then
    err "A Client Component imports the database layer directly. Move the query into lib/services/* (server-side) and pass the result in as a prop."
  else
    warn "$REL imports the DB/ORM directly. Components — even Server Components — should call a service in lib/services/*, which owns the query and the business rules."
  fi
elif grep -qE "$DATA_PATH_RE" <<<"$BODY" && grep -qE "$QUERY_RE" <<<"$BODY"; then
  if [ "$IS_CLIENT" = 1 ]; then
    err "A Client Component imports from a db/ module and runs queries against it. Move the query server-side into a service and pass the result in as a prop."
  else
    warn "$REL queries a db/ module directly. Put the query behind a service so the component only renders."
  fi
fi

# data fetching inside an effect: look at the 12 lines following each useEffect(.
# Only real network calls count — fetch(), axios/ky/got, or an HTTP-verb method called with a
# URL literal. A bare `.get(` is far too broad: searchParams.get, Map.get and FormData.get
# are ordinary reads and must not block an edit.
FETCH_RE='(^|[^A-Za-z0-9_$])(fetch|axios|ky|got|ofetch)[.(]|[.](get|post|put|patch|delete)[(][[:space:]]*[`"'"'"'](/|https?:)'
# ENVIRON, not -v: -v would run the regex through escape processing (and mawk lacks \<).
if RE="$FETCH_RE" awk '/useEffect\(/{n=12} n-- > 0 && $0 ~ ENVIRON["RE"] {found=1} END{exit !found}' <<<"$BODY"; then
  err "Data fetching inside useEffect. Fetch in a Server Component via a service and pass the data down; if it is genuinely user-triggered, use a Server Action, or move the whole effect into a hooks/use-*.ts hook."
fi

if grep -qE "^[[:space:]]*(export )?(async )?function [a-z][A-Za-z]*\(" <<<"$BODY" && grep -qE "(await (db|prisma|sql)\.|\.findMany\(|\.findUnique\(|\.insert\(|\.update\(\{)" <<<"$BODY"; then
  err "Query code lives in this component file. Queries belong in the data-access layer, business rules in lib/services/*."
fi

# --- single responsibility ---------------------------------------------------
COMPONENTS="$(grep -cE "^export (default )?(function|const) [A-Z][a-z]" <<<"$BODY" || true)"
[ "${COMPONENTS:-0}" -gt 1 ] && warn "$REL exports $COMPONENTS components. One exported component per file — keep only file-private subcomponents alongside it."

USESTATE="$(grep -c "useState" <<<"$BODY" || true)"
[ "${USESTATE:-0}" -gt 5 ] && warn "$USESTATE useState calls in $REL. That much state is a state machine — extract it into a hooks/use-*.ts hook that returns { data, actions }."

USEEFFECT="$(grep -c "useEffect(" <<<"$BODY" || true)"
[ "${USEEFFECT:-0}" -gt 2 ] && warn "$USEEFFECT useEffect calls in $REL. Effect choreography belongs in a custom hook, not in the component that renders."

[ "$LINES" -gt 200 ] && warn "$REL is $LINES lines. Past ~150 a component is usually rendering two things — extract the second one."

# --- logic that belongs in helpers/schemas -----------------------------------
grep -qE "(z|yup|v)\.object\(" <<<"$BODY" && warn "A validation schema is defined in $REL. Put it in lib/validation/* so the form, the Server Action and the API all validate against the same shape."
grep -q "new Intl\." <<<"$BODY" && warn "Inline Intl formatting in $REL. Wrap it in a pure helper (lib/utils/format.ts) — components should call formatX(value), not construct formatters."
grep -qE "^[[:space:]]*(} )?catch[[:space:]]*\(" <<<"$BODY" && [ "$IS_CLIENT" = 1 ] && warn "try/catch in $REL — error handling for an operation means the operation is being performed here. Move it to the hook or Server Action and let the component render the resulting state."

# --- report -------------------------------------------------------------------
LEVEL=block; [ "$MODE" = enforce ] || LEVEL=warn
for m in "${ERRORS[@]:-}"; do [ -n "$m" ] && wf_metric guard guard component file "$REL" level "$LEVEL"; done
for m in "${WARNS[@]:-}";  do [ -n "$m" ] && wf_metric guard guard component file "$REL" level warn; done
if [ "${#ERRORS[@]}" -gt 0 ] && [ "$MODE" = enforce ]; then
  { echo "Component conventions blocked $REL (see skills/react-component-conventions):"
    printf '  ✗ %s\n' "${ERRORS[@]}"
    [ "${#WARNS[@]}" -gt 0 ] && printf '  ! %s\n' "${WARNS[@]}"
    echo "A component renders; it does not decide. Move the logic out, then re-apply the edit."; } >&2
  exit 2
fi

MSG=""
for m in "${ERRORS[@]:-}" "${WARNS[@]:-}"; do [ -n "$m" ] && MSG="$MSG  - $m"$'\n'; done
if [ -n "$MSG" ]; then
  TEXT="Component conventions — advisory for $REL:
$MSG"
  if [ "${NEXT_WF_RAW:-0}" = 1 ]; then printf '%s\n' "$TEXT"; else wf_context PostToolUse "$TEXT"; fi
fi
exit 0
