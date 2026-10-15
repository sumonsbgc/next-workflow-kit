// Playwright config used only by the next-verifier agent for [browser] acceptance criteria.
// It exists because Playwright only discovers specs inside a config's testDir: a throwaway spec
// under .claude/.cache/verify is invisible to the project's own playwright.config.
// Specs are .mjs so the project's TypeScript check never sees them.
//
//   NEXT_WF_DEV_URL=http://localhost:3000 bash .claude/hooks/verify-browser.sh <task-id>
//
// Run it from the project root: testDir is resolved from the working directory, which keeps
// this file usable from a global install (~/.claude) too.
export default {
  testDir: `${process.cwd()}/.claude/.cache/verify`,
  testMatch: '**/*.spec.mjs',
  reporter: 'line',
  retries: 0,
  timeout: 30_000,
  use: {
    baseURL: process.env.NEXT_WF_DEV_URL,
    headless: true,
    trace: 'off',
  },
}
