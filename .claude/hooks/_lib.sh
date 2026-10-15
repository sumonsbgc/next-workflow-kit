#!/usr/bin/env bash
# Shared helpers for the next-workflow hooks. Sourced, never run.

# wf_str <text> -> the text as a JSON string literal
wf_str() {
  local s="${1//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="$(printf '%s' "$s" | tr -d '\000-\037')"
  printf '"%s"' "$s"
}

# wf_metric <event> [key value]... -> appends one JSON line to .claude/.cache/metrics.jsonl
# Values are written as strings, except ones that are plain integers.
wf_metric() {
  local root="${CLAUDE_PROJECT_DIR:-$PWD}" line k v
  [ "${NEXT_WF_METRICS:-on}" = off ] && return 0
  mkdir -p "$root/.claude/.cache" 2>/dev/null || return 0
  line="{\"ts\":$(date +%s),\"event\":$(wf_str "$1")"
  shift
  while [ $# -ge 2 ]; do
    k="$1"; v="$2"; shift 2
    # integers only without leading zeros: an id like "001" stays a string (001 is invalid JSON)
    if [[ "$v" =~ ^(0|[1-9][0-9]*)$ ]]; then line="$line,$(wf_str "$k"):$v"
    else line="$line,$(wf_str "$k"):$(wf_str "$v")"; fi
  done
  printf '%s}\n' "$line" >> "$root/.claude/.cache/metrics.jsonl" 2>/dev/null || true
}

# wf_file_from_input <json> -> tool_input.file_path (empty if absent)
wf_file_from_input() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null
  else
    printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const t=JSON.parse(s).tool_input||{};process.stdout.write(t.file_path||t.notebook_path||"")}catch{}})'
  fi
}

# wf_context <event> <text> -> hook JSON carrying additionalContext
wf_context() {
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg e "$1" --arg t "$2" '{hookSpecificOutput:{hookEventName:$e,additionalContext:$t}}'
  else
    node -e 'process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:process.argv[1],additionalContext:process.argv[2]}}))' "$1" "$2"
  fi
}
