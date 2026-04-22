# PRD: Nodes/Taxonomy Domain — Phase 2 Improvements (SAF-376)

## Problem Statement

The Tenant Taxonomies domain has six accumulated improvement threads identified during the SAF-376 punchlist review. These range from foundational data-layer changes (ltree materialized paths per ADR-022) to missing feature parity (customer-entity taxonomy assignments) and operational gaps (hardcoded pagination, no full-text search, no optimistic locking). Each thread is independently valuable but they share the same domain surface, making coordinated planning important to avoid conflicting migrations and rework.

The enterprise codebase is in active use for the Tenant Taxonomies project with ongoing UI work (SAF-56, SAF-354, SAF-391) and several bug fixes already completed or in review (SAF-414 through SAF-426). These improvements need to land without disrupting that work.

## Goals

1. **Implement ADR-022 Phase 2 (ltree materialized paths)**: Add the nullable `path ltree` column with GiST index to tenant taxonomy node tables, compute paths on write in the repository, switch ancestor/descendant queries from recursive CTEs to ltree operators, and clean up CTE code. This is the highest-value change — it simplifies ~25 lines per tree method to ~5 and enables O(1) depth-independent queries.

2. **Add optimistic locking to node operations**: Introduce a `version` column and ETag-based concurrency control to prevent lost-update scenarios on concurrent node edits. The pg-node-repository has explicit TODOs for this.

3. **Implement real node pagination**: Replace the hardcoded `hasMore: false` in list-nodes responses with cursor-based or offset pagination that actually pages through results. Large taxonomies (legacy platform has 2,500+ facilities with deep hierarchies) need this.

4. **Add full-text search on nodes**: Enable searching nodes by displayName, code, and description within a taxonomy. Likely via PostgreSQL tsvector/GIN index. This supports the taxonomy editor UI (SAF-56) where users need to find nodes in large trees.

5. **Add customer-entity taxonomy assignments**: Five other entity types (Items, Locations, Workcenters, and two others) already support taxonomy assignments. Customer entity is the gap. Close it so all entity types have parity.

6. **Clean up stale branch**: Delete `feature/TaxonomySettingsManagementAdjustments` which is 0 commits ahead of main.

## Non-Goals

- **Changing the taxonomy provisioning model** — ADR-021 (auto-provision 2 disabled taxonomies per tenant) is settled and working. This PRD does not revisit it.
- **Item taxonomy nodes** — ADR-022 mentions three tree entities (TenantTaxonomyNode, ItemTaxonomyNode, Location). This PRD scopes ltree work to TenantTaxonomyNode only. The pattern can be applied to the other two later.
- **Security axis evaluation refactoring** — ADR-022 notes ltree enables ABAC subtree containment. That's a separate initiative.
- **UI changes beyond what these API changes enable** — The taxonomy editor UI (SAF-56, SAF-354) is a parallel workstream. This PRD covers API/domain/data changes only.
- **Addressing the open SAF-376 child bugs still in progress** — SAF-423 (deactivate response envelope), SAF-419 (description validation), SAF-424 (reposition off-by-one) are tracked separately and should not be bundled into this plan.

## User Stories / Scenarios

**US-1: Admin navigates a deep taxonomy tree efficiently**
As a tenant admin configuring a taxonomy with 15+ levels of hierarchy, I need ancestor/descendant queries to return in <1ms regardless of depth, so the tree editor remains responsive. (Currently degrades to 15-120ms with recursive CTEs at depth 15.)

**US-2: Two admins edit the same node concurrently**
As an admin updating a node's displayName, if another admin has already modified that node since I loaded it, I should receive a 409 Conflict (ETag mismatch) rather than silently overwriting their changes.

**US-3: Admin browses a large flat taxonomy**
As an admin viewing a taxonomy with 500+ nodes at one level, I need paginated results so the list endpoint doesn't return all 500 nodes in a single response. The UI can load pages as I scroll.

**US-4: Admin searches for a node by name**
As an admin in the taxonomy editor, I need to search for "Dairy" across node names, codes, and descriptions to quickly find the node I want to edit, rather than manually expanding tree branches.

