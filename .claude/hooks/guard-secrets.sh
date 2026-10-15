#!/usr/bin/env bash
# PreToolUse(Bash): the Read deny rules in settings.json don't cover `cat .env` and friends.
# Block shell commands that name an env file or a private key. Example/template env files
# (.env.example, .env.sample, .env.template, .env.dist) are allowed — they hold no secrets.
#
# This is a speed bump against accidents, not a security boundary: a determined command can
# always spell the name differently. The real protection is not having production secrets in
# the workspace, and running unattended batches in a container.
#
# Allowed on purpose, because they read no secret:
#   echo ".env*" >> .gitignore            (ignoring env files)
#   cp .env.example .env.local           (only when the target doesn't exist yet: never overwrites)
#   NEXT_WF_SECRETS_GUARD=off  -> disable
set -uo pipefail
[ "${NEXT_WF_SECRETS_GUARD:-on}" = off ] && exit 0
INPUT="$(cat)"
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"
else
  CMD="$(printf '%s' "$INPUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).tool_input?.command||"")}catch{}})')"
fi
[ -n "$CMD" ] || exit 0

# Writing an ignore rule names .env without reading it.
if grep -qE '^[[:space:]]*(echo|printf)[^|;&<]*>>?[[:space:]]*[^[:space:];&|]*\.gitignore[[:space:]]*$' <<<"$CMD"; then exit 0; fi
# Seeding a missing env file from the example reads only the example.
if [[ "$CMD" =~ ^[[:space:]]*cp[[:space:]]+(-n[[:space:]]+)?([^[:space:]]*\.env\.(example|sample|template|dist))[[:space:]]+([^[:space:];&|]+)[[:space:]]*$ ]]; then
  DEST="${BASH_REMATCH[4]}"; ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
  case "$DEST" in /*) ;; *) DEST="$ROOT/$DEST" ;; esac
  [ -e "$DEST" ] || exit 0
fi

HITS=""
for t in $(grep -oE '(^|[^A-Za-z0-9_])\.env(\.[A-Za-z0-9_-]+)*' <<<"$CMD" | sed -E 's/^[^.]//'); do
  case "$t" in .env.example|.env.sample|.env.template|.env.dist) ;; *) HITS="$HITS $t" ;; esac
done
KEYS="$(grep -oE '[A-Za-z0-9_./-]*(\.pem|id_rsa|id_ed25519|id_ecdsa)([^A-Za-z0-9_]|$)' <<<"$CMD" | tr '\n' ' ' || true)"
[ -n "$KEYS" ] && HITS="$HITS $KEYS"
[ -n "$HITS" ] || exit 0

echo "Blocked by next-workflow: this command touches secret files ($(echo $HITS)). Env files and private keys stay out of the transcript. For variable names, read .env.example (allowed). To create a missing .env.local, copy it from .env.example. Anything else: ask the user to run it themselves." >&2
exit 2
