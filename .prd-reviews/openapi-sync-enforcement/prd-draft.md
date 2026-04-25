# PRD: OpenAPI Spec Sync Enforcement

## Problem Statement

The SafetyChain enterprise repo has 6 hand-written OpenAPI YAML spec files across 4 bounded contexts (identity, operational-components, operational-context, quality-rules), plus platform-level variants. These specs are manually maintained alongside Deno + Hono API implementations with no mechanical enforcement that they match the actual API surface.

The reviewer of PR #405 flagged this gap: specs can silently drift from the implementation, becoming under-documented (endpoints exist but aren't in the spec) or over-documented (spec describes endpoints that don't exist or have changed signatures). Additionally, the Scalar-based API documentation in builder-studio currently only merges OC and QR specs — identity and platform specs may not be rendered.

The reviewer explicitly called for shift-left enforcement (build/lint/commit time, not PR-action time).

## Goals

1. **Mechanical sync verification**: A build-time or pre-commit check that detects when OpenAPI specs diverge from the implemented Hono route surface — catching both under- and over-documentation.
2. **Shift-left placement**: Enforcement runs at build/lint/commit time in the developer's local workflow, not deferred to CI/PR review.
3. **Complete Scalar coverage**: Every BC's OpenAPI spec is accounted for in the builder-studio Scalar docs rendering, not just OC and QR.
4. **Zero false positives at rest**: When specs and routes are in sync, the check passes silently with no developer friction.

## Non-Goals

- **Auto-generating OpenAPI specs from code**: The specs are hand-authored with intentional annotations (`x-sc-dev-notes`, `x-sc-dev-business-rules`, `x-sc-dev-stakeholders`). The goal is verification, not replacement.
- **Runtime spec validation or request/response contract testing**: This is about structural sync (do the documented paths/methods match the registered routes?), not payload validation.
- **Migrating away from hand-written YAML**: The manual specs support rich developer context annotations that code-gen wouldn't produce.
- **OpenAPI linting for style/quality** (e.g., Spectral rules for naming conventions): Useful but orthogonal to the sync enforcement problem.

## User Stories / Scenarios

1. **Developer adds a new route but forgets to update the spec**: At `deno task build` or pre-commit hook time, the sync check fails and reports "Route `POST /api/items/:id/archive` exists in code but is missing from `openapi.yaml`."
2. **Developer removes a route but leaves the spec entry**: The check reports "Path `DELETE /api/items/:id` is documented in `openapi.yaml` but no matching route is registered."
3. **Developer modifies route method (GET → POST)**: The check catches the method mismatch.
4. **New BC is added**: The check reports "No openapi.yaml found for bounded context `<name>`" until one is created.
5. **Builder-studio coverage gap**: A build-time check or manifest validates that all BC specs are included in the Scalar merge logic.

## Constraints

- **Deno + Hono stack**: Route introspection must work with Hono's router API. Hono exposes registered routes, but the exact introspection API depends on the version.
- **Monorepo structure**: Each BC is a separate Deno project under `contexts/<bc>/app/api/`. The check must run per-BC and also aggregate results.
- **Hand-authored specs with extensions**: The sync check must not flag custom `x-sc-*` extensions as errors.
- **ADR-024 direct-merge workflow**: The check must work locally (no reliance on GitHub Actions for first-line enforcement).
- **Multiple spec files per BC**: Some BCs have both `app/api/openapi.yaml` and `app/platform/openapi.yaml` (or `app/platform/api/openapi.yaml`). The check must know which spec maps to which route set.

## Open Questions

1. **Hono route introspection**: Does the current Hono version expose registered routes programmatically? If not, can we extract routes via static analysis of the `app.get()`/`app.post()` call sites, or do we need a boot-time introspection script that starts the app and dumps routes?
2. **Parameterized paths**: How do we normalize Hono's `:param` syntax to OpenAPI's `{param}` syntax for comparison? Are there edge cases (wildcards, regex routes)?
3. **Gateway routing**: The builder-studio fetches specs through the gateway at runtime. Does each BC serve its own `openapi.json` endpoint, or are the YAML files served statically? This affects whether we check the YAML source or the served JSON.
4. **Identity and platform spec gaps**: Are the identity and platform OpenAPI specs intentionally excluded from Scalar, or is this an oversight? The `fetchOpenApiSpec()` in `api.ts` only merges OC + QR.
5. **Commit-time vs build-time**: Should this be a git pre-commit hook (fastest feedback but can be bypassed with `--no-verify`) or a Deno task that's part of the build graph (slightly slower but always runs)?
6. **Scope of "sync"**: Just path + method, or also parameters, response codes, and request/response body schemas?

## Rough Approach

### Phase 1: Route extraction and comparison tool
Build a Deno script (e.g., `scripts/check-openapi-sync.ts`) that:
- For each BC: imports the Hono app, introspects registered routes, parses the corresponding `openapi.yaml`, and diffs them.
- Reports under-documented routes (in code, not in spec) and over-documented routes (in spec, not in code).
- Normalizes `:param` ↔ `{param}` syntax.
- Exits non-zero on mismatch.

### Phase 2: Shift-left integration
- Add as a Deno task (`deno task check:openapi`) in each BC's `deno.json`.
- Wire into the monorepo-level lint task so it runs alongside existing checks.
- Optionally add as a git pre-commit hook via a lightweight hook manager.

### Phase 3: Scalar coverage manifest
- Create a manifest file listing all BC specs that should appear in Scalar.
- Update `fetchOpenApiSpec()` in builder-studio to iterate the manifest rather than hard-coding OC + QR.
- Add a build-time check that every `openapi.yaml` in the repo is accounted for in the manifest.

### Phase 4: CI guardrail (belt-and-suspenders)
- Add a GitHub Actions step that runs `deno task check:openapi` as a required check.
- This catches cases where the pre-commit hook was bypassed.