**US-5: Admin assigns a taxonomy to a customer entity**
As a tenant admin, I need to assign taxonomy nodes to customer entities the same way I can for items, locations, and workcenters, so customers can be classified along taxonomy axes for reporting and filtering.

**US-6: Developer cleans up stale branches**
As a developer, I need the stale `feature/TaxonomySettingsManagementAdjustments` branch deleted from origin so it doesn't clutter the branch list.

## Constraints

- **PostgreSQL ltree extension**: Must be enabled on the database. ADR-022 confirms this is already the plan and the extension is available.
- **Drizzle ORM v0.44**: No native ltree type. Must use `customType()` for the column and `sql` template tags for ltree queries (same pattern as existing CTE queries). This is documented in ADR-022.
- **Backward compatibility**: The path column must be nullable initially to support a phased rollout. Existing nodes won't have paths until a backfill runs. Queries must fall back to CTEs when path is null (or backfill must happen in the same migration).
- **GxP compliance (21 CFR Part 11)**: All changes must preserve audit trail integrity. Node version increments must produce domain events. No hard deletes.
- **Active development**: SAF-391, SAF-354, SAF-56 (UI work) and SAF-388, SAF-389, SAF-424 (in review) are concurrent. Avoid schema conflicts.
- **Empty tables currently**: Per ADR-022, tables are empty in the new platform, making schema changes zero-cost now. This is the optimal time for ltree adoption.

## Open Questions

1. **Backfill strategy for ltree paths**: ADR-022 says tables are currently empty, so no backfill needed. Is this still true, or has seed/test data been loaded? If non-empty, do we backfill in the migration or via a separate script?

2. **Pagination cursor strategy**: Should node list pagination use cursor-based (opaque token, good for real-time consistency) or offset-based (simpler, matches existing `listResponse` pattern)? The existing `listResponse` helper supports both.

3. **Full-text search scope**: Should search be scoped to a single taxonomy (most likely use case) or cross-taxonomy? Should it support fuzzy matching or just prefix/contains?

4. **Customer entity taxonomy assignment — which bounded context?** Taxonomy assignment for other entities lives in the operational-context domain. Does the customer entity exist in the same BC, or is it in identity/CRM? This affects where the assignment aggregate and repository go.

5. **Optimistic locking granularity**: Should the version/ETag apply per-node or per-taxonomy? Per-node is simpler and more precise, but the taxonomy aggregate also needs protection.

6. **ltree scope**: ADR-022 mentions three tree entities. Should we do all three in this plan (to share the migration and pattern) or just TenantTaxonomyNode?

## Rough Approach

### Phase 1: Schema & Foundation (can be one PR)
- Enable ltree extension in migration
- Add nullable `path ltree` column with GiST index to tenant_taxonomy_nodes table
- Add `version integer NOT NULL DEFAULT 1` column to tenant_taxonomy_nodes
- Add tsvector column and GIN index for full-text search (displayName, code, description)
- Create `customType` for ltree in Drizzle schema
- Backfill paths for any existing nodes (likely empty, but safe to include)

### Phase 2: Repository & Domain (per-thread PRs)
- **ltree queries**: Update pg-node-repository to compute path on save(), switch findAncestors/findDescendants/findSubtree from recursive CTEs to ltree operators
- **Optimistic locking**: Add version check to update/reposition/deactivate operations, return 409 on conflict, expose version in DTOs and ETag headers
- **Pagination**: Replace hardcoded `hasMore: false` with real cursor/offset pagination in findChildrenOf and list endpoints
- **Full-text search**: Add search endpoint or query parameter to list nodes, using tsvector `@@` operator

### Phase 3: Feature Parity
- **Customer entity assignments**: Add taxonomy assignment aggregate, repository, and API endpoints for customer entities, following the pattern established by the other 5 entity types

### Phase 4: Cleanup
- Delete stale branch `feature/TaxonomySettingsManagementAdjustments`
- Remove recursive CTE code once ltree queries are verified
- Make path column NOT NULL (ADR-022 Phase 4)
