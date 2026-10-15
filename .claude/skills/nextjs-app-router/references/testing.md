# Testing a Next.js App Router project

## Split

- **Vitest + React Testing Library** — pure functions, hooks, and *client* components.
- **Playwright** — routes, async Server Components, Server Actions, redirects, middleware, auth flows. RTL cannot render an async Server Component; don't fight it, test the route.

## Vitest setup

```ts
// vitest.config.ts
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tsconfigPaths from 'vite-tsconfig-paths'

export default defineConfig({
  plugins: [tsconfigPaths(), react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./vitest.setup.ts'],
    globals: true,
    include: ['**/*.test.{ts,tsx}'],
    exclude: ['**/node_modules/**', '**/e2e/**'],
  },
})
```

```ts
// vitest.setup.ts
import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach, vi } from 'vitest'

afterEach(cleanup)

vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), refresh: vi.fn(), back: vi.fn() }),
  usePathname: () => '/',
  useSearchParams: () => new URLSearchParams(),
  redirect: vi.fn(),
  notFound: vi.fn(),
}))
```

## Component test

```tsx
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Counter } from './counter'

test('increments on click', async () => {
  render(<Counter start={1} />)
  await userEvent.click(screen.getByRole('button', { name: /increment/i }))
  expect(screen.getByRole('status')).toHaveTextContent('2')
})
```

Query by role/label/text — never by class name or test id unless nothing else identifies the element. A test that can only find its target by test id usually means the markup isn't accessible.

## Server Action test

Actions are plain async functions — call them directly with a `FormData`, mock the DB layer, and assert on the returned state:

```ts
const fd = new FormData()
fd.set('title', '')
expect(await createPost({}, fd)).toMatchObject({ fieldErrors: { title: expect.any(Array) } })
```

## Playwright

```ts
// playwright.config.ts
export default defineConfig({
  testDir: './e2e',
  use: { baseURL: 'http://localhost:3000', trace: 'on-first-retry' },
  webServer: {
    command: 'npm run build && npm run start',   // test the production build: caching differs from dev
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
  },
})
```

```ts
test('publishes a post', async ({ page }) => {
  await page.goto('/posts/new')
  await page.getByLabel('Title').fill('Hello')
  await page.getByRole('button', { name: 'Save' }).click()
  await expect(page.getByRole('heading', { name: 'Hello' })).toBeVisible()
})
```

Prefer `getByRole`/`getByLabel` and web-first assertions (`toBeVisible`) over `waitForTimeout`.

## What's worth testing

Server Action validation and authorization branches, redirect/`notFound` behaviour, loading and error states, form submission without JS (`javaScriptEnabled: false` in Playwright) when you claim progressive enhancement. Skip snapshot tests of whole pages — they break on every copy change and catch nothing.
