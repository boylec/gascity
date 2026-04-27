# PRD Review Synthesis: Permissions API (SAF-449)

**Review ID:** permissions-api
**Date:** 2026-04-26
**Coordinator:** quartermaster-3
**Method:** Inline review (Phase 1 already implemented — code verification
takes priority over speculative review)

---

## Executive Summary

Phase 1 of SAF-449 is **already fully implemented** on `boylec/develop`. The
static permission registry at `contexts/identity/app/routes/permissions.ts`
provides GET list + GET detail for 11 system-defined permissions. The
permission catalog is consistent with `ROLE_PERMISSIONS` in
`identity-contracts/permission-resolution.ts`.

The remaining work is verification, documentation, and follow-on filing —
estimated at 2-3 hours total, appropriate for a single sonnet-tier polecat.

---

## Before You Build: Critical Questions

### 1. Implementation is complete — this is a review/doc plan, not a build plan

The PRD correctly identifies that Phase 1 is done. No new implementation
work is needed. The plan should produce: (a) a verified review confirming
spec compliance, (b) Phase 2 migration documentation, (c) follow-on beads.

### 2. Pagination: document the deviation, don't add it

The Linear spec says "cursor-paginated" but the static set has 11 items.
Adding cursor pagination to a static array is unnecessary complexity.
Recommendation: document the intentional deviation ("static set of N items,
pagination added when migrating to DB in Phase 2") in both the endpoint
docstring and the Phase 2 migration doc.

### 3. Permission IDs are synthetic but should be treated as permanent

The `perm_01000000-0000-4000-8000-00000000000X` IDs are clearly synthetic.
Phase 2 DB migration must seed with these exact IDs to maintain client
compatibility. This must be documented as a constraint in the migration doc.

---

## Important But Non-Blocking

- **Permission-role inverse lookup** (Open Q3): useful but separate feature.
  File as a follow-on if the UI team requests it.
- **The `/api/v1/permissions/:path*` Next.js rewrite** already exists on
  `boylec/develop` — no routing work needed.

---

## Confidence Assessment

| Aspect | Confidence | Notes |
|--------|-----------|-------|
| Implementation is spec-compliant | **High** | Verified: 2 endpoints, perm_ prefix, 11 permissions, auth middleware |
| Catalog consistency | **High** | Verified: API matches ROLE_PERMISSIONS exactly |
| Phase 2 path is clear | **High** | Extension points already exist in codebase |
| Pagination can be deferred | **High** | 11 items, static set, no client-side pagination needed |

---

## Next Steps

1. Create a single implementation bead: "Verify SAF-449 + document Phase 2
   migration path" (sonnet tier, XS effort)
2. The bead should produce: review notes confirming spec compliance, a
   migration path section in identity docs, and follow-on beads for Phase 2
3. Transition SAF-449 in Linear upon convoy completion
