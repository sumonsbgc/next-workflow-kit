#!/usr/bin/env bash
# Self-test for the next-workflow kit. Run after changing any hook, the installer, or a template.
#   ./test.sh            run everything
#   ./test.sh -v         show the output of failing assertions
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE=0; [ "${1:-}" = "-v" ] && VERBOSE=1
PASS=0; FAIL=0
TMP="$(mktemp -d)"
# NEXT_WF_TEST_KEEP=1 leaves the fixture project behind for inspection.
if [ "${NEXT_WF_TEST_KEEP:-0}" = 1 ]; then trap 'printf "\nfixture kept: %s\n" "$TMP"' EXIT
else trap 'rm -rf "$TMP"' EXIT; fi
# The suite stands in for the user's terminal, not a Claude Code session (approve/accept refuse there).
unset CLAUDECODE
# Groups written before the verdict gate close tasks directly; the gate has its own group below.
export NEXT_WF_REQUIRE_VERDICT=off

ok()   { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; [ "$VERBOSE" = 1 ] && [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
group(){ printf '\n\033[1m%s\033[0m\n' "$1"; }

# assert_contains <label> <haystack> <needle>
assert_contains() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "expected to find: $3" ;; esac; }
assert_absent()   { case "$2" in *"$3"*) bad "$1" "should not contain: $3" ;; *) ok "$1" ;; esac; }
assert_eq()       { [ "$2" = "$3" ] && ok "$1" || bad "$1" "got '$2' want '$3'"; }

# hook <script> <project-dir> <file> -> stdout+stderr, sets RC
hook() {
  local out rc
  out="$(printf '{"tool_input":{"file_path":"%s/%s"}}' "$2" "$3" | CLAUDE_PROJECT_DIR="$2" bash "$KIT/.claude/hooks/$1" 2>&1)"; rc=$?
  printf '%s' "$out"
  return $rc          # callers use: O="$(hook ...)"; RC=$?
}

# --- 1. everything parses -----------------------------------------------------
group "syntax"
for f in "$KIT"/*.sh "$KIT"/.claude/hooks/*.sh; do
  if bash -n "$f" 2>/dev/null; then ok "parses: ${f#$KIT/}"; else bad "parses: ${f#$KIT/}" "$(bash -n "$f" 2>&1)"; fi
done
for f in "$KIT"/.claude/agents/*.md "$KIT"/.claude/skills/*/SKILL.md; do
  head -1 "$f" | grep -q '^---$' && grep -q '^name:' "$f" && grep -q '^description:' "$f" \
    && ok "frontmatter: ${f#$KIT/.claude/}" || bad "frontmatter: ${f#$KIT/.claude/}"
done

# --- 2. install ---------------------------------------------------------------
group "install"
P="$TMP/proj"; mkdir -p "$P"
printf '{"dependencies":{"next":"15.1.0","tailwindcss":"^4.3.0"}}' > "$P/package.json"
mkdir -p "$P/node_modules/tailwindcss" "$P/app"
printf '{"name":"tailwindcss","version":"4.3.1"}' > "$P/node_modules/tailwindcss/package.json"
OUT="$("$KIT/install.sh" "$P" 2>&1)"
assert_contains "installer runs" "$OUT" "skills:"
for want in agents/next-ui-builder.md commands/next/task.md skills/code-conventions/SKILL.md \
            skills/react-component-conventions/references/state-and-forms.md \
            skills/nextjs-app-router/references/client-boundary.md \
            hooks/guard-styles.sh hooks/tasks.sh templates/task.md; do
  [ -e "$P/.claude/$want" ] && ok "installed: $want" || bad "installed: $want"
done
if python3 -c "import json,sys;json.load(open('$P/.claude/settings.json'))" 2>/dev/null; then ok "settings.json is valid JSON"; else bad "settings.json is valid JSON"; fi
HOOKS="$(python3 -c "import json;d=json.load(open('$P/.claude/settings.json'));print(' '.join(h['command'].split('/')[-1] for g in d['hooks']['PostToolUse'] for h in g['hooks']))")"
assert_eq "PostToolUse: one dispatcher for edits, one for shell" "$HOOKS" "post-edit.sh bash-guard.sh"
"$KIT/install.sh" "$P" >/dev/null 2>&1
HOOKS2="$(python3 -c "import json;d=json.load(open('$P/.claude/settings.json'));print(' '.join(h['command'].split('/')[-1] for g in d['hooks']['PostToolUse'] for h in g['hooks']))")"
assert_eq "reinstall is idempotent" "$HOOKS2" "$HOOKS"
for gone in route component action; do
  [ -e "$P/.claude/commands/next/$gone.md" ] && bad "not installed: /next:$gone" || ok "not installed: /next:$gone"
done
touch "$P/.claude/commands/next/route.md"; "$KIT/install.sh" "$P" >/dev/null 2>&1
[ -e "$P/.claude/commands/next/route.md" ] && bad "reinstall drops commands removed from the kit" || ok "reinstall drops commands removed from the kit"
[ -e "$P/.claude/commands/next/write-task.md" ] && ok "installed: /next:write-task" || bad "installed: /next:write-task"
HOME="$TMP/home" "$KIT/install.sh" --global >/dev/null 2>&1
assert_contains "global install rewrites hook paths" "$(cat "$TMP/home/.claude/settings.json")" '$HOME/.claude/hooks/post-edit.sh'

# --- 3. guard-rsc -------------------------------------------------------------
group "guard-rsc"
mk() { mkdir -p "$(dirname "$P/$1")"; cat > "$P/$1"; }
mk app/async-client.tsx <<'EOF'
'use client'
export default async function C() { return <div /> }
EOF
hook guard-rsc.sh "$P" app/async-client.tsx >/dev/null; RC=$?; assert_eq "blocks async Client Component" "$RC" "2"
mk app/error.tsx <<'EOF'
export default function Error() { return <div /> }
EOF
hook guard-rsc.sh "$P" app/error.tsx >/dev/null; RC=$?; assert_eq "blocks error.tsx without 'use client'" "$RC" "2"
mk app/leak.tsx <<'EOF'
'use client'
export function L() { return <div>{process.env.DATABASE_URL}</div> }
EOF
hook guard-rsc.sh "$P" app/leak.tsx >/dev/null; RC=$?; assert_eq "blocks server env in client" "$RC" "2"
mk app/meta.tsx <<'EOF'
'use client'
export const metadata = { title: 'x' }
export function M() { return <nav /> }
EOF
hook guard-rsc.sh "$P" app/meta.tsx >/dev/null; RC=$?; assert_eq "blocks metadata from client module" "$RC" "2"
mk app/dyn.tsx <<'EOF'
import dynamic from 'next/dynamic'
const M = dynamic(() => import('./m'), { ssr: false })
export default function P() { return <M /> }
EOF
hook guard-rsc.sh "$P" app/dyn.tsx >/dev/null; RC=$?; assert_eq "blocks ssr:false in Server Component" "$RC" "2"
mk stores/bad.ts <<'EOF'
import { create } from 'zustand'
export const useS = create<{ a: number }>()(() => ({ a: 1 }))
EOF
hook guard-rsc.sh "$P" stores/bad.ts >/dev/null; RC=$?; assert_eq "blocks zustand create() in server module" "$RC" "2"
mk stores/vanilla.ts <<'EOF'
import { createStore } from 'zustand/vanilla'
export const make = () => createStore(() => ({ a: 1 }))
EOF
O="$(hook guard-rsc.sh "$P" stores/vanilla.ts)"; RC=$?; assert_eq "allows zustand/vanilla store module" "$RC$O" "0"
mk app/hydration.tsx <<'EOF'
export function H() { return <div>{new Date().toLocaleTimeString()}</div> }
EOF
O="$(hook guard-rsc.sh "$P" app/hydration.tsx)"
assert_contains "warns on rendered clock" "$O" "hydration mismatch"
mk app/clean.tsx <<'EOF'
import { Btn } from './btn.client'
export default async function P({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  return <section><h1>{id}</h1><Btn id={id} /></section>
}
EOF
O="$(hook guard-rsc.sh "$P" app/clean.tsx)"; RC=$?; assert_eq "silent on idiomatic server page" "$RC$O" "0"

# --- 4. guard-component -------------------------------------------------------
group "guard-component"
mk components/fat.tsx <<'EOF'
'use client'
import { prisma } from '@/lib/prisma'
import { useEffect, useState } from 'react'
export function F() {
  const [d, setD] = useState(null)
  useEffect(() => { fetch('/api/x').then(r => r.json()).then(setD) }, [])
  return <div>{d}</div>
}
EOF
hook guard-component.sh "$P" components/fat.tsx >/dev/null; RC=$?; assert_eq "blocks DB import + effect fetch" "$RC" "2"
O="$(printf '{"tool_input":{"file_path":"%s/components/fat.tsx"}}' "$P" | NEXT_WF_COMPONENT_GUARD=warn CLAUDE_PROJECT_DIR="$P" bash "$KIT/.claude/hooks/guard-component.sh" 2>&1)"
assert_contains "warn mode downgrades to advisory" "$O" "additionalContext"
O="$(printf '{"tool_input":{"file_path":"%s/components/fat.tsx"}}' "$P" | NEXT_WF_COMPONENT_GUARD=off CLAUDE_PROJECT_DIR="$P" bash "$KIT/.claude/hooks/guard-component.sh" 2>&1)"
assert_eq "off mode is silent" "$O" ""
mk components/static-data.tsx <<'EOF'
'use client'
import { locations } from '@/db/locations'
export function Cities() { return <ul>{locations.map(l => <li key={l.id}>{l.name}</li>)}</ul> }
EOF
O="$(hook guard-component.sh "$P" components/static-data.tsx)"; RC=$?
assert_eq "static db/ content module is not a data-layer import" "$RC$O" "0"
mk components/real-query.tsx <<'EOF'
'use client'
import { db } from '@/db/client'
export async function L() { const r = await db.select().from(x); return <div>{r.length}</div> }
EOF
hook guard-component.sh "$P" components/real-query.tsx >/dev/null; RC=$?
assert_eq "querying a db/ module still blocks" "$RC" "2"
mk components/clean.tsx <<'EOF'
export function Card({ name }: { name: string }) { return <article>{name}</article> }
EOF
O="$(hook guard-component.sh "$P" components/clean.tsx)"; RC=$?; assert_eq "silent on a clean component" "$RC$O" "0"

# --- 5. guard-styles ----------------------------------------------------------
group "guard-styles"
mk components/v3.tsx <<'EOF'
export function V() { return <div className="bg-opacity-50 flex-shrink-0 cursor-pointer" /> }
EOF
O="$(hook guard-styles.sh "$P" components/v3.tsx)"
assert_contains "flags removed v4 utilities" "$O" "Removed in v4"
mk components/new.tsx <<'EOF'
export function N() { return <div className="scrollbar-thin cursor-pointer" /> }
EOF
printf '{"name":"tailwindcss","version":"4.1.7"}' > "$P/node_modules/tailwindcss/package.json"
O="$(hook guard-styles.sh "$P" components/new.tsx)"
assert_contains "flags class newer than installed version" "$O" "v4.3"
printf '{"name":"tailwindcss","version":"4.3.1"}' > "$P/node_modules/tailwindcss/package.json"
O="$(hook guard-styles.sh "$P" components/new.tsx)"
assert_absent "same class is fine once installed" "$O" "v4.3"
mk components/btn.tsx <<'EOF'
export function B() { return <button className="px-2">go</button> }
EOF
O="$(hook guard-styles.sh "$P" components/btn.tsx)"
assert_contains "flags missing pointer cursor" "$O" "pointer cursor"
mkdir -p "$P/app"; printf '@layer base { button { cursor: pointer; } }\n' > "$P/app/globals.css"
O="$(hook guard-styles.sh "$P" components/btn.tsx)"
assert_absent "silent once globals.css has the base rule" "$O" "pointer cursor"
rm -f "$P/app/globals.css"
printf '{"name":"tailwindcss","version":"3.4.1"}' > "$P/node_modules/tailwindcss/package.json"
O="$(hook guard-styles.sh "$P" components/v3.tsx)"; assert_eq "silent on Tailwind v3 projects" "$O" ""
printf '{"name":"tailwindcss","version":"4.3.1"}' > "$P/node_modules/tailwindcss/package.json"

# --- 6. verify.sh -------------------------------------------------------------
group "verify"
mkdir -p "$P/.claude/.cache"; touch "$P/.claude/.cache/dirty"
O="$(printf '{"stop_hook_active":true}' | CLAUDE_PROJECT_DIR="$P" bash "$KIT/.claude/hooks/verify.sh" 2>&1)"; RC=$?
assert_eq "honours stop_hook_active (with jq)" "$RC" "0"
NODE_OUT="$(printf '{"stop_hook_active":true}' | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).stop_hook_active===true))}catch{process.stdout.write("false")}})' 2>/dev/null)"
assert_eq "node fallback parses stop_hook_active" "$NODE_OUT" "true"
assert_absent "loop guard is not nested inside the jq branch" \
  "$(awk '/^if command -v jq/,/^fi$/' "$KIT/.claude/hooks/verify.sh")" 'ACTIVE" = true'
touch "$P/.claude/.cache/dirty"
O="$(printf '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$P" bash "$KIT/.claude/hooks/verify.sh" 2>&1)"; RC=$?
assert_eq "runs and clears the dirty marker when not looping" "$RC" "0"
[ -f "$P/.claude/.cache/dirty" ] && bad "dirty marker cleared" || ok "dirty marker cleared"

