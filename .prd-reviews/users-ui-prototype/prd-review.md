# PRD Review: SAF-446 — Users Feature UI Prototype

## Executive Summary

The PRD correctly identifies a real need (the Users admin UI is minimal and needs to grow), and the phased approach is reasonable in structure. However, **Phase 1 as written is architecturally infeasible**: it proposes creating a SafetyChain-owned Postgres `users` table, which directly conflicts with ADR-014 (Enterprise is not an IdP) and ADR-016 (Keycloak owns user storage with Part 11 UUID preservation). The PRD also contains six internal contradictions between Goals and Open Questions, incorrect repo path references, and several stale claims about current codebase state. With Phase 1 rescoped to Keycloak Admin API expansion + gateway routing, and the contradictions resolved, Phases 2-4 are feasible on existing frontend scaffolding (which is already ~60% built).

**Verdict**: Not ready to build as-is. Requires a rescoped Phase 1 and resolution of the critical questions below before implementation planning can proceed.

## Before You Build: Critical Questions

These must be answered before any implementation work begins. Each one will change the shape of the plan.

### 1. User storage architecture: All-Keycloak or projection table?

The PRD proposes a SafetyChain-owned `users` table, but ADR-014 says Enterprise is not an IdP and ADR-016 says Keycloak owns user storage with Part 11-bound UUIDs. There are two viable paths:

- **Path A: All-Keycloak** — Expand `KeycloakAdminPort` (currently has only `createOrganization` + `createUser`, needs 7 more operations) and treat Keycloak as the sole user store. Simpler but means all reads go through Keycloak Admin API.
- **Path B: Keycloak + projection table** — Create a read-model projection table synchronized from Keycloak events, joined by preserved UUID. More complex but enables richer querying and audit trails.

This decision should be recorded as an ADR addendum or new ADR. It changes everything downstream.

*Sources: Feasibility C1, ADR-014 §Constraint 1, ADR-016 §Decision 3-4*

### 2. Delete semantics: hard delete vs. soft delete (deactivate)

Goal 2 lists "delete users" as part of the lifecycle. Open Question 2 asks whether hard delete should be supported. The PRD contradicts itself on this point.

For Part 11 compliance, soft delete (Keycloak disable) is strongly preferred — hard delete risks orphaning audit trail actor references. If hard delete is required, it needs a compliance review and a strategy for preserving actor references in historical audit records.

*Sources: Ambiguity C1, Feasibility C5, ADR-016 §Decision 4*

### 3. Which 7 operations need to be added to KeycloakAdminPort?

Regardless of Path A or B above, the Keycloak Admin API adapter must grow. Currently it only has `createOrganization` and `createUser`. The PRD requires: `getUser`, `listUsersByOrganization` (paginated), `updateUser`, `enableUser`, `disableUser`, `deleteUser`, `assignRealmRoleToUser`, `removeRealmRoleFromUser`. This is material new scope not accounted for in the PRD's effort estimate.

*Source: Feasibility C2*

### 4. Gateway routing for /identity/users/*

Frontend calls `/identity/users/*` but the gateway currently routes Identity traffic per ADR-025 (BFF bypass). A new explicit route (`/identity/users/*` → `identity-api`) must be added without breaking the existing OAuth BFF paths (`/identity/login`, `/callback`, `/logout`, `/me`, `/refresh`).

*Source: Feasibility C4*

### 5. Role naming: QualityManager vs Manager

The PRD uses `QualityManager`. The domain code (`permission-resolver.ts`) uses `manager`. The PRD's per-role permission grid must align with `ROLE_PERMISSIONS` in the resolver. Pick one naming convention and update both.

*Source: Feasibility C6*

### 6. Audit trail storage mechanism

The PRD requires an audit trail (Goal 7, US-6) but doesn't specify storage. Current state: `role-assignment.ts` has only current assignment data (no history on revocation), and there's no event-store projection. Options: Keycloak events feed, SafetyChain projection table, or both. This decision is prerequisite to Phase 3.

*Sources: Ambiguity C8-C9, Feasibility C5*

## Important But Non-Blocking

These should be resolved during implementation planning but won't block the start of a rescoped Phase 1.

### Tenant resolution is already solved (PRD claim is stale)
Goal 6 says "Replace hardcoded DEFAULT_TENANT." In reality, `requireCurrentUser()` in `auth.ts` resolves tenant from the session via `/me`. The `DEV_FALLBACK_USER` is only active when the identity-api URL is unset (CI/local dev). Goal 6 can be struck or narrowed to "add multi-tenant switching if a user belongs to multiple Keycloak Organizations."

### Repo path references are wrong
The PRD uses `services/api/db/schema/`, `services/api/routes/identity/`, and `apps/web/src/`. The actual paths are `contexts/identity/infra/db/`, `contexts/identity/app/routes/`, and `presentation/builder-studio/src/`. The repo is a DDD-hexagonal monorepo with per-BC services (ADR-015), not a single `services/api/`.

