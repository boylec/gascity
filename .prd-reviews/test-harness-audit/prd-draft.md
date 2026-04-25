# PRD: Test Harness Audit & Async Event Handler Coverage

## Problem Statement

PR safety-chain/enterprise#405 review surfaced three gaps:

1. **No single inventory** of where every test suite lives, how and when it runs (CI pipeline, local `deno test`, scheduled, manual), and what it covers. Tests are spread across four distinct locations with different runners and no unified map.
2. **Missing integration/e2e coverage for async event handlers.** Each Dapr subscription handler has a co-located `_test.ts` file, but those are unit-level tests that mock the Dapr runtime. There is no test that fires a real event from the identity bounded context and verifies it propagates through Dapr to the operational-context (or quality-rules) consumer and produces the expected side effects.
3. **No formal coordination with QE** on what exists, where it lives, and how new coverage integrates with the existing harness.

## Goals

- **G1**: Produce a complete test inventory — every suite, its runner, trigger mechanism, scope, and known gaps.
- **G2**: Design and implement integration or e2e tests that cover the full async event path: identity publishes event → Dapr routes → target BC subscriber handles → observable side effect verified.
- **G3**: Cover every async handler in the enterprise repo with at least one integration/e2e test:
  - `operational-context/app/async/routes/dapr-subscriptions.ts`
  - `operational-context/app/subscribers/tenant-provisioned-handler.ts`
  - `operational-components/app/async/routes/dapr-subscriptions.ts`
  - `quality-rules/app/async/routes/dapr-subscriptions.ts`
  - `quality-rules/app/async/handlers/characteristic-projection-handler.ts`
- **G4**: Coordinate findings and plan with QE to ensure new tests integrate with the existing harness, not in parallel to it.

## Non-Goals

- Rewriting existing unit tests or the Rust-based api-harness.
- Changing the Dapr subscription wiring or event schemas.
- Achieving 100% line coverage — this is about exercising the async paths end-to-end, not covering every branch.
- Modifying CI pipeline infrastructure (only adding test invocations to existing pipeline stages).

## User Stories / Scenarios

**S1 — Test inventory consumer (developer or QE)**
As a developer or QE engineer, I want a single document listing every test suite, where it lives, how it runs, and what it covers, so I know where to add or find tests without guessing.

**S2 — Async event confidence (developer)**
As a developer modifying a Dapr subscription handler, I want an integration test that exercises the full event path (publish → subscribe → side effect) so I catch regressions before merge.

**S3 — QE coordination (QE engineer)**
As a QE engineer, I want the new integration tests to follow the existing harness conventions and run alongside current suites in CI, so I don't inherit a second, disconnected test ecosystem.

## Constraints

- Enterprise rig merges directly to `boylec/develop` (ADR-024) — no PR-based gating, tests must pass pre-merge.
- Dapr subscriptions run in Deno async processes — integration tests need a local Dapr sidecar or a mock that preserves the pub/sub contract.
- The Rust api-harness uses JSON fixture files and a custom runner — new tests should use the existing e2e framework (Playwright + API specs) or per-BC `_test.ts` patterns, not a third pattern.
- QE team bandwidth and process TBD — inventory and gap list must be shared before implementation begins.

## Open Questions

1. **How are the per-BC `_test.ts` files currently triggered in CI?** The `ci.yml` workflow needs to be audited for which `deno test` invocations actually run on each push/PR.
2. **Does the e2e suite (`tests/e2e/specs/api/tenant-provisioning-and-tiers.spec.ts`) already exercise any Dapr event path, or only the synchronous API?** If it does, the gap may be smaller than the review comments suggest.
3. **What is QE's preferred integration test pattern for async flows?** We should adopt their convention, not invent a new one.
4. **Can we run a local Dapr sidecar in CI, or do we need a contract-test approach** (e.g., publish a known event payload, mock the Dapr HTTP endpoint, verify handler behavior)?
5. **Are there async handlers beyond the five identified above** that were added recently or are in-flight on other branches?

## Rough Approach

1. **Audit phase**: Enumerate every test suite, its runner, trigger, and scope. Cross-reference with CI config (`ci.yml`, `playwright-run.yml`, etc.) to confirm what actually executes. Produce the inventory document.
2. **Gap analysis**: For each async handler, determine whether existing tests exercise the real event path or only mock it. Classify each as covered / partially-covered / uncovered.
3. **QE sync**: Share inventory + gap list with QE. Align on test pattern (e2e spec vs. integration `_test.ts` vs. api-harness fixture) and ownership.
4. **Design**: Propose integration test architecture — likely per-handler `_test.ts` files that start a local Dapr sidecar (or HTTP mock) and publish a real event, then assert on DB/API side effects.
5. **Implement**: Write tests for each uncovered async handler, starting with `tenant-provisioned-handler` (highest reviewer urgency).
6. **CI integration**: Ensure new tests run in the existing CI pipeline without a separate job.