# --- 7. tasks.sh --------------------------------------------------------------
group "tasks"
T="$KIT/.claude/hooks/tasks.sh"
export CLAUDE_PROJECT_DIR="$P"
bash "$T" init >/dev/null
[ -f "$P/.claude/tasks/TEMPLATE.md" ] && ok "init creates TEMPLATE.md" || bad "init creates TEMPLATE.md"
[ -f "$P/.claude/project-context.md" ] && ok "init creates project-context.md" || bad "init creates project-context.md"
printf -- '---\nid: 001\ntitle: First\nstatus: done\n---\n' > "$P/.claude/tasks/001-a.md"
printf -- '---\nid: 002\ntitle: Second\nstatus: todo\ndepends: 001\n---\n' > "$P/.claude/tasks/002-b.md"
printf -- '---\nid: 003\ntitle: Third\nstatus: todo\ndepends: 002\n---\n' > "$P/.claude/tasks/003-c.md"
printf 'a plain note, not a task\n' > "$P/.claude/tasks/save-for-payment.md"
assert_absent "a note without frontmatter is not a task" "$(bash "$T" list)" "save-for-payment"
assert_contains "next never picks a note" "$(bash "$T" next)" "002-b.md"
rm -f "$P/.claude/tasks/save-for-payment.md"
assert_contains "list shows all tasks" "$(bash "$T" list)" "002    todo    Second"
assert_contains "list marks dependency-blocked tasks" "$(bash "$T" list)" "[blocked by deps]"
assert_contains "next respects dependencies" "$(bash "$T" next)" "002-b.md"
assert_eq "count todo" "$(bash "$T" count todo)" "2"
bash "$T" start 002 >/dev/null
assert_contains "start sets doing" "$(bash "$T" show 002)" "status: doing"
assert_contains "next prefers in-progress task" "$(bash "$T" next)" "002-b.md"
bash "$T" "done" 002 >/dev/null; bash "$T" log 002 "reused ProjectCard" >/dev/null
assert_contains "done sets status" "$(bash "$T" show 002)" "status: done"
assert_contains "log appends under ## Log" "$(bash "$T" show 002)" "- reused ProjectCard"
assert_contains "next advances after completion" "$(bash "$T" next)" "003-c.md"
bash "$T" block 003 "waiting on API access" >/dev/null
assert_contains "block records the reason" "$(bash "$T" show 003)" "blocked: waiting on API access"
assert_eq "nextid follows the highest id" "$(bash "$T" nextid)" "004"
printf -- '---\nid: 004\ntitle: Fourth\nstatus: todo\nsize: large\n---\n' > "$P/.claude/tasks/004-d.md"
assert_contains "list flags large tasks" "$(bash "$T" list)" "Fourth [large]"
bash "$T" close 004 "built the projects page" >/dev/null
assert_contains "close sets done" "$(bash "$T" show 004)" "status: done"
assert_contains "close logs the line" "$(bash "$T" show 004)" "- built the projects page"
rm "$P/.claude/tasks/004-d.md"

# tasks folder location: .claude/tasks by default, legacy ./tasks until migrated
TD="$TMP/tdir"; mkdir -p "$TD"; printf '{"dependencies":{"next":"16.0.0"}}' > "$TD/package.json"
assert_eq "default tasks dir" "$(CLAUDE_PROJECT_DIR="$TD" bash "$T" dir)" ".claude/tasks"
CLAUDE_PROJECT_DIR="$TD" bash "$T" init >/dev/null
[ -f "$TD/.claude/tasks/TEMPLATE.md" ] && ok "init writes .claude/tasks/TEMPLATE.md" || bad "init writes .claude/tasks/TEMPLATE.md"
[ -e "$TD/tasks" ] && bad "init leaves no top-level tasks/" || ok "init leaves no top-level tasks/"
assert_eq "override wins" "$(CLAUDE_PROJECT_DIR="$TD" NEXT_WF_TASKS_DIR=work/plan bash "$T" dir)" "work/plan"
LG="$TMP/legacy"; mkdir -p "$LG/tasks"; printf '{"dependencies":{"next":"16.0.0"}}' > "$LG/package.json"
cp "$KIT/templates/task.md" "$LG/tasks/TEMPLATE.md"; printf '/tasks\n' > "$LG/.gitignore"
printf -- '---\nid: 001\ntitle: Old layout\nstatus: todo\n---\n' > "$LG/tasks/001-old.md"
assert_eq "legacy ./tasks is still used" "$(CLAUDE_PROJECT_DIR="$LG" bash "$T" dir)" "tasks"
assert_contains "legacy tasks still list" "$(CLAUDE_PROJECT_DIR="$LG" bash "$T" list)" "Old layout"
O="$(CLAUDE_PROJECT_DIR="$LG" bash "$T" migrate 2>&1)"
assert_contains "migrate moves the folder" "$O" "moved ./tasks -> .claude/tasks"
assert_contains "migrate warns about the /tasks ignore rule" "$O" "will now show up in git"
[ -f "$LG/.claude/tasks/001-old.md" ] && [ ! -e "$LG/tasks" ] && ok "migrated files are in place" || bad "migrated files are in place"
assert_contains "tasks list after migrate" "$(CLAUDE_PROJECT_DIR="$LG" bash "$T" list)" "Old layout"
CLAUDE_PROJECT_DIR="$LG" bash "$T" migrate >/dev/null 2>&1; assert_eq "migrate twice refuses" "$?" "1"
NT="$TMP/notes"; mkdir -p "$NT/tasks"; printf '{"dependencies":{"next":"16.0.0"}}' > "$NT/package.json"; printf 'my notes\n' > "$NT/tasks/plan.md"
assert_eq "a user's own ./tasks folder is not taken over" "$(CLAUDE_PROJECT_DIR="$NT" bash "$T" dir)" ".claude/tasks"

# tasks.sh new: tasks written by the helper (Claude Code prompts on every Write/Edit under .claude/)
NW="$TMP/newtask"; mkdir -p "$NW"; printf '{"dependencies":{"next":"16.0.0"}}' > "$NW/package.json"; touch "$NW/artisan"
nw() { CLAUDE_PROJECT_DIR="$NW" bash "$T" new "$@" >/dev/null 2>&1; echo $?; }
assert_eq "new writes a todo task" "$(printf -- '---\nid: 001\ntitle: Footer\nstatus: todo\n---\n' | nw 001-add-footer)" "0"
[ -f "$NW/.claude/tasks/001-add-footer.md" ] && ok "new writes into .claude/tasks" || bad "new writes into .claude/tasks"
assert_contains "the new task is runnable" "$(CLAUDE_PROJECT_DIR="$NW" bash "$T" next)" "001-add-footer.md"
assert_eq "new refuses an existing id" "$(printf -- '---\nid: 001\nstatus: todo\n---\n' | nw 001-dup)" "1"
assert_eq "new refuses another status" "$(printf -- '---\nid: 002\nstatus: done\n---\n' | nw 002-x)" "1"
assert_eq "new refuses a mismatched id" "$(printf -- '---\nid: 003\nstatus: todo\n---\n' | nw 002-x)" "1"
assert_eq "new refuses a path in the name" "$(printf -- '---\nid: 002\nstatus: todo\n---\n' | nw '002-../../evil')" "1"
assert_eq "new refuses text without frontmatter" "$(printf 'notes\n' | nw 002-notes)" "1"

# --- 7b. models and command wiring -------------------------------------------
group "commands"
C="$KIT/.claude/commands/next"
assert_contains "write-task plans on opus" "$(sed -n '1,6p' "$C/write-task.md")" "model: opus"
assert_contains "write-task never implements" "$(cat "$C/write-task.md")" "Do not write or edit any source file"
assert_contains "task runs on sonnet" "$(sed -n '1,6p' "$C/task.md")" "model: sonnet"
assert_contains "feature runs on sonnet" "$(sed -n '1,6p' "$C/feature.md")" "model: sonnet"
assert_contains "feature takes task ids" "$(cat "$C/feature.md")" "bash \$T start <id>"
assert_contains "task routes large tasks to the feature phases" "$(cat "$C/task.md")" "size: large"
assert_contains "reviewer stays on opus" "$(sed -n '1,6p' "$KIT/.claude/agents/next-reviewer.md")" "model: opus"
assert_absent "no task.md reference to removed commands" "$(cat "$C"/*.md "$KIT/install.sh")" "next:component"

# --- 8. session-context -------------------------------------------------------
group "session-context"
O="$(CLAUDE_PROJECT_DIR="$P" bash "$KIT/.claude/hooks/session-context.sh")"
assert_contains "emits SessionStart JSON" "$O" "SessionStart"
assert_contains "reports the installed Tailwind version" "$O" "4.3.1 (installed)"
assert_contains "reports blocked tasks" "$O" "1 blocked"
assert_absent "does not inject an unfilled context template" "$O" "Known about this codebase"
printf '\n## Conventions\n- class helper: cn() from @/lib/utils\n' >> "$P/.claude/project-context.md"
O="$(CLAUDE_PROJECT_DIR="$P" bash "$KIT/.claude/hooks/session-context.sh")"
assert_contains "injects a filled context file" "$O" "cn() from @/lib/utils"
assert_absent "strips template comments" "$O" "e.g. components:"

# --- 8b. frontend-design wiring ----------------------------------------------
group "frontend-design"
UI="$(cat "$KIT/.claude/agents/next-ui-builder.md")"
assert_contains "ui-builder loads it for UI work" "$UI" "frontend-design"
assert_contains "ui-builder scopes it out of refactors/fixes" "$UI" "Do **not** load it for a refactor"
assert_contains "ui-builder resolves it against 'match the codebase'" "$UI" "established design system wins"
assert_contains "task table routes it" "$(cat "$KIT/.claude/commands/next/task.md")" "building new UI"
for a in next-data-layer next-route-builder next-test-writer next-reviewer next-perf-auditor next-a11y-auditor; do
  assert_absent "not wired into $a" "$(cat "$KIT/.claude/agents/$a.md")" "frontend-design"
done
SKILLDIR="$TMP/home2/.claude/skills/frontend-design"; mkdir -p "$SKILLDIR"
O="$(HOME="$TMP/home2" CLAUDE_PROJECT_DIR="$P" NEXT_WF_NO_CACHE=1 bash "$KIT/.claude/hooks/session-context.sh")"
assert_contains "announced when the skill exists" "$O" "frontend-design\` skill is available"
O="$(HOME="$TMP/home3" CLAUDE_PROJECT_DIR="$P" NEXT_WF_NO_CACHE=1 bash "$KIT/.claude/hooks/session-context.sh")"
assert_absent "silent when the skill is absent" "$O" "frontend-design"

# --- 9. stack cache -----------------------------------------------------------
group "stack"
A="$(CLAUDE_PROJECT_DIR="$P" bash "$KIT/.claude/hooks/stack.sh")"
B="$(CLAUDE_PROJECT_DIR="$P" bash "$KIT/.claude/hooks/stack.sh")"
assert_eq "cached run matches cold run" "$A" "$B"
[ -f "$P/.claude/.cache/stack.env" ] && ok "writes the cache file" || bad "writes the cache file"
touch "$P/package.json"
C="$(CLAUDE_PROJECT_DIR="$P" bash "$KIT/.claude/hooks/stack.sh")"
assert_eq "cache invalidates when package.json changes" "$C" "$A"
# regression: a detection that finds no Next.js must never be cached, or the whole
# workflow silently switches itself off until package.json next changes.
BROKEN="$TMP/broken"; mkdir -p "$BROKEN/.claude/.cache"
printf '{"dependencies":{}}' > "$BROKEN/package.json"
CLAUDE_PROJECT_DIR="$BROKEN" bash "$KIT/.claude/hooks/stack.sh" >/dev/null
[ -f "$BROKEN/.claude/.cache/stack.env" ] && bad "empty detection is not cached" || ok "empty detection is not cached"

# --- 10. review fixes (v2) ---------------------------------------------------
H="$KIT/.claude/hooks"
newproj() { # newproj <dir> [next-version] -> a minimal Next project
  mkdir -p "$1"; printf '{"dependencies":{"next":"%s"}}' "${2:-15.1.0}" > "$1/package.json"
}

