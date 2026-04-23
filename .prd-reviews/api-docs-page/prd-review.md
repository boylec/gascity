# PRD Review Synthesis: Interactive API Documentation Page

## Executive Summary

The PRD is well-grounded in the existing codebase — it correctly identifies the current Scalar integration, the multi-spec merge pattern, Dev Mode annotations, and the gateway architecture. The problem statement accurately captures real gaps (single-spec limitation, no versioning story, no audience segmentation). The rough approach is feasible within Scalar's capabilities and the existing Next.js App Router pattern.

Key risks: (1) Scalar's single-instance-per-spec model may create UX jank during context switching, (2) the Operational Components API may not be gateway-routed yet, creating a prerequisite gap, and (3) the "API Conventions" section scope is undefined enough to balloon.

Overall confidence: **High** — this is a well-scoped enhancement to an existing, working page with clear boundaries.

## Before You Build: Critical Questions

### 1. How will multi-spec navigation interact with Scalar's single-instance rendering?
The PRD proposes per-context Scalar instances loaded on-demand. Scalar's `ApiReferenceReact` component takes a `content` prop — swapping it re-renders the entire reference. This works, but: (a) there's no built-in cross-spec search in Scalar, (b) each context switch drops Scalar's internal state (expanded sections, scroll position), and (c) multiple simultaneous instances would be heavy. **Decision needed:** tabs with destroy/recreate, or hidden instances with visibility toggle?

### 2. What bounded contexts will be included at launch?
The codebase has 4 OpenAPI specs:
- `contexts/operational-context/app/api/openapi.yaml` (gateway-routed at `/`)
- `contexts/quality-rules/app/api/openapi.yaml` (gateway-routed at `/quality-rules`)
- `contexts/operational-components/app/api/openapi.yaml` (gateway routing status unknown)
- `contexts/operational-context/app/platform/api/openapi.yaml` (internal platform API — likely not public-facing)

**Recommendation:** Launch with OC + QR (already working). Add Operational Components when its gateway route is confirmed. Exclude Platform API unless explicitly needed.

### 3. Should the Keycloak dev credentials be removed for non-local builds?
The current code at `api-docs-client.tsx:198-201` hardcodes `admin/admin` with a `dev-client-secret-not-for-production` client secret in Scalar's auth configuration. The PRD mentions environment gating but doesn't specify the mechanism. **This is a security requirement, not a nice-to-have.** The try-it-out feature should render auth fields empty in production and only pre-fill in local/dev environments.

### 4. What is the minimal "API Conventions" section?
The PRD lists auth, versioning, error format, and naming rules. Existing sources:
- API versioning: `Api-Version` header, date-based (visible in `api.ts:60`, `api-docs-client.tsx:46`)
- Error format: RFC 9457 Problem Details (visible in `api.ts:461-472`)
- Auth: Bearer token via Keycloak OAuth

**Recommendation:** Static MDX page with 4 sections: Authentication, Versioning, Error Responses, Rate Limits. Link to it from the API docs sidebar. Do not build a dynamic system.

## Important But Non-Blocking

### Spec merge vs. spec selector tradeoff
The current `mergeOpenApiSpecs()` function in `api.ts:111-152` handles tag deduplication, path prefixing, and component merging. Switching to per-context rendering eliminates this complexity but loses the "search everything" capability. Consider keeping the merged view as a "All APIs" tab alongside per-context tabs.

### Dev Mode annotations are sparse
The PRD mentions the `x-sc-dev-*` extensions, but only the OC spec has them (`x-sc-dev-notes`, `x-sc-dev-business-rules`, `x-sc-dev-stakeholders`). The QR spec has none. The Dev Mode toggle will show "0 of N operations annotated" for QR. This is fine — just set expectations.

### The `rewriteForBrowser()` function needs per-context gateway URLs
Currently `rewriteForBrowser()` sets all servers to a single gateway URL. With per-context rendering, each context may have its own base path (QR is at `/quality-rules`). The rewrite function needs to be context-aware.

### OpenAPI parity test coverage
The architecture test at `tests/architecture/openapi_parity_test.ts` only covers OC, not QR or Operational Components. The PRD should note that extending parity testing to all rendered specs is a natural follow-on.

## Observations and Suggestions

1. **Route structure:** The proposed `/develop/api-docs/[context]` pattern is correct. Use the bounded context name as the slug (`operational-context`, `quality-rules`). Default to `operational-context` since it has the most endpoints.

2. **Scalar theme:** The existing `scalar-theme.css` customizes Scalar to match the SafetyChain design system (dark mode, hide download button, etc.). This carries forward unchanged to multi-context — good.

3. **Performance:** Each OpenAPI spec is fetched server-side with a 300s revalidation cache (`api.ts:57`). Multiple specs won't create client-side performance issues. The main cost is the initial Scalar render, which is ~200-400ms per spec.

4. **The `fetchOpenApiSpec()` refactor is clean:** Replace it with `fetchSpecByContext(context: string)` that takes a gateway path prefix. The existing `apiFetch()` infrastructure handles auth headers, timeouts, and caching.

5. **Deprecation handling:** Scalar natively renders `deprecated: true` with strikethrough. No custom work needed — just ensure specs mark deprecated operations.

## Confidence Assessment

| Dimension | Confidence | Notes |
|-----------|------------|-------|
| Problem clarity | High | Gaps are real and visible in the code |
| Scope appropriateness | High | Phases are well-ordered, non-goals are justified |
| Technical feasibility | High | Scalar + Next.js App Router supports all proposed features |
| Completeness | Medium | Missing: error handling for unavailable BCs, loading states during context switch, URL state management for deep-links |
| Stakeholder alignment | Medium | "Naming standards docs" scope is vague — could be 1 page or 10 |
| Security | Medium | Keycloak credential exposure needs explicit gating, not just a note |

## Next Steps

1. **Resolve the 4 critical questions above** before design exploration.
2. **Confirm OC Components gateway routing** — this determines launch scope.
3. **Decide on static vs. dynamic API Conventions** — static is strongly recommended.
4. **Gate the try-it-out credentials** — this should be an explicit task in the convoy, not left implicit.
