#!/usr/bin/env bash
# 004 — behaviour: URL-driven, case-insensitive search with an empty state, works without JS
H="$(curl -fsS -b 'eval_user=u1' "$BASE_URL/projects?q=WEB")" || { echo "/projects?q= did not render"; exit 1; }
printf '%s' "$H" | grep -q "Website redesign" || { echo "q=WEB does not match 'Website redesign'"; exit 1; }
printf '%s' "$H" | grep -q "Mobile app" && { echo "q=WEB still shows 'Mobile app'"; exit 1; }
H="$(curl -fsS -b 'eval_user=u1' "$BASE_URL/projects?q=zzz")"
printf '%s' "$H" | grep -q "No projects match" || { echo "no empty-result message"; exit 1; }
FORM="$(printf '%s' "$H" | tr '\n' ' ' | grep -oE '<form[^>]*>')"
[ -n "$FORM" ] || { echo "no search <form> in the HTML"; exit 1; }
printf '%s' "$FORM" | grep -qiE 'method="post"' && { echo "search form posts instead of GET"; exit 1; }
true
