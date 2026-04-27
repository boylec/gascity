# Plan Review Manifest

- **Review ID**: permissions-api
- **Repo root**: /Users/caseyboyle/src/SafetyChain/gas-city
- **Coordinator**: quartermaster-3
- **Review target**: enterprise/polecats.sonnet
- **Target rig**: enterprise
- **Root bead**: hq-t0jos9
- **Linear ID**: SAF-449
- **Problem**: Implement Permissions API per Linear spec — endpoints:
  GET /api/v1/permissions (list, paginated), GET /api/v1/permissions/:permissionId
  (detail). Resource prefix perm_. Formalize permission string literals as a
  registry. Decision: seeded in DB or static registry in code.
- **Context**: Phase 1 (static registry) is already implemented on boylec/develop.
  Remaining work: review verification, pagination decision, Phase 2 doc, follow-ons.
