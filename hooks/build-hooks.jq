# Builds hooks/hooks.json (the plugin's hooks) from .claude/settings.json (the project install's),
# so the two never drift:   jq -f hooks/build-hooks.jq .claude/settings.json > hooks/hooks.json
# Every command goes through plugin-dispatch.sh. The plugin adds two hooks a project install gets
# from permission rules instead: guard-read (Read deny for secrets) and allow-helpers (allow rules).
def dispatch($n): "bash \"${CLAUDE_PLUGIN_ROOT}/.claude/hooks/plugin-dispatch.sh\" \($n)";
{
  description: "next-workflow hooks (plugin install). Generated from .claude/settings.json by hooks/build-hooks.jq; each runs through plugin-dispatch.sh, which steps aside when the project has its own install.",
  hooks: (
    .hooks
    | with_entries(.value |= map(.hooks |= map(
        .command |= (capture("/\\.claude/hooks/(?<n>[a-z-]+)\\.sh$").n as $n | dispatch($n))
      )))
    # Plugin agents are scoped (`next:next-verifier`); a matcher with ( or : is an unanchored regex.
    | .SubagentStart |= map(.matcher = "(^|:)next-")
    | .PreToolUse = (
        [{matcher: "Read", hooks: [{type: "command", command: dispatch("guard-read"), timeout: 10}]}]
        + (.PreToolUse | map(.hooks += [{type: "command", command: dispatch("allow-helpers"), timeout: 10}]))
      )
  )
}
