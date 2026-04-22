# Implementation Beads — SAF-446: Users Feature UI Prototype

**Convoy:** hq-pzmfp
**Linear:** SAF-446
**Created:** 2026-04-22
**Coordinator:** quartermaster-1

## Beads (10 tasks, 3 opus-high / 7 sonnet)

| # | Bead ID | Title | Tier | Blocked By |
|---|---------|-------|------|------------|
| 1 | hq-72ak9 | Permission gate + CSRF protection for identity user routes | opus-high | — |
| 2 | hq-772a7 | Add 7 operations to KeycloakAdminPort + adapter | opus-high | — |
| 3 | hq-426ex | Add reactivate method to User aggregate | sonnet | 2 |
| 4 | hq-gyfcp | Add identity-api cluster + user routes to YARP gateway | sonnet | — |
| 5 | hq-dz2cl | Create identity-api user management routes (9 endpoints) | opus-high | 1, 2, 3 |
| 6 | hq-5aof4 | Users list page with pagination, search, and filters | sonnet | 4, 5 |
| 7 | hq-y66e7 | User detail page + edit profile form | sonnet | 6 |
| 8 | hq-skort | Deactivation, reactivation, and role management UI | sonnet | 7 |
| 9 | hq-qgarr | Audit trail timeline on user detail page | sonnet | 7 |
| 10 | hq-mouyj | UI polish — validation, dialogs, error states, accessibility | sonnet | 6, 8, 9 |

## Dependency DAG

```
1 (security)  ──┐
2 (port)  ──────┼──► 5 (routes) ──► 6 (list) ──► 7 (detail) ──┬──► 8 (mgmt) ──► 10 (polish)
3 (reactivate)─┘       │                          └──► 9 (audit) ──┘
4 (gateway) ───────────┘
```

## Artifacts

- PRD: `.prd-reviews/users-ui-prototype/prd-draft.md`
- PRD Review: `.prd-reviews/users-ui-prototype/prd-review.md`
- Human Clarifications: `.plan-reviews/users-ui-prototype/human-clarifications.md`
- Design Doc: `.designs/users-ui-prototype/design-doc.md`
- Design Reviews: hq-n6is (api), hq-vihk (data), hq-me2b (ux), hq-53a4 (scale), hq-l7gk (security), hq-gpxl (integration)

## Dispatch

```bash
gc sling hq/mayor mol-sc-sling-convoy --formula --var convoy_id=hq-pzmfp
```
