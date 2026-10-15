// Hidden eval config: lets a plain Vitest process import server modules ('server-only' is a
// no-op here, next/headers + next/cache are mocked inside the test).
import { fileURLToPath } from 'node:url'

const root = process.cwd()
export default {
  resolve: {
    alias: [
      { find: /^@\//, replacement: `${root}/` },
      { find: 'server-only', replacement: fileURLToPath(new URL('./empty.ts', import.meta.url)) },
    ],
  },
  test: { include: ['**/__eval_hidden__*.test.ts'], root },
}
