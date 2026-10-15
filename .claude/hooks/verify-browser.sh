#!/usr/bin/env bash
# Run the verifier's throwaway browser specs for one task, with the kit's Playwright config.
#   bash .claude/hooks/verify-browser.sh <task-id>
# Exists so the permission rule can allow exactly this. A prefix rule on `npx playwright test`
# would also allow `-c <any file>` or `--reporter <any module>`, which runs arbitrary code.
# Takes a task id and nothing else.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[ $# -eq 1 ] && [[ "$1" =~ ^[A-Za-z0-9_-]{1,32}$ ]] || { echo "usage: verify-browser.sh <task-id>" >&2; exit 64; }
[ -n "${NEXT_WF_DEV_URL:-}" ] || { echo "UNVERIFIED: NEXT_WF_DEV_URL is not set (start the dev server and export it)"; exit 3; }
[ -d "$ROOT/node_modules/@playwright/test" ] || { echo "UNVERIFIED: @playwright/test is not installed in this project"; exit 3; }
CONFIG="$SELF_DIR/../verify.playwright.config.mjs"
[ -f "$CONFIG" ] || { echo "kit config missing: $CONFIG" >&2; exit 1; }
ls "$ROOT/.claude/.cache/verify/$1-"*.spec.mjs >/dev/null 2>&1 || { echo "no specs at .claude/.cache/verify/$1-*.spec.mjs" >&2; exit 1; }
cd "$ROOT" && exec npx --no-install playwright test -c "$CONFIG" "$1-"
