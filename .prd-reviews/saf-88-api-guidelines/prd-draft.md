# PRD: API Guidelines — Security, Operations & Extensibility Implementation

## Problem Statement

SafetyChain has comprehensive written API guidelines (sections 15–23) covering authentication, rate limiting, health checks, hypermedia, OpenAPI documentation, tooling/observability, and webhooks. However, the guidelines are a specification — not all are implemented in code. SAF-88 tracks closing the gap between the written guidelines and the running platform.

Key gaps identified:

1. **Rate limiting (section 16)**: Guidelines specify per-tenant read/write quotas with `RateLimit-*` headers. No rate limiting middleware exists in the codebase today. The YARP gateway could host this, or it could live in the Hono middleware stack.
2. **Tooling/observability (section 23)**: The guideline is a stub (`<!-- TODO: sc-ahp -->`). Content needs to be authored covering OpenTelemetry conventions, structured logging, request correlation, and how API tooling connects to the platform telemetry stack.
3. **OpenAPI serving**: Guidelines specify `/openapi.json` (no auth) and `/docs` via Scalar. Current implementation serves `/openapi.json` and `/doc` (singular) via Swagger UI from unpkg CDN — needs migration to Scalar and route rename.
4. **Hypermedia links**: Guidelines define `links.self`/`next`/`prev` as siblings to `data`. Unclear whether existing endpoints emit these links. The compliance firewall (`complianceFirewallMiddleware`) may or may not validate link presence.
5. **Webhook delivery layer**: The internal event pipeline (transactional outbox → Debezium CDC → Kafka → Dapr pub/sub) is production-ready. The external-facing webhook subscription API (section 20.8: registration, verification, HMAC signing, dead letter management) does not appear to exist yet.
6. **Auth completeness**: JWT validation and Keycloak integration are implemented. API key authentication (opaque tokens for M2M integrations) and OAuth 2.0 Authorization Code + PKCE flow for third-party apps are specified in the guidelines but their implementation status is uncertain.

## Goals

- Implement rate limiting middleware with per-tenant read/write quotas and standard `RateLimit-*` response headers
- Author section 23 (Tooling Integration) to complete the guideline set
- Migrate interactive API docs from Swagger UI to Scalar at `/docs`
- Implement the external webhook subscription API (CRUD, verification challenge, HMAC signing, retry/dead-letter)
- Add `links` object to collection and detail responses where missing
- Validate auth guidelines completeness: API key issuance and OAuth 2.0 PKCE flows
- Extend the compliance firewall to validate newly implemented guidelines (rate limit headers, links, OpenAPI route)

## Non-Goals

- Rewriting existing guidelines sections 15–22 (they are stable and thorough)
- Changing the internal event pipeline (Kafka/Dapr/Debezium) — it works
- Implementing full HATEOAS (Level 3) — guidelines explicitly reject this
- Per-user or per-API-key rate limiting — guidelines specify per-tenant only
- CloudEvents format support — deferred per section 20.10
- Event replay API — deferred per section 20.10
- Sections 1–14 (URL structure through versioning) — these are out of scope for SAF-88

## User Stories / Scenarios

**External integrator (ERP vendor)** — "I register a webhook subscription via the API, receive a verification challenge, and then get signed event payloads when items or quality checks change. I can rotate my signing secret without downtime."

**Platform engineer** — "I add rate limiting to the gateway with configurable per-tenant quotas. Enterprise tenants with contractual SLAs get higher limits. Every response includes `RateLimit-*` headers so integrators can self-monitor."

**Frontend developer** — "I use Scalar at `/docs` instead of raw Swagger UI. The interactive docs load from the same OpenAPI spec that drives code generation."

**DevOps / SRE** — "Section 23 documents our OpenTelemetry conventions, structured log format, and request correlation flow so I can build dashboards and alerts against a stable contract."

**Compliance officer** — "The compliance firewall in dev validates that new endpoints return rate limit headers and proper `links` objects, catching guideline violations before they reach staging."

## Constraints

- Rate limiting must be tenant-scoped (identified by JWT `tenant_id` claim). The token validation middleware already extracts this.
- Webhook signing secrets must be generated per-subscription and stored securely (not in plaintext in the database — use envelope encryption or a key management service).
- The compliance firewall runs in dev only (`complianceFirewallMiddleware`). It must not add latency in production.
- Section 23 must align with existing OpenTelemetry and Grafana LGTM stack already deployed via Aspire.
- Webhook delivery must use the transactional outbox pattern already in place — no new dual-write paths.
- GxP/FDA 21 CFR Part 11 implications: rate limit responses (429 vs 503) must be accurately categorized in audit trails per section 16.4.

## Open Questions

1. **Rate limiting storage**: Redis (already deployed) or in-memory with YARP? Redis enables distributed rate limiting across gateway instances; in-memory is simpler but doesn't share state.
2. **Webhook secret storage**: Envelope encryption in PostgreSQL, or delegate to Azure Key Vault? Key Vault adds latency on every webhook delivery for secret retrieval.
3. **Scalar hosting**: Self-hosted Scalar bundle (like current Swagger UI from unpkg), or Scalar cloud? Self-hosted avoids external dependency on plant-floor networks with restricted internet access.
4. **API key issuance scope**: Is API key auth (section 15.1) in scope for SAF-88, or tracked separately? The guidelines define it but implementation may be a separate work item.
5. **Compliance firewall coverage**: Which specific guideline rules should the firewall validate? All MUST rules from sections 15–23, or a prioritized subset?
6. **Webhook delivery infrastructure**: Build the delivery/retry engine from scratch, or adopt an existing library (e.g., Svix, Hookdeck)? Building gives full control; a library accelerates delivery but adds a dependency.

## Rough Approach

### Phase 1: Foundation (rate limiting + tooling guideline)
- Implement rate limiting middleware in the Hono stack or YARP gateway
- Author section 23 (Tooling Integration) guideline content
- Migrate `/doc` → `/docs` with Scalar

### Phase 2: Webhook subscription API
- Build subscription CRUD endpoints (section 20.8)
- Implement verification challenge flow
- Implement HMAC-SHA256 signing (section 20.4)
- Connect to existing outbox/Kafka pipeline for event delivery
- Build retry engine with exponential backoff (section 20.7)
- Dead letter store and replay endpoint

### Phase 3: Polish and validation
- Add `links` object to existing collection/detail endpoints
- Validate API key and OAuth 2.0 PKCE implementation status
- Extend compliance firewall for new rules
- End-to-end integration testing across all guideline sections
