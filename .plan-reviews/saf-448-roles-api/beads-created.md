# SAF-448 Roles API — Beads Created

**Convoy**: `hq-gtw9f` (saf-448-roles-api)
**Design reference**: `.designs/identity-rbac-api/design-doc.md` (Phases 1+3)

## Task Beads

| ID | Title | Tier | Phase | Dependencies |
|----|-------|------|-------|-------------|
| hq-gmgo3 | Role + Permission Drizzle schema and seed migration | sonnet | 1 | — |
| hq-n3i9t | Role aggregate and PgRoleRepository | opus-high | 1 | hq-gmgo3 |
| hq-8shht | PermissionResolver refactor (sync to async + DB) | opus-high | 1 | hq-gmgo3 |
| hq-6njbj | Read-only Permissions API (2 endpoints) | sonnet | 1 | hq-gmgo3 |
| hq-3iyl5 | Roles API route handlers (5 endpoints) | sonnet | 2 | hq-n3i9t |
| hq-kak41 | Unit and integration tests for Roles API | opus-high | 3 | hq-3iyl5, hq-8shht |

## Tier Summary
- **sonnet** (3): schema+seed, permissions API, roles routes
- **opus-high** (3): Role aggregate+repo, PermissionResolver refactor, tests

## Note
Design sourced from identity-rbac-api design doc. Existing convoy hq-cm6lf covers broader scope — this convoy focuses on SAF-448 (Roles API) specifically.
