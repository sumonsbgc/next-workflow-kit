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
# The directory the command runs in (hook input `cwd`), for the filesystem check below.
if command -v jq >/dev/null 2>&1; then
  HCWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""')"
else
  HCWD="$(printf '%s' "$INPUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).cwd||"")}catch{}})')"
fi
[ -n "$HCWD" ] && [ -d "$HCWD" ] || HCWD="${CLAUDE_PROJECT_DIR:-$PWD}"

# A draft task written through the helper (`tasks.sh new <id>-<name> <<'TASK'` … `TASK`): the body is
# quoted heredoc text — never expanded, never run — and only tasks.sh reads it, so words like
# ".env" in a task's prose are not file accesses. Only this exact shape: one command line, a quoted
# delimiter, and nothing after the closing delimiter.
TQ="'"; FIRST="${CMD%%$'\n'*}"
if [[ "$FIRST" =~ ^[[:space:]]*bash[[:space:]]+(~/|\./)?\.claude/hooks/tasks\.sh[[:space:]]+new[[:space:]]+[0-9]{3,}-[a-z0-9-]+[[:space:]]+\<\<[[:space:]]*($TQ([A-Za-z_]+)$TQ|\"([A-Za-z_]+)\")[[:space:]]*$ ]]; then
  TAG="${BASH_REMATCH[3]}${BASH_REMATCH[4]}"
  BODY="${CMD#*$'\n'}"; BODY="${BODY%"${BODY##*[![:space:]]}"}"   # drop trailing blank lines
  if [ "$BODY" != "$CMD" ] && [ "${BODY##*$'\n'}" = "$TAG" ] && [ "$(grep -cxF -- "$TAG" <<<"$BODY")" = 1 ]; then exit 0; fi
fi

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
# ANSI-C quoting ($'.e\156v', $'\x2eenv') decodes to a name the text never shows. Decode each
# $'…' segment with bash itself (no expansion happens inside $'…') and check the result too.
# Fail CLOSED: anything this can't decode with certainty is treated as a secret reference.
UNSURE=0; GUARD_N=0; REST="$CMD"
while [[ "$REST" =~ \$\'([^\']*)\' ]]; do
  GUARD_N=$((GUARD_N+1)); [ "$GUARD_N" -gt 32 ] && { UNSURE=1; break; }
  SEG="${BASH_REMATCH[1]}"
  if DEC="$(eval "printf '%s' \$'$SEG'" 2>/dev/null)"; then NORM="$NORM $DEC"; else UNSURE=1; break; fi
  BEFORE="$REST"; REST="${REST/"\$'$SEG'"/ }"
  [ "$REST" = "$BEFORE" ] && { UNSURE=1; break; }   # no progress: never loop, never pass
done
# An unterminated $' is also undecidable.
[ "$UNSURE" = 0 ] && [[ "$REST" == *"\$'"* ]] && UNSURE=1
# Brace expansion (.{e,x}nv → .env): expand words made only of plain characters with bash's own
# brace/tilde expansion, globbing off, so nothing in them can run; anything else with braces is unsure.
set -f
BRACE_WORDS=0
for w in $NORM; do
  # Only real brace lists expand ({a,b} / {1..3}); {x} or code like map({id}) is left alone.
  [[ "$w" =~ \{[^{}]*(,|\.\.)[^{}]*\} ]] || continue
  # Bounded work: a hook that times out does not block, so expansion must never be expensive.
  # Many brace words, or more than 256 combinations (ranges counted by their real size): don't
  # expand — fall back to the letter check below.
  BRACE_WORDS=$((BRACE_WORDS+1)); [ "$BRACE_WORDS" -gt 16 ] && { UNSURE=1; break; }
  COMBOS=1; REM="$w"
  while [[ "$REM" =~ \{([^{}]*)\} ]]; do
    G="${BASH_REMATCH[1]}"
    if [[ "$G" =~ ^(-?[0-9]{1,9})\.\.(-?[0-9]{1,9})(\.\.-?[0-9]{1,9})?$ ]]; then        # {1..10[..2]}
      N=$(( BASH_REMATCH[2] - BASH_REMATCH[1] )); N=$(( (N<0 ? -N : N) + 1 ))
    elif [[ "$G" =~ ^([A-Za-z])\.\.([A-Za-z])(\.\.-?[0-9]{1,9})?$ ]]; then             # {a..z}: at most 58
      N=$(( $(printf '%d' "'${BASH_REMATCH[2]}") - $(printf '%d' "'${BASH_REMATCH[1]}") )); N=$(( (N<0 ? -N : N) + 1 ))
    elif [[ "$G" == *..* && "$G" != *,* ]]; then N=999999; UNSURE=1                       # a range it can't size
    else C="${G//[^,]/}"; N=$(( ${#C} + 1 )); fi
    COMBOS=$(( COMBOS * N ))
    [ "$COMBOS" -gt 256 ] && break
    REM="${REM/"{$G}"/ }"
  done
  # Over the bound only numeric ranges can be that large, and they expand to digits, never to a
  # file name, so the letter check is enough.
  if [ "$COMBOS" -gt 256 ]; then
    L="$(printf '%s' "$w" | tr -d '{},.0-9' | tr 'A-Z' 'a-z')"
    [[ "$L" =~ (env|pem|key|auth|id_) ]] && UNSURE=1
    continue
  fi
  # Expand just the brace-list part and the plain characters touching it: in `$(echo .{e,x}nv)`
  # that is `.{e,x}nv`, whatever punctuation surrounds it.
  [[ "$w" =~ [A-Za-z0-9._~/*?+@%=-]*\{[^{}]*\}[A-Za-z0-9._~/*?+@%=-]* ]] && w="${BASH_REMATCH[0]}"
  if [[ "$w" =~ ^[A-Za-z0-9._~/*?{},+@%=-]+$ ]] && X="$(eval "printf '%s ' $w" 2>/dev/null)"; then
    NORM="$NORM $X"
  else
    # Can't expand it safely: unsure only if its letters could still spell a secret name.
    L="$(printf '%s' "$w" | tr -d '{},.' | tr 'A-Z' 'a-z')"
    [[ "$L" =~ (env|pem|key|auth|id_) ]] && UNSURE=1
  fi
done
set +f
[ "$UNSURE" = 1 ] && NORM="$NORM .env"   # undecidable quoting/expansion: block
HITS=""
# Globs: block any word whose pattern would expand to a secret file name (.en*, .e[n]v, .*,
# ~/.ss?/id_*), judged with bash's own pattern matching rather than a regex.
SHELL_GLOBS=1
[[ "$NORM" =~ (^|[^A-Za-z0-9_])(cd|pushd|popd|shopt|setopt|dotglob|globdots|GLOBIGNORE|find|fd|fdfind|rg|ag|ack|grep|egrep|git|tar|rsync|zip|unzip|du|locate|xargs|awk|perl|python3?|node|php)([^A-Za-z0-9_]|$) ]] && SHELL_GLOBS=0
[[ "$NORM" =~ (^|[[:space:]])(-name|-iname|-path|-ipath|-wholename|-regex|-g|--glob|--include|--exclude)([[:space:]=]|$) ]] && SHELL_GLOBS=0
set -f
for w in $NORM; do
  case "$w" in *'*'*|*'?'*|*'['*) ;; *) continue ;; esac
  b="${w##*/}"
  for cand in .env .env.local .env.production .env.development id_rsa id_ed25519 id_ecdsa server.pem; do
    # The two shortcuts below assume SHELL globbing. Tools with their own matchers (find -name/-path,
    # rg -g, grep --include, git pathspecs, tar/rsync filters) let `*` match dotfiles and any depth,
    # and dotglob/GLOBIGNORE change the shell's rules; after cd/pushd the directory the filesystem
    # check looks in is no longer the one the glob runs in. With any of those, every match blocks.
    if [ "$SHELL_GLOBS" = 1 ]; then
    # Shell globs never match a leading dot unless the pattern starts with one (dotglob is off),
    # so `ls src/*` cannot reach .env; only `.e*`-style patterns can.
    case "$cand" in .*) [[ "$b" == .* ]] || continue ;; esac
    # A bare wildcard (`*`, `*.*`) is just "all files": it reaches a key only if one is really
    # there, so ask the filesystem (globbing the directory part too) instead of blocking `ls *`.
    if [[ "$cand" != .* ]] && [[ "$b" =~ ^[*?.]+$ ]]; then
      d="${w%/*}"; [ "$d" = "$w" ] && d="."; d="${d/#\~/$HOME}"
      case "$d" in /*) ;; *) d="$HCWD/$d" ;; esac
      # shellcheck disable=SC2053
      [[ "$cand" == $b ]] && compgen -G "$d/$cand" >/dev/null 2>&1 && { HITS="$HITS $w"; break; }
      continue
    fi
    fi
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
