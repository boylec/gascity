# Human Clarifications Checkpoint — saf-450-user-role-assignments

**Coordinator:** quartermaster-2
**Mode:** autonomous (require_human_approval=false)
**Resolution:** accepted review recommendations verbatim
**Date:** 2026-04-26

See `.prd-reviews/saf-450-user-role-assignments/prd-review.md` for the
questions and the recommended answers that were accepted.

| # | Question | Resolution |
|---|----------|------------|
| 1 | Auth mechanism | Dual cookie+bearer middleware, extract tenantId+actorId |
| 2 | Authorization model | `oc:users:manage` for writes; any authed user for reads |
| 3 | `:roleId` semantics | Rename to `:roleName`, commit to string key |
| 4 | `toSnapshot()` bug | Fix to include `audit` field |
| 5 | `UserRepository` port | Add `findByTenantAndId(tenantId, userId)` |
| 6 | `/me` source of truth | Keycloak for now; DB reconciliation deferred |
| 7 | Downstream BCs | Acknowledged; coordination section in design doc |
