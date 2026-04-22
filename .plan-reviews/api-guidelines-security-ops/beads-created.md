# Implementation Beads — SAF-88: API Guidelines Security, Operations & Extensibility

**Convoy:** hq-jgkny
**Linear:** SAF-88
**Created:** 2026-04-22
**Coordinator:** quartermaster-1

## Beads (11 tasks, 3 opus-high / 8 sonnet)

| # | Bead ID | Title | Tier | Blocked By |
|---|---------|-------|------|------------|
| 1 | hq-af404 | Fix section 16 rate-limit tenant ID reference | sonnet | — |
| 2 | hq-ljmj9 | Write section 04 (Response Envelope) from existing code | sonnet | — |
| 3 | hq-i9sog | Write section 23 (Tooling Integration) from existing OTEL stack | sonnet | — |
| 4 | hq-tpqgk | Add API guidelines Key References to CLAUDE.md | sonnet | — |
| 5 | hq-8fdxb | Conformance audit of OC against API guidelines sections 15-23 | opus-high | 1, 2, 3, 4 |
| 6 | hq-6y6mq | Add WWW-Authenticate header to 401 responses | sonnet | — |
| 7 | hq-f51ho | Implement rate limiting middleware (Redis token bucket) | opus-high | 1, 5 |
| 8 | hq-vkcgm | Implement idempotency middleware (Redis SET NX) | opus-high | 5 |
| 9 | hq-jwp9c | Add /version endpoint + fix /ready response shape | sonnet | — |
| 10 | hq-brmin | OpenAPI spec-drift CI validation | sonnet | — |
| 11 | hq-5zwan | Enable rate limiting + idempotency in OCC and QR | sonnet | 7, 8 |

## Dependency DAG

```
1 (fix §16) ──┬──► 5 (audit) ──┬──► 7 (rate limit) ──┬──► 11 (propagate)
2 (§04 doc) ──┤               └──► 8 (idempotency) ──┘
3 (§23 doc) ──┤
4 (CLAUDE.md)─┘

6 (WWW-Auth)     ← independent
9 (health)       ← independent
10 (OpenAPI CI)  ← independent
```

## Artifacts

- PRD: `.prd-reviews/api-guidelines-security-ops/prd-draft.md`
- PRD Review: `.prd-reviews/api-guidelines-security-ops/prd-review.md`
- Design Doc: `.designs/api-guidelines-security-ops/design-doc.md`
- Design Reviews: hq-rvo6 (api), hq-s6nm (data), hq-pv9m (ux), hq-sr48 (scale), hq-wwn4 (security), hq-yceh (integration)

## Dispatch

```bash
gc sling hq/mayor mol-sc-sling-convoy --formula --var convoy_id=hq-jgkny
```
