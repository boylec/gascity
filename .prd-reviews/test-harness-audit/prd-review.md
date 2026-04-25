# PRD Review: Test Harness Audit & Async Event Handler Coverage

## Executive Summary

Six independent review legs analyzed the PRD from requirements, gaps, ambiguity, feasibility, scope, and stakeholder perspectives. All six converged on the same core finding: **the PRD identifies the right problem but proposes the wrong shape of solution.** The document bundles a documentation exercise (inventory audit), an organizational process (QE coordination), and the actual deliverable (integration tests) into a single waterfall-shaped plan, when the PR review feedback demands one thing: prove these async handlers work.

The feasibility review uncovered that the codebase is already well-structured for testability — handler functions are cleanly separated from Dapr routing. The existing `_test.ts` files exercise full Hono route handlers but use in-memory repositories. The highest-value gap is **handler integration tests against real PostgreSQL**, not full Kafka-through-Dapr e2e. The `deno-integration` CI job already provides PostgreSQL infrastructure. This reframing reduces the effort from "build Kafka-in-CI infrastructure" to "swap in-memory repos for Pg repos in handler tests."

**Consensus confidence: MEDIUM.** The PRD is directionally correct but needs one revision pass before implementation.

## Before You Build: Critical Questions

These must be answered before implementation begins. They emerged independently from multiple review legs, signaling high importance.

### 1. What kind of test are we actually writing? (Ambiguity, Feasibility, Requirements)

The PRD uses "integration test," "e2e test," and "contract test" interchangeably. The feasibility review found three distinct options with very different cost profiles:

- **Handler-level Pg integration tests** (~30s CI overhead): Call handler functions directly with real PostgreSQL repos instead of in-memory mocks. No Dapr, no Kafka. Tests business logic + DB correctness.
- **Dapr HTTP integration tests** (minutes of CI overhead): Start Dapr sidecar in slim mode, POST CloudEvents to handlers. Tests routing + parsing + business logic, but no event bus.
- **Full async e2e through Kafka** (5+ min CI overhead, significant YAML complexity): Requires Kafka broker, Schema Registry, Dapr, PostgreSQL in CI. Tests the complete event path.

The PRD's Non-Goals say "not modifying CI infrastructure" — this rules out option 3. **Recommend option 1 as the MVP**, with option 2 as a stretch goal. Define the chosen tier explicitly in the PRD.

### 2. Which handlers actually have testable side effects? (Feasibility)

Of the five handlers listed in G3:
- `tenant-provisioned-handler`: Rich side effects (taxonomy creation in PostgreSQL) — **testable now**
- `characteristic-projection-handler` (quality-rules): Side effects (reference upsert) — **testable now**
- `operational-context/dapr-subscriptions`: Routes to 16 aggregate handlers that **only log and return SUCCESS** — no DB side effects to verify
- `operational-components/dapr-subscriptions`: Handler has a `TODO: persist AclResult` — **no persistence layer to test yet**
- `quality-rules/dapr-subscriptions`: Routes to handler above — testable through the handler

G3's "cover every async handler" is not achievable for handlers that have no side effects. The PRD must acknowledge this and scope G3 to handlers with observable outcomes.

### 3. Does the existing e2e suite already cover any Dapr event paths? (Scope, Gaps)

`tests/e2e/specs/api/tenant-provisioning-and-tiers.spec.ts` exists. If it already exercises the async subscriber path (even indirectly), the gap is smaller than assumed. **This is a 1-hour investigation that directly affects scope.** Answer before designing new tests.

### 4. Who decides the test pattern if QE disagrees? (Requirements, Ambiguity, Stakeholders)

The PRD sequences QE sync before implementation but defines no escalation path, decision owner, or timeout. If QE is unresponsive for two sprints or wants a pattern incompatible with the existing `_test.ts` convention, what happens? Name the decision-maker.

### 5. Who owns these tests after merge? (Gaps, Stakeholders)

