# Plan Review Manifest

- **Review ID**: test-harness-audit
- **Repo root**: /Users/caseyboyle/src/SafetyChain/gas-city
- **Coordinator**: quartermaster/nux (session hq-ig31qu)
- **Review target**: enterprise/polecat
- **Root bead**: hq-ds9gbvr (mol-sc-idea-to-plan)

## Problem Statement

Audit the existing test harness end-to-end — where every test suite lives, how/when it runs (CI, local, scheduled), what it covers — then design integration/e2e coverage for all async event handlers (identity → operational-context Dapr subscriptions, tenant-provisioned-handler, etc.). Coordinate with QE on the inventory and gap list; produce a plan and child beads for the concrete coverage additions.

Triggered by PR safety-chain/enterprise#405 review feedback.