group "security (H1, H2, L4)"
assert_absent "settings grant no /home-wide read" "$(cat "$KIT/.claude/settings.json")" "//home"
INJ="$TMP/inj"; newproj "$INJ"
printf '{"dependencies":{"next":"$(touch %s/pwned)"}}' "$INJ" > "$INJ/package.json"
CLAUDE_PROJECT_DIR="$INJ" NEXT_WF_NO_CACHE=1 bash "$H/session-context.sh" >/dev/null 2>&1
[ -e "$INJ/pwned" ] && bad "package.json values are never executed" || ok "package.json values are never executed"
newproj "$INJ"; mkdir -p "$INJ/.claude/.cache"
printf 'PM="npm"\nNEXT_VERSION="$(touch %s/pwned2)"\n' "$INJ" > "$INJ/.claude/.cache/stack.env"; touch "$INJ/.claude/.cache/stack.env"
O="$(CLAUDE_PROJECT_DIR="$INJ" bash "$H/stack.sh")"
assert_absent "a tampered cache file is ignored" "$O" "pwned2"
sec() { printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | bash "$H/guard-secrets.sh" >/dev/null 2>&1; echo $?; }
assert_eq "blocks cat .env" "$(sec 'cat .env')" "2"
assert_eq "blocks grep in .env.local" "$(sec 'grep KEY .env.local')" "2"
assert_eq "blocks reading a private key" "$(sec 'cat ~/.ssh/id_rsa')" "2"
assert_eq "allows .env.example" "$(sec 'cat .env.example')" "0"
assert_eq "allows process.env in code" "$(sec 'node -e "console.log(process.env.NODE_ENV)"')" "0"
assert_eq "allows ordinary commands" "$(sec 'git status && npm run build')" "0"

NL=$'\n'; GP="$TMP/globs"; mkdir -p "$GP/keys" "$GP/src"; touch "$GP/keys/server.pem"
gsec() { printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | (cd "$GP" && CLAUDE_PROJECT_DIR="$GP" bash "$H/guard-secrets.sh" >/dev/null 2>&1); echo $?; }
assert_eq "ls */node_modules/* is not a secret" "$(gsec 'ls -d */node_modules/*')" "0"
assert_eq "ls src/* is allowed" "$(gsec 'ls src/*')" "0"
assert_eq "dot globs still block (.en*)" "$(gsec 'cat .en*')" "2"
assert_eq "cat .* still blocks" "$(gsec 'cat .*')" "2"
assert_eq "find -name '*' still blocks (find matches dotfiles)" "$(gsec "find . -name '*' -exec cat {} +")" "2"
assert_eq "find -path '*/x/*' still blocks" "$(gsec "find . -path '*/node_modules/*'")" "2"
assert_eq "rg -g '*' still blocks" "$(gsec "rg -uu -g '*' KEY")" "2"
assert_eq "cd into a key folder, then a bare *: still blocks" "$(gsec 'cd keys && cat *')" "2"
assert_eq "the check uses the hook's cwd, not the project root" "$(printf '{"cwd":"%s","tool_input":{"command":"cat *"}}' "$GP/keys" | CLAUDE_PROJECT_DIR="$GP" bash "$H/guard-secrets.sh" >/dev/null 2>&1; echo $?)" "2"
assert_eq "dotglob changes the rules: still blocks" "$(gsec 'shopt -s dotglob; cat *')" "2"
assert_eq "GLOBIGNORE changes the rules: still blocks" "$(gsec 'GLOBIGNORE=x; cat src/*')" "2"
assert_eq "a bare * blocks where a key really is" "$(gsec 'cat keys/*')" "2"
assert_eq "a draft heredoc to tasks.sh new may mention .env" "$(gsec "bash .claude/hooks/tasks.sh new 001-x <<'TASK'${NL}---${NL}never commit .env${NL}TASK")" "0"
assert_eq "a command after the heredoc still blocks" "$(gsec "bash .claude/hooks/tasks.sh new 001-x <<'TASK'${NL}x${NL}TASK${NL}cat .env")" "2"
assert_eq "an unquoted heredoc still blocks" "$(gsec "bash .claude/hooks/tasks.sh new 001-x <<TASK${NL}\$(cat .env)${NL}TASK")" "2"
assert_eq "a heredoc into bash still blocks" "$(gsec "bash <<'TASK'${NL}cat .env${NL}TASK")" "2"

group "guards (M1, M3, L3)"
G="$TMP/g"; newproj "$G"
mkdir -p "$G/components" "$G/app"
cat > "$G/components/tabs.client.tsx" <<'TSX'
'use client'
import { useEffect, useState } from 'react'
export function Tabs({ params }: { params: URLSearchParams }) {
  const [tab, setTab] = useState('a')
  useEffect(() => {
    setTab(params.get('tab') ?? 'a')
  }, [params])
  return <div>{tab}</div>
}
TSX
hook guard-component.sh "$G" components/tabs.client.tsx >/dev/null; RC=$?
assert_eq "searchParams.get in an effect is not blocked" "$RC" "0"
cat > "$G/components/load.client.tsx" <<'TSX'
'use client'
import { useEffect, useState } from 'react'
export function Load() {
  const [d, setD] = useState(null)
  useEffect(() => {
    axios.get('/api/items').then(r => setD(r.data))
  }, [])
  return <div>{String(d)}</div>
}
TSX
hook guard-component.sh "$G" components/load.client.tsx >/dev/null; RC=$?
assert_eq "axios.get('/api') in an effect is blocked" "$RC" "2"
cat > "$G/app/bad.tsx" <<'TSX'
'use client'
export default async function C() { return <div /> }
TSX
O="$(hook post-edit.sh "$G" app/bad.tsx)"; RC=$?
assert_eq "dispatcher blocks what a guard blocks" "$RC" "2"
assert_contains "dispatcher passes the guard's message" "$O" "Client Components cannot be async"
cat > "$G/app/warn.tsx" <<'TSX'
export function W() { return <img src="/a.png" alt="" /> }
TSX
O="$(hook post-edit.sh "$G" app/warn.tsx)"; RC=$?
assert_eq "dispatcher: advisories don't block" "$RC" "0"
assert_contains "dispatcher: one merged advisory" "$O" "next/image"
N16="$TMP/n16"; newproj "$N16" "16.0.1"
printf 'export default { cacheComponents: true }\n' > "$N16/next.config.ts"
O="$(CLAUDE_PROJECT_DIR="$N16" NEXT_WF_NO_CACHE=1 bash "$H/session-context.sh")"
assert_contains "Next 16 sessions are pointed at next16.md" "$O" "references/next16.md"
assert_contains "cacheComponents is reported" "$O" "cacheComponents is ON"
printf 'export function middleware() {}\n' > "$N16/middleware.ts"
O="$(hook guard-rsc.sh "$N16" middleware.ts)"
assert_contains "Next 16: middleware.ts -> proxy.ts advisory" "$O" "proxy.ts"
printf "import { unstable_cache } from 'next/cache'\nexport const f = unstable_cache(async () => 1)\n" > "$N16/cached.ts"
O="$(hook guard-rsc.sh "$N16" cached.ts)"; RC=$?
assert_eq "unstable_cache is still valid on Next 16 (per the docs)" "$RC$O" "0"
mkdir -p "$N16/app/p"; printf "export const revalidate = 60\nexport default function P() { return null }\n" > "$N16/app/p/page.tsx"
hook guard-rsc.sh "$N16" app/p/page.tsx >/dev/null; RC=$?
assert_eq "cacheComponents: segment config revalidate is an error" "$RC" "2"
printf "export const dynamicParams = false\nexport default function P() { return null }\n" > "$N16/app/p/page.tsx"
hook guard-rsc.sh "$N16" app/p/page.tsx >/dev/null; RC=$?
assert_eq "cacheComponents: dynamicParams is an error" "$RC" "2"
printf "export function proxy() {}\nexport const config = { matcher: '/a', runtime: 'edge' }\n" > "$N16/proxy.ts"
hook guard-rsc.sh "$N16" proxy.ts >/dev/null; RC=$?
assert_eq "proxy.ts cannot set a runtime" "$RC" "2"
printf "export function middleware() {}\nexport const config = { runtime: 'edge' }\n" > "$N16/middleware.ts"
O="$(hook guard-rsc.sh "$N16" middleware.ts)"
assert_absent "Edge middleware is not told to become proxy" "$O" "proxy.ts"
printf "import { revalidateTag } from 'next/cache'\nexport async function a() { revalidateTag('posts') }\n" > "$N16/act.ts"
assert_contains "revalidateTag without a profile is flagged" "$(hook guard-rsc.sh "$N16" act.ts)" "'max'"
printf "import { revalidateTag } from 'next/cache'\nexport async function a() { revalidateTag('posts', 'max') }\n" > "$N16/act.ts"
O="$(hook guard-rsc.sh "$N16" act.ts)"; assert_absent "revalidateTag with a profile passes" "$O" "revalidateTag"
mkdir -p "$N16/node_modules/next/dist/docs"
O="$(CLAUDE_PROJECT_DIR="$N16" NEXT_WF_NO_CACHE=1 bash "$H/session-context.sh")"
assert_contains "bundled version-matched docs are pointed to" "$O" "node_modules/next/dist/docs"
N16R="$KIT/.claude/skills/nextjs-app-router/references/next16.md"
assert_contains "next16.md records what it was verified against" "$(cat "$N16R")" "Verified"
assert_contains "next16.md links the official upgrade guide" "$(cat "$N16R")" "nextjs.org/docs/app/guides/upgrading/version-16"
assert_absent "next16.md no longer bans unstable_cache" "$(cat "$N16R")" "**Do not** use"
assert_contains "ship knows Next 16 dropped First Load JS" "$(cat "$KIT/.claude/commands/next/ship.md")" "Next 16 removed"
assert_contains "perf auditor knows Next 16 dropped First Load JS" "$(cat "$KIT/.claude/agents/next-perf-auditor.md")" "Next 16 removed"
O="$(CLAUDE_PROJECT_DIR="$P" NEXT_WF_NO_CACHE=1 bash "$H/session-context.sh")"
assert_absent "Next 15 sessions don't load next16.md" "$O" "references/next16.md"
[ -f "$KIT/.claude/skills/nextjs-app-router/references/next16.md" ] && ok "next16 reference ships" || bad "next16 reference ships"

