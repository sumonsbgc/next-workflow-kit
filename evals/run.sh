#!/usr/bin/env bash
# End-to-end eval of the workflow: does it turn tasks into working features, and at what cost?
# Each run builds a fresh copy of the fixture app, installs the kit, runs the seeded tasks
# headless (fresh context per task), builds and starts the app, then scores every task with a
# behaviour check: real HTTP requests against the running app, plus a hidden test the agent
# never sees. Results from several runs are aggregated, because one run of a model is noise.
#
#   evals/run.sh                       3 runs on the Next 15 fixture (network + real spend)
#   evals/run.sh --runs 5              more runs: tighter numbers
#   evals/run.sh --next 16             the Next 16.4 + cacheComponents variant
#   evals/run.sh --budget 3            per-task spending cap in USD (default 5)
#   evals/run.sh --keep                keep the work directories for inspection
#   evals/run.sh --dry-run             set everything up, run nothing (checks the harness wiring)
#   evals/run.sh --reference           apply evals/reference/ (a known-good solution) instead of the
#                                      agent, then build, serve and score it: proves every check CAN
#                                      pass. No API spend. Must score 5/5 before trusting real runs.
#
# Compare evals/results/*.json before and after any change to a command, agent or skill.
# A prompt change that lowers the pass rate or raises cost is a regression.
set -uo pipefail
EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(dirname "$EVALS")"
export EVALS
RUNS=3; NEXTV=15; BUDGET=5; KEEP=0; DRY=0; REF=0
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) RUNS="$2"; shift ;;
    --next) NEXTV="$2"; shift ;;
    --budget) BUDGET="$2"; shift ;;
    --keep) KEEP=1 ;;
    --dry-run) DRY=1; RUNS=1 ;;
    --reference) REF=1; RUNS=1 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
  esac
  shift
