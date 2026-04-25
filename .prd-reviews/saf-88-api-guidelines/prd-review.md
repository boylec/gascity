# PRD Review: API Guidelines — Security, Operations & Extensibility

## Executive Summary

The PRD correctly identifies the six implementation gaps between written API guidelines (sections 15–23) and the running platform. Problem framing is strong, non-goals are precise, and the phased approach is directionally correct. However, the PRD has three structural problems that must be resolved before committing to implementation:

1. **SAF-88 is three projects, not one.** The webhook subscription API (Phase 2) is a 4–8 week standalone project. OAuth 2.0 PKCE and API key auth are separate features. Bundling them guarantees SAF-88 never closes cleanly.
2. **Six open questions block architecture and sizing.** Three of them (Redis vs. in-memory, build vs. buy for webhooks, API key scope) change the work by 2–3x. These are prerequisites, not questions to answer during implementation.
3. **No measurable acceptance criteria.** The PRD lists deliverables but no pass/fail thresholds. The guidelines themselves contain concrete numbers (300 read/min, 60 write/min, 72-hour retry) that should be testable assertions.

## Before You Build: Critical Questions

These must be answered before the PRD is approved. Each one changes scope, architecture, or timeline.

### 1. Where does rate limiting live — Hono or YARP?

The PRD says "Hono stack or YARP gateway" without deciding. Feasibility review finds YARP has zero Redis wiring and no tenant extraction, while Hono already has auth middleware that extracts `tenantId` from JWT and has Redis client abstractions. **But**: the guidelines (section 16.1) say limits key on `X-Tenant-Id` header, while the auth middleware uses the JWT `org_id` claim. These are different mechanisms. Must decide which layer and which identifier.

Additionally: there are two gateways (customer-facing `gateway` and internal `platform-gateway`). Rate limiting policy may differ between them — the PRD assumes a single gateway.

### 2. Build or buy the webhook delivery engine?

This is a 4–6 week custom build (subscription CRUD, verification challenge, per-subscription secret management, delivery worker, retry state machine, DLQ + replay) vs. adopting Svix/Hookdeck. The build/buy decision changes Phase 2 timeline by an order of magnitude and has GxP audit implications. No existing webhook code or envelope encryption exists in the codebase.

### 3. Are API key auth and OAuth 2.0 PKCE in scope for SAF-88?

The PRD lists "validate auth guidelines completeness" as a goal but Open Question 4 already flags uncertainty. No API key code path exists in the auth middleware (`auth.ts` only handles JWT). These are net-new authentication flows touching Keycloak, token issuance, key storage, and rotation — each a standalone project. **Recommendation: cut from SAF-88, track separately.**

### 4. What is the scope of compliance firewall extension?

Open Question 5 asks "all MUST rules from sections 15–23, or a prioritized subset?" Without an answer, Phase 3 has no definition of done. The spec contains 40+ MUST rules. Should firewall rules ship alongside each feature (recommended) or as a separate phase?

### 5. What is the webhook delivery SLA?

Section 20.7 specifies retry timing, but the PRD sets no target for initial delivery latency (e.g., p95 < 5s from outbox write to first HTTP POST). For GxP events like `quality-hold.created`, this matters. Also: what happens during Debezium connector restarts or blue-green deployments?

### 6. What happens to webhook signing secrets during rotation?

Section 20.4 specifies dual signing (`v1`/`v2`) during a 24-hour window. But if secrets are in Key Vault, rotation needs a cache-invalidation strategy (~30–50ms per uncached fetch is unacceptable at scale). If envelope-encrypted in PostgreSQL, master key rotation is a separate concern. Neither is addressed.

## Important But Non-Blocking

### Scalar migration needs a redirect

Renaming `/doc` to `/docs` breaks bookmarks and CI scripts. The PRD should require a 301 redirect from `/doc` → `/docs` for at least one release cycle. The migration itself is trivial (single-file change per BC).