group "verify baseline (M2)"
V="$TMP/v"; mkdir -p "$V/node_modules" "$V/.claude/.cache"
printf '{"dependencies":{"next":"15.1.0"},"scripts":{"typecheck":"sh errors.sh"}}' > "$V/package.json"
printf 'echo "app/(shop)/page.tsx(3,5): error TS2322: old problem"; exit 1\n' > "$V/errors.sh"
stop() { touch "$V/.claude/.cache/dirty"; printf '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$V" NEXT_WF_NO_CACHE=1 bash "$H/verify.sh" 2>&1; }
O="$(stop)"; RC=$?
assert_eq "no baseline: any error fails" "$RC" "2"
assert_contains "no baseline: tells the user how to record one" "$O" "--baseline"
CLAUDE_PROJECT_DIR="$V" NEXT_WF_NO_CACHE=1 bash "$H/verify.sh" --baseline >/dev/null
O="$(stop)"; RC=$?
assert_eq "baselined errors don't fail the turn" "$RC" "0"
printf 'echo "app/(shop)/page.tsx(9,1): error TS2322: old problem"; exit 1\n' > "$V/errors.sh"
O="$(stop)"; RC=$?
assert_eq "a baselined error that moved lines still passes" "$RC" "0"
printf 'echo "app/(shop)/page.tsx(9,1): error TS2322: old problem"; echo "lib/x.ts(1,1): error TS2304: new problem"; exit 1\n' > "$V/errors.sh"
O="$(stop)"; RC=$?
assert_eq "a new error fails" "$RC" "2"
assert_contains "only the new error is shown" "$O" "new problem"
assert_absent "the baselined error is not shown" "$O" "old problem"
assert_contains "agents may not baseline their own errors" "$(cat "$KIT/.claude/settings.json")" "verify.sh --baseline"

group "tasks: diff, checkpoint, undo, metrics (L6, H4, M7)"
R="$TMP/r"; newproj "$R"
( cd "$R" && git init -q && git config user.email t@t && git config user.name t && printf '.claude/.cache/\n' > .gitignore && git add -A && git commit -qm init )
export CLAUDE_PROJECT_DIR="$R"
bash "$H/tasks.sh" init >/dev/null
printf -- '---\nid: 001\ntitle: Add footer\nstatus: todo\nsize: small\n---\n## Acceptance\n- [ ] [review] x\n' > "$R/.claude/tasks/001-footer.md"
assert_contains "next finds the todo task" "$(bash "$H/tasks.sh" next)" "001-footer.md"
bash "$H/tasks.sh" start 001 >/dev/null
printf 'export const Footer = () => null\n' > "$R/footer.tsx"
assert_contains "diff shows the task's new files" "$(bash "$H/tasks.sh" diff 001)" "footer.tsx"
O="$(NEXT_WF_CHECKPOINT=commit bash "$H/tasks.sh" close 001 "added footer")"
assert_contains "close makes a checkpoint commit" "$O" "checkpoint:"
assert_contains "commit is named after the task" "$(git -C "$R" log -1 --format=%s)" "task 001: Add footer"
bash "$H/tasks.sh" undo 001 >/dev/null
[ -e "$R/footer.tsx" ] && bad "undo reverts the task's changes" || ok "undo reverts the task's changes"
assert_contains "undo sets the task back to todo" "$(bash "$H/tasks.sh" show 001)" "status: todo"
assert_contains "metrics are recorded" "$(cat "$R/.claude/.cache/metrics.jsonl")" '"event":"task_close"'
assert_contains "stats summarises them" "$(bash "$H/tasks.sh" stats)" "tasks closed: 1"

group "shell writes (M5)"
bash "$H/bash-guard.sh" --snapshot
mkdir -p "$R/app"; printf "'use client'\nexport default async function X() { return null }\n" > "$R/app/sneaky.tsx"
rm -f "$R/.claude/.cache/dirty"
O="$(printf '{"tool_input":{"command":"cat > app/sneaky.tsx"}}' | bash "$H/bash-guard.sh" 2>&1)"; RC=$?
assert_eq "a bad file written by shell is blocked" "$RC" "2"
assert_contains "says why" "$O" "changed by a shell command"
[ -f "$R/.claude/.cache/dirty" ] && ok "shell writes still trigger the Stop typecheck" || bad "shell writes still trigger the Stop typecheck"
O="$(printf '{"tool_input":{"command":"ls"}}' | bash "$H/bash-guard.sh" 2>&1)"; RC=$?
assert_eq "silent when the command changed nothing" "$RC$O" "0"

group "headless runner (H3)"
printf -- '---\nid: 002\ntitle: Second\nstatus: todo\n---\n' > "$R/.claude/tasks/002-second.md"
O="$(bash "$H/run-tasks.sh" --dry-run 2>&1)"
assert_contains "runner plans the next task in a fresh session" "$O" '/next:task 001 headless'
O="$(bash "$H/run-tasks.sh" --dry-run 002 2>&1)"
assert_contains "runner runs a freshly planned task" "$O" '/next:task 002 headless'
assert_contains "task.md caps in-session batches" "$(cat "$KIT/.claude/commands/next/task.md")" "at most 3"
assert_contains "task.md has a headless mode" "$(cat "$KIT/.claude/commands/next/task.md")" "headless"
unset CLAUDE_PROJECT_DIR

group "verification and agents (H5, L1, L2)"
VF="$KIT/.claude/agents/next-verifier.md"
[ -f "$VF" ] && ok "next-verifier agent exists" || bad "next-verifier agent exists"
assert_contains "verifier runs on sonnet" "$(sed -n '1,6p' "$VF")" "model: sonnet"
assert_absent "verifier cannot edit" "$(sed -n '1,6p' "$VF")" "Edit"
assert_contains "task runner delegates to the verifier" "$(cat "$KIT/.claude/commands/next/task.md")" "next-verifier"
assert_contains "feature delegates to the verifier" "$(cat "$KIT/.claude/commands/next/feature.md")" "next-verifier"
assert_contains "planner tags acceptance criteria" "$(cat "$KIT/.claude/commands/next/write-task.md")" "[browser]"
assert_contains "planner writes runnable tasks" "$(cat "$KIT/.claude/commands/next/write-task.md")" "status: todo"
assert_absent "planner has no approval step" "$(cat "$KIT/.claude/commands/next/write-task.md")" "tasks.sh approve"
assert_absent "a11y auditor has no shell" "$(sed -n '1,6p' "$KIT/.claude/agents/next-a11y-auditor.md")" "Bash"
assert_absent "ui-builder doesn't re-detect Tailwind" "$(cat "$KIT/.claude/agents/next-ui-builder.md")" "node -p"
assert_absent "setup no longer copies the stack into CLAUDE.md" "$(cat "$KIT/.claude/commands/next/setup.md")" "the stack line ("

group "installer: version, upgrade, uninstall (L5)"
U="$TMP/u"; newproj "$U"; mkdir -p "$U/.claude"
cat > "$U/.claude/settings.json" <<'JSON'
{"hooks":{"PostToolUse":[{"matcher":"Edit|Write|MultiEdit","hooks":[
 {"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/guard-rsc.sh"},
 {"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/format.sh"},
 {"type":"command","command":"$CLAUDE_PROJECT_DIR/my-own-hook.sh"}]}]},
 "permissions":{"allow":["Bash(make:*)","Read(//home/**)","Bash(git diff:*)"],"deny":["Read(./.env.*)","Read(./secrets/**)"]}}
JSON
"$KIT/install.sh" "$U" >/dev/null 2>&1
SU="$(cat "$U/.claude/settings.json")"
assert_absent "upgrade drops the old per-guard hook entries" "$SU" "hooks/guard-rsc.sh"
assert_contains "upgrade keeps the user's own hooks" "$SU" "my-own-hook.sh"
assert_contains "upgrade adds the dispatcher" "$SU" "post-edit.sh"
assert_absent "upgrade removes the retired /home read rule" "$SU" "//home"
assert_absent "upgrade removes the retired git diff rule" "$SU" "git diff:*"
assert_contains "upgrade keeps the user's own permission" "$SU" "Bash(make:*)"
assert_contains "upgrade never removes a deny rule (kit's)" "$SU" '"Read(./.env.*)"'
assert_contains "upgrade never removes a deny rule (user's)" "$SU" "Read(./secrets/**)"
assert_eq "kit version is stamped" "$(cat "$U/.claude/next-workflow.version")" "$(cat "$KIT/VERSION")"
assert_contains "session report shows the version" "$(CLAUDE_PROJECT_DIR="$U" bash "$U/.claude/hooks/session-context.sh")" "next-workflow $(cat "$KIT/VERSION")"
mkdir -p "$U/.claude/tasks"; touch "$U/.claude/tasks/keep.md"
"$KIT/install.sh" "$U" --uninstall >/dev/null 2>&1
[ -e "$U/.claude/commands/next" ] && bad "uninstall removes commands" || ok "uninstall removes commands"
[ -e "$U/.claude/hooks/post-edit.sh" ] && bad "uninstall removes hooks" || ok "uninstall removes hooks"
assert_absent "uninstall removes kit hook entries" "$(cat "$U/.claude/settings.json")" "post-edit.sh"
assert_contains "uninstall keeps the user's hooks" "$(cat "$U/.claude/settings.json")" "my-own-hook.sh"
[ -e "$U/.claude/tasks/keep.md" ] && ok "uninstall keeps .claude/tasks/" || bad "uninstall keeps .claude/tasks/"

group "eval harness (M6)"
O="$(bash "$KIT/evals/run.sh" --dry-run 2>&1)"
assert_contains "harness sets up the fixture and plans every task" "$O" "/next:task 004 headless"
assert_contains "harness dry run completes" "$O" "harness OK"
EW="$(printf '%s' "$O" | sed -n 's/^work dir: //p')"; [ -n "$EW" ] && [ -d "$EW" ] && rm -rf "${EW%/app}"
for c in "$KIT"/evals/tasks/*.md; do id="$(basename "$c" | cut -d- -f1)"; [ -f "$KIT/evals/checks/$id.sh" ] && ok "eval task $id has a check" || bad "eval task $id has a check"; done

# --- 11. v2 review fixes (N1–N15) ---------------------------------------------
gitproj() { # gitproj <dir> -> a committed minimal Next project with .claude/.cache ignored
  newproj "$1"
  ( cd "$1" && git init -q && git config user.email t@t && git config user.name t \
    && printf '.claude/.cache/\n' > .gitignore && git add -A && git commit -qm init )
}

group "checkpoints never commit secrets or others' work (N1)"
C1="$TMP/c1"; gitproj "$C1"
export CLAUDE_PROJECT_DIR="$C1"
bash "$H/tasks.sh" init >/dev/null
printf 'draft notes\n' > "$C1/notes.txt"                                  # dirty before the task
printf -- '---\nid: 001\ntitle: Footer\nstatus: todo\n---\n' > "$C1/.claude/tasks/001-f.md"
bash "$H/tasks.sh" start 001 >/dev/null
printf 'export const F = 1\n' > "$C1/footer.ts"
O="$(NEXT_WF_CHECKPOINT=commit bash "$H/tasks.sh" close 001 "footer")"
SHOWN="$(git -C "$C1" show --stat --format= HEAD)"
assert_contains "checkpoint commits the task's file" "$SHOWN" "footer.ts"
assert_absent "checkpoint leaves out pre-existing edits" "$SHOWN" "notes.txt"
assert_absent "checkpoint never commits the kit cache" "$SHOWN" ".claude/.cache"
printf -- '---\nid: 002\ntitle: Env\nstatus: todo\n---\n' > "$C1/.claude/tasks/002-e.md"
bash "$H/tasks.sh" start 002 >/dev/null
printf 'SECRET=1\n' > "$C1/.env"; printf 'export const G = 1\n' > "$C1/g.ts"
HEADBEFORE="$(git -C "$C1" rev-parse HEAD)"
O="$(NEXT_WF_CHECKPOINT=commit bash "$H/tasks.sh" close 002 "env" 2>&1)"
assert_contains "checkpoint refuses when a secret file changed" "$O" "SKIPPED"
assert_eq "nothing was committed" "$(git -C "$C1" rev-parse HEAD)" "$HEADBEFORE"
assert_absent ".env is not even staged" "$(git -C "$C1" diff --cached --name-only)" ".env"
unset CLAUDE_PROJECT_DIR
assert_contains "runner puts checkpoints on a batch branch" "$(cat "$H/run-tasks.sh")" "nw/batch-"

group "browser verification is runnable (N3)"
assert_contains "kit ships a Playwright config with its own testDir" "$(cat "$KIT/.claude/verify.playwright.config.mjs")" ".claude/.cache/verify"
assert_contains "specs are .mjs (outside the project typecheck)" "$(cat "$KIT/.claude/verify.playwright.config.mjs")" "*.spec.mjs"
[ -f "$U/.claude/verify.playwright.config.mjs" ] && bad "uninstall removes the verify config" || ok "uninstall removes the verify config"
assert_contains "verifier runs specs through the wrapper" "$(cat "$KIT/.claude/agents/next-verifier.md")" "verify-browser.sh <id>"
assert_contains "verifier can write its specs" "$(sed -n '1,6p' "$KIT/.claude/agents/next-verifier.md")" "Write"
assert_contains "only the wrapper is pre-approved" "$(cat "$KIT/.claude/settings.json")" "Bash(bash .claude/hooks/verify-browser.sh:*)"
I2="$TMP/i2"; newproj "$I2"; "$KIT/install.sh" "$I2" >/dev/null 2>&1
[ -f "$I2/.claude/verify.playwright.config.mjs" ] && ok "installer ships the verify config" || bad "installer ships the verify config"

group "shell check judges only new violations (N4)"
B4="$TMP/b4"; gitproj "$B4"; mkdir -p "$B4/app"
printf "'use client'\nexport default async function Old() { return null }\n" > "$B4/app/old.tsx"
( cd "$B4" && git add -A && git commit -qm old )
export CLAUDE_PROJECT_DIR="$B4"
bash "$H/bash-guard.sh" --snapshot; sleep 1
sed -i.bak 's/return null/return  null/' "$B4/app/old.tsx" && rm -f "$B4/app/old.tsx.bak"
O="$(printf '{"tool_input":{"command":"npx prettier --write ."}}' | bash "$H/bash-guard.sh" 2>&1)"; RC=$?
assert_eq "reformatting a file with an old violation is not blocked" "$RC" "0"
assert_contains "the old violation is reported, not hidden" "$O" "pre-existing"
printf "'use client'\nexport default async function New() { return null }\n" > "$B4/app/new.tsx"
O="$(printf '{"tool_input":{"command":"cat > app/new.tsx"}}' | bash "$H/bash-guard.sh" 2>&1)"; RC=$?
assert_eq "a new file with a violation still blocks" "$RC" "2"
printf "import { headers } from 'next/headers'\n'use client'\nexport default async function Old() { return null }\n" > "$B4/app/old.tsx"
sed -i.bak '1d' "$B4/app/old.tsx" && rm -f "$B4/app/old.tsx.bak"
printf "'use client'\nimport { cookies } from 'next/headers'\nexport default async function Old() { return null }\n" > "$B4/app/old.tsx"
O="$(printf '{"tool_input":{"command":"sed -i x app/old.tsx"}}' | bash "$H/bash-guard.sh" 2>&1)"; RC=$?
assert_eq "a NEW violation in an old file still blocks" "$RC" "2"
unset CLAUDE_PROJECT_DIR

group "secrets: precise rules (N5)"
SETT="$(cat "$KIT/.claude/settings.json")"
assert_contains "every .env.* file is denied to the Read tool" "$SETT" '"Read(./.env.*)"'
assert_contains "real secret files are still denied" "$SETT" '"Read(./.env.local)"'
assert_eq "echo '.env' >> .gitignore is allowed" "$(sec 'echo ".env" >> .gitignore')" "0"
SD="$TMP/sd"; mkdir -p "$SD"
assert_eq "seeding a missing .env.local from the example is allowed" "$(cd "$SD" && CLAUDE_PROJECT_DIR="$SD" sec 'cp .env.example .env.local')" "0"
touch "$SD/.env.local"
assert_eq "overwriting an existing .env.local is blocked" "$(cd "$SD" && CLAUDE_PROJECT_DIR="$SD" sec 'cp .env.example .env.local')" "2"
assert_eq "appending to .env is blocked" "$(sec 'echo X=1 >> .env')" "2"
assert_eq "reading after an allowed clause is blocked" "$(sec 'echo ".env" >> .gitignore; cat .env')" "2"
assert_contains "the guard documents that it is a speed bump" "$(cat "$H/guard-secrets.sh")" "not a security boundary"

group "undo respects dependencies (N6)"
D6="$TMP/d6"; gitproj "$D6"
export CLAUDE_PROJECT_DIR="$D6"
bash "$H/tasks.sh" init >/dev/null
printf -- '---\nid: 001\ntitle: Base\nstatus: todo\n---\n' > "$D6/.claude/tasks/001-a.md"
printf -- '---\nid: 002\ntitle: Builds on base\nstatus: todo\ndepends: 001\n---\n' > "$D6/.claude/tasks/002-b.md"
bash "$H/tasks.sh" start 001 >/dev/null; printf 'export const a = 1\n' > "$D6/a.ts"
NEXT_WF_CHECKPOINT=commit bash "$H/tasks.sh" close 001 "a" >/dev/null
bash "$H/tasks.sh" start 002 >/dev/null; printf 'import { a } from "./a"\nexport const b = a\n' > "$D6/b.ts"
NEXT_WF_CHECKPOINT=commit bash "$H/tasks.sh" close 002 "b" >/dev/null
O="$(bash "$H/tasks.sh" undo 001 2>&1)"; RC=$?
assert_eq "undo refuses while a done task depends on it" "$RC" "1"
assert_contains "and names the dependents" "$O" "002"
bash "$H/tasks.sh" undo 001 --cascade >/dev/null 2>&1; RC=$?
assert_eq "undo --cascade succeeds" "$RC" "0"
[ -e "$D6/a.ts" ] || [ -e "$D6/b.ts" ] && bad "cascade reverted both tasks' code" || ok "cascade reverted both tasks' code"
assert_contains "dependent is back to todo" "$(bash "$H/tasks.sh" show 002)" "status: todo"
assert_contains "base is back to todo" "$(bash "$H/tasks.sh" show 001)" "status: todo"

group "verifier measured and skipped by rule (N7, N11)"
printf -- '---\nid: 003\ntitle: Copy tweak\nstatus: todo\n---\n## Acceptance\n- [ ] [review] Heading says Projects\n\n## Notes\n' > "$D6/.claude/tasks/003-c.md"
printf -- '---\nid: 004\ntitle: Has a test\nstatus: todo\n---\n## Acceptance\n- [ ] [test] Validates input\n' > "$D6/.claude/tasks/004-d.md"
bash "$H/tasks.sh" start 003 >/dev/null; printf 'export const h = "Projects"\n' > "$D6/h.ts"
assert_contains "a tiny all-[review] task may skip the verifier" "$(bash "$H/tasks.sh" can-skip-verify 003)" "yes"
bash "$H/tasks.sh" start 004 >/dev/null
bash "$H/tasks.sh" can-skip-verify 004 >/dev/null 2>&1; RC=$?
assert_eq "a [test] task may not skip the verifier" "$RC" "1"
seq 1 40 | sed 's/^/export const x/; s/$/ = 1/' > "$D6/big.ts"
bash "$H/tasks.sh" can-skip-verify 003 >/dev/null 2>&1; RC=$?
assert_eq "a large diff may not skip the verifier" "$RC" "1"
bash "$H/tasks.sh" verdict 004 FAIL 1 >/dev/null; bash "$H/tasks.sh" verdict 004 PASS 2 >/dev/null
bash "$H/tasks.sh" verdict 003 PASS 1 >/dev/null
assert_contains "stats reports the verifier first-pass rate" "$(bash "$H/tasks.sh" stats)" "first-pass 50%"
bash "$H/tasks.sh" verdict 004 MAYBE >/dev/null 2>&1; RC=$?
assert_eq "verdict rejects unknown results" "$RC" "1"
assert_contains "task runner uses the mechanical skip rule" "$(cat "$KIT/.claude/commands/next/task.md")" "can-skip-verify"
assert_contains "task runner records every verifier round" "$(cat "$KIT/.claude/commands/next/task.md")" 'bash $T verdict <id>' 

group "in-session batches are measured (N15)"
assert_contains "task starts record where they came from" "$(cat "$D6/.claude/.cache/metrics.jsonl")" '"via":"session"'
O="$(NEXT_WF_RUNNER=1 bash "$H/tasks.sh" start 003 2>&1)"
assert_contains "runner starts are tagged" "$(tail -1 "$D6/.claude/.cache/metrics.jsonl")" '"via":"runner"'
printf -- '---\nid: 005\ntitle: Five\nstatus: todo\n---\n' > "$D6/.claude/tasks/005-e.md"
bash "$H/tasks.sh" start 001 >/dev/null 2>&1; bash "$H/tasks.sh" start 002 >/dev/null 2>&1
O="$(bash "$H/tasks.sh" start 005 2>&1)"
assert_contains "the 4th+ in-session start within 3h gets a nudge" "$O" "run-tasks.sh"
unset CLAUDE_PROJECT_DIR

group "context truncation, latency, global helpers (N12, N13, N14)"
L="$TMP/l"; newproj "$L"; mkdir -p "$L/.claude"
{ printf '## Layout\n'; for i in $(seq 1 120); do printf -- '- fact %03d: components live in src/components/feature-%03d with tests beside them\n' "$i" "$i"; done; } > "$L/.claude/project-context.md"
O="$(CLAUDE_PROJECT_DIR="$L" NEXT_WF_NO_CACHE=1 bash "$H/session-context.sh")"
assert_contains "an oversized context file is flagged, not silently cut" "$O" "only the first 4000 were loaded"
assert_contains "session report names the helper path" "$O" "Kit helpers"
LP="$TMP/lp"; newproj "$LP"; mkdir -p "$LP/app"; printf 'export function A() { return <div /> }\n' > "$LP/app/a.tsx"
printf '{"tool_input":{"file_path":"%s/app/a.tsx"}}' "$LP" | CLAUDE_PROJECT_DIR="$LP" bash "$H/post-edit.sh" >/dev/null 2>&1
if [ -n "${EPOCHREALTIME:-}" ]; then
  assert_contains "per-edit hook latency is recorded" "$(cat "$LP/.claude/.cache/metrics.jsonl" 2>/dev/null)" '"event":"edit_hook"'
else ok "per-edit hook latency is recorded (skipped: bash < 5)"; fi
GH="$TMP/gh"; HOME="$GH" "$KIT/install.sh" --global >/dev/null 2>&1
GS="$(cat "$GH/.claude/settings.json")"
assert_contains "global install pre-approves ~/.claude helper calls" "$GS" "Bash(bash ~/.claude/hooks/tasks.sh:*)"
assert_absent "global install doesn't point at project-local helpers" "$GS" "Bash(bash .claude/hooks/tasks.sh"
GP="$TMP/gp"; gitproj "$GP"
export CLAUDE_PROJECT_DIR="$GP"
bash "$GH/.claude/hooks/tasks.sh" init >/dev/null 2>&1
[ -f "$GP/.claude/tasks/TEMPLATE.md" ] && ok "global helpers scaffold a project" || bad "global helpers scaffold a project"
printf -- '---\nid: 001\ntitle: G\nstatus: todo\n---\n' > "$GP/.claude/tasks/001-g.md"
bash "$GH/.claude/hooks/tasks.sh" start 001 >/dev/null; printf 'export const g = 1\n' > "$GP/g.ts"
O="$(NEXT_WF_CHECKPOINT=commit bash "$GH/.claude/hooks/tasks.sh" close 001 g)"
assert_contains "a full task cycle works from a global install" "$O" "checkpoint:"
O="$(HOME="$GH" bash "$GH/.claude/hooks/session-context.sh")"
# shellcheck disable=SC2088
assert_contains "global session report points at ~/.claude/hooks" "$O" "~/.claude/hooks"
unset CLAUDE_PROJECT_DIR

group "eval harness quality (N10)"
EV="$KIT/evals"
for id in 001 002 003 004 005; do [ -f "$EV/checks/$id.sh" ] && ok "check for task $id" || bad "check for task $id"; done
assert_contains "checks hit the running app" "$(cat "$EV/checks/004.sh")" 'curl'
assert_contains "authorization is tested by behaviour" "$(cat "$EV/checks/003.sh")" "hidden"
assert_contains "an ambiguous task must be blocked" "$(cat "$EV/checks/005.sh")" "blocked"
assert_contains "harness aggregates multiple runs" "$(cat "$EV/run.sh")" "pass_rate_sd"
assert_contains "harness has a Next 16 + cacheComponents variant" "$(cat "$EV/run.sh")" "cacheComponents: true"
assert_contains "harness can prove its checks against a reference" "$(cat "$EV/run.sh")" "--reference"
ls "$EV"/results/*-reference.json >/dev/null 2>&1 && ok "a reference run is on record" || bad "a reference run is on record"

group "security review fixes (allowlist + guard parsing)"
SETT="$(cat "$KIT/.claude/settings.json")"
assert_absent "no prefix rule for git diff (--no-index/--output escape the deny rules)" "$SETT" '"Bash(git diff:*)"'
assert_absent "no prefix rule for git log (--output writes files)" "$SETT" '"Bash(git log:*)"'
assert_absent "no prefix rule for playwright (-c/--reporter run any file)" "$SETT" '"Bash(npx playwright test'
assert_eq "a second line can't ride on the .gitignore exemption" "$(sec $'echo x >> .gitignore\ncat .env')" "2"
assert_eq "command substitution can't ride on it" "$(sec 'echo "$(cat .env)" >> .gitignore')" "2"
assert_eq "backticks can't ride on it" "$(sec 'echo `cat .env.local` >> .gitignore')" "2"
assert_eq "plain ignore lines still pass" "$(sec 'echo .env.local >> .gitignore')" "0"
VB="$TMP/vb"; newproj "$VB"
O="$(CLAUDE_PROJECT_DIR="$VB" bash "$H/verify-browser.sh" '003 --reporter=/tmp/x.mjs' 2>&1)"; RC=$?
assert_eq "verify-browser rejects anything but a task id" "$RC" "64"
O="$(CLAUDE_PROJECT_DIR="$VB" bash "$H/verify-browser.sh" 003 2>&1)"; RC=$?
assert_contains "verify-browser explains a missing dev URL" "$O" "UNVERIFIED: NEXT_WF_DEV_URL"

group "secrets guard: obfuscation (second security pass)"
SG="$TMP/sg"; mkdir -p "$SG"
sg() { (cd "$SG" && CLAUDE_PROJECT_DIR="$SG" sec "$1"); }
assert_eq "blocks \$(…) hidden in the cp exemption" "$(sg 'cp $(<.env).env.example out')" "2"
assert_eq "blocks glob .en*" "$(sg 'cat .en*')" "2"
assert_eq "blocks glob .e[n]v" "$(sg 'cat .e[n]v')" "2"
assert_eq "blocks quote-split .en''v" "$(sg "cat .en''v")" "2"
assert_eq "blocks backslash-split .en\\v" "$(sg 'cat .en\v')" "2"
assert_eq "blocks key globs ~/.ss?/id_*" "$(sg 'cat ~/.ss?/id_*')" "2"
assert_eq "blocks .* (it expands to .env)" "$(sg 'cat .*')" "2"
assert_eq "ordinary globs still pass" "$(sg 'ls src/*.ts')" "0"
assert_eq "test globs still pass" "$(sg 'npx vitest run lib/**/*.test.ts')" "0"
assert_eq "seeding from the example still passes" "$(sg 'cp .env.example .env.local')" "0"

group "hook messages never execute text"
CS="$TMP/cs"; mkdir -p "$CS"; printf 'MARKER_FROM_ENV_EXAMPLE=1\n' > "$CS/.env.example"
O="$(cd "$CS" && printf '{"tool_input":{"command":"cat .env"}}' | CLAUDE_PROJECT_DIR="$CS" bash "$H/guard-secrets.sh" 2>&1)"
assert_absent "guard-secrets message runs no command substitution" "$O" "MARKER_FROM_ENV_EXAMPLE"

group "security review: cached commands and task diffs"
CI="$TMP/ci"; newproj "$CI"; mkdir -p "$CI/.claude/.cache" "$CI/node_modules"
printf 'NEXT_VERSION="15.1.0"\nCMD_TYPECHECK="true > %s/pwned"\n' "$CI" > "$CI/.claude/.cache/stack.env"; touch "$CI/.claude/.cache/stack.env" "$CI/.claude/.cache/dirty"
printf '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$CI" bash "$H/verify.sh" >/dev/null 2>&1
[ -e "$CI/pwned" ] && bad "a tampered cached command is never executed" || ok "a tampered cached command is never executed"
assert_absent "commands are written in the strict charset" "$(CLAUDE_PROJECT_DIR="$P" NEXT_WF_NO_CACHE=1 bash "$H/stack.sh" | grep '^CMD_')" "|"
SD2="$TMP/sd2"; mkdir -p "$SD2/.claude/tasks"; ( cd "$SD2" && git init -q && git config user.email t@t && git config user.name t && echo "SECRET=old" > .env && printf -- '---\nid: 001\ntitle: x\nstatus: todo\n---\n' > .claude/tasks/001-x.md && git add -A && git commit -qm i )
CLAUDE_PROJECT_DIR="$SD2" bash "$H/tasks.sh" start 001 >/dev/null; echo "SECRET=new-value" > "$SD2/.env"
O="$(CLAUDE_PROJECT_DIR="$SD2" bash "$H/tasks.sh" diff 001)"
assert_absent "task diff never prints a secret file's content" "$O" "new-value"
assert_contains "task diff names the changed secret file" "$O" "secret files changed"

group "security review: cache keys and quoted cp"
KEYS_RE="$(sed -n "s/^CACHE_KEYS='\(.*\)'$/\1/p" "$H/stack.sh")"
MISSING="$(CLAUDE_PROJECT_DIR="$P" NEXT_WF_NO_CACHE=1 bash "$H/stack.sh" | sed -n 's/^\([A-Z0-9_]*\)=.*/\1/p' | grep -v '^DESIGN_SKILL$' | grep -vxE "$KEYS_RE" || true)"
assert_eq "every key stack.sh writes is in the cache allow-list" "$MISSING" ""
CK="$TMP/ck"; newproj "$CK"; mkdir -p "$CK/.claude/.cache"
printf 'NEXT_VERSION="15.1.0"\nPATH="/nonexistent"\n' > "$CK/.claude/.cache/stack.env"; touch "$CK/.claude/.cache/stack.env"
assert_absent "a cache that sets PATH is rejected" "$(CLAUDE_PROJECT_DIR="$CK" bash "$H/stack.sh")" "/nonexistent"
QC="$TMP/qc"; mkdir -p "$QC"; echo SECRET > "$QC/.env.local"
assert_eq "quoted cp onto an existing .env.local is blocked" "$(cd "$QC" && CLAUDE_PROJECT_DIR="$QC" sec 'cp .env.example ".env.local"')" "2"

group "secrets guard: brace expansion and ANSI-C quoting"
assert_eq "blocks brace expansion .{e,x}nv" "$(sec 'cat .{e,x}nv')" "2"
assert_eq "blocks ANSI-C octal \$'.e\\156v'" "$(sec "cat \$'.e\\156v'")" "2"
assert_eq "blocks ANSI-C hex \$'\\x2eenv'" "$(sec "cat \$'\\x2eenv'")" "2"
assert_eq "ordinary brace lists still pass" "$(sec 'ls src/{a,b}.ts')" "0"
O="$(timeout 5 bash -c "printf '{\"tool_input\":{\"command\":%s}}' \"\$(printf '%s' \"cat \$'a\\\\' \$'b'\" | jq -Rs .)\" | bash '$H/guard-secrets.sh'" >/dev/null 2>&1; echo $?)"
[ "$O" != 124 ] && ok "odd ANSI-C input can't hang the guard" || bad "odd ANSI-C input can't hang the guard"

