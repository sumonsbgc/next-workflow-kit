#!/usr/bin/env bash
# 003 — behaviour: per-user list, signed-out redirect; structure: authz + zod in the action
H="$(curl -fsS -b 'eval_user=u1' "$BASE_URL/projects")" || { echo "/projects did not render for u1"; exit 1; }
printf '%s' "$H" | grep -q "Website redesign" || { echo "u1 does not see their project"; exit 1; }
printf '%s' "$H" | grep -q "Someone else" && { echo "u1 sees another user's project"; exit 1; }
printf '%s' "$H" | grep -qE "2 projects" || { echo "heading doesn't show '2 projects' (projectCountLabel)"; exit 1; }
read -r CODE URL <<<"$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$BASE_URL/projects")"
case "$CODE" in 301|302|303|307|308) ;; *) echo "signed-out request was not redirected (HTTP $CODE)"; exit 1 ;; esac
[[ "$URL" =~ ^https?://[^/]+/?$ ]] || { echo "signed-out redirect goes to '$URL', not /"; exit 1; }
A="$(grep -rlE "^['\"]use server['\"]" app lib 2>/dev/null | xargs grep -il "archive" 2>/dev/null | head -1)"
[ -n "$A" ] || { echo "no 'use server' module with an archive action"; exit 1; }
grep -rqE "from ['\"]zod['\"]" lib/validation 2>/dev/null || { echo "no zod schema in lib/validation"; exit 1; }
# Authorization, by behaviour: a hidden test calls the action as u1 against u2's project.
mkdir -p .eval-hidden
cp "$EVALS/hidden/vitest.config.mts" "$EVALS/hidden/empty.ts" .eval-hidden/
sed "s|__ACTION__|$PWD/${A%.*}|" "$EVALS/hidden/003.test.ts" > .eval-hidden/__eval_hidden__003.test.ts
OUT="$(npx vitest run --config .eval-hidden/vitest.config.mts .eval-hidden/__eval_hidden__003.test.ts 2>&1)"; RC=$?
rm -rf .eval-hidden
[ "$RC" = 0 ] || { echo "authorization test failed: $(printf '%s' "$OUT" | grep -E '✗|×|FAIL|AssertionError|Error:' | head -3 | tr '\n' ' ')"; exit 1; }
