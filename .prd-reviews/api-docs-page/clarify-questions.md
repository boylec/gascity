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