group "secrets guard: fails closed, without over-blocking"
PAD="$(printf "\$'a' %.0s" $(seq 1 40))"
assert_eq "40 decoy \$'…' segments can't push a secret past the cap" "$(sec "echo $PAD; cat \$'.e\\156v'")" "2"
assert_eq "an unterminated \$' is blocked" "$(sec "cat \$'abc\\")" "2"
assert_eq "brace list inside a subshell is expanded" "$(sec 'cat $(echo .{e,x}nv)')" "2"
assert_eq "jq object braces pass" "$(sec "jq 'map({id})' f.json")" "0"
assert_eq "node -e code with braces passes" "$(sec 'node -e "if(x){y}"')" "0"
assert_eq "awk program passes" "$(sec "awk '{print \$1}' f")" "0"

group "secrets guard: bounded work (a timed-out hook doesn't block)"
S0=$(date +%s); R="$(sec 'cat .env {1..99999999}')"; S1=$(date +%s)
assert_eq "a huge brace range can't time the guard out (and .env is still caught)" "$R" "2"
[ $((S1-S0)) -lt 5 ] && ok "guard stays fast on a huge range" || bad "guard stays fast on a huge range"
S0=$(date +%s); sec 'cat {a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b} f' >/dev/null; S1=$(date +%s)
[ $((S1-S0)) -lt 5 ] && ok "guard stays fast on stacked brace lists" || bad "guard stays fast on stacked brace lists"

