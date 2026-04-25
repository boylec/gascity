# PRD Review: Establish a mechanical shift-left enforcement that OpenAPI specs across all bounded contexts (identity, operational-context, operational-components, quality-rules, platform) always match the implemented API surface — neither under- nor over-documented — and that the Scalar-based documentation in builder-studio renders every BC's spec.

## Executive Summary

The PRD identifies a real problem — OpenAPI specs drifting from Hono route implementations — and proposes a sensible 4-phase approach. However, **the PRD is unaware that the core enforcement mechanism already exists**: `tests/architecture/openapi_parity_test.ts` (554 lines) performs static regex extraction of Hono routes, normalizes `:param` → `{param}`, diffs bidirectionally against OpenAPI YAML, and currently covers OC, QR, OCC, and OC-platform. The PRD's Phase 1 ("build a route extraction and comparison tool") and Phase 2 ("wire into build/lint/pre-commit") are largely implemented.

The remaining work is **incremental, not greenfield**:
1. Extend the existing parity test to cover **Identity BC** (the only unchecked BC, and the most security-critical)
2. Add **method-level checking** (currently only path parity, not HTTP method matching)
3. Update builder-studio's `fetchOpenApiSpec()` to include Identity and OCC specs in Scalar
4. Document the existing + new coverage

The PRD should be **reframed from "build" to "extend"** before proceeding to design.

## Before You Build: Critical Questions

These questions must be answered before design work begins. They surfaced independently across multiple review legs.

### 1. Have you read `tests/architecture/openapi_parity_test.ts`?
The PRD reads as if no enforcement exists. This 554-line file already implements the core of Phases 1-2. The PRD should explicitly acknowledge it and scope remaining work as extensions. Without this, developers may build a parallel system.

### 2. Which spec files map to which route sets?
There are 6 spec files across 4 BCs with **inconsistent directory structures**:
- `contexts/identity/app/api/openapi.yaml` → identity customer BFF routes
- `contexts/identity/app/platform/openapi.yaml` → identity platform admin routes
- `contexts/operational-context/app/api/openapi.yaml` → OC customer API routes
- `contexts/operational-context/app/platform/api/openapi.yaml` → OC platform routes
- `contexts/operational-components/app/api/openapi.yaml` → OCC component interfaces
- `contexts/quality-rules/app/api/openapi.yaml` → QR rules engine

Note: identity uses `app/platform/openapi.yaml` while OC uses `app/platform/api/openapi.yaml`. The mapping mechanism (manifest file? convention scan? hardcoded?) must be decided. The existing parity test uses a hardcoded `ADDITIONAL_CONTEXTS` array.

### 3. What is a "route" for purposes of the sync check?
The PRD uses "route surface" without definition. Each BC API has at least 3 categories:
- **Domain routes**: `/items`, `/users`, `/roles` — the business API
- **Infrastructure routes**: `/alive`, `/ready`, `/health`, `/version` — platform plumbing
- **Documentation routes**: `/openapi.json`, `/doc`, `/` — serve the spec itself

If infrastructure and documentation routes aren't carved out, the check will produce false positives for every `/alive`, `/health`, `/ready`, `/version`, `/openapi.json`, and `/doc` endpoint. Take a position.

### 4. What does "sync" mean — path+method or deeper?
Open Question #6 is a foundational scope decision, not an open question. Path+method-only sync is a few hundred lines of code and extends naturally from the existing test. Schema-level sync is an order of magnitude more complex and moves toward runtime contract testing (which the PRD explicitly excludes as a non-goal). The existing test checks path parity but **not** HTTP method parity. Recommend: commit to path+method as Phase 1 scope.

### 5. Static analysis or runtime introspection?
The existing parity test uses **static regex analysis** of route files — no app boot required. The PRD's Rough Approach proposes importing Hono apps and introspecting routes at runtime. **Runtime introspection is the wrong approach**:
- Each BC's `main.ts` connects to PostgreSQL, Redis, and Keycloak at import time — build-time introspection would fail without running infrastructure
- Identity mounts Google auth routes conditionally (`GOOGLE_OAUTH_CLIENT_ID`) — runtime introspection misses them without env vars
- Static analysis is already proven, requires no Deno permissions beyond file read, and runs in <1 second

### 6. How do you handle conditionally-mounted routes?
Identity BC mounts Google Workspace auth routes only when `GOOGLE_OAUTH_CLIENT_ID` is set. Static analysis finds the `app.route()` call regardless of env vars (which is the desired behavior — the spec should document what CAN be mounted). This should be documented as a design decision.

### 7. Should the identity customer API spec be served?
Identity's `main.ts` serves `/platform/openapi.json` but has NO `/openapi.json` endpoint for customer-facing routes. The customer API spec exists (`app/api/openapi.yaml`) but is never served. Is this intentional? If not, adding the endpoint is part of Phase 3.

## Important But Non-Blocking

