---
id: 003
title: Projects page with archive
status: todo
depends: 002
size: large
---

## Goal
Signed-in users see their own active projects at /projects and can archive one. This is the first page that mutates data, so it sets the pattern for authorization.

## Acceptance
- [ ] [review] /projects lists only the signed-in user's non-archived projects (lib/projects.ts listProjectsByOwner + getSession)
- [ ] [review] The heading uses projectCountLabel from task 002
- [ ] [test] archiveProject Server Action rejects a project owned by another user and changes nothing
- [ ] [test] archiveProject validates its input with a zod schema in lib/validation/
- [ ] [browser] Signed-out users (no eval_user cookie) are redirected to "/"
- [ ] [browser] After archiving, the project disappears from the list

## Notes
Auth is lib/session.ts getSession() (reads the eval_user cookie); data is lib/projects.ts. Out of scope: un-archive, pagination.
