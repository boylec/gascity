# PR 405 rev2 — Bucket D: questions needing human discussion

17 review comments that weren't filed as beads because the reviewer raised a concern/question rather than prescribing a fix. Answer inline in the `> ANSWER:` block under each item and hand back; mayor will act on the resolved set.

Legend: each item shows file:line, the reviewer's verbatim text, mayor's reading (what's ambiguous / what B/C bead it touches if relevant), then an answer block.

---

## Group 1 — Blocked on SAF-447..450 Linear breakdown (6)

All six items reference SAF-447..450 (tenant seeding / users / roles / permissions). Until those Linear issues are broken down in Gas Town, everything in this group stays frozen.

### D1.1 — `contexts/identity/app/api/routes/roles.ts:12`

> Need to file linear issues 447-450 to beads formula. These issues will touch this file and many others. Blocker until SAF 447-450 are broken down.

Reading: this is an explicit ask to run SAF-447..450 through `mol-sc-idea-to-plan` with `--var linear_id=SAF-447` (etc.). Mayor can kick off those cooks.

> ANSWER: 

### D1.2 — `contexts/identity/app/api/routes/roles.ts:152`

> Do identity routes require elevated auth? Checking for permissions? Tied to SAF 447-450 (tenant seeding, access control).

Reading: auth-on-roles-routes design question; reviewer is signalling it should be answered as part of SAF-447..450 decomposition, not in isolation.

> ANSWER: 

### D1.3 — `contexts/identity/app/routes/permissions.ts:1`

> may be covered by SAF 447-450 (TODO). Clarify scope of SAF 447-450.

Reading: does SAF-447..450 already encompass this file, or is it adjacent?

> ANSWER: 

### D1.4 — `contexts/identity/app/routes/user-roles.ts:5`

> may be covered by SAF 447-450 (TODO). Clarify scope of SAF 447-450.

Reading: same as D1.3 — file-scope vs SAF-447..450 scope.

> ANSWER: 

### D1.5 — `contexts/identity/app/services/permission-resolution.ts:4`

> may be covered by SAF 447-450 (TODO). Clarify scope of SAF 447-450.

Reading: same as D1.3/D1.4. Note: Bucket C theme C2 (DDD ports/services — `hq-uww31id`) is independently wrestling with permission-resolution as port-vs-service. If SAF-447..450 rewrites this file, C2's recommendations may become moot or need reconciliation.

> ANSWER: 

### D1.6 — identity routes section in `contexts/identity/app/api/main.ts`

> (distinct from the `:319` env-var comment covered by B9/sc-050tu) — identity routes require elevated auth? Multiple routes in this file touch permissions. Tied to SAF-447..450.

Reading: broader-surface version of D1.2 — the whole file's auth posture is under SAF-447..450.

> ANSWER: 

### D1-meta — unified ask for this whole group

Do you want mayor to:
- **(a)** Cook SAF-447, SAF-448, SAF-449, SAF-450 through `mol-sc-idea-to-plan` right now (4 quartermaster workflows) and then revisit D1.1–D1.6 once the plans come back?
- **(b)** Hold off — you'll break down SAF-447..450 yourself?
- **(c)** Cook one combined workflow that covers all four Linear IDs in a single plan?

> ANSWER (a/b/c):

---

## Group 2 — Design-intent clarification (5)

Bucket B beads took a mechanical interpretation of each of these comments. If the reviewer's intent was different, the bead needs to be retargeted or superseded.

### D2.1 — `aspire/SafetyChain.AppHost/Program.cs:139` (CHANGE_ME default)

> its strange to set them to "CHANGE_ME" and make that default the way to disable broker buttons on login page no? why not make the lack of the env var the trigger for disabling... or sometthing more obvious/mechanical besides "CHANG_ME"?

B4 (`sc-vx3hl`) took: "make absence of env var the trigger; remove CHANGE_ME as a sentinel." Alternative interpretations: (i) explicit boolean feature flag `EnableBrokerButtons`, (ii) different sentinel that errors at startup rather than silently disabling.

> ANSWER (B4 interpretation OK, or pick one of the alternatives):

### D2.2 — `aspire/SafetyChain.AppHost/Program.cs:248` (port 8083 pinning)

> is 8083 port pinned? or is that the default for kafka connect? or both? we should pin it if we are hard coding it here. should we not plug in this value from the "kafkaConnect" variable rather than hard-coding?

B5 (`sc-nhudn`) assumed: "consume from `kafkaConnect.GetEndpoint(...)` handle; pin declaratively on the resource if needed." Open question: is there a reason to *intentionally* pin 8083 (host tooling expects it)? If so, B5 should pin + comment; if 8083 is just the Kafka Connect default, B5 should let the resource auto-assign.

> ANSWER (pin 8083 or let resource auto-assign):

### D2.3 — `contexts/identity/domain/aggregates/tenant.ts:33` (isAdmin rename)

> Consider renaming "isAdmin" to "ownerUserId"

Reading: this is a model-shape question. `isAdmin` implies role-based admin (multiple admins possible); `ownerUserId` implies owner-singular (one owner, distinct from admin role). Picking one changes the tenant aggregate semantics.

> ANSWER (role-based admin, owner-singular, or other):

### D2.4 — `contexts/operational-context/domain/aggregates/tenant-taxonomy-node.ts:219` (removed validation)

> it looksl ike we removed this validation piece across item taxonomy node AND tenant taxonomy node. thats fine... but it sort of speaks to the need to factor validation out into the base taxonomy type/object no?

C3 (`hq-jbl5ozk`) is already cooking "lift validation to a shared base taxonomy type." Open question: was the removal *intentional* (validation moves elsewhere, or was genuinely redundant) or a *drop* (should have been retained in some form)?

> ANSWER (intentional removal / retain in base / restore per subtype):

### D2.5 — `contexts/identity/app/employee-auth-routes.ts:6` (employees = ?)

> Are these routes for tenant employees (customer's staff) or SafetyChain employees?

Reading: scope/naming ambiguity. Tenant employees = customer's workforce (many tenants, diverse populations). SafetyChain employees = internal SC staff (one population, Google Workspace per B3/sc-b5w.21). They're very different auth surfaces.

> ANSWER (tenant-employees / SafetyChain-employees / both):

---

## Group 3 — Test-coverage confirmation questions (3)

C5 (`hq-ds9gbvr`) will produce a test-harness audit and gap plan, but these three questions deserve your read before the plan comes back.

### D3.1 — `contexts/operational-context/app/async/routes/dapr-subscriptions.ts:329`

> do we have e2e or integration tests that ensure that identity -> this BC comms via events are actually working?

Reading: the answer is either "yes, under `tests/...`" or "no, need to add them." If yes, point C5 at the existing suite; if no, C5 will file child beads.

> ANSWER (existing suite location / confirm missing):

### D3.2 — `contexts/operational-context/app/subscribers/tenant-provisioned-handler.ts:64`

> is there an integration, e2e, or other test path that flexed this subscription and makes sure it does what its supposed to do?

Same question for the tenant-provisioned subscription specifically.

> ANSWER (existing suite location / confirm missing):

### D3.3 — `presentation/builder-studio/src/components/session-expired-modal.tsx:3`

> Test coverage for session expiry modal (e2e/smoke/integration)?

Reading: UI component test. Not in C5's scope (C5 covers async handlers, not UI). Needs its own answer: do we have a test pattern for builder-studio modals? If yes, add coverage (small enough to be a B-type bead); if no, that's a larger tooling gap.

> ANSWER (existing pattern exists / file as new bead / defer):

---

## Group 4 — Route-migration clarification (2)

Both about deletions in `operational-context/app/platform/api/main.ts`.

### D4.1 — `contexts/operational-context/app/platform/api/main.ts:190`

> Code removed — did routes move elsewhere or just deleted?

Reading: diff-intent question. Did the routes that were at line 190 move to another file (where?) or were they deliberately removed?

> ANSWER (moved to <path> / deleted permanently / temp-removed pending X):

### D4.2 — `contexts/operational-context/app/platform/api/main.ts:180`

> Hardcoded platform API docs. Temporary, pending UI layer? Needs clarification; may be blocked on future work.

Reading: the hardcoded docs are a known placeholder — reviewer wants to confirm and know what unblocks replacing them.

> ANSWER (placeholder until <X>, file bead / final form / delete):

---

## Group 5 — Contract clarity (1)

### D5.1 — `contexts/identity/contracts/permission-resolution.ts:15`

> Are roles/permissions hard-coded, or can customers edit them? What's the current state? Unclear whether these are just mappings or configurable.

Reading: current-state question. Two distinct worlds: (i) static compile-time mapping (roles/permissions baked into code), (ii) runtime-editable (each tenant customizes). Which world are we in today, and which are we moving toward?

Note: if the answer is "customer-editable and it touches routes", this may merge into the SAF-447..450 scope (Group 1).

> ANSWER (current state + target state):

---

## Summary of pending decisions

Before mayor can act, the following decisions are needed from you:

- **Group 1** — 6 items frozen pending SAF-447..450 Linear breakdown. Also one meta-question (a/b/c) on how to kick those cooks off.
- **Group 2** — 5 items where Bucket B beads may need retargeting based on your design intent.
- **Group 3** — 3 items to inform the test-harness cook's direction.
- **Group 4** — 2 items about the operational-context main.ts diff intent.
- **Group 5** — 1 item about permission-resolution runtime shape (possibly subsumed into Group 1).

Hand this file back with answers inline; mayor will read each `> ANSWER:` block and file beads, supersede existing beads, or decline individual items as you direct.