group "secrets guard: brace ranges are sized, not skipped"
assert_eq "letter range .e{n..n}v is expanded and caught" "$(sec 'cat .e{n..n}v')" "2"
assert_eq "letter range .{d..f}nv is expanded and caught" "$(sec 'cat .{d..f}nv')" "2"
assert_eq "small numeric ranges still pass" "$(sec 'ls x{1..5}.log')" "0"

group "context memory: repo map, task handoff, subagents, compaction"
MP="$TMP/mp"; newproj "$MP"; mkdir -p "$MP/app/projects/[id]" "$MP/app/api/items" "$MP/components" "$MP/lib"
printf 'export default function P() { return null }\n' > "$MP/app/page.tsx"
printf 'export default function P() { return null }\n' > "$MP/app/projects/[id]/page.tsx"
printf 'export async function GET() { return Response.json([]) }\n' > "$MP/app/api/items/route.ts"
printf "'use client'\nexport function Btn() { return null }\n" > "$MP/components/btn.tsx"
printf "'use server'\nexport async function archiveProject() {}\n" > "$MP/lib/actions.ts"
O="$(CLAUDE_PROJECT_DIR="$MP" bash "$H/repo-map.sh")"
assert_contains "map lists page routes" "$O" "/projects/[id] → app/projects/[id]/page.tsx"
assert_contains "map lists route handlers with methods" "$O" "route handler (GET)"
assert_contains "map lists components with exports and client flag" "$O" "btn.tsx: Btn [client]"
assert_contains "map lists server actions" "$O" "archiveProject"
assert_contains "map is served from cache" "$(CLAUDE_PROJECT_DIR="$MP" bash "$H/repo-map.sh"; ls "$MP/.claude/.cache")" "repo-map.key"
printf 'export function Card() { return null }\n' > "$MP/components/card.tsx"
assert_contains "map regenerates when files change" "$(CLAUDE_PROJECT_DIR="$MP" bash "$H/repo-map.sh")" "card.tsx: Card"
CX="$TMP/cx"; newproj "$CX"; ( cd "$CX" && git init -q && git config user.email t@t && git config user.name t && printf '.claude/.cache/\n' > .gitignore && git add -A && git commit -qm i )
export CLAUDE_PROJECT_DIR="$CX"; bash "$H/tasks.sh" init >/dev/null
printf -- '---\nid: 001\ntitle: Base\nstatus: todo\n---\n' > "$CX/.claude/tasks/001-a.md"
printf -- '---\nid: 002\ntitle: Next\nstatus: todo\ndepends: 001\n---\n' > "$CX/.claude/tasks/002-b.md"
bash "$H/tasks.sh" start 001 >/dev/null; printf 'export const svc = 1\n' > "$CX/svc.ts"; bash "$H/tasks.sh" close 001 "added svc helper" >/dev/null
O="$(bash "$H/tasks.sh" context 002)"
assert_contains "context includes the dependency's log line" "$O" "added svc helper"
assert_contains "context includes the files the dependency changed" "$O" "svc.ts"
unset CLAUDE_PROJECT_DIR
O="$(printf '{"agent_type":"next-ui-builder"}' | CLAUDE_PROJECT_DIR="$P" bash "$H/subagent-context.sh")"
assert_contains "subagents get the context as SubagentStart" "$O" '"hookEventName": "SubagentStart"'
assert_contains "subagents are told to use the map" "$O" "tasks.sh map"
SET="$(cat "$KIT/.claude/settings.json")"
assert_contains "context is re-injected after compaction" "$SET" "compact"
assert_contains "SubagentStart is scoped to kit agents" "$SET" '^(next-.*)$'
L1="$(CLAUDE_PROJECT_DIR="$P" bash "$H/session-context.sh" | jq -r .hookSpecificOutput.additionalContext | wc -c)"
[ "$L1" -lt 9000 ] && ok "session context stays under the 10,000-char hook cap ($L1)" || bad "session context stays under the 10,000-char hook cap ($L1)"

group "owner steps: verdict gate, status edits"
V="$TMP/gate"; mkdir -p "$V"
printf '{"dependencies":{"next":"15.1.0"}}' > "$V/package.json"
( cd "$V" && git init -q && git config user.email t@t && git config user.name t && echo a > a.txt && git add . && git commit -qm init )
CLAUDE_PROJECT_DIR="$V" bash "$H/tasks.sh" init >/dev/null 2>&1
mkt() { printf -- '---\nid: %s\ntitle: %s\nstatus: %s\ndepends: %s\n---\n\n## Acceptance\n- [ ] %s\n\n## Log\n' "$1" "$2" "$3" "${5:-}" "$4" > "$V/.claude/tasks/$1-t.md"; }
gt() { CLAUDE_PROJECT_DIR="$V" NEXT_WF_REQUIRE_VERDICT=on bash "$H/tasks.sh" "$@" 2>&1; }
mkt 101 First todo "[browser] it shows"
mkt 102 Second todo "[browser] it shows" 101
CLAUDECODE=1 gt start 101 >/dev/null; echo b > "$V/b.txt"
assert_contains "Claude can start a planned task" "$(gt show 101)" "status: doing"
assert_contains "close refuses without a verdict" "$(gt close 101 built)" "no verdict recorded"
assert_contains "and the task is still doing" "$(gt show 101)" "status: doing"
gt verdict 101 FAIL 1 >/dev/null
assert_contains "close refuses after FAIL" "$(gt close 101 built)" "FAIL"
gt verdict 101 SKIPPED 2 >/dev/null
assert_contains "SKIPPED needs can-skip-verify's yes" "$(gt close 101 built)" "can-skip-verify"
gt verdict 101 UNVERIFIED 2 >/dev/null
gt close 101 'built; UNVERIFIED [browser]: it shows' >/dev/null
assert_contains "UNVERIFIED closes to done" "$(gt show 101)" "status: done"
assert_contains "and the log names what to check" "$(gt show 101)" "UNVERIFIED [browser]: it shows"
assert_contains "then the dependent runs" "$(gt next)" "102-t.md"
gt start 102 >/dev/null; gt verdict 102 PASS 1 >/dev/null; gt close 102 "built it" >/dev/null
assert_contains "PASS closes to done" "$(gt show 102)" "status: done"
mkt 103 Third todo "[review] it reads well"
gt start 103 >/dev/null; echo c >> "$V/a.txt"
gt can-skip-verify 103 >/dev/null; gt verdict 103 SKIPPED 1 >/dev/null; gt close 103 tiny >/dev/null
assert_contains "an allowed SKIPPED closes" "$(gt show 103)" "status: done"
own() { printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | bash "$H/guard-owner.sh" >/dev/null 2>&1; echo $?; }
for c in "sed -i 's/status: todo/status: done/' .claude/tasks/001-x.md" 'echo status: todo > .claude/tasks/001-x.md' \
         "$(printf "bash <<'EOF'\necho status: done > .claude/tasks/001-x.md\nEOF")"; do
  assert_eq "owner guard blocks: ${c%%$'\n'*}" "$(own "$c")" "2"
done
for c in 'git push' 'git push -u origin main' 'cd app && git -C .. push' '"git" push' 'sudo -u x git push'; do
  assert_eq "owner guard sends plain push through git-sync: $c" "$(own "$c")" "2"
done
for c in 'gh pr create --fill' 'git status' 'git commit -m "push the fix"' 'bash .claude/hooks/git-sync.sh push' \
         'bash .claude/hooks/tasks.sh start 001' \
         'bash .claude/hooks/tasks.sh close 001 "done"' 'grep -n status: .claude/tasks/001-x.md' \
         "$(printf "bash .claude/hooks/tasks.sh new 005-x <<'TASK'\n---\nstatus: todo\n---\nsee .claude/tasks/ > x\nTASK")"; do
  assert_eq "owner guard allows: ${c%%$'\n'*}" "$(own "$c")" "0"
