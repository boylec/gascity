# Design: SAF-88 — API Guidelines: Security, Operations & Extensibility

## Executive Summary

SAF-88 closes the gap between comprehensive API guidelines (sections 15-23, already written) and actual codebase conformance. The design has three layers: (1) document the two remaining stubs (sections 04 Response Envelope and 23 Tooling) which describe already-implemented infrastructure, (2) audit the enterprise codebase against all guideline sections, and (3) produce a prioritized implementation backlog for conformance gaps. The highest-value implementation targets are rate limiting middleware (Redis token bucket) and idempotency middleware (Redis SET NX), both well-bounded patterns with existing infrastructure support.

Two security findings from the design review must be resolved before any rate limiting or idempotency implementation: (1) Section 16 must use `authenticatedIdentity.tenantId` from Hono context, not the nonexistent `X-Tenant-Id` header, and (2) idempotency keys must be tenant-scoped to prevent cross-tenant replay attacks.

## Problem Statement

The enterprise API guidelines (23 sections, ~200KB total) describe the ideal API behavior. Sections 15-22 are complete and thorough. However:
- Sections 04 (Response Envelope) and 23 (Tooling) are stubs despite describing fully-implemented infrastructure
- No systematic conformance audit has been performed
- Key guideline sections (rate limiting, idempotency) have zero implementation
- Section 16 contains an architectural inconsistency (`X-Tenant-Id` header vs. JWT-derived tenantId)

## Proposed Design

### Phase 1: Complete Documentation Stubs

**Section 04 (Response Envelope)** — Document the existing `platform-core/http/responses.ts` helpers:
- `okResponse(data)` → `{ data }` + ETag
- `createdResponse(data, location)` → `{ data }` + Location + ETag + 201
- `listResponse(data, pagination)` → `{ data, pagination }`
- `noContentResponse()` → 204
- Error responses: RFC 9457 Problem Details via `problem-details.ts`

**Section 23 (Tooling Integration)** — Document the existing OTEL stack:
- Deno `--unstable-otel` for server/client spans with W3C traceparent
- `telemetryMiddleware()` for `x-request-id`, structured logging, route attribution
- `X-Correlation-Id` via AsyncLocalStorage request context
- Custom metrics: `httpServerRequestDuration`, `auditEventsCounter`, `domainEventsCounter`
- Aspire AppHost for local telemetry dashboard
- Structured JSON logger → OTLP log records

**CLAUDE.md update** — Add Key References entry for `docs/api-guidelines/`.

### Phase 2: Conformance Audit

Audit operational-context (OC) as the reference BC. Produce a conformance matrix:

| Section | Guideline Rule | Status | Location/Gap |
|---------|---------------|--------|--------------|
| 15 Auth | JWT validation | Implemented | `auth.ts` |
| 15 Auth | 401 vs 403 semantics | Implemented | `auth.ts` |
| 16 Rate Limiting | Per-tenant limits | Not implemented | No middleware |
| 17 Idempotency | Idempotency-Key header | Not implemented | No middleware |
| ... | ... | ... | ... |

Focus areas from design reviews:
- **Auth (§15)**: High conformance. JWT validation, issuer check, clock skew, JWKS rotation all correct.
- **Rate limiting (§16)**: Zero implementation. Guideline text needs fix (X-Tenant-Id → JWT tenantId).
- **Idempotency (§17)**: Zero implementation. Redis infrastructure exists.
- **Health checks (§21)**: Partial — `/alive`, `/ready`, `/health` exist in OC platform API but not business-facing API.
- **OpenAPI (§22)**: 4 hand-authored YAML files exist. No automated spec-drift CI.

### Phase 3: Implementation Backlog

Priority order (from design review consensus):

| Priority | Section | Implementation | Effort | Risk |
|----------|---------|---------------|--------|------|
| 1 | §16 Rate Limiting | Redis token bucket middleware (Lua script) | M | Medium — fix tenant ID source first |
| 2 | §17 Idempotency | Redis SET NX middleware | S | Low — well-bounded pattern |
| 3 | §21 Health Checks | Add `/health/*` to business-facing APIs | S | Low |
| 4 | §22 OpenAPI | Spec-drift CI test | M | Low — extends existing `openapi_parity_test.ts` |
| 5 | §15 Auth fixes | WWW-Authenticate header on 401s | S | Low |
| 6 | §19 Hypermedia | `_links` injection in response helpers | L | High — maximally disruptive |
| 7 | §20 Webhooks | Delivery engine + subscription management | XL | High — depends on Debezium/Kafka pipeline |

