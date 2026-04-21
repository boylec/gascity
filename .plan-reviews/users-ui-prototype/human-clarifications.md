# Human Clarifications Checkpoint — SAF-446 Users UI Prototype

**Date:** 2026-04-21
**Coordinator:** quartermaster-hq-1ae (sc-03umw)
**Review ID:** users-ui-prototype
**Linear:** SAF-446

## Outcome

Human directive: **"accept your best recommendations"** (blanket approval of the review's ADR-grounded guidance).

Full Q&A written into `.prd-reviews/users-ui-prototype/prd-draft.md` under the "Clarifications from Human Review" section. No scope-material changes to Goals/Non-Goals needed — the Phase 1 rescope (All-Keycloak, no hard delete) is the biggest shift, already captured.

## Decision summary

| # | Question | Resolution |
|---|----------|------------|
| 1 | Storage architecture | Path A — All-Keycloak. ADR addendum to be drafted. |
| 2 | Delete semantics | Soft delete only. Hard delete out of scope. |
| 3 | KeycloakAdminPort ops | Add 7 (no deleteUser per Q2). |
| 4 | Gateway routing | Explicit `/identity/users/*` route; BFF paths untouched. |
| 5 | Role naming | `manager` (lowercase). Update PRD + UI copy. |
| 6 | Audit trail | Keycloak events feed primary; projection deferred to Phase 3. |

## Context for downstream steps

- `design-exploration` should treat Phase 1 as "KeycloakAdminPort expansion + gateway routing + identity-api /users endpoints" — **not** as "create users table".
- `prd-align-*` steps should validate Goals/Non-Goals against the above — expect Goal 2 wording change (remove "delete"), Goal 6 narrowing, and a new Non-Goal line for "hard delete / user table creation."
- Phase estimates should be updated: Phase 1 is bigger than the draft implied (7 new adapter ops + gateway + routes + frontend wiring for the existing scaffold).

## Unblock note

This checkpoint was written by the mayor on the human's behalf after the quartermaster's `human-clarify` step stalled — the upstream step asks for in-chat answers, but SafetyChain's quartermaster runs in a pool session the human isn't attached to. Same root-cause class as `sc-plan-approval` (pre-existing SafetyChain wrapper fix). The wrapper is being extended to make `human-clarify` mail-gated too, so future runs won't require manual unblock.