done
assert_contains "the owner guard is registered before Bash runs" "$(cat "$KIT/.claude/settings.json")" "guard-owner.sh"
assert_contains "the installer knows the owner guard" "$(cat "$KIT/install.sh")" "guard-owner"

# --- 2.5: existing stacks, cache, verifier knobs, track record, context tidy -----
group "stack cache (2.5)"
SC="$TMP/sc"; newproj "$SC"; printf '{"dependencies":{"next":"15.1.0"},"devDependencies":{"@playwright/test":"1.50.0"}}' > "$SC/package.json"
CLAUDE_PROJECT_DIR="$SC" bash "$H/stack.sh" >/dev/null
N="$(CLAUDE_PROJECT_DIR="$SC" bash -x "$H/stack.sh" 2>&1 | grep -c 'jq -r' || true)"
assert_eq "a second call is served from the cache (no package.json probes)" "$N" "0"
sleep 1; printf "const c = { cacheComponents: true }\nexport default c\n" > "$SC/next.config.mjs"
assert_contains "editing next.config invalidates the cache" "$(CLAUDE_PROJECT_DIR="$SC" bash "$H/stack.sh")" 'CACHE_COMPONENTS="yes"'
touch "$SC/bun.lock"; sleep 1; touch "$SC/package.json"
assert_contains "bun.lock (text lockfile) means bun" "$(CLAUDE_PROJECT_DIR="$SC" bash "$H/stack.sh")" 'PM="bun"'

group "existing stacks: match mode (2.5)"
RX="$TMP/rx"; mkdir -p "$RX/src/store" "$RX/app"
printf '{"dependencies":{"next":"15.1.0","@reduxjs/toolkit":"2.5.0","antd":"5.22.0","formik":"2.4.6","yup":"1.6.0"}}' > "$RX/package.json"
echo 'export const api = createApi({ reducerPath: "api" })' > "$RX/src/store/api.ts"
O="$(CLAUDE_PROJECT_DIR="$RX" bash "$H/stack.sh")"
assert_contains "detects Redux Toolkit" "$O" 'STORE="redux-toolkit"'
assert_contains "detects RTK Query from createApi" "$O" 'DATA_CLIENT="rtk-query"'
assert_contains "detects formik" "$O" 'FORMS="formik"'
assert_contains "detects yup" "$O" 'VALIDATION="yup"'
assert_contains "detects antd" "$O" 'UI_KIT="antd"'
assert_contains "Redux/antd/formik/yup means match mode" "$O" 'STACK_MODE="match"'
assert_contains "NEXT_WF_STACK_MODE=kit overrides it" "$(CLAUDE_PROJECT_DIR="$RX" NEXT_WF_STACK_MODE=kit bash "$H/stack.sh" | grep STACK_MODE | tail -1)" 'STACK_MODE="kit"'
assert_absent "the override is never cached" "$(cat "$RX/.claude/.cache/stack.env")" 'STACK_MODE="kit"'
R="$(CLAUDE_PROJECT_DIR="$RX" bash "$H/session-context.sh")"
assert_contains "session report says to match the existing stack" "$R" "match the existing stack"
assert_contains "and points at existing-stacks.md" "$R" "existing-stacks.md"
assert_contains "and lists the libraries" "$R" "redux-toolkit, rtk-query, formik, yup, antd"
assert_absent "a zod + zustand project stays on the kit line" "$(CLAUDE_PROJECT_DIR="$P" bash "$H/session-context.sh")" "match the existing stack"
[ -f "$KIT/.claude/skills/react-component-conventions/references/existing-stacks.md" ] && ok "existing-stacks reference ships" || bad "existing-stacks reference ships"
mkdir -p "$RX/components"
cat > "$RX/components/list.tsx" <<'EOF'
'use client'
import { useEffect, useState } from 'react'
export function List() {
  const [x, setX] = useState([])
  useEffect(() => { fetch('/api/x').then(r => r.json()).then(setX) }, [])
  return <ul>{x.length}</ul>
}
EOF
O="$(hook guard-component.sh "$RX" components/list.tsx)"; RC=$?
assert_eq "match mode: fetch in useEffect advises, doesn't block" "$RC" "0"
assert_contains "and names the project's data layer" "$O" "RTK Query"
cp "$RX/components/list.tsx" "$P/components/list.tsx"
hook guard-component.sh "$P" components/list.tsx >/dev/null; RC=$?
assert_eq "kit mode: fetch in useEffect still blocks" "$RC" "2"
rm -f "$P/components/list.tsx"

group "permissions for every package manager (2.5)"
for r in 'Bash(pnpm run typecheck:*)' 'Bash(yarn test:*)' 'Bash(yarn run build:*)' 'Bash(bun run lint:*)'; do
  assert_contains "allows $r" "$(cat "$KIT/.claude/settings.json")" "$r"
done

group "verifier knobs and track record (2.5)"
K="$TMP/knobs"; mkdir -p "$K/.claude/tasks"
( cd "$K" && git init -q && git config user.email t@t && git config user.name t && printf '{"dependencies":{"next":"15.1.0"}}' > package.json && git add -A && git commit -qm i )
printf -- '---\nid: 201\ntitle: k\nstatus: todo\n---\n\n## Acceptance\n- [ ] [review] reads well\n' > "$K/.claude/tasks/201-k.md"
kt() { CLAUDE_PROJECT_DIR="$K" bash "$H/tasks.sh" "$@" 2>&1; }
kt start 201 >/dev/null 2>&1; seq 1 30 > "$K/big.txt"
assert_contains "30 lines is over the default skip size" "$(kt can-skip-verify 201)" "> 20"
assert_contains "NEXT_WF_SKIP_VERIFY_LINES raises it" "$(CLAUDE_PROJECT_DIR="$K" NEXT_WF_SKIP_VERIFY_LINES=40 bash "$H/tasks.sh" can-skip-verify 201)" "yes"
seq 1 100 > "$K/big.txt"
assert_contains "but never past 60" "$(CLAUDE_PROJECT_DIR="$K" NEXT_WF_SKIP_VERIFY_LINES=500 bash "$H/tasks.sh" can-skip-verify 201)" "> 60"
kt verdict 201 FAIL 1 "the empty state is missing" >/dev/null
assert_contains "a FAIL reason is recorded" "$(cat "$K/.claude/.cache/metrics.jsonl")" '"why":"the empty state is missing"'
assert_contains "verdict rejects a non-numeric round" "$(kt verdict 201 FAIL oops)" "round must be a number"
kt verdict 201 PASS 2 >/dev/null
B="$(kt stats --brief)"
assert_contains "stats --brief gives the first-pass rate" "$B" "first-pass 0% (0/1)"
assert_contains "and the recent failure" "$B" "201: the empty state is missing"
assert_contains "the session report carries the track record" "$(CLAUDE_PROJECT_DIR="$K" bash "$H/session-context.sh")" "Track record: verifier first-pass"
assert_absent "the Stop-hook mode NEXT_WF_VERIFY no longer switches browser checks" "$(CLAUDE_PROJECT_DIR="$K" NEXT_WF_VERIFY=typecheck,lint bash "$H/session-context.sh")" "browser checks are OFF"
assert_contains "and says when browser checks are off" "$(CLAUDE_PROJECT_DIR="$K" NEXT_WF_VERIFY_BROWSER=off bash "$H/session-context.sh")" "browser checks are OFF"
assert_contains "verify-browser.sh honours NEXT_WF_VERIFY_BROWSER=off" "$(cd "$K" && CLAUDE_PROJECT_DIR="$K" NEXT_WF_VERIFY_BROWSER=off NEXT_WF_DEV_URL=http://x bash "$H/verify-browser.sh" 201)" "UNVERIFIED: browser checks are off"
for c in 'NEXT_WF_REQUIRE_VERDICT=off bash .claude/hooks/tasks.sh close 201 x' 'export NEXT_WF_SKIP_VERIFY_LINES=60' 'env NEXT_WF_VERIFY_BROWSER=off claude -p x'; do
  assert_eq "owner guard blocks the gate's switches: $c" "$(own "$c")" "2"
done
assert_eq "owner guard allows reading them" "$(own 'printenv NEXT_WF_DEV_URL')" "0"

group "compact-context (2.5)"
CC="$TMP/cc"; mkdir -p "$CC/.claude"
cp "$KIT/templates/project-context.md" "$CC/.claude/project-context.md"
CLAUDE_PROJECT_DIR="$CC" bash "$H/tasks.sh" compact-context >/dev/null
assert_eq "the pristine template is left as it is" "$(diff "$KIT/templates/project-context.md" "$CC/.claude/project-context.md" && echo same)" "same"
printf '\n## Layout\n- pages: app/(site)\n-   pages:  app/(site)\n\n## Empty\n\n## Gotchas\n- seed first\n' >> "$CC/.claude/project-context.md"
O="$(CLAUDE_PROJECT_DIR="$CC" bash "$H/tasks.sh" compact-context)"
C="$(cat "$CC/.claude/project-context.md")"
assert_eq "duplicate facts are dropped" "$(grep -c 'pages:' <<<"$C")" "1"
assert_eq "repeated headings are merged" "$(grep -c '^## Layout' <<<"$C")" "1"
assert_absent "empty sections are dropped" "$C" "## Empty"
assert_contains "facts are kept" "$C" "seed first"
assert_contains "a backup is kept" "$O" "backup in .claude/.cache"
assert_contains "the runner is told about compact-context" "$(cat "$KIT/.claude/commands/next/task.md")" "compact-context"

group "plugin packaging (2.5)"
PJ="$KIT/.claude-plugin/plugin.json"
jq -e . "$PJ" >/dev/null 2>&1 && ok "plugin.json is valid JSON" || bad "plugin.json is valid JSON"
jq -e . "$KIT/.claude-plugin/marketplace.json" >/dev/null 2>&1 && ok "marketplace.json is valid JSON" || bad "marketplace.json is valid JSON"
assert_eq "plugin version matches VERSION" "$(jq -r .version "$PJ")" "$(cat "$KIT/VERSION")"
assert_eq "plugin is named next (commands stay /next:*)" "$(jq -r .name "$PJ")" "next"
assert_eq "marketplace lists the same plugin name" "$(jq -r '.plugins[0].name' "$KIT/.claude-plugin/marketplace.json")" "next"
assert_eq "plugin.json lists every agent" "$(jq -r '.agents[]' "$PJ" | sed 's|^\./||' | sort | tr '\n' ' ')" "$(cd "$KIT" && ls .claude/agents/*.md | sort | tr '\n' ' ')"
for f in $(jq -r '.agents[], .commands, .skills' "$PJ"); do [ -e "$KIT/$f" ] && ok "plugin path exists: $f" || bad "plugin path exists: $f"; done
assert_eq "hooks.json is up to date with settings.json (jq -f hooks/build-hooks.jq)" \
  "$(jq -f "$KIT/hooks/build-hooks.jq" "$KIT/.claude/settings.json" | jq -S .)" "$(jq -S . "$KIT/hooks/hooks.json")"
for n in $(jq -r '.. | .command? // empty' "$KIT/hooks/hooks.json" | awk '{print $NF}'); do
  [ -f "$KIT/.claude/hooks/$n.sh" ] && ok "plugin hook exists: $n" || bad "plugin hook exists: $n"
done
assert_contains "plugin SubagentStart matches scoped agent names" "$(jq -r '.hooks.SubagentStart[0].matcher' "$KIT/hooks/hooks.json")" "(^|:)next-"

PL="$TMP/plugin-proj"; newproj "$PL"; mkdir -p "$PL/app"
pd() { CLAUDE_PLUGIN_ROOT="$KIT" CLAUDE_PROJECT_DIR="$PL" bash "$H/plugin-dispatch.sh" "$@"; }
assert_contains "plugin session report names the plugin's helper folder" "$(pd session-context </dev/null)" "Kit helpers: \`$H\`"
assert_contains "plugin session report reads the kit VERSION" "$(pd session-context </dev/null)" "next-workflow $(cat "$KIT/VERSION")"
assert_eq "dispatcher refuses odd hook names" "$(pd '../x' </dev/null; echo $?)" "0"
mkdir -p "$PL/.claude/hooks"; cp "$H/session-context.sh" "$PL/.claude/hooks/"
assert_absent "a stray project file alone doesn't make the plugin step aside" "$(pd session-context </dev/null)" "installed twice"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/session-context.sh"}]}]}}' > "$PL/.claude/settings.json"
assert_contains "with a registered project install, the plugin steps aside and says so" "$(pd session-context </dev/null)" "installed twice"
cp "$H/guard-read.sh" "$PL/.claude/hooks/"
printf '#!/bin/sh\nexit 0\n' > "$PL/.claude/hooks/guard-read.sh"
printf '{"hooks":{"PreToolUse":[{"matcher":"Read","hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/guard-read.sh"}]}]}}' > "$PL/.claude/settings.local.json"
assert_eq "a project file can't switch a plugin guard off" "$(printf '{"tool_input":{"file_path":"%s/.env"}}' "$PL" | CLAUDE_PLUGIN_ROOT="$KIT" CLAUDE_PROJECT_DIR="$PL" bash "$H/plugin-dispatch.sh" guard-read >/dev/null 2>&1; echo $?)" "2"
rm -rf "$PL/.claude/hooks/guard-read.sh" "$PL/.claude/settings.json" "$PL/.claude/settings.local.json"
assert_eq "without a project install the plugin's guard blocks" "$(printf '{"tool_input":{"file_path":"%s/.env"}}' "$PL" | CLAUDE_PLUGIN_ROOT="$KIT" CLAUDE_PROJECT_DIR="$PL" bash "$H/plugin-dispatch.sh" guard-read >/dev/null 2>&1; echo $?)" "2"
rm -rf "$PL/.claude/hooks"