## Key Components

### Rate Limiting Middleware

```
Key schema:  rl:{bc}:{limit-class}:{tenantId}:{endpoint-slug}
Algorithm:   Token bucket via Redis Lua script (~150 lines)
Limits:      300 req/min reads, 60 req/min writes (per §16)
Tenant ID:   authenticatedIdentity.tenantId from Hono context (NOT X-Tenant-Id header)
Headers:     RateLimit-Limit, RateLimit-Remaining, RateLimit-Reset (IETF draft)
429 body:    RFC 9457 Problem Details with Retry-After
```

Requires extending `RedisCache` with raw `RedisClientType` wrapper (current `CachePort` abstraction doesn't support Lua EVAL).

### Idempotency Middleware

```
Key schema:  idem:{bc}:{tenantId}:{sha256(Idempotency-Key)}
Storage:     Redis SET NX with EX 86400 (24h TTL per §17)
No Lua:      Simple SET NX + GET pattern
Scope:       POST endpoints only (GET/PUT/DELETE are naturally idempotent)
Conflict:    409 if key reused with different request fingerprint
```

Tenant-scoped keys prevent cross-tenant replay attacks (critical security finding from design review).

### Per-BC Rollout Strategy

1. **OC first** — most routes, most mature tests, reference BC
2. **OCC second** — identical middleware stack to OC
3. **QR third** — simpler stack (no actionRewriteContextMiddleware)
4. **Identity exempt** — OAuth2/OIDC BFF has its own security model

Activation via env-var gates (same pattern as `complianceFirewallMiddleware`):
```
RATE_LIMIT_ENABLED=false    # default; enable per-BC during rollout
IDEMPOTENCY_ENABLED=false   # same pattern
```

## Data Model

No Postgres schema changes. Redis only:
- Rate limit counters: token bucket state per tenant+endpoint
- Idempotency entries: request fingerprint + cached response, 24h TTL

## Trade-offs and Decisions

| Decision | Rationale | Trade-off |
|----------|-----------|-----------|
| Fix §16 to use JWT tenantId | X-Tenant-Id header is unauthenticated, spoofable | Guideline text changes (non-breaking) |
| Tenant-scope idempotency keys | Prevent cross-tenant replay/data leak | Slightly longer Redis key names |
| OC-first rollout | Most mature BC, best test coverage | Other BCs wait for pattern to stabilize |
| Env-var activation gates | Safe per-BC rollout, easy rollback | One more config knob per service |
| Defer webhooks | Depends on Debezium/Kafka production status | §20 conformance postponed |
| Defer hypermedia | Maximally disruptive, lowest value-add | §19 conformance postponed |

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| X-Tenant-Id spoofable for rate limits | CRITICAL | Fix §16 guideline before implementation |
| Idempotency key not tenant-scoped | CRITICAL | Prefix all keys with tenantId |
| No shared middleware root (4 BCs) | MEDIUM | Use complianceFirewallMiddleware as template; env-var gates |
| OpenAPI spec drift without automation | MEDIUM | Extend existing `openapi_parity_test.ts` |
| Webhook delivery pipeline not production-ready | LOW (deferred) | Explicitly defer §20 implementation |

## Implementation Plan

### Wave 1: Documentation (1-2 days)
- Write section 04 (Response Envelope) from existing `responses.ts`
- Write section 23 (Tooling) from existing OTEL stack
- Fix section 16 tenant ID reference
- Update CLAUDE.md Key References

### Wave 2: Conformance Audit (2-3 days)
- Audit OC routes against sections 15-23
- Produce conformance matrix
- File implementation tasks from gaps

### Wave 3: Middleware Implementation (OC reference)
- Rate limiting middleware + tests
- Idempotency middleware + tests
- Health check endpoints on business-facing API
- OpenAPI spec-drift CI

### Wave 4: Propagate to OCC + QR
- Enable middleware in OCC and QR
- BC-specific adjustments if needed

## Open Questions

1. **Redis cluster vs. standalone**: Is Redis running as a cluster in production? Affects Lua script compatibility (cluster mode restricts cross-slot operations).
2. **Debezium/Kafka pipeline status**: Is it production-ready beyond local dev? Determines when webhook implementation can start.
3. **External API consumers**: Do they exist today? Affects whether rate limiting headers are a breaking change requiring communication.
