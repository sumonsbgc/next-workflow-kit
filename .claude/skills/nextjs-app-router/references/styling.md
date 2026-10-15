# Styling

**Check the session-start stack report first.** Do not introduce Tailwind, shadcn/ui, or any component library that isn't already installed — write CSS Modules instead and say so in your report.

## Know the exact version before you write a class

Tailwind v4 ships new utilities in every minor. A class from a newer version than the one installed **silently produces no CSS** — no error, no warning, just an element with no styling. Read the real version, not the range in `package.json`:

```bash
node -p "require('tailwindcss/package.json').version"
```

The stack report's `TAILWIND_VERSION` is the declared range; the command above is the truth. Target the installed minor. If a utility you want landed later, use the arbitrary-value or plain-CSS equivalent rather than upgrading the dependency on your own initiative.

## Tailwind v4 setup (CSS-first)

There is no `tailwind.config.js` in v4 — configuration lives in the CSS entrypoint:

```css
@import "tailwindcss";

@theme {
  --color-brand: oklch(0.62 0.19 258);
  --font-display: "Inter", sans-serif;
  --radius-card: 0.75rem;
  --spacing: 0.25rem;              /* the whole spacing scale derives from this */
}

@custom-variant dark (&:where(.dark, .dark *));   /* class-based dark mode */

@utility card {                                    /* custom utility */
  border-radius: var(--radius-card);
  box-shadow: var(--shadow-sm);
}
```

- Every `@theme` entry becomes both a utility and a CSS variable: `--color-brand` gives you `bg-brand`, `text-brand`, `border-brand`, and `var(--color-brand)` in hand-written CSS.
- `@theme inline` when the value references another variable that must resolve at use time.
- Content detection is automatic — there is no `content` array. Use `@source "…"` to add a path outside the project (a UI package in a monorepo), `@source not "…"` to exclude one, and `@source inline("…")` to safelist classes that only exist in strings (v4.1+).
- `@plugin "@tailwindcss/typography";` for plugins. `@config "../tailwind.config.js";` only when a legacy JS config must still be read.
- Custom CSS goes in `@layer components` / `@layer utilities`, or as an `@utility` — never as an unlayered global rule that fights specificity.

### Next.js integration

PostCSS is the default: `@tailwindcss/postcss` in `postcss.config.mjs`. From **v4.2** there is also `@tailwindcss/webpack`, a first-party webpack plugin that is roughly 2× faster in Next.js builds and works through Turbopack's compatibility layer. Don't switch an existing project's build pipeline unless asked — but prefer it when setting one up fresh on 4.2+.

## Preflight changed the cursor — fix it once, globally

In v4, Preflight no longer sets `cursor: pointer` on buttons; they inherit the browser default (`cursor: default`). Interactive elements must therefore say so. **Every button and every link gets a pointer cursor** — a control that doesn't look clickable isn't obviously clickable.

Do it once in the base layer rather than remembering `cursor-pointer` on every element:

```css
@layer base {
  button:not(:disabled),
  [role="button"]:not(:disabled),
  a[href],
  summary,
  label[for] {
    cursor: pointer;
  }
  button:disabled,
  [role="button"][aria-disabled="true"] {
    cursor: not-allowed;
  }
}
```

If the project has no such base rule, add `cursor-pointer` to the class list of every button and link you write (and `disabled:cursor-not-allowed` where the control can be disabled). Prefer adding the base rule — it can't be forgotten on the next component.

## v3 classes that are dead in v4

If you learned these from older code or older docs, they emit nothing now:

| v3 | v4 |
|---|---|
| `bg-opacity-50`, `text-opacity-*`, `border-opacity-*` | `bg-black/50`, `text-white/70` |
| `flex-shrink-0`, `flex-grow` | `shrink-0`, `grow` |
| `overflow-ellipsis` | `text-ellipsis` |
| `decoration-slice` | `box-decoration-slice` |
| `outline-none` | `outline-hidden` (`outline-none` now really means `outline: none`) |
| `shadow-sm` → `shadow-xs`, `shadow` → `shadow-sm` | shadow/radius/blur scales all shifted one step |
| `rounded-sm` → `rounded-xs`, `rounded` → `rounded-sm` | same shift |
| `ring` (was 3px) | `ring` is 1px; use `ring-3` for the old look |
| `w-4 h-4` | `size-4` |

## Utilities worth reaching for, by version

