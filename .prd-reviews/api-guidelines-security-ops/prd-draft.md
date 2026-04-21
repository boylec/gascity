# PRD: API Guidelines — Security, Operations & Extensibility (SAF-88)

## Problem Statement

SAF-88 was created to cover the "security, operations, and extensibility" sections of SafetyChain's API guidelines: authentication/authorization, rate limiting, health checks, hypermedia, OpenAPI, tooling, and webhooks/events. These correspond to sections 15-23 of `docs/api-guidelines/`.

**Current state (as of 2026-04-21)**: The documentation work is substantially complete. All seven original beads (sc-e9m through sc-qf1) are closed. Sections 15-22 contain thorough, well-researched content (125-695 lines each) covering auth, rate limiting, idempotency, batch operations, hypermedia, webhooks, health checks, and OpenAPI. However:

1. **Section 23 (Tooling Integration)** is a stub — 8 lines with a `<!-- TODO: sc-ahp -->` marker, despite bead sc-ahp being marked closed.
2. **Section 04 (Response Envelope)** is also a stub — 7 lines with `<!-- TODO: sc-csi -->`. This is foundational to all other sections but incomplete. (May belong to a different issue scope.)
3. **Implementation conformance is unknown.** The guidelines describe the ideal API behavior. Whether the actual enterprise API routes follow these guidelines has not been audited.
4. **CLAUDE.md Key References** was not updated with pointers to the guidelines (sc-ahp deliverable partially missed).

The remaining work for SAF-88 falls into three categories: complete the documentation stubs, audit the codebase for conformance, and close the gap between documented standards and actual implementation.

## Goals

1. **Complete section 23 (Tooling Integration)** — Write the full section covering OpenTelemetry tracing conventions, structured logging format, request correlation headers (`X-Request-Id`, `X-Correlation-Id`), and how API tooling connects to the platform telemetry stack (Aspire dashboard, Grafana).
2. **Complete section 04 (Response Envelope)** — Define the standard response wrapper shapes for single-resource, collection, mutation, and error responses. This is referenced by many other sections but currently undefined.
3. **Conformance audit** — Assess which guidelines from sections 15-23 are actually implemented in the enterprise codebase vs. documented-but-not-implemented. Produce a conformance matrix.
4. **Implementation tasks** — For each guideline that is documented but not implemented, create a scoped implementation task with clear acceptance criteria.
5. **Finish sc-ahp deliverables** — Update CLAUDE.md Key References with pointers to `docs/api-guidelines/` and relevant ADRs.

## Non-Goals

- **Rewriting existing sections.** Sections 15-22 are comprehensive and well-researched. No rewrites unless the conformance audit reveals that a section contradicts actual architecture decisions.
- **Implementing all guidelines immediately.** The conformance audit will produce a prioritized backlog. Not all gaps need to be closed in this initiative.
- **Sections 01-14.** Those sections are complete and under SAF-67 (Done). Only sections 04, 15-23 are in scope.
- **New guideline topics.** No new sections beyond 23. If new topics emerge, they should be separate issues.

## User Stories / Scenarios

### US-1: Developer consults guidelines for a new route
As a developer building a new API route, I want every guideline section to be complete (no stubs) so I can reference the full standard without guessing at the intended convention for response envelopes or tooling integration.

**Acceptance**: Sections 04 and 23 contain the same level of detail as sections 15-22 (prescriptive rules, examples, rationale, references).

### US-2: Tech lead audits conformance
As a tech lead, I want a conformance matrix showing which guidelines are implemented, partially implemented, or not yet implemented, so I can prioritize implementation work.

**Acceptance**: Conformance matrix covers sections 04, 15-23 against the current enterprise codebase. Each row shows: section, guideline rule, status (implemented/partial/not-implemented), and location in codebase or gap description.

### US-3: Developer implements a missing guideline
As a developer, I want implementation tasks with clear scope (which files to change, what the before/after looks like) so I can pick up guideline implementation work without ambiguity.

**Acceptance**: Each implementation task references the specific guideline rule, the target file(s), and has testable acceptance criteria.

## Constraints

- **Enterprise repo**: All code changes are in `/Users/caseyboyle/src/SafetyChain/enterprise`.
- **Existing architecture**: DDD hexagonal, per-BC services (ADR-015). Routes in `contexts/<bc>/app/routes/`, middleware in platform-core packages.
- **Tooling stack**: Deno + Hono API, OpenTelemetry (already partially configured per ADR and Aspire), structured logging via platform-core.
- **Target branch**: `boylec/develop` or feature branch off it.
- **Guidelines are normative**: Implementation should follow the documented rules. If a rule is wrong or impractical, the guideline should be updated (with ADR if breaking), not silently ignored.

## Open Questions

1. **Section 04 ownership**: Is the Response Envelope stub under SAF-88's scope, or should it be a separate issue? It's foundational but was originally part of SAF-67 (sections 1-14 scope).
2. **Conformance depth**: Should the audit cover all routes in all bounded contexts, or focus on one BC (e.g., operational-context) as the reference implementation?
3. **Priority of implementation tasks**: Should we prioritize by safety/compliance impact (auth, audit trail) or by developer friction (missing response envelope, incomplete tooling)?
4. **Rate limiting implementation**: Section 16 specifies per-tenant rate limits, but is there middleware in the gateway or API layer that enforces this today? If not, is that in scope for SAF-88 or a separate initiative?
5. **Webhook implementation**: Section 20 is comprehensive (620 lines) but the transactional outbox pattern is described as the delivery mechanism. Is the outbox pipeline (Debezium + Kafka) operational, or is webhook delivery deferred until the pipeline is production-ready?

## Rough Approach

### Phase 1: Complete Documentation Stubs
- Write section 23 (Tooling Integration): OTEL tracing, structured logging, correlation headers, Aspire/Grafana integration
- Write section 04 (Response Envelope): standard wrapper shapes, envelope fields, collection metadata
- Update CLAUDE.md Key References
- Estimated: 1-2 tasks, documentation-only

### Phase 2: Conformance Audit
- Audit enterprise codebase against sections 15-23 guidelines
- Focus on operational-context routes as the reference BC (most mature, most routes)
- Produce conformance matrix in `.plan-reviews/api-guidelines-security-ops/conformance-matrix.md`
- Identify which guidelines are: implemented, partially implemented, not implemented, or not applicable yet
- Estimated: 1 task, read-only analysis

### Phase 3: Implementation Backlog
- For each gap found in Phase 2, create a scoped implementation task
- Prioritize: (1) auth/security gaps, (2) response envelope (used everywhere), (3) health checks, (4) rate limiting, (5) OpenAPI, (6) tooling, (7) hypermedia, (8) webhooks (depends on pipeline)
- Each task gets: guideline reference, target files, acceptance criteria, estimated size (S/M/L)
- Estimated: 5-15 tasks depending on audit results

### Phase 4: Reference Implementation
- Implement highest-priority gaps in operational-context as the reference BC
- Other BCs follow the same pattern in subsequent convoys
- Estimated: varies by audit findings
