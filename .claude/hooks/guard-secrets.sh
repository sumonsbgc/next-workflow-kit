#!/usr/bin/env bash
# PreToolUse(Bash): the Read deny rules in settings.json don't cover `cat .env` and friends.
# Block shell commands that name an env file or a private key. Example/template env files
# (.env.example, .env.sample, .env.template, .env.dist) are allowed — they hold no secrets.
#
# This is a speed bump against accidents, not a security boundary. It normalizes quotes and
# backslashes and expands globs against secret names, but a determined command can still reach
# the file another way (a variable built at runtime, a script, `grep -r` over the project). The real protection is not having production secrets in
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

# Writing an ignore rule names .env without reading it. Matched against the WHOLE command
# with bash's own regex (never line-by-line grep: a second line would ride along), and only
# for plain literal words: no $, backticks, quotes-with-substitution, redirects in, or newlines.
LIT='[A-Za-z0-9._*/!-]+'
PLAIN=1   # 0 if the command has any shell syntax that could hide a second action or expansion
case "$CMD" in *$'\n'*|*'$'*|*'`'*|*'<'*|*';'*|*'&'*|*'|'*|*'('*|*'{'*|*\\*) PLAIN=0 ;; esac
# Quotes change what the shell sees vs what this script checks (".env.local" exists as .env.local,
# not as a file named with quotes), so the cp exemption only applies to quote-free commands.
NOQUOTE=1; case "$CMD" in *\"*|*\'*) NOQUOTE=0 ;; esac
case "$PLAIN" in 0) ;; *)
  if [[ "$CMD" =~ ^[[:space:]]*(echo|printf)([[:space:]]+(\'$LIT(\\n)?\'|\"$LIT(\\n)?\"|$LIT))+[[:space:]]*\>\>?[[:space:]]*(\./)?\.gitignore[[:space:]]*$ ]]; then exit 0; fi ;;
esac
# Seeding a missing env file from the example reads only the example.
if [ "$PLAIN" = 1 ] && [ "$NOQUOTE" = 1 ] && [[ "$CMD" =~ ^[[:space:]]*cp[[:space:]]+(-n[[:space:]]+)?([^[:space:]]*\.env\.(example|sample|template|dist))[[:space:]]+([^[:space:];&|]+)[[:space:]]*$ ]]; then
  DEST="${BASH_REMATCH[4]}"; ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
  case "$DEST" in /*) ;; *) DEST="$ROOT/$DEST" ;; esac
  [ -e "$DEST" ] || exit 0
fi

# Match on a normalized copy: quotes and backslashes removed, so .e""nv, .en\v and '.env' all
# read as .env, the way the shell will see them.
NORM="$(tr -d "\"'\\\\" <<<"$CMD")"
HITS=""
# Globs: block any word whose pattern would expand to a secret file name (.en*, .e[n]v, .*,
# ~/.ss?/id_*), judged with bash's own pattern matching rather than a regex.
set -f
for w in $NORM; do
  case "$w" in *'*'*|*'?'*|*'['*) ;; *) continue ;; esac
  b="${w##*/}"
  for cand in .env .env.local .env.production .env.development id_rsa id_ed25519 id_ecdsa server.pem; do
    # shellcheck disable=SC2053  # $b is meant to be a pattern here
    [[ "$cand" == $b ]] && { HITS="$HITS $w"; break; }
  done
done
set +f
for t in $(grep -oE '(^|[^A-Za-z0-9_])\.env(\.[A-Za-z0-9_-]+)*' <<<"$NORM" | sed -E 's/^[^.]//'); do
  case "$t" in .env.example|.env.sample|.env.template|.env.dist) ;; *) HITS="$HITS $t" ;; esac
done
KEYS="$(grep -oE '[A-Za-z0-9_./-]*(\.pem|id_rsa|id_ed25519|id_ecdsa)([^A-Za-z0-9_]|$)' <<<"$NORM" | tr '\n' ' ' || true)"
[ -n "$KEYS" ] && HITS="$HITS $KEYS"
[ -n "$HITS" ] || exit 0

echo "Blocked by next-workflow: this command touches secret files ($(echo $HITS)). Env files and private keys stay out of the transcript. For variable names, run: cat .env.example (allowed; the Read tool denies every .env.* file). To create a missing .env.local, copy it from .env.example. Anything else: ask the user to run it themselves." >&2
exit 2
