#!/usr/bin/env bash
# Plugin installs only: every hook in hooks/hooks.json runs through here.
#   plugin-dispatch.sh <hook-name>      (stdin: the hook input, passed through untouched)
# If the project also has the kit's own files (install.sh), those already run from settings.json:
# the plugin steps aside, so no guard fires twice. At session start it says so, because the
# commands and agents are then loaded twice as well.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="${1:-}"
[[ "$NAME" =~ ^[a-z-]+$ ]] && [ -f "$SELF_DIR/$NAME.sh" ] || exit 0
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
if [ -f "$ROOT/.claude/hooks/$NAME.sh" ] && [ "$ROOT/.claude/hooks" != "$SELF_DIR" ]; then
  if [ "$NAME" = session-context ]; then
    . "$SELF_DIR/_lib.sh"
    wf_context SessionStart "next-workflow is installed twice in this project: as a plugin and as project files (.claude/hooks, .claude/commands/next, .claude/agents/next-*). The project files are in use. Ask the user to keep one: remove the project files with install.sh --uninstall, or disable the plugin."
  fi
  exit 0
fi
exec bash "$SELF_DIR/$NAME.sh"
