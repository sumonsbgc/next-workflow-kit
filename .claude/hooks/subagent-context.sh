#!/usr/bin/env bash
# SubagentStart (kit agents only, see the matcher in settings.json): give the subagent the same
# stack report and project memory the main session got, so it doesn't rediscover them. Subagents
# start with a fresh context; without this every delegation re-explores the codebase.
# Documented: SubagentStart additionalContext is injected before the subagent's first prompt and
# leaves its prompt cache intact.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/_lib.sh"
cat >/dev/null   # input carries agent_id/agent_type; the matcher already filtered on agent_type
OUT="$(bash "$SELF_DIR/session-context.sh" </dev/null 2>/dev/null)" || exit 0
[ -n "$OUT" ] || exit 0
if command -v jq >/dev/null 2>&1; then TEXT="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty')"
else TEXT="$(printf '%s' "$OUT" | php -r '$d=json_decode(stream_get_contents(STDIN),true); echo $d["hookSpecificOutput"]["additionalContext"] ?? "";' 2>/dev/null || printf '%s' "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).hookSpecificOutput.additionalContext||"")}catch{}})')"; fi
[ -n "$TEXT" ] || exit 0
wf_context SubagentStart "$TEXT

You are a subagent: the above is everything the main session already knows. Don't re-detect the stack or re-read what project-context.md says. For layout, run \`bash <Kit helpers>/tasks.sh map\` (cached) before any grep; for a task, \`bash <Kit helpers>/tasks.sh context <id>\` gives the task and what its dependencies changed."