done
case "$NEXTV" in 15|16) ;; *) echo "--next must be 15 or 16" >&2; exit 1 ;; esac
[ "$REF" = 1 ] && [ "$NEXTV" = 16 ] && { echo "--reference exists for the Next 15 fixture only" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

setup_app() { # setup_app <dir>
  local W="$1"
  cp -R "$EVALS/fixture" "$W"
  if [ "$NEXTV" = 16 ]; then
    # Versions checked on npm 2026-10-15: next 16.4.1 (peer react ^19), react 19.3.1, @types 19.3.0.
    jq '.dependencies.next="16.4.1" | .dependencies.react="19.3.1" | .dependencies["react-dom"]="19.3.1"
        | .devDependencies["@types/react"]="19.3.0" | .devDependencies["@types/react-dom"]="19.3.0"' \
       "$W/package.json" > "$W/package.json.tmp" && mv "$W/package.json.tmp" "$W/package.json"
    printf "import type { NextConfig } from 'next'\n\nconst config: NextConfig = { cacheComponents: true }\n\nexport default config\n" > "$W/next.config.ts"
  fi
  if [ "$DRY" = 0 ]; then
    (cd "$W" && npm install --silent --no-audit --no-fund) || { echo "npm install failed" >&2; return 1; }
  fi
  (cd "$W" && git init -q && git config user.email eval@local && git config user.name eval && git add -A && git commit -qm fixture)
  "$KIT/install.sh" "$W" >/dev/null 2>&1 || { echo "kit install failed" >&2; return 1; }
  mkdir -p "$W/.claude/tasks" && cp "$EVALS"/tasks/*.md "$W/.claude/tasks/"
  (cd "$W" && git add -A && git commit -qm "kit + tasks")
}

serve() { # serve <dir> <port> -> starts `next start` in the background, waits until it answers
  (cd "$1" && npx next start -p "$2" >/dev/null 2>&1 & echo $! > "$1/.eval-server.pid")
  for _ in $(seq 1 60); do curl -s -o /dev/null "http://127.0.0.1:$2/" && return 0; sleep 1; done
  return 1
}

ALL="[]"
for r in $(seq 1 "$RUNS"); do
  W="$(mktemp -d)/app"
  echo "── run $r/$RUNS (Next $NEXTV) — $W"
  setup_app "$W" || exit 1

  RUNNER=(bash "$W/.claude/hooks/run-tasks.sh" --checkpoint --budget "$BUDGET")
  [ "$DRY" = 1 ] && RUNNER+=(--dry-run)
  START=$(date +%s)
  if [ "$REF" = 1 ]; then
    # Stand in for a perfect agent: the reference solution, and the statuses it would leave.
    cp -R "$EVALS/reference/." "$W/"
    for t in "$W"/.claude/tasks/00[1-4]-*.md; do sed -i.bak -E 's/^status:.*/status: done/' "$t" && rm -f "$t.bak"; done
    sed -i.bak -E 's/^status:.*/status: blocked/' "$W"/.claude/tasks/005-*.md && rm -f "$W"/.claude/tasks/005-*.md.bak
  else
    (cd "$W" && CLAUDE_PROJECT_DIR="$W" "${RUNNER[@]}")
  fi
  WALL=$(( $(date +%s) - START ))
  if [ "$DRY" = 1 ]; then echo "dry run: harness OK"; exit 0; fi

  # build + serve, then score every task by behaviour
  BUILD="$(cd "$W" && npx next build >/dev/null 2>&1 && echo pass || echo fail)"
  TYPECHECK="$(cd "$W" && npm run -s typecheck >/dev/null 2>&1 && echo pass || echo fail)"
  PORT=$(( 4300 + r )); SERVED=0
  [ "$BUILD" = pass ] && serve "$W" "$PORT" && SERVED=1
  TASKS="[]"
  for c in "$EVALS"/checks/*.sh; do
    ID="$(basename "$c" .sh)"
    ST="$(sed -n '2,/^---/p' "$W"/.claude/tasks/"$ID"-*.md 2>/dev/null | sed -nE 's/^status:[[:space:]]*([a-z]+).*/\1/p' | head -1)"
    if [ "$SERVED" = 1 ] || [ "$ID" = 005 ] || [ "$ID" = 002 ]; then
      WHY="$(cd "$W" && BASE_URL="http://127.0.0.1:$PORT" STATUS="$ST" bash "$c" 2>&1)"; RC=$?
    else WHY="app did not build or start"; RC=1; fi
    TASKS="$(jq -c --arg id "$ID" --arg st "${ST:-?}" --argjson ok "$([ "$RC" = 0 ] && echo true || echo false)" --arg why "${WHY:-ok}" \
      '. + [{id:$id, status:$st, pass:$ok, detail:$why}]' <<<"$TASKS")"
    printf '   %-4s %-8s %-5s %s\n' "$ID" "${ST:-?}" "$([ "$RC" = 0 ] && echo pass || echo FAIL)" "${WHY:-}"
  done
  [ -f "$W/.eval-server.pid" ] && kill "$(cat "$W/.eval-server.pid")" 2>/dev/null
  M="$W/.claude/.cache/metrics.jsonl"
  COST=0; FP=null   # no metrics file (e.g. a reference run): jq would print a value AND fail
  if [ -s "$M" ]; then
  COST="$(jq -s '[.[] | select(.event=="run") | (.cost_usd|tonumber)] | add // 0' "$M" 2>/dev/null)" || COST=0
  FP="$(jq -s '[.[] | select(.event=="verdict" and (.round|tostring)=="1" and .result!="SKIPPED")] as $v
              | if ($v|length)==0 then null else (([$v[] | select(.result|startswith("PASS"))]|length) / ($v|length)) end' "$M" 2>/dev/null)" || FP=null
  fi
  ALL="$(jq -c --argjson t "$TASKS" --arg b "$BUILD" --arg tc "$TYPECHECK" --argjson cost "${COST:-0}" --argjson s "$WALL" --argjson fp "${FP:-null}" \
    '. + [{tasks:$t, build:$b, typecheck:$tc, cost_usd:$cost, seconds:$s, verifier_first_pass:$fp}]' <<<"$ALL")"
  [ "$KEEP" = 1 ] || rm -rf "${W%/app}"
done

# --- aggregate -----------------------------------------------------------------
SUMMARY="$(jq -c '
  def mean: if length==0 then 0 else add/length end;
  def sd: (mean) as $m | if length<2 then 0 else (map(.-$m|.*.)|add/(length-1)|sqrt) end;
  (map([.tasks[]|select(.pass)]|length) ) as $passed
  | ((.[0].tasks|length)) as $n
  | { runs: length, tasks: $n,
      pass_rate_mean: (($passed|map(./$n))|mean), pass_rate_sd: (($passed|map(./$n))|sd),
      per_task: ([.[].tasks[]] | group_by(.id) | map({id:.[0].id, passed:(map(select(.pass))|length), of:length})),
      build_pass: (map(select(.build=="pass"))|length), cost_mean: (map(.cost_usd)|mean),
      seconds_mean: (map(.seconds)|mean),
      verifier_first_pass_mean: ([.[].verifier_first_pass|select(.!=null)] | if length==0 then null else mean end) }' <<<"$ALL")"
echo
jq -r '"pass rate \((.pass_rate_mean*100|round))% ± \((.pass_rate_sd*100|round))  over \(.runs) runs · builds \(.build_pass)/\(.runs) · $\(.cost_mean*100|round/100)/run · \(.seconds_mean|round)s/run · verifier first-pass \(if .verifier_first_pass_mean == null then "n/a" else "\(.verifier_first_pass_mean*100|round)%" end)",
       (.per_task[] | "  task \(.id): \(.passed)/\(.of)")' <<<"$SUMMARY"
mkdir -p "$EVALS/results"
OUTF="$EVALS/results/$(date +%Y%m%d-%H%M%S)-v$(cat "$KIT/VERSION")-next$NEXTV$([ "$REF" = 1 ] && echo -reference).json"
jq -n --arg v "$(cat "$KIT/VERSION")" --arg next "$NEXTV" --argjson s "$SUMMARY" --argjson runs "$ALL" \
  '{version:$v, next:$next, summary:$s, runs:$runs}' > "$OUTF"
echo "result: $OUTF"