### Links (section 19) are MAY, not MUST

The PRD goal "add `links` object where missing" implies MUST, but section 19.2 explicitly says the `links` object is optional. The compliance firewall cannot validate "where missing" without a defined endpoint set. Clarify: is this upgrading MAY to MUST, or selectively adding links to high-value endpoints?

### Health check readiness should cover Redis

If rate limiting depends on Redis, then Redis becomes a critical dependency that `/health/ready` must check. Current gateway readiness only checks downstream BC APIs. The PRD should note this transitive dependency.

### IETF RateLimit header format needs pinning

The draft `RateLimit-Limit` / `RateLimit-Remaining` / `RateLimit-Reset` has been superseded. The final RFC uses `RateLimit` with policy parameters. Shipping the wrong format means a breaking header rename later.

### Batch request rate limiting detection

Section 16.1 says batch requests count as one hit. The PRD does not mention how batch endpoints are distinguished from regular endpoints in the middleware.

### Phasing can be parallelized

Phase 2 (webhooks) has no dependency on Phase 1 (rate limiting). The PRD should state whether phases are sequential or parallel-eligible. Teams may block on a false sequential assumption.

## Observations and Suggestions

- **Missing stakeholders**: QA (who builds the 72-hour retry test harness?), Support (who triages webhook dead letters and rate limit complaints?), Security (HMAC review, SSRF threat modeling for registered webhook URLs), and Tenant Admin (who manages subscriptions within a customer org) need explicit user stories.
- **Failure paths are underrepresented**: What happens when a webhook endpoint is down for days during a holiday? What happens when a plant floor hits write rate limits during a critical batch release submission? These are not edge cases in food manufacturing.
- **Fat events vs. low-latency tension**: Section 20.3 mandates full resource snapshots for GxP compliance. An `item.updated` event for a record with 50 custom fields could be large. The PRD should acknowledge this tension.
- **Dead letter monitoring is a compliance requirement**: An unnoticed dead letter in a GxP context is a reportable audit gap. The PRD should require alerts when dead letters accumulate.
- **Section 23 authoring is documentation, not implementation**: Aspire already wires OTEL, Grafana LGTM, and structured logging. The section 23 deliverable is writing the guideline, not building infrastructure.
- **The `links` retrofit is more pervasive than implied**: Adding `links` to existing endpoints touches every route handler across all bounded contexts. Budget accordingly.

## Confidence Assessment

| Dimension | Rating | Notes |
|-----------|--------|-------|
| Problem identification | High | The six gaps are real and correctly prioritized |
| Phase 1 feasibility | High | Rate limiting + Scalar = 2–3 weeks with existing Redis/Hono infrastructure |
| Phase 2 feasibility | Medium | 4–8 weeks depending on build/buy; secret management is hardest sub-problem |
| Phase 3 feasibility | Medium | Links retrofit is a long tail of per-endpoint changes |
| Scope accuracy | Low | SAF-88 bundles 3–4 projects; will not close cleanly as written |
| Requirements completeness | Low | No measurable criteria, no SLAs, no done-gates between phases |
| Stakeholder coverage | Medium | Builder personas covered; operator/support/security/regulatory gaps |

## Next Steps

1. **Resolve blocking decisions**: Rate limiting layer, webhook build/buy, API key scope, compliance firewall scope (questions 1–4 above)
2. **Split SAF-88**: Phase 1 (rate limiting + Scalar + section 23) ships as SAF-88. Webhook subscription API becomes its own tracked item. API key and OAuth 2.0 PKCE tracked separately.
3. **Add measurable criteria**: Latency targets, delivery SLAs, error budgets, done-gates per phase
4. **Add missing stakeholder stories**: QA, Support, Security, Tenant Admin
5. **Add failure-path scenarios**: Holiday webhook outage, rate limit during critical submission
6. **Present to the human for approval or revision**
