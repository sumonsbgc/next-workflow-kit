#!/usr/bin/env bash
# 001 — behaviour: every page renders a <footer> containing a link to "/"
HTML="$(curl -fsS "$BASE_URL/")" || { echo "home page did not render"; exit 1; }
FOOT="$(printf '%s' "$HTML" | tr '\n' ' ' | grep -oE '<footer[^>]*>.*</footer>')"
[ -n "$FOOT" ] || { echo "no <footer> on /"; exit 1; }
printf '%s' "$FOOT" | grep -qE 'href="/"' || { echo "footer has no link to /"; exit 1; }
