# Working inside an existing stack

Read this when the session report says **Conventions: match the existing stack**. That means the project was built on libraries the kit doesn't default to: Redux Toolkit, RTK Query, react-query, SWR, formik, yup, antd, MUI and so on. The project's choices win. This file replaces the zustand/zod/react-hook-form defaults in the rest of the skill. Everything else still applies.

## The rule

**Extend what is there; don't introduce a parallel way of doing the same job.**

- Before writing state, data-fetching, form or validation code, find one existing example of the same kind and follow it. Use `tasks.sh map` first, then one grep (`grep -rln "createSlice\|createApi\|useFormik\|Yup.object" src`), then read that one file. If you had to look, record where the pattern lives in `.claude/project-context.md`.
- **Never add** zustand next to Redux, zod next to yup, or react-hook-form next to formik, unless the task explicitly says to migrate. Two ways to do one job is worse than either one.
- Don't move existing client code to the server as a side effect. A task that says "add a filter" doesn't also convert the page to a Server Component.
- New, self-contained pieces may still be server-first: a new route whose data doesn't come from the client store, a pure helper, a static page. Use the kit's rules there.

## Redux Toolkit

- **One store per request, never a module singleton.** In the App Router the store is created in a client `StoreProvider` (`useRef(makeStore())`) that wraps the tree. If the project already has `makeStore`, use it. If it exports a global `store` instance, don't copy that pattern into new code, and flag it in your report.
- Use the project's typed hooks (`useAppDispatch`, `useAppSelector`, usually in `store/hooks.ts`), not the bare `useDispatch`/`useSelector`.
- New state goes into the slice that owns that feature, or a new `createSlice` beside the others. Follow the existing folder layout (`features/x/x-slice.ts`, `store/slices/…`).
- Selectors live with the slice. Components select the narrowest value they need.
- Business rules and validation still don't belong in components. In a Redux codebase they live in thunks, services, or the slice's reducers, wherever the project already puts them.

## RTK Query, react-query, SWR

- **Server data goes through the project's data client.** Don't hand-roll `fetch` in `useEffect`, and don't copy server data into a Redux slice when RTK Query already caches it.
- RTK Query: add endpoints to the existing `createApi` (or `injectEndpoints` if the project splits them) and use the generated hooks. Invalidate with `providesTags`/`invalidatesTags`, following the tag names already in use.
- react-query: follow the existing `queryKey` shape (usually a factory like `projectKeys.list(filters)`). The `QueryClient` is created once per browser session inside the provider (`useState(() => new QueryClient())`), never at module scope on the server. Invalidate after mutations with `queryClient.invalidateQueries`.
- SWR: use the project's fetcher and key conventions; `mutate` after writes.
- If the project already prefetches on the server (`HydrationBoundary`, `initialData`, RTK Query SSR), follow it. Don't introduce server prefetching in a project that doesn't use it.

## formik + yup

- Schemas live where the project keeps them. Look for `Yup.object` / `yup.object` before creating a new file. If there is no convention yet, use `lib/validation/`.
- **The server validates too.** A Server Action or route handler that receives the form's data parses it with the **same yup schema** (`await schema.validate(input, { abortEarly: false, stripUnknown: true })`). yup runs on the server; there's no reason to add zod for this.
- Use the project's form wrapper components if it has them (`<FormikField>`, antd `<Form.Item>` bindings) rather than raw `useFormik` wiring.
- Accessibility is unchanged: every field labelled, errors tied to inputs with `aria-invalid`/`aria-describedby`, and focus moved to the first invalid field on submit.

## antd, MUI, Chakra, Mantine

- These are client components. That's fine. The page can stay a Server Component that loads data and renders a client island built from the kit. Only that island needs `'use client'`.
- Use the library's components for anything it already provides (tables, modals, forms, date pickers). Don't hand-roll a modal in an antd app.
- **antd + App Router:** the root layout must wrap children in `AntdRegistry` from `@ant-design/nextjs-registry`, or styles flash on load. MUI uses `AppRouterCacheProvider` from `@mui/material-nextjs`. If it's missing and the task touches styling, say so; don't silently add the dependency.
- Theme through the library's theme (antd `ConfigProvider` tokens, the MUI theme), not one-off inline colours.
- With Tailwind 3 beside antd, Tailwind's Preflight can override antd base styles. Follow whatever the project already does (Preflight disabled, `important`, a prefix). Don't change it.

## What still applies, unchanged

- Security at the boundary: every Server Action and route handler authenticates, authorizes the specific object, and validates with the project's validator before acting.
- Hydration rules: no `Date.now()`, `Math.random()`, storage reads or `typeof window` branches during render.
- One exported component per file; logic out of components (into hooks, thunks, services); typed props.
- Accessibility, `next/image`, `next/link`, and no server-only env vars in client code.

## Guards in this mode

The edit guards still run. In match mode, "data fetching inside useEffect" is a warning, not a block. The fix it points to is the project's data client (an RTK Query endpoint, a `useQuery` hook), not necessarily a Server Component.