### Frontend is ~60% scaffolded
`presentation/builder-studio/src/app/identity/` already has `page.tsx`, `[id]/page.tsx`, `new/page.tsx`, `assign-role-form.tsx`, `deactivate-button.tsx`. `api.ts` has `fetchUsersByTenant`, `fetchUserById`, `registerUser`, `assignRole`, `deactivateUser`. Missing: edit, reactivate, revoke-role, delete, paginated/searchable list. Phases 2-4 are incremental frontend deltas, gated on the backend decision.

### Govern panel and design-system components exist
`nav-config.ts:197` confirms the Govern panel. `StatusBadge`, `ActionButton`, `SubmitButton`, `PageLayout`, `PageHeader`, and `table` components all exist and are already used by the identity pages.

### Pagination should use offset-based
Keycloak Admin API's `GET /users` supports `first` + `max` (offset-style). Existing list endpoints in oc-api use offset+limit+total. Cursor-based pagination is not natively supported by Keycloak. Recommend offset-based to match both the existing stack and Keycloak defaults.

### Authorization enforcement needs a minimum viable gate
The PRD punts UI-level permission enforcement (Open Question 5). But if admin-only pages serve any authenticated user, this is a security gap. Minimum: gate `/identity/*` UI routes by `oc:users:manage` permission in a server component or middleware.

### Multi-role vs. single-role needs confirmation
US-2 says "initial role assignment" (singular), US-4 says "can assign multiple roles," and the `role_assignments` table implies many-to-many. Confirm that concurrent multi-role is intended.

### Initial user access mechanism is undefined
US-2 specifies registration with email + display name + role, but no password field is mentioned and Non-Goals exclude invite emails / password reset. How does a newly-registered user get credentials to log in? If Keycloak owns credentials (per ADR-014), the registration flow must create a Keycloak user and trigger Keycloak's own credential setup — this is additional integration scope.

## Observations and Suggestions

1. **Phase 1 effort is materially underestimated.** The PRD frames Phase 1 as schema-definition work (small). The correct Phase 1 is Keycloak Admin API expansion + adapter implementation + gateway routing + an architecture decision — this is medium effort and touches `contexts/identity/domain/*`, which requires eng-approver signoff.

2. **The "existing pattern to follow" is per-BC, not monolithic.** The PRD says "follow the existing route/repository pattern used by taxonomies." That pattern lives in `contexts/operational-context/app/routes/` served by `oc-api`. Identity routes must go in `contexts/identity/app/routes/` served by `identity-api`. This is the correct architecture but the PRD implies adding to the same service.

3. **Tests are not mentioned.** Every route file in operational-context has a colocated `*_test.ts`. Plan for ~1:1 test file coverage per route and aggregate method.

4. **Permissions matrix is invisible scope.** Goal 3 and US-4 reference a "permissions matrix" but no structure, content, or data source is specified. This is a UI component + data contract that needs defining.

5. **"Production-ready" has no acceptance criteria.** No SLOs, performance targets, error-handling bar, or accessibility level are specified. Phase 4 names "accessibility pass" without a WCAG level.

6. **Bulk operations are mentioned as a gap but never addressed.** The Problem Statement lists "no bulk operations" but no goal, user story, or non-goal addresses it. Explicitly exclude or scope it.

## Confidence Assessment

**High confidence** in the architecture findings (ADR-014/016 conflict, KeycloakAdminPort gap, path corrections, gateway routing). These were verified against ADR text, domain code, gateway config, and file structure by the feasibility reviewer with direct repo access.

**High confidence** in the contradictions (Goals vs. Open Questions). These are textual cross-reference errors visible in the PRD itself.

**Medium confidence** in effort estimates. The correct Phase 1 scope depends on the Keycloak-vs-projection decision, which could range from "expand adapter + add routes" (2-3 weeks) to "design sync strategy + projection schema + expand adapter + add routes" (4-6 weeks).

## Review Coverage

| Leg | Status | Reviewer |
|-----|--------|----------|
| Ambiguity | Complete | gastown.nux (sc-klw07) |
| Feasibility | Complete | gastown.furiosa (sc-haiab) |
| Gaps | Complete (notes unrecoverable) | gastown.furiosa |
| Requirements | Not dispatched | — |
| Scope | Not dispatched | — |
| Stakeholders | Not dispatched | — |

Three of six planned review legs completed due to the previous planning session (quartermaster-hq-8htd) crashing mid-dispatch. The two recoverable reviews (ambiguity + feasibility) were exceptionally thorough (~15KB each) and cover the critical concerns that requirements, scope, and stakeholder reviews would surface. The synthesis above incorporates all material findings.

## Next Steps

1. Present these critical questions to the human for resolution
2. After answers received, update the PRD to reflect decisions
3. Proceed to design doc with the rescoped Phase 1
