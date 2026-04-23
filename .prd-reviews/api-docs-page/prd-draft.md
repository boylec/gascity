# PRD: Interactive API Documentation Page

## Problem Statement

SafetyChain needs an interactive API Documentation page under the Develop menu that serves customers, partners, and internal teams during fusion sprints. A basic page already exists at `/develop/api-docs` using Scalar to render the Operational Context OpenAPI spec (with optional Quality Rules spec merge). However, the current implementation has gaps:

1. **Single-spec limitation** — only OC and QR specs are merged; Operational Components and OC Platform specs are not surfaced. As more bounded contexts ship APIs, this merge approach won't scale.
2. **No audience segmentation** — the Dev Mode toggle is a binary on/off, but external customers and partners should never see `x-sc-dev-*` annotations or internal endpoints.
3. **No versioning story** — `Api-Version` header is injected with today's date, but there is no UI for viewing or selecting historical API versions, understanding what changed, or seeing deprecation status.
4. **No navigation structure** — with a single merged spec, users can't browse by bounded context, domain area, or audience-relevance.
5. **No naming standards documentation** — API guidelines (section 14, versioning; section 22, parity) are referenced in code comments but not exposed to consumers.

The existing `/develop/api-docs` page (Scalar + `@scalar/api-reference-react`, server-side spec fetch, gateway URL rewrite, Keycloak OAuth) is a solid foundation. This PRD scopes the work to evolve it into a production-ready experience.

## Goals

1. **Multi-spec navigation** — let users browse API documentation organized by bounded context (Operational Context, Quality Rules, Operational Components, Identity, etc.) with a persistent sidebar or tab structure.
2. **Dynamic rendering from OpenAPI specs** — continue using Scalar for interactive try-it-out, but load specs on-demand per context rather than merging all into one blob.
3. **Versioning awareness** — surface the current API version date, link to a changelog/release notes section, and show deprecated endpoints visually.
4. **Audience-appropriate content** — serve a "public" view by default (endpoints, schemas, try-it-out) and an opt-in "dev context" view for internal teams (business rules, stakeholders, implementation notes via `x-sc-dev-*` extensions).
5. **Basic interactive features** — maintain try-it-out (Scalar already provides this), add search across all specs, and provide a link to download the raw spec.
6. **Naming standards docs** — include a lightweight "API Conventions" section covering versioning strategy, authentication, error format (RFC 9457), and naming rules — derived from existing API guidelines.

## Non-Goals

1. **SDK generation or download** — the Develop nav lists "Download SDKs" separately; this page only documents APIs.
2. **Webhook documentation** — separate concern; also listed as its own nav item.
3. **Real-time spec sync** — specs are served from the running API at `/openapi.json`; this page does not need to poll or push-update.
4. **Multi-tenant spec customization** — all tenants see the same API surface; no per-tenant filtering.
5. **GraphQL or gRPC documentation** — REST only for this iteration.
6. **Full changelog/diff engine** — versioning awareness means showing the current version and linking to release notes, not building an automated spec-diff tool.
7. **Operational Components API page composition** — that spec may not yet have a `/openapi.json` endpoint served by a gateway route; wiring it up is implementation work, not a PRD concern, but should be noted as a prerequisite.

## User Stories / Scenarios

### S1: Partner reviewing APIs during a fusion sprint
A partner engineer visits `/develop/api-docs` to understand what endpoints are available, how to authenticate, and what data shapes to expect. They select "Quality Rules" from the sidebar, find the inspection-rule-set endpoints, use try-it-out to test a GET, and download the spec for code generation.

### S2: Internal QA validating a new endpoint
A QA engineer enables Dev Mode to see business rules and stakeholder annotations for the new `POST /items` endpoint before writing test scenarios. They also check the "API Conventions" section to confirm the error response shape matches RFC 9457.

### S3: Customer integration developer learning versioning
A customer developer building an ERP integration navigates to the "API Conventions" section, reads the versioning strategy (date-based `Api-Version` header), and understands which version to pin for stability.

### S4: New team member onboarding
An internal developer new to the platform browses the sidebar to understand the API surface area across bounded contexts. The per-context organization gives them a mental model of the domain decomposition.

## Constraints

1. **Scalar is the rendering engine** — `@scalar/api-reference-react` is already integrated and paid for. The solution must work within Scalar's configuration surface (themes, authentication, content injection) rather than building a custom renderer.
2. **Specs are served at runtime** — the `fetchOpenApiSpec()` function in `src/lib/api.ts` fetches from the running API gateway. Multi-spec support must follow this pattern (fetch each BC's spec independently).
3. **Gateway routing** — each bounded context's API is accessible through the Aspire gateway. New BCs need gateway route entries before their specs can be fetched.
4. **Authentication** — Scalar's try-it-out uses Keycloak password-grant OAuth (currently hardcoded dev credentials). This must not leak to production; environment-based toggling is needed.
5. **Next.js App Router** — the page uses server components for spec fetching and client components for Scalar rendering. New navigation must follow this pattern.
6. **API guidelines compliance** — the page itself is subject to the project's API guidelines (e.g., the parity test in `tests/architecture/openapi_parity_test.ts` ensures spec-route alignment).
7. **Dev Mode annotations (`x-sc-dev-*`) exist only on some endpoints** — the page must gracefully handle specs with zero annotations.

## Open Questions

1. **How many bounded contexts will have public-facing OpenAPI specs at launch?** Currently OC and QR have specs; OC Components and OC Platform also have specs but may not be gateway-routed. Should the page launch with just OC + QR and add more later?
2. **Should the "API Conventions" section be a static MDX page or dynamically derived from a machine-readable source?** Static is simpler; dynamic could be kept in sync with an API guidelines repo.
3. **Is the Keycloak dev-credential approach acceptable for the try-it-out feature in non-local environments?** The current code has hardcoded `admin/admin` — this must be gated.
4. **Does the Operational Components BC have a gateway route for `/openapi.json`?** If not, wiring it up is a prerequisite task.
5. **Should deprecated endpoints be filtered from the public view or just visually marked?** Scalar supports `deprecated: true` in OpenAPI — is that sufficient?
6. **What is the "naming standards docs" expectation — a full style guide, or a short "getting started" section covering auth, versioning, and errors?**
7. **Is there a desire to surface the API parity test results (spec-route alignment) on the page itself, or is that purely CI?**

## Rough Approach

### Phase 1: Multi-spec navigation (core)
- Replace the single-spec merge with a per-context spec selector (tabs or sidebar).
- Each context gets its own Scalar instance loaded on-demand.
- Refactor `fetchOpenApiSpec()` into `fetchSpecByContext(context: string)`.
- Add route structure: `/develop/api-docs` (default to first context), `/develop/api-docs/[context]` for deep-links.

### Phase 2: Versioning and conventions
- Add an "API Conventions" static section (MDX or inline) covering auth, versioning, error shapes.
- Surface spec version in each context's header alongside the existing download link.
- Mark deprecated operations visually (Scalar handles this natively if `deprecated: true` is set in the spec).

### Phase 3: Audience gating
- Keep the existing Dev Mode toggle for internal annotations.
- Ensure dev credentials are environment-gated (no Keycloak password-grant in production builds).
- Consider a lightweight "public" view that hides internal-only tags/endpoints (using OpenAPI `x-internal: true` convention).

### Backlog project (next-level features)
Per the request, file a separate project for:
- Automated spec-diff / changelog generation
- SDK download integration
- Webhook documentation
- Search across all specs
- Embedded code samples per language
