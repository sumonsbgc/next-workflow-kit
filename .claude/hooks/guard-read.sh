#!/usr/bin/env bash
# PreToolUse(Read): keep env files and private keys out of the transcript.
# A project install gets this from the Read deny rules in settings.json. A plugin can't ship
# permission rules (only hooks), so the plugin wires this hook instead. Example/template env files
# (.env.example, .env.sample, .env.template, .env.dist) hold no secrets and stay readable.
set -uo pipefail
[ "${NEXT_WF_SECRETS_GUARD:-on}" = off ] && exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/_lib.sh"
FILE="$(wf_file_from_input "$(cat)")"
[ -n "$FILE" ] || exit 0
B="$(basename "$FILE")"
case "$B" in
  .env.example|.env.sample|.env.template|.env.dist) exit 0 ;;
  .env|.env.*|*.pem|*.key|id_rsa|id_rsa.*|id_ed25519|id_ed25519.*|id_ecdsa|id_ecdsa.*) ;;
  *) case "$FILE" in "$HOME"/.ssh/*|"$HOME"/.aws/*|*/.ssh/*|*/.aws/*) ;; *) exit 0 ;; esac ;;
esac
wf_metric guard guard read level block
echo "Blocked by next-workflow: $B is a secret file (env file or private key), and secrets stay out of the transcript. For variable names, read .env.example. If you need a value, ask the user." >&2
exit 2
