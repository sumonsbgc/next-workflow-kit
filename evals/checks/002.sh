#!/usr/bin/env bash
# 002 — behaviour: a hidden vitest spec (never shown to the agent) must pass against the helper
F="$(grep -rlE "export (function|const) projectCountLabel" lib/utils 2>/dev/null | grep -vE '\.test\.' | head -1)"
[ -n "$F" ] || { echo "no projectCountLabel export in lib/utils"; exit 1; }
grep -qE "from ['\"]react['\"]" "$F" && { echo "helper imports React"; exit 1; }
REL="./$(basename "${F%.*}")"
sed "s|__HELPER__|$REL|" "$EVALS/hidden/002.test.ts" > "$(dirname "$F")/__eval_hidden__.test.ts"
OUT="$(npx vitest run "$(dirname "$F")/__eval_hidden__.test.ts" 2>&1)"; RC=$?
rm -f "$(dirname "$F")/__eval_hidden__.test.ts"
[ "$RC" = 0 ] || { echo "hidden test failed: $(printf '%s' "$OUT" | grep -E 'FAIL|Expected|Received' | head -3 | tr '\n' ' ')"; exit 1; }
