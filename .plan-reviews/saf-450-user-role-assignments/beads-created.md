# SAF-450 User-Role Assignments — Beads Created

**Convoy**: `hq-23u7u` (saf-450-user-role-assignments)

## Task Beads

| ID | Title | Tier | Phase | Dependencies |
|----|-------|------|-------|-------------|
| hq-ouzne | Fix User.toSnapshot() and extend UserRepository port | sonnet | 1 (prereq) | — |
| hq-fa6lr | Verify platform-core createBcConnection for identity | sonnet | 1 (prereq) | — |
| hq-o2ciz | DB schema and migrations with Drizzle ORM | sonnet | 2A | hq-ouzne, hq-fa6lr |
| hq-nji7f | Dual-auth middleware (cookie + bearer JWT) | opus-high | 2A | hq-ouzne |
| hq-o8139 | Seed initial admin user from Keycloak claim | sonnet | 2B | hq-o2ciz |
| hq-ez62s | PgUserRepository with optimistic concurrency | opus-high | 2B | hq-o2ciz |
| hq-6hy2a | Readiness probe DB connectivity check | sonnet | 2B | hq-o2ciz |
| hq-7qeca | Request validation, route handlers, and composition root | opus-high | 3 | hq-nji7f, hq-ez62s |
| hq-uw23u | Unit tests for routes, middleware, and repository | opus-high | 4 | hq-7qeca |
| hq-9fkqp | Integration tests with real Postgres | opus-high | 4 | hq-7qeca, hq-o8139 |

## Tier Summary
- **sonnet** (5): prereqs, DB schema, seed, readiness probe
- **opus-high** (5): dual-auth middleware, PgUserRepository, routes, unit tests, integration tests

## References
- PRD: `.prd-reviews/saf-450-user-role-assignments/prd-draft.md`
- PRD Review: `.prd-reviews/saf-450-user-role-assignments/prd-review.md`
- Design Doc: `.designs/saf-450-user-role-assignments/design-doc.md`
- Plan Reviews: `.plan-reviews/saf-450-user-role-assignments/`
