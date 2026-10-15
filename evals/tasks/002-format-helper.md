---
id: 002
title: Project count label helper
status: todo
depends:
size: small
---

## Goal
A pure helper turns a number of projects into a label ("No projects", "1 project", "3 projects") so pages never hand-roll pluralisation.

## Acceptance
- [ ] [test] projectCountLabel(0) === "No projects"
- [ ] [test] projectCountLabel(1) === "1 project"
- [ ] [test] projectCountLabel(3) === "3 projects"
- [ ] [review] Lives in lib/utils/, has no React imports

## Notes
Vitest is installed. Out of scope: i18n.