rd() { printf '{"tool_input":{"file_path":"%s"}}' "$1" | bash "$H/guard-read.sh" >/dev/null 2>&1; echo $?; }
for f in "$PL/.env" "$PL/.env.local" "$PL/.env.production" "$PL/certs/server.pem" "$HOME/.ssh/id_ed25519" "$PL/id_rsa"; do
  assert_eq "guard-read blocks ${f##*/}" "$(rd "$f")" "2"
done
for f in "$PL/.env.example" "$PL/app/page.tsx" "$PL/environment.ts"; do
  assert_eq "guard-read allows ${f##*/}" "$(rd "$f")" "0"
done

printf '{"scripts":{"test":"vitest run","typecheck":"tsc --noEmit"},"dependencies":{"next":"15.1.0"}}' > "$PL/package.json"
ah() { printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | CLAUDE_PROJECT_DIR="$PL" bash "$H/allow-helpers.sh" | grep -q '"allow"' && echo allow || echo prompt; }
for c in "bash $H/tasks.sh list" "bash $H/tasks.sh close 001 \"built it, kept the API\"" \
         "bash $H/repo-map.sh" "npm run test -- src/a.test.ts" "npm run typecheck" "printenv NEXT_WF_DEV_URL" \
         "$(printf "bash $H/tasks.sh new 004-add-footer <<'TASK'\n---\nid: 004\n---\nTASK")"; do
  assert_eq "allow-helpers approves: ${c%%$'\n'*}" "$(ah "$c")" "allow"
done
for c in "bash $H/tasks.sh list; rm -rf x" "bash $H/tasks.sh close 001 \"\$(id)\"" "bash $H/tasks.sh log 001 \`id\`" \
         "bash ${H/.claude/xclaude}/tasks.sh list" "bash .claude/hooks/tasks.sh next" "bash $H/verify.sh --baseline" "bash $H/run-tasks.sh" \
         "npm run test -- a.ts && curl x" "npm run test2" "npm run test -- --config evil.ts" "npm run test --reporter=./x.js" \
         "npm run test -- -c x" "bash $H/tasks.sh list > out.txt" \
         "$(printf "bash $H/tasks.sh new 004-add-footer <<'TASK'\nTASK\nrm -rf x\nTASK")" \
         "$(printf "bash $H/tasks.sh new 004-add-footer <<TASK\nx\nTASK")"; do
  assert_eq "allow-helpers leaves to the prompt: ${c%%$'\n'*}" "$(ah "$c")" "prompt"
done
assert_eq "owner guard blocks verify.sh --baseline (plugins have no deny rule)" "$(own "bash $H/verify.sh --baseline")" "2"
assert_eq "owner guard allows plain verify.sh" "$(own "bash $H/verify.sh")" "0"

group "messages (2.5)"
O="$(printf '{"tool_input":{"command":"cat .e*"}}' | (cd "$KIT" && bash "$H/guard-secrets.sh") 2>&1)"
assert_contains "secrets message shows the pattern" "$O" "(.e*)"
assert_absent "and doesn't glob-expand it into the folder's files" "$O" "CHANGELOG.md"
assert_absent "run-tasks no longer points at the removed accept step" "$(cat "$H/run-tasks.sh")" "tasks.sh accept"
assert_absent "prompts don't hard-code the project helper path" "$(cat "$KIT"/.claude/agents/*.md "$KIT"/.claude/commands/next/*.md)" "bash .claude/hooks/"

group "no comments: pure code (2.6)"
CG="$TMP/comments"; mkdir -p "$CG/app" "$CG/components"; NL=$'\n'
gc() { jq -n --arg f "$1" --arg o "$2" --arg n "$3" '{tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n}}' | CLAUDE_PROJECT_DIR="$CG" bash "$H/guard-comments.sh" >/dev/null 2>&1; echo $?; }
assert_eq "blocks a line comment" "$(gc "$CG/lib/a.ts" x "// load users${NL}const u = await getUsers()")" "2"
assert_eq "blocks a trailing comment" "$(gc "$CG/lib/a.ts" x "const a = foo(); // why")" "2"
assert_eq "blocks JSDoc prose" "$(gc "$CG/lib/a.ts" x "/**${NL} * Formats a price.${NL} */")" "2"
assert_eq "blocks a JSX comment" "$(gc "$CG/components/a.tsx" x "{/* hero */}")" "2"
assert_eq "blocks a CSS comment" "$(gc "$CG/app/globals.css" x "/* brand */${NL}a { color: red; }")" "2"
assert_eq "allows @ts-expect-error" "$(gc "$CG/lib/a.ts" x "// @ts-expect-error${NL}foo()")" "0"
assert_eq "allows eslint-disable-next-line" "$(gc "$CG/lib/a.ts" x "// eslint-disable-next-line no-console${NL}console.log(1)")" "0"
assert_eq "allows 'use client'" "$(gc "$CG/components/a.tsx" x "'use client'${NL}export function A() { return null }")" "0"
assert_eq "allows a URL in a string" "$(gc "$CG/lib/a.ts" x "const u = 'https://example.com'")" "0"
assert_eq "allows a CSS universal selector" "$(gc "$CG/app/globals.css" x "* { box-sizing: border-box; }")" "0"
assert_eq "ignores markdown" "$(gc "$CG/README.md" x "<!-- hi -->")" "0"
assert_eq "ignores node_modules and .next" "$(gc "$CG/node_modules/x/a.js" x "// hi")$(gc "$CG/.next/x.js" x "// hi")" "00"
printf '// existing note\nexport const a = 1\n' > "$CG/lib-b.ts"
assert_eq "comments already in the file are kept" "$(gc "$CG/lib-b.ts" 'export const a = 1' "// existing note${NL}export const a = 2")" "0"
assert_eq "NEXT_WF_COMMENT_GUARD=off turns it off" "$(NEXT_WF_COMMENT_GUARD=off gc "$CG/lib/a.ts" x "// hi")" "0"
printf 'export const c = 1\n' > "$CG/c.ts"
O="$(jq -n --arg f "$CG/c.ts" --arg c "// make it${NL}export const c = 1" '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}' | CLAUDE_PROJECT_DIR="$CG" bash "$H/guard-comments.sh" 2>&1)"
assert_contains "a Write that adds a comment is blocked and names the line" "$O" "// make it"
assert_contains "the comment guard runs before Edit/Write" "$(cat "$KIT/.claude/settings.json")" "guard-comments.sh"
for f in next-route-builder next-data-layer next-ui-builder; do
  assert_contains "$f is told: no comments" "$(cat "$KIT/.claude/agents/$f.md")" "No comments — pure code"
done
assert_contains "the task runner is told: no comments" "$(cat "$KIT/.claude/commands/next/task.md")" "No comments — pure code"
assert_contains "code-conventions states the rule" "$(cat "$KIT/.claude/skills/code-conventions/SKILL.md")" "carries no comments"

group "git: commit, pull the stage branch, push (2.6)"
GS="$TMP/gitsync"; mkdir -p "$GS"
git init -q --bare "$GS/remote.git"
git clone -q "$GS/remote.git" "$GS/app" 2>/dev/null
gcfg() { git -C "$1" config user.email t@t; git -C "$1" config user.name t; git -C "$1" config commit.gpgsign false; }
gcfg "$GS/app"
( cd "$GS/app" && git checkout -q -b main && printf 'a\n' > a.txt && git add a.txt && git commit -qm init && git push -q origin main \
  && git checkout -q -b stage && git push -q origin stage && git checkout -q -b feature && printf 'f\n' > f.txt && git add f.txt && git commit -qm feature ) 2>/dev/null
git clone -q "$GS/remote.git" "$GS/mate" 2>/dev/null; gcfg "$GS/mate"
( cd "$GS/mate" && git checkout -q stage && printf 's\n' > s.txt && git add s.txt && git commit -qm "stage work" && git push -q origin stage ) 2>/dev/null
gsync() { (cd "$GS/app" && CLAUDE_PROJECT_DIR="$GS/app" bash "$H/git-sync.sh" "$@" 2>&1); }
gsync_rc() { (cd "$GS/app" && CLAUDE_PROJECT_DIR="$GS/app" bash "$H/git-sync.sh" "$@" >/dev/null 2>&1); echo $?; }
assert_eq "no stage branch configured: exit 2" "$(gsync_rc push)" "2"
assert_contains "it suggests the stage branch from the remote" "$(gsync stage)" "likely candidates on origin: stage"
assert_contains "stage <branch> records it" "$(gsync stage stage)" "stage branch: stage"
assert_contains "the choice lives in .claude/workflow.conf" "$(cat "$GS/app/.claude/workflow.conf")" "STAGE_BRANCH=stage"
( cd "$GS/app" && git add .claude/workflow.conf && git commit -qm conf )
assert_eq "push refuses a branch missing the stage branch's commits" "$(gsync_rc push)" "5"
assert_contains "sync merges the stage branch in" "$(gsync sync)" "brought in"
assert_eq "after sync, push succeeds" "$(gsync_rc push)" "0"
assert_eq "the branch is on the remote" "$(git -C "$GS/remote.git" rev-parse --verify --quiet refs/heads/feature >/dev/null && echo yes)" "yes"
printf 'dirty\n' > "$GS/app/dirty.txt"
assert_eq "push refuses uncommitted changes" "$(gsync_rc push)" "4"
rm -f "$GS/app/dirty.txt"
( cd "$GS/mate" && git pull -q origin stage && printf 'mate\n' > a.txt && git commit -qam "mate edit" && git push -q origin stage ) 2>/dev/null
( cd "$GS/app" && printf 'mine\n' > a.txt && git commit -qam "my edit" )
assert_eq "a conflicting stage change: exit 3" "$(gsync_rc sync)" "3"
( cd "$GS/app" && git merge --abort )
assert_contains "/next:sync runs only when the user types it" "$(cat "$KIT/.claude/commands/next/sync.md")" "disable-model-invocation: true"
IG="$TMP/install-stage"; newproj "$IG"; git init -q "$IG"
bash "$KIT/install.sh" "$IG" --stage-branch develop >/dev/null 2>&1
assert_contains "install.sh --stage-branch records the stage branch" "$(cat "$IG/.claude/workflow.conf" 2>/dev/null)" "STAGE_BRANCH=develop"
mkdir -p "$IG/app"
assert_contains "the session report names the stage branch" "$(CLAUDE_PROJECT_DIR="$IG" bash "$H/session-context.sh")" "stage branch \`develop\`"
assert_eq "a mixed-quote heredoc delimiter can't hide a push" "$(own "$(printf 'cat <<"E"OF > f\nx\nEOF\ngit push')")" "2"
assert_eq "a heredoc with no terminator is scanned whole" "$(own "$(printf 'cat <<EOF > f\nx\ngit push')")" "2"
assert_eq "a quoted << can't fake a heredoc" "$(own "$(printf 'echo "<<EOF"\ngit push\nEOF')")" "2"
assert_eq "a << after # can't fake a heredoc" "$(own "$(printf 'true # <<EOF\ngit push\nEOF')")" "2"
assert_eq "a quoted-delimiter task draft still passes" "$(own "$(printf "bash .claude/hooks/tasks.sh new 005-x <<'TASK'\ngit push\nTASK")")" "0"
mkdir -p "$IG/.claude/.cache"; printf 'CMD_TEST="rm -rf x"\n' > "$IG/.claude/.cache/stack.env"
assert_eq "allow-helpers ignores a tampered stack cache" "$(printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf x"}}' | CLAUDE_PROJECT_DIR="$IG" bash "$H/allow-helpers.sh" | grep -c allow)" "0"
assert_eq "allow-helpers still approves a known verify command" "$(printf '{"tool_name":"Bash","tool_input":{"command":"npm run test"}}' | CLAUDE_PROJECT_DIR="$IG" bash "$H/allow-helpers.sh" | grep -c allow)" "1"

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
