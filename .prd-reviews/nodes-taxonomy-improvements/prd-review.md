# PRD Review Synthesis: SAF-376 Nodes/Taxonomy Phase 2 Improvements

**Review ID**: nodes-taxonomy-improvements
**Coordinator**: quartermaster-2
**Date**: 2026-04-22
**Sources**: 4 completed review legs (requirements, gaps, feasibility, stakeholders) + 2 dispatched (ambiguity, scope — pending polecat completion)

---

## Executive Summary

The PRD correctly identifies all six improvement threads and provides reasonable phasing. However, it has a critical accuracy problem: **Phase 1 of the Rough Approach describes work that is already done** (ltree extension, path column, GiST index, customType, version column all exist in the codebase). The "empty tables" assumption is also false — demo seed data inserts ~22 nodes without paths.

Three open questions are already answerable from the codebase and should be closed before planning begins. Several missing sections (test plan, migration rollback, monitoring) need to be added.

**Must-fix count: 8 | Should-fix count: 11**

---

## Before You Build: Critical Questions

These must be resolved before implementation planning begins:

### 1. Which work is already done vs. remaining?

The PRD Phase 1 lists six items. Four are already complete:
- `CREATE EXTENSION IF NOT EXISTS ltree` — migration `0003_wooden_sandman.sql`
- Nullable `path ltree` columns with GiST indexes — on both `tenant_taxonomy_nodes` and `item_taxonomy_nodes`
- `customType()` for ltree — `schema.ts` lines 19-29
- `version integer NOT NULL DEFAULT 1` — already on `tenant_taxonomy_nodes` line 83

**Remaining Phase 1 work**: only the tsvector/GIN index is genuinely new schema work.

The Phase 1/2/3/4 breakdown must be rewritten to reflect: Phase 1 is schema-ONLY for tsvector. Phases 2-4 are the actual ltree implementation work.

### 2. Cursor or offset pagination?

Open Question #2 is blocking. **Recommendation**: cursor-based using `nextPageToken` — it matches the existing `PaginationMeta` interface in platform-core (`hasMore`, `nextPageToken`, `totalCount`) and avoids count queries. Decide before planning.

### 3. ILIKE or tsvector for search?

Open Question #3 is blocking. **Recommendation**: ILIKE first. Seven existing entity repositories (items, locations, workcenters, customers, suppliers, equipment, characteristics) all use `ILIKE` with Drizzle's built-in operators. tsvector adds unproven infrastructure (custom types, raw SQL, no codebase precedent). ILIKE with `pg_trgm` index is sufficient for taxonomy nodes (~2,500 max). Revisit tsvector only if stemming or multi-language is needed.

### 4. Where does the Customer entity live?

Open Question #4 is already answered: **operational-context**. Confirmed via `customers` table in `schema.ts`, `customer.ts` aggregate in `domain/aggregates/`, `pg-customer-*` repositories in `infra/repositories/`. Close this question.

### 5. What branch should be cleaned up?

The PRD names `feature/TaxonomySettingsManagementAdjustments` — this branch does **not exist** in remote tracking branches. The closest match is `feat/saf-389-taxonomy-settings-tiers`, which is 405 commits ahead of main (active work, NOT stale). **Clarify the target branch name before planning.**

---

## Important But Non-Blocking

### Missing PRD Sections

1. **Migration rollback plan**: Multi-phase schema migration with no rollback procedure. Demo seed creates ~22 nodes without paths — the "empty tables" assumption is false. A backfill must be part of Phase 2, and if it fails, the rollback strategy matters.

2. **Test plan**: Six threads introduce testable behavior. QE team (SAF-29) must be looped in. Need: ltree path computation unit tests, CTE→ltree equivalence integration tests, performance regression benchmarks (<1ms at depth 15+), pagination boundary conditions, conflict detection for optimistic locking.

3. **Monitoring/observability**: No metrics for taxonomy operations. Recommend adding `safetychain.taxonomy_node_queries` histogram and `taxonomy_search_queries` counter. OTLP/Prometheus pipeline is already wired.

