#!/usr/bin/env bash
# Plugin installs only: every hook in hooks/hooks.json runs through here.
#   plugin-dispatch.sh <hook-name>      (stdin: the hook input, passed through untouched)
# Guards always run: a project file can't switch a plugin guard off, and a guard running twice is
# harmless. The other hooks (context, formatting, the Stop check) step aside only when the
# project's own settings really register the same hook, so they don't run twice; at session start
# the plugin says so, because the commands and agents are then loaded twice as well.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="${1:-}"
[[ "$NAME" =~ ^[a-z-]+$ ]] && [ -f "$SELF_DIR/$NAME.sh" ] || exit 0
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
case "$NAME" in
  guard-secrets|guard-owner|guard-read|bash-guard|allow-helpers) exec bash "$SELF_DIR/$NAME.sh" ;;
esac
registered() { # the project's settings run this hook themselves
  local f
  for f in "$ROOT/.claude/settings.json" "$ROOT/.claude/settings.local.json"; do
    [ -f "$f" ] && grep -qF "/.claude/hooks/$NAME.sh" "$f" && return 0
  done
  return 1
}
if [ "$ROOT/.claude/hooks" != "$SELF_DIR" ] && [ -f "$ROOT/.claude/hooks/$NAME.sh" ] && registered; then
  if [ "$NAME" = session-context ]; then
    . "$SELF_DIR/_lib.sh"
    wf_context SessionStart "next-workflow is installed twice in this project: as a plugin and as project files (.claude/hooks, .claude/commands/next, .claude/agents/next-*). The project files are in use. Ask the user to keep one: remove the project files with install.sh --uninstall, or disable the plugin."
  fi
  exit 0
fi
exec bash "$SELF_DIR/$NAME.sh"