### Phase 3 (Scalar coverage) is genuinely independent
Updating `fetchOpenApiSpec()` in builder-studio to include identity and OCC specs is a frontend rendering task, not a build-time enforcement concern. It should be a separate ticket. The frontend team should be consulted on the manifest design since they own the Scalar rendering.

### Phase 4 (CI guardrail) is already solved
The parity test runs as a Deno test in the architecture test suite, which runs in CI. Adding it to `just check` (Phase 2) provides the "can't forget" guarantee locally. A separate CI step adds marginal value. Consider deferring or eliminating.

### Phase 2's integration point
Don't introduce a new pre-commit hook. The repo's `.githooks/pre-commit` already exists. Wire the sync check into `just check` (which feeds `just preflight`) alongside existing checks (`check-agent-surfaces`, `check-versions`, `check-age-gate`). This is consistent with existing patterns and means Phase 2 is just wiring — fold it into Phase 1's definition of done.

### Stakeholders not addressed in the PRD
- **Frontend team**: Directly affected by spec drift — Scalar shows incorrect docs
- **QE team**: API contract tests become unreliable if specs diverge from implementation
- **eng-infra/gateway team**: Gateway routing has path prefix transformations that could affect spec accuracy
- **Operator/maintainer**: Who owns the sync check script long-term? Needs a CODEOWNERS entry

### New BC auto-discovery
The existing test has a hardcoded BC list — a new BC added without an entry silently passes. User Story #4 ("New BC: check reports no openapi.yaml") requires either a directory-scan convention or a manifest file. This is a genuine enhancement over the current state.

### Gateway path prefix complexity
The YARP gateway strips/rewrites paths (e.g., `/quality-rules/{**remainder}` → `/{**remainder}`). The sync check validates local spec-to-route sync but won't catch gateway-level mismatches. Clarify whether gateway routing validation is in scope.

### Per-BC rollout strategy
Each BC team has different spec maturity. OC has 172 `x-sc-dev-*` annotation references; others may be less mature. If the check enforces the same strictness immediately across all BCs, teams with less-developed specs face high initial failure rates. Consider per-BC opt-in or phased rollout.

### Security: allow-list for undocumented routes
Some internal/admin routes may be intentionally undocumented. The sync check should support an ignore-list so that intentionally undocumented routes don't trigger false positives.

## Observations and Suggestions

1. **Reframe the PRD from "build" to "extend."** The existing `openapi_parity_test.ts` is the foundation. The PRD should reference it explicitly and scope remaining work as incremental improvements.

2. **Start with Identity BC as the vertical slice.** Identity is the smallest BC (437-line spec, 3 route modules), the most security-critical (OAuth2/OIDC, RBAC, tenant provisioning), and the only one not currently covered. Proving the approach here validates it before touching the 6200-line OC spec.

3. **Collapse Phases 1+2 into a single deliverable.** Phase 2 is "wire into build/lint" — with the existing infrastructure, this is just adding `identity` to the `ADDITIONAL_CONTEXTS` array and verifying `just check` runs it. It's not a separate phase.

4. **Split Phases 3 and 4 into separate tickets.** Phase 3 (Scalar coverage) is independent frontend work. Phase 4 (CI guardrail) is already effectively done. Neither should block the core enforcement extension.

5. **Open Questions 1 and 2 are already answered.** The existing code uses static regex analysis (not runtime introspection) and handles `:param` → `{param}` normalization. Remove these from the "open" list.

6. **Add measurable acceptance criteria.** Each goal should specify concrete pass/fail metrics: which BCs, which spec files, path+method or deeper, zero tolerance or per-BC phasing.

7. **The "Rough Approach" reads as a design doc, not requirements.** Consider separating "what we need" (PRD) from "how we'll build it" (design doc). The Phases 1-4 implementation detail belongs in the design phase.

## Confidence Assessment

**Confidence: HIGH** across all 6 review dimensions. All reviewers independently examined the codebase, read the OpenAPI specs, inspected route registration patterns, and analyzed the existing parity test. The most significant finding — that Phase 1-2 are largely already implemented — was corroborated by requirements, gaps, and feasibility reviews independently.

The core requirements are sound. The main risk is **commissioning greenfield work that duplicates existing infrastructure**. With the PRD reframed to "extend," this initiative reduces from a multi-phase build to a focused Identity BC integration + Scalar coverage update.

## Next Steps

1. **Revise the PRD**: Acknowledge existing parity test, reframe as "extend," resolve the critical questions above
2. **Proceed to human clarification gate**: Present the critical questions to the human for decisions
3. **After clarification**: Update PRD, then proceed to design doc phase

---

*Synthesized from 6 parallel review legs dispatched to enterprise/claude-opus-high. Review beads: sc-cgib1 (requirements), sc-1nolp (gaps), sc-8t4xn (ambiguity), sc-ujto0 (feasibility), sc-f94jn (scope), sc-el1sn (stakeholders).*
