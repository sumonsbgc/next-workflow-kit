---
id: 004
title: Search projects by name
status: todo
depends: 003
size: small
---

## Goal
Users can filter /projects by name with a ?q= query, and the filter survives reloads and sharing because it lives in the URL.

## Acceptance
- [ ] [review] /projects?q=web shows only projects whose name contains "web" (case-insensitive)
- [ ] [review] searchParams are awaited and validated before use
- [ ] [browser] An empty result shows "No projects match"
- [ ] [review] The search input is a plain GET form, so it works without JavaScript

## Notes
Out of scope: debounced live search.