4. **Frontend coordination**: Pagination is a **breaking API change** for `GET /:systemKey/nodes`. SAF-56, SAF-354, SAF-391 are actively consuming this endpoint. Must sync with frontend team before landing.

### Implementation Details to Specify

5. **Optimistic locking: upsert row-count check**. Drizzle v0.44 supports `setWhere` in `onConflictDoUpdate`, but a 0-row result (version conflict) is silently ignored. `save()` must check affected row count and throw a domain error. The current `save()` does not check row counts.

6. **ltree path/parent_id consistency invariant**. If reposition updates `parentNodeId` but path computation fails or races, path and parentNodeId can diverge. Need: domain rule or DB check constraint, defined error response for violations.

7. **TaxonomyVisibilityService is an ltree consumer**. Uses `findDescendants()` via recursive CTE. Must be a switchover gate — verify correctness before removing CTE code.

8. **Customer entity assignment scope is wider than implied**: Needs (a) `tenantTaxonomyAssignments jsonb` column on customers table, (b) `taxonomyAssignments` property on Customer aggregate, (c) `CustomerTaxonomyAssignmentChanged` integration event, (d) outbox mapper entry, (e) `PUT /customers/:id/taxonomy-assignments` route endpoint.

9. **Demo seed must update with Phase 2**: `demo-taxonomy.ts` inserts nodes without path values. After Phase 2 (write path on save) and Phase 3 (switch to ltree queries), these nodes will have null paths causing silent query failures.

### GxP/Compliance

10. **Version increment must include before/after in domain events**. The Constraints section acknowledges this but the approach doesn't specify which events carry version deltas.

11. **Search surface needs access-control acknowledgment**. The search endpoint must apply the same tenant-scoping and role checks as the existing list endpoint.

12. **Customer taxonomy is a new classification axis**. The `applicableEntityTypes` field on TenantTaxonomy provides an opt-in gate — note this as a safety mechanism.

---

## Observations and Suggestions

- **ItemTaxonomyNode has identical gaps** (ltree path not written, optimistic locking TODO, no pagination, no search) but is excluded from scope. The shared `pg-tree-queries.ts` cleanup in Phase 4 (remove CTE code) must not happen until all three tree entities are migrated, or create a follow-up issue explicitly.

- **Node ETag is partially implemented at HTTP layer**. `checkIfMatch`/`checkIfNoneMatch` is already wired on PATCH routes. The actual gap is only at the repository layer (WHERE version = expected).

- **The five "other entity types" are**: Items, Locations, Workcenters, Equipment, Suppliers. Name them explicitly in the PRD to eliminate ambiguity.

---

## Confidence Assessment

| Thread | Feasibility | PRD Accuracy | Ready to Plan? |
|--------|-------------|-------------|----------------|
| ltree (ADR-022) | High — schema done, operators via sql`` | Low — Phase 1 describes done work | After PRD fix |
| Optimistic locking | High — column exists, Drizzle supports setWhere | Medium — "introduce version" is wrong | After PRD fix |
| Pagination | High — PaginationMeta supports cursor | Medium — blocking open question | After Q2 resolved |
| Full-text search | High — ILIKE is proven pattern | Medium — blocking open question | After Q3 resolved |
| Customer assignments | High — same BC, established pattern | Low — scope underspecified | After enumeration |
| Branch cleanup | Unknown — target branch name is wrong | Low — branch doesn't exist | After clarification |

**Overall**: The PRD has the right scope and reasonable phasing, but needs a corrective pass to align the approach with codebase reality. After the must-fixes are applied, this is ready for design review.

---

## Next Steps

1. Apply all must-fix items to the PRD draft
2. Resolve the 3 blocking open questions (pagination strategy, search approach, branch name)
3. Close Open Question #4 (customer BC = operational-context)
4. Add missing sections: test plan, migration rollback, monitoring
5. Proceed to human gate for PRD approval, then design legs
