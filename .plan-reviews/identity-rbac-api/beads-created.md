# Beads Created: identity-rbac-api

**Convoy**: hq-cm6lf (identity-rbac-api, owned)
**Created by**: quartermaster-hq-w4qmu (quartermaster-2)
**Date**: 2026-04-21

## Task Beads (13)

| Phase | Bead ID | Title | Tier | Dependencies |
|-------|---------|-------|------|-------------|
| 0 | hq-tg857 | Identity BC Database Bootstrap | opus-high | — |
| 1 | hq-0dqcw | Permission & Role schema + seed migration + perm prefix | sonnet | hq-tg857 |
| 1 | hq-pdmtw | PermissionResolver refactor (sync->async+DB) | opus-high | hq-0dqcw |
| 1 | hq-jxkzt | Permission resolution pipeline in auth middleware | opus-high | hq-pdmtw |
| 1 | hq-8ztw4 | Read-only Permissions API | sonnet | hq-0dqcw |
| 2 | hq-nr91t | User-role assignment schema + RoleAssignment VO migration | sonnet | hq-0dqcw |
| 2 | hq-nxzbi | KeycloakAdminPort expansion (5 ops) | sonnet | — |
| 2 | hq-gp611 | User aggregate updates (reactivate + role-ref) | opus-high | hq-nr91t |
| 3 | hq-m95e2 | Roles API (5 endpoints) | sonnet | hq-0dqcw |
| 3 | hq-a0o2w | Users API (6 endpoints, KC proxy) | opus-high | hq-nxzbi, hq-gp611 |
| 3 | hq-ahlrb | User-Role Assignments API (3 endpoints) | sonnet | hq-nr91t, hq-m95e2 |
| 3 | hq-achpy | Me endpoint (GET /api/v1/me) | sonnet | hq-jxkzt, hq-a0o2w |
| 4 | hq-c25lf | Gateway routing + ACL activation | opus-high | hq-jxkzt, hq-m95e2, hq-a0o2w, hq-ahlrb, hq-achpy |

## Parallelism Opportunities

- hq-nxzbi (Keycloak adapter) can start immediately in parallel with Phase 0/1
- After hq-0dqcw: three tasks can run in parallel (hq-pdmtw, hq-8ztw4, hq-nr91t, hq-m95e2)
- hq-8ztw4 (Permissions API) and hq-m95e2 (Roles API) can run in parallel

## Tier Summary

- **opus-high** (6): DB bootstrap, resolver refactor, resolution pipeline, user aggregate, users API, integration
- **sonnet** (7): schema+seed, permissions API, assignment schema, KC adapter, roles API, assignments API, me endpoint