**v4.0** — container queries built in (`@container`, `@sm:`, `@max-md:`), `size-*`, `inset-shadow-*`, `field-sizing-content`, `starting:` for enter animations, `not-*`, `in-*`, `nth-*`, `open:`, `inert:`, 3D transforms, OKLCH colours, `text-*/leading-*` shorthand.

**v4.1** — `text-shadow-2xs…text-shadow-lg` (with colour and `/opacity`), `mask-*` (`mask-b-from-50%`, `mask-radial-at-right`), `wrap-break-word` and `wrap-anywhere`, safe alignment (`items-center-safe`, `justify-center-safe`) which stops centred overflow from clipping, `items-baseline-last`, coloured `drop-shadow-*`, `pointer-fine:` / `pointer-coarse:` / `any-pointer-*:`, `user-valid:` / `user-invalid:`, `noscript:`, `details-content:`, `inverted-colors:`.

**v4.2** — `mauve`, `olive`, `mist`, `taupe` palettes; the webpack plugin.

**v4.3** — `scrollbar-thin` / `scrollbar-auto` / `scrollbar-none`, `scrollbar-thumb-*` and `scrollbar-track-*`, `scrollbar-gutter-stable` (kills the layout shift when a scrollbar appears); `zoom-*`; `tab-*` for tab width in code blocks; `@container-size` for container queries that depend on height (`cqb`/`cqh` units); logical properties — `mbs-*`, `mbe-*`, `pbs-*`, `pbe-*`, `inline-*` / `block-*` sizing (plus `min-`/`max-`), `inset-s-*`, `inset-e-*`, `inset-bs-*`, `inset-be-*`; `font-features-*` for OpenType features like tabular numerals; `@variant` with stacked (`@variant hover:focus`) and compound (`@variant hover, focus`) forms; `--default(…)` in `@utility` definitions.

**Deprecated in 4.3:** `start-*` / `end-*` — use `inset-s-*` / `inset-e-*`.

Prefer these over hand-written CSS and over arbitrary values: `scrollbar-gutter-stable` beats a magic `padding-right`, `items-center-safe` beats an overflow hack, `font-features-["tnum"]` beats a one-off class.

## Conventions either way

- **Compose with the project's `cn`/`clsx` helper**, never string concatenation with inline ternaries in the class attribute.
- **Class names must be complete literal strings.** `` `bg-${color}-500` `` produces nothing — the scanner reads source text, it doesn't execute it. Map to full class names instead:
  ```ts
  const tone = { danger: 'bg-red-500', ok: 'bg-emerald-500' }[status]
  ```
- **Tokens over arbitrary values.** `w-[437px]`, `text-[#0ea5e9]`, `p-[13px]` scattered through markup means the design system exists only in your head. Define it once in `@theme`. Arbitrary values are for genuine one-offs.
- **Dark mode via tokens that flip**, not a duplicated palette on every element. Define light and dark values for the same `--color-*` names and use `dark:` only where the mapping genuinely differs.
- Sort classes with `prettier-plugin-tailwindcss` if the project has it; don't hand-order against the tool.
- Long class lists are a signal: extract a component (not a `@apply` soup file). `@apply` is for the rare shared primitive, not a way to write CSS with extra steps.
- Responsive is mobile-first: unprefixed is small, `md:` and up override. **Prefer container queries (`@container`) over viewport breakpoints for components** — a card should respond to its slot, not to the window.
- `next/font` for fonts, wired to `--font-*` in `@theme`. Never `<link>` a Google Font — it costs a round trip and breaks the font-display strategy.
- `next/image` for images: it prevents the layout shift that `w-full h-auto` alone won't.
- Respect `prefers-reduced-motion` with `motion-safe:` / `motion-reduce:` on anything that moves.

## shadcn/ui (only when `components.json` exists)

Components are *your* source in `components/ui/*` — edit them directly, they're not a dependency. Add new ones with `npx shadcn@latest add <name>`. Never hand-write a file into `components/ui/` pretending to be a shadcn component; either add it via the CLI or put it in `components/`. Most shadcn primitives are client components — wrap them in a small island rather than marking a page `'use client'` to use one.

## No Tailwind

CSS Modules (`project-card.module.css`) colocated with the component, plus CSS custom properties in `app/globals.css` for tokens. Keep global CSS to resets, tokens, and element defaults — everything else is scoped. Don't introduce a CSS-in-JS runtime library into an App Router project: most break in Server Components.