No ownership model is defined. On a direct-merge branch (ADR-024), a broken integration test hits trunk immediately. The PRD must state: BC team that owns the handler, or QE? And who triages flaky tests?

## Important But Non-Blocking

### Scope: Restructure into MVP + follow-up

The scope review recommends:
- **MVP**: Answer questions 1-3 above (2-3 hours of spikes), then write handler-level Pg integration tests for the 2-3 handlers with real side effects (G2/G3).
- **Follow-up phase 1**: Full test inventory (G1), QE coordination (G4).
- **Follow-up phase 2**: CI pipeline integration, remaining handler coverage as those handlers gain side effects.

This delivers the PR review response faster and avoids gating real work behind a documentation exercise.

### Rollout safety on direct-merge trunk (Gaps)

New tests should be introduced as non-blocking (allow-failure) in CI for a stabilization period before becoming gating. The PRD should specify: Phase A (opt-in/tagged), Phase B (allow-failure in CI), Phase C (gating after N consecutive green runs).

### Security stakeholder for tenant provisioning (Stakeholders)

The `tenant-provisioned-handler` is in the identity→operational-context event chain. If it misbehaves, a tenant could end up partially provisioned with incorrect access boundaries. InfoSec should review the test scenarios for this handler.

### Terminology precision (Ambiguity)

Define these terms once in the PRD and use consistently:
- "Integration test" = handler function called directly with real DB, no Dapr
- "E2e test" = full-stack Playwright test through the API surface
- "Contract test" = verify Dapr subscription discovery + CloudEvent schema without event bus
- "The existing harness" = specify which of the four test locations is meant in each context

### Definition of Done for each goal (Requirements)

Add binary pass/fail acceptance criteria. Example for G3: "Each handler with database side effects has at least one `_integration_test.ts` file that asserts on PostgreSQL state after handler execution, running in the `deno-integration` CI job."

### Identity-side publisher coverage (Gaps)

The PRD only tests the subscriber side. If the identity BC publishes a malformed or schema-drifted event, subscriber-side tests won't catch it. Clarify whether tests start from the identity publish call or from a synthetic event at the Dapr boundary — and if the latter, acknowledge the gap.

## Observations and Suggestions

- The PRD is well-grounded in PR enterprise#405, giving it concrete urgency. The problem statement and non-goals are clear and appropriate.
- The codebase architecture is already test-friendly: clean handler/router separation, existing `deno-integration` CI job with PostgreSQL, co-located `_test.ts` patterns. The infrastructure cost of the MVP is low.
- The Rough Approach is logically sequenced but waterfall-shaped. For what is fundamentally "write 2-3 integration tests," a focused spike (pick tenant-provisioned-handler, prove the pattern, replicate) would deliver faster.
- The existing PDHC tests (`async.pdhc.spec.ts`) already validate Dapr subscription discovery and service health in CI with a slim Dapr sidecar. The gap is not "Dapr routing is untested" but "handler business logic uses mocks instead of real DB."
- G1 (inventory) has value beyond this plan — onboarding, architecture reviews, compliance — but should not gate G2/G3 implementation.

## Confidence Assessment

| Leg | Confidence | Key Concern |
|-----|-----------|-------------|
| Requirements | Low-Medium | No testable acceptance criteria, failure modes unaddressed |
| Gaps | Medium | Rollout strategy and ownership model missing |
| Ambiguity | Medium | Terminology inconsistency, "existing harness" undefined |
| Feasibility | High (architecture), Medium (PRD as written) | PRD ambiguity could lead to over-engineering |
| Scope | Medium-High | MVP buried under process overhead |
| Stakeholders | Medium-High | Security stakeholder absent, ownership tension unresolved |

**Overall: The PRD needs one revision pass addressing the 5 critical questions above before proceeding to implementation.**

## Next Steps

1. Present the 5 critical questions to the human for clarification.
2. Incorporate answers into a revised PRD draft.
3. Proceed to design phase with the clarified scope.
