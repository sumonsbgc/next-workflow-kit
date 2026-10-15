#!/usr/bin/env bash
# PostToolUse(Edit|Write): catch the Next.js App Router mistakes that are cheap to
# detect by reading the file and expensive to detect by running `next build`.
# Definite errors -> exit 2 (Claude is told to fix them). Heuristics -> advisory context.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
grep -qE '"next"[[:space:]]*:' "$ROOT/package.json" 2>/dev/null || exit 0   # not a Next.js project
. "$SELF_DIR/_lib.sh"
# Run standalone (hook JSON on stdin) or from post-edit.sh, which parses once and sets NEXT_WF_FILE.
if [ -n "${NEXT_WF_FILE:-}" ]; then FILE="$NEXT_WF_FILE"; else FILE="$(wf_file_from_input "$(cat)")"; fi
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs) ;;
  *) exit 0 ;;
esac

REL="${FILE#$ROOT/}"
BASE="$(basename "$FILE")"
BODY="$(cat "$FILE")"
HEAD5="$(head -n 5 "$FILE")"

IS_CLIENT=0; printf '%s' "$HEAD5" | grep -qE "^[[:space:]]*['\"]use client['\"]" && IS_CLIENT=1
IS_SERVER_FILE=0; printf '%s' "$HEAD5" | grep -qE "^[[:space:]]*['\"]use server['\"]" && IS_SERVER_FILE=1
IN_APP=0; case "$REL" in app/*|src/app/*) IN_APP=1 ;; esac

ERRORS=(); WARNS=()
err()  { ERRORS+=("$1"); }
warn() { WARNS+=("$1"); }

# --- hard errors -------------------------------------------------------------
if [ "$IS_CLIENT" = 1 ] && grep -qE "^[[:space:]]*export default async function" <<<"$BODY"; then
  err "Client Components cannot be async. Remove 'use client' and keep it a Server Component, or drop async and fetch in an effect / from a parent Server Component."
fi

if [ "$IN_APP" = 1 ] && { [ "$BASE" = "error.tsx" ] || [ "$BASE" = "error.jsx" ] || [ "$BASE" = "global-error.tsx" ]; } && [ "$IS_CLIENT" = 0 ]; then
  err "$BASE must start with the 'use client' directive — Next.js error boundaries are Client Components."
fi

if [ "$IS_CLIENT" = 1 ]; then
  LEAKS="$(grep -oE 'process\.env\.[A-Z0-9_]+' <<<"$BODY" | sort -u | grep -vE 'process\.env\.(NEXT_PUBLIC_[A-Z0-9_]+|NODE_ENV)$' || true)"
  [ -n "$LEAKS" ] && err "Client Component reads server-only env vars: $(tr '\n' ' ' <<<"$LEAKS"). Only NEXT_PUBLIC_* is available in the browser; anything else is a secret leak or is silently undefined. Pass the value down as a prop from a Server Component instead."
  grep -qE "from ['\"]next/headers['\"]" <<<"$BODY" && err "next/headers (cookies/headers/draftMode) is server-only and cannot be imported into a Client Component."
  grep -qE "from ['\"]server-only['\"]" <<<"$BODY" && err "This file imports 'server-only' but is marked 'use client' — one of the two is wrong."
fi

if [ "$IN_APP" = 1 ] && grep -qE "from ['\"]next/router['\"]" <<<"$BODY"; then
  err "next/router does not work in the App Router. Import useRouter/usePathname/useSearchParams from 'next/navigation' instead."
fi

if [ "$IS_CLIENT" = 1 ] && grep -qE "^export (const|async function) (metadata|generateMetadata)\b" <<<"$BODY"; then
  err "metadata/generateMetadata cannot be exported from a 'use client' module — it is server-only. Move it to the server parent (page.tsx/layout.tsx) and keep this file to the interactive part."
fi

if [ "$IS_CLIENT" = 0 ] && { [ -d "$ROOT/app" ] || [ -d "$ROOT/src/app" ]; } && grep -qE "ssr:[[:space:]]*false" <<<"$BODY" && grep -qE "from ['\"]next/dynamic['\"]" <<<"$BODY"; then
  err "next/dynamic with { ssr: false } is not allowed in a Server Component. Move the dynamic import into a Client Component island."
fi

if [ "$IS_SERVER_FILE" = 1 ]; then
  BAD="$(grep -nE "^export (async )?(function|const) " <<<"$BODY" | grep -vE "async (function|\()" | grep -vE "= async" || true)"
  [ -n "$BAD" ] && err "Every export from a 'use server' file must be an async function. Non-async exports found: $(cut -d: -f1 <<<"$BAD" | tr '\n' ' ' | sed 's/ $//') (line numbers)."
fi

# --- advisories --------------------------------------------------------------
if grep -q "useSearchParams(" <<<"$BODY"; then
  warn "useSearchParams() opts the nearest route into client-side rendering and fails \`next build\` unless the component is inside a <Suspense> boundary."
fi
if [ "$IN_APP" = 1 ] && { [ "$BASE" = "page.tsx" ] || [ "$BASE" = "layout.tsx" ]; } && [ "$IS_CLIENT" = 1 ]; then
  warn "$REL is a Client Component, so its whole subtree ships to the browser. Prefer keeping page/layout on the server and pushing 'use client' down to the smallest interactive leaf."
fi
if grep -qE "<img[[:space:]]" <<<"$BODY"; then
  warn "Raw <img> found in $REL — next/image gives you sizing, lazy loading and format negotiation for free."
fi
if grep -q "dangerouslySetInnerHTML" <<<"$BODY"; then
  warn "dangerouslySetInnerHTML in $REL — sanitize the HTML or render it as text."
fi
if [ "$IN_APP" = 1 ] && grep -qE "\b(params|searchParams)\.[a-zA-Z_]" <<<"$BODY" && ! grep -qE "await (params|searchParams|props\.(params|searchParams))" <<<"$BODY"; then
  warn "Since Next.js 15 \`params\` and \`searchParams\` are Promises (on 16, sync access is removed) — await them before reading properties (e.g. \`const { id } = await params\`). Ignore if this project is on Next 14."
fi

# --- Next 16+ (rules verified against nextjs.org docs, see references/next16.md) ----
eval "$(bash "$SELF_DIR/stack.sh")"   # cached: a cat, not a probe
if [ "${NEXT_MAJOR:-0}" -ge 16 ] 2>/dev/null; then
  case "$REL" in middleware.ts|src/middleware.ts|middleware.js|src/middleware.js)
    grep -qE "runtime[[:space:]]*:[[:space:]]*['\"]edge" <<<"$BODY" \
      || warn "Next $NEXT_MAJOR deprecated middleware: use proxy.ts exporting proxy() (Node.js runtime only). Keep middleware.ts only if this must run on the Edge runtime." ;;
  esac
  case "$REL" in proxy.ts|src/proxy.ts|proxy.js|src/proxy.js)
    grep -qE "^export const config[^;]*runtime" <<<"$BODY" && err "proxy.ts cannot set a runtime: Proxy always runs on Node.js, and setting runtime throws. Remove it (use middleware.ts if you truly need Edge)." ;;
  esac
  grep -qE "revalidateTag\([^,()]+\)" <<<"$BODY" && warn "revalidateTag(tag) without a profile is deprecated on Next 16 (a TypeScript error; it behaves like { expire: 0 }). Use revalidateTag(tag, 'max') for stale-while-revalidate, updateTag(tag) in a Server Action for read-your-own-writes, or revalidateTag(tag, { expire: 0 }) in a webhook/Route Handler."
  grep -qE "^export const experimental_ppr" <<<"$BODY" && err "experimental_ppr was removed in Next 16. Delete it; Partial Prerendering is part of cacheComponents."
  grep -qE "from ['\"]next/legacy/image['\"]" <<<"$BODY" && warn "next/legacy/image is deprecated in Next 16 — use next/image."
  if [ -n "$CACHE_COMPONENTS" ]; then
    grep -qE "^export const (revalidate|dynamic|fetchCache)[[:space:]]*=" <<<"$BODY" && err "cacheComponents is on: route segment config dynamic/revalidate/fetchCache errors. force-dynamic or revalidate=0: delete it. revalidate=N: 'use cache' + cacheLife(). force-static/force-cache: 'use cache' around the data (see references/next16.md)."
    grep -qE "^export const dynamicParams" <<<"$BODY" && err "cacheComponents is on: dynamicParams fails the build. Delete it and call notFound() for params that don't resolve."
    grep -qE "^export const runtime[[:space:]]*=[[:space:]]*['\"]edge" <<<"$BODY" && err "cacheComponents requires the Node.js runtime — remove runtime = 'edge'."
  fi
fi

# --- hydration hazards: anything that renders differently on server and client
case "$FILE" in
  *.tsx|*.jsx)
    if grep -qE "\{[^}]*(new Date\(\)|Date\.now\(\)|Math\.random\(\))" <<<"$BODY"; then
      warn "A time or random value is rendered directly in $REL — the server and the browser compute different values, which is a hydration mismatch. Format on the server and pass the string down, or use useId() for ids."
    fi
    if grep -qE "toLocale(Date|Time)?String\(\)" <<<"$BODY"; then
      warn "toLocaleString() with no explicit locale in $REL resolves to the server's locale during SSR and the browser's during hydration. Pass the locale and options explicitly."
    fi
    if grep -qE "typeof window[[:space:]]*[!=]==?[[:space:]]*['\"]undefined['\"]" <<<"$BODY"; then
      warn "A \`typeof window\` branch in $REL guarantees the first client render differs from the server render. Render the same markup on both sides and use CSS, a mounted flag, useSyncExternalStore, or next/dynamic with ssr:false instead."
    fi
    if [ "$IS_CLIENT" = 1 ] && grep -qE "(localStorage|sessionStorage|matchMedia|document\.)" <<<"$BODY" && ! grep -q "useEffect(" <<<"$BODY"; then
      warn "$REL touches a browser API outside an effect. It does not exist during SSR — read it in useEffect after mount, or via useSyncExternalStore with a server snapshot."
    fi
  ;;
esac

# --- zustand in the App Router ------------------------------------------------
# `create()` from 'zustand' builds a React hook bound to a module singleton.
# `createStore()` from 'zustand/vanilla' does not, and legitimately lives in a
# plain (non-'use client') module that the provider imports — don't flag that.
if grep -qE "from ['\"]zustand" <<<"$BODY"; then
  MAKES_HOOK=0
  grep -qE "from ['\"]zustand(/react)?['\"]" <<<"$BODY" && grep -qE "(^|[^A-Za-z])create[<(]" <<<"$BODY" && MAKES_HOOK=1
  if [ "$MAKES_HOOK" = 1 ]; then
    [ "$IS_CLIENT" = 0 ] && err "zustand create() builds a store bound to this module, and this file is not a Client Component — on the server that single object is shared by every request hitting the process, leaking one user's state into another's. Use createStore() from 'zustand/vanilla' in a plain module and instantiate it per mount in a 'use client' provider."
    [ "$IS_CLIENT" = 1 ] && warn "$REL creates a module-singleton zustand store with create(). It works in the browser but is shared across requests wherever this module is evaluated on the server. The per-request pattern (createStore + provider + useRef) is in react-component-conventions/references/state-and-forms.md."
  fi
  grep -q "persist(" <<<"$BODY" && ! grep -q "skipHydration" <<<"$BODY" &&
    warn "zustand persist() in $REL rehydrates from storage after mount, so the first client render differs from the server HTML. Pass skipHydration: true and rehydrate in an effect."
fi

# --- server-first: is this island actually as small as it should be?
if [ "$IS_CLIENT" = 1 ]; then
  CLIENT_LINES="$(wc -l < "$FILE" | tr -d ' ')"
  [ "$CLIENT_LINES" -gt 120 ] && warn "$REL is a $CLIENT_LINES-line Client Component. Everything it imports ships to the browser too — split the interactive part into its own island and keep the rest on the server."
  grep -qE "^import .*from ['\"]@/(lib/services|server)/" <<<"$BODY" && warn "$REL imports a service module. Services are server-side; the data should arrive as a prop from a Server Component, or the call should go through a Server Action."
fi

# --- report ------------------------------------------------------------------
for m in "${ERRORS[@]:-}"; do [ -n "$m" ] && wf_metric guard guard rsc file "$REL" level block; done
for m in "${WARNS[@]:-}";  do [ -n "$m" ] && wf_metric guard guard rsc file "$REL" level warn; done
if [ "${#ERRORS[@]}" -gt 0 ]; then
  { echo "Next.js guard blocked $REL:"; printf '  ✗ %s\n' "${ERRORS[@]}"
    [ "${#WARNS[@]}" -gt 0 ] && printf '  ! %s\n' "${WARNS[@]}"
    echo "Fix these in $REL before continuing."; } >&2
  exit 2
fi

if [ "${#WARNS[@]}" -gt 0 ]; then
  TEXT="Next.js guard — advisory for $REL:
$(printf '  - %s\n' "${WARNS[@]}")"
  if [ "${NEXT_WF_RAW:-0}" = 1 ]; then printf '%s\n' "$TEXT"; else wf_context PostToolUse "$TEXT"; fi
fi
exit 0
