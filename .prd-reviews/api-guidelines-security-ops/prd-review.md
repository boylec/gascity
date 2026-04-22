# PRD Review: SAF-88 — API Guidelines: Security, Operations & Extensibility

## Executive Summary

The PRD accurately identifies the remaining work but significantly **overestimates Phase 1 difficulty**. The feasibility review found that sections 04 (Response Envelope) and 23 (Tooling) are stubs that document *already-implemented infrastructure* — `platform-core/http/responses.ts` fully implements the envelope pattern, and the OTEL/structured-logging stack is complete. Phase 1 is near-zero risk documentation work.

The real complexity lives in Phase 4 (implementation). Rate limiting and idempotency are technically bounded (Redis middleware, well-understood patterns) but face an architectural inconsistency: section 16 specifies `X-Tenant-Id` header for rate limit scoping, but the auth middleware derives tenantId from JWT `org_id` claims — no such header exists anywhere. Additionally, there's no shared middleware root across 4 BCs, so any new cross-cutting middleware requires parallel changes everywhere.

Webhook delivery (section 20) depends on Debezium/Kafka pipeline production readiness, which is unconfirmed beyond local dev. Hypermedia (section 19) is the most disruptive change — lowest priority, highest churn.

**Verdict**: Phases 1-3 are high-feasibility, low-risk. Phase 4 is mixed and should be scoped per-section based on the conformance audit.

## Before You Build: Critical Questions

### 1. Rate limiting tenant identification: X-Tenant-Id header vs. JWT claim

Section 16 specifies per-tenant limits identified by `X-Tenant-Id` header. The auth middleware (`platform-core/http/middleware/auth.ts`) derives tenantId from JWT `org_id` — no such header exists. The rate limiting middleware should read from `authenticatedIdentity` in the Hono context, or the guideline needs correction. Resolve before implementation.

### 2. Section 04 ownership: SAF-88 or separate issue?

Section 04 was part of SAF-67's original scope (sections 1-14). The PRD includes it. The content is trivial (document existing response helpers). Recommendation: include in SAF-88 Phase 1 since it's just documentation of existing code.

### 3. External API consumers: do they exist?

The stakeholders review found that sections 04, 15, 16, and 20 define observable contracts for API callers. If SafetyChain has external integration partners, changing response envelopes or adding rate limiting headers is a breaking change requiring a communication plan. The PRD is silent on this.

### 4. GxP/Part 11 compliance review

Auth (section 15), rate limiting fault attribution (section 16), and audit trail (section 17 idempotency keys) have compliance implications. The conformance audit (Phase 2) should include a compliance lens, or compliance gaps will be missed and require rework.

## Important But Non-Blocking

### Sections 04 and 23 are documentation-only (no design needed)
- **Section 04**: `okResponse` → `{ data }`, `createdResponse` → `{ data }` + Location, `listResponse` → `{ data, pagination }`, `noContentResponse` → 204. Error: RFC 9457 Problem Details. All in `platform-core/http/responses.ts`.
- **Section 23**: Full OTEL stack operational — `--unstable-otel`, `telemetryMiddleware()`, `x-request-id`, `X-Correlation-Id` via AsyncLocalStorage, structured JSON logging, custom metrics, Aspire AppHost.

### No shared middleware composition root
All 4 Deno services have independent `main.ts`. New middleware (rate limiting, idempotency) needs parallel additions to each. The `complianceFirewallMiddleware` pattern is the right template.

### Health check conformance is partial
`/alive`, `/ready`, `/health` exist in the platform-facing OC API. The business-facing API may not have them. Conformance audit will clarify.

### OpenAPI parity CI is aspirational
Four hand-authored OpenAPI YAML files exist. Hono lacks automatic schema extraction (not using `@hono/zod-openapi`). CI validation requires integration tests or snapshot comparison.

### CLAUDE.md Key References may already be partially done
The `.claude/rules/api-routes.md` file exists (11KB). Verify before filing a task.

## Observations and Suggestions

1. **Reorder implementation priority**: Auth conformance > response envelope docs > health checks > rate limiting > idempotency > OpenAPI CI > tooling docs > webhooks > hypermedia. Hypermedia last — highest churn, lowest value-add at current maturity.

2. **Fix section 16 before implementation**: Update the rate limiting guideline to reference `authenticatedIdentity.tenantId` from Hono context rather than a nonexistent `X-Tenant-Id` header.

3. **Scope Phase 4 to operational-context only**: Use OC as the reference implementation BC. Other BCs follow in subsequent convoys.

4. **Mark webhook implementation explicitly deferred**: Acknowledge the Debezium/Kafka pipeline dependency and defer webhook delivery engine to a separate initiative.

5. **Add external consumer stakeholder entry or explicit exclusion**: Either add a communication plan or state "no external consumers today" as a constraint.

## Confidence Assessment

| Phase | Confidence | Notes |
|-------|-----------|-------|
| Phase 1 (docs) | High | Documenting existing code. Near-zero risk. |
| Phase 2 (audit) | High | Read-only analysis of mature codebase. |
| Phase 3 (backlog) | High | Mechanical output of Phase 2. |
| Phase 4 (implementation) | Mixed | Auth/health: high. Rate limiting/idempotency: medium (Redis + middleware, but BC proliferation). Webhooks: low (pipeline dependency). Hypermedia: low (maximally disruptive). |

## Review Coverage

| Leg | Bead | Status | Key Finding |
|-----|------|--------|-------------|
| Requirements | hq-l8mf | Complete | Section 04 ownership is pre-gate; US acceptance criteria need sharpening |
| Gaps | hq-szix | Complete | Rate limiting 0% implemented; idempotency 0%; no shared middleware root |
| Ambiguity | hq-zemp | Complete | 11 issues: scope/conformance definition, Phase 4 underspecification |
| Feasibility | hq-l23m | Complete | Sections 04/23 document existing infra; rate limiting tenant ID contradiction |
| Scope | hq-pdbq | Complete | (Notes overwritten by multi-polecat race; summary only) |
| Stakeholders | hq-e0a7 | Complete | External consumers invisible; GxP/Part 11 compliance absent |

## Next Steps

1. Close step 3 (this synthesis)
2. Skip human gate (human pre-approved via mail: "plan approved, follow all best recommendations")
3. Proceed to design exploration
4. Create convoy + implementation beads
