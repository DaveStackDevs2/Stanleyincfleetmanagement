
## 2026-08-18 — Pre-check-in Reservation editing

- **VERIFIED LIVE / RECORDED:** The browser-safe five-field edit backend preserves the existing Reservation, Transportation Event, and pricing agreement, and delegates the Transportation Event schedule mirror to the existing expected-return engine.
- **VERIFIED LIVE:** A controlled scheduled start, scheduled return, service advisor, RO number, and notes edit produced exactly five matching audit rows without VIN, continuity, contract period, pricing, billing, snapshot, or identity changes.
- **IMPLEMENTED / NOT YET VERIFIED IN PRODUCTION BROWSER:** Reservations now includes an RPC-only Edit Reservation workspace. Check-in / Pickup browser activation also remains **NOT YET VERIFIED**.
- **TBD / DEFERRED:** The future penalty-free edit cutoff remains TBD. Model, workflow, pay-type, and rate-plan edits remain deferred pending authoritative pricing and availability policy.

# Changelog

## 2026-08-18 — Check-in / Pickup timing and Billing eligibility

- Recorded verified-live Check-in orchestration: actual handoff starts continuity, while the established billing engine starts Billing and pricing at the Reservation scheduled start and preserves the scheduled return.
- Recorded verified-live Billing workspace eligibility through existing Transportation Event operational state, excluding normal pre-check-in Reservations with neither continuity nor billing.
- Recorded pre-check-in Reservation editing as the next checkpoint; no browser-safe general edit RPC or penalty cutoff exists yet. Weekly/monthly and “Now” remain deferred, and production browser Check-in activation is not verified.


## 2026-08-18 — Reservations Pickup and fleet compatibility

- Recorded the verified-live normalized reservation/vehicle fleet-type guard and model-plus-fleet-type candidate view after production overlap testing found Loaners in a Rental candidate list. The failed Rental-to-Loaner check produced no continuity or billing.
- Added RPC-only Pickup/VIN activation to Reservations with authoritative result/Billing preview display. This frontend is **NOT VERIFIED** by a production browser activation until after merge; weekly/monthly remains fail-closed and “Now” remains deferred. `vehicle_class` is retained but displayed as Vehicle model.


## 2026-08-13 — Operational Reservations workspace

- Recorded the verified secured intake and daily-only pickup RPCs in migration history without applying SQL to live Supabase.
- Implemented the operational Reservations destination with intake-driven existing customers, pay types, vehicle classes, configured plans, Quote/direct Reservation/Walk-in writes, active Quote review, and same-event conversion.
- Preserved pre-pickup boundaries: no VIN, vehicle use, contract period, pricing timer, billing line, arithmetic, tax, or cashiering action is started by the frontend. Pickup UI remains open.

## 2026-08-10 — Verified Extended Warranty reconciliation integration

- Added an idempotent, data-free migration recording the verified live `billing.extended_warranty_reconcile` permission, name-based Dev assignment, revoked browser execution of the unchanged payload engine, an explicit wrapper that adds the effective-permission boundary, and a non-AAL2 automatic Billing workspace orchestrator that calls the established lower-level reconciliation engine directly.
- Changed Billing Dashboard's single shared-client load to reconcile eligible active Extended Warranty cases before receiving the unchanged authoritative workspace payload. Complete validation, exact string monetary display, selected-case reload, Mark billed through, sanitized messages, separate case and vehicle timers, and read-only behavior remain intact.
- Recorded that Zurich creation through the existing Admin workflow and the live callable contract were verified. No provider, rate, covered-day cap, UUID, customer, vehicle, RO, or controlled fixture was seeded, and GM Warranty was not changed.
- Authenticated split-boundary browser verification, vehicle-swap verification, override verification, and unauthorized-session denial remain **OPEN / NOT VERIFIED**. Live Supabase was not modified by this work.

## 2026-08-05 — Extended Warranty mandatory provider cap follow-up

- Recorded the verified live mandatory-cap contract in an idempotent follow-up migration after the existing Extended Warranty live billing contract migration.
- Updated Extended Warranty Providers administration to remove provider-level approval controls, require a positive covered-day cap, validate returned compatibility `requires_approval` values as `false`, and keep sending `p_requires_approval: false` to the existing Admin RPC signatures.
- Preserved the existing case-level `billing.extended_warranty_override` path for exceptional coverage extensions and did not change GM Warranty behavior, pay-type behavior, rate behavior, coverage timers, VIN-swap continuity, or other billing engines.
- Real authenticated mutation/browser verification remains **NOT VERIFIED**; this repository migration is not claimed as applied live by this changelog entry.

## 2026-08-04 — Billing Phase 2 pay-type editing implementation

- Recorded the verified live ownership, security-definer/search-path configuration, authorization path, and restricted execution grants for `update_admin_pay_type_rule_state(uuid, boolean, numeric, integer, text)` in an idempotent repository migration.
- Added editing for existing enabled and disabled pay types to Rates, Fees & Billing Rules, limited to description, taxable status, nullable default daily amount, and sort order; pay-type identity remains read-only.
- Added strict mutation-response validation, authoritative rules-and-colors reload, sanitized success/failure states, uncertain-result guidance, cancellation, and duplicate-submission prevention.
- Added focused repository-native contract tests. Deployment, real-session/browser verification, and the overall Phase 2 exit remain **NOT VERIFIED**.

## 2026-08-04 — Phase 1 live deployment reconciliation

- Verified that GitHub `main` includes the start/assign/bill, continuation/reassignment, and PL/pgSQL terminator checkpoint merges from PRs #11–#13.
- Verified that live Supabase contains the six secured top-level case-write RPCs and the expected browser-role, internal-helper, service-role, direct-table, unique-index, and same-vehicle restart boundaries.
- Removed stale documentation claiming the continuation/reassignment and start/assign/bill migrations were still waiting for live application.
- Kept broad Phase 1 open for real-session anonymous, unauthorized, authorized, RLS, and browser workflow tests.
- Recorded Phase 2 pay-type editing as the next implementation step and preserved the unresolved Ontrac import-path verification.
- Changed documentation only; no SQL, production data, frontend code, authorization behavior, or billing behavior changed.

## 2026-07-30 — Fleet Board Day timeline

- Added a horizontally scrollable Day timeline for the fixed 7:00 AM–7:00 PM operating window, with twelve hourly intervals, a final 7:00 PM boundary, and sticky hourly and VIN headers.
- Positioned and clamped assignments from actual operational timestamps, added deterministic overlap lanes, and expanded VIN rows when assignments overlap.
- Added adaptive pay type, transportation-event status, source type, and time details while preserving Admin-configured colors, neutral fallback colors, and conflict indicators.
- Added a once-per-minute current-time marker shown only for today's displayed operating window, and preserved Reservation Capacity and Week view behavior.
- Made no database, authorization, Supabase configuration, or workflow changes.

## 2026-07-29 — Admin pay-type management

- Connected Rates, Fees & Billing Rules to the live Admin pay-type RPC contracts.
- Added strict payload validation, pay-type creation, disable/reactivate actions, and authoritative reloads after successful mutations.
- Added explicit Fleet Board palette editing for active pay types with native color inputs, six-digit hex validation, and one neutral fallback pair.
- Added the idempotent repository migration for the three already-live Admin pay-type functions and their verified execution grants.
- Recorded the verified unique normalized pay-type index so case-insensitive uniqueness is enforced atomically.
- Added an accessible inline confirmation after Fleet Board colors save and reload successfully.

## 2026-07-29 — Fleet Board live read contracts

- Replaced Fleet Board table/view reads with the authenticated, visible-period `get_fleet_board_state` RPC.
- Added the idempotent repository migration for the already-live Fleet Board state and pay-type color functions, grants, Admin setting, and `user_admin.manage` mapping.
- Applied validated saved pay-type colors with a single neutral fallback; the Admin palette UI remains future work.

## 2026-07-29 — Fleet Board foundation

- Removed the Vehicle Calendar navigation, page state, component imports, calendar components, calendar-only CSS, and calendar permission references.
- Removed the unmerged branch-only calendar-foundation migration and its separate scheduling model.
- Added a read-only Fleet Board that visualizes existing vehicles, model-level reservations, rental capacity, and unified transportation-event operational state.
- Preserved the authenticated application boundary and did not invent a Fleet Board permission.
- Added no database objects, migrations, hardcoded production values, or frontend mutation rules.
- Corrected date navigation to use local calendar arithmetic and ignore invalid date-picker values.
- Excluded only the verified `cancelled` reservation status from displayed capacity and stopped treating resolved conflicts as active.
- Documented missing authenticated reads and a missing backend-supported assignment range boundary as backend blockers rather than adding unsafe frontend workarounds.

## 2026-07-28

### Phase 2 — User and role management

- Added the seven required system roles and the minimal `user_admin.manage` administration permission.
- Added a single-role constraint and per-user permission overrides with `grant` and `deny` effects.
- Replaced effective-permission calculation with role defaults plus grants minus denies.
- Added permission-checking authenticated RPCs for management payloads, role assignment, user overrides, and role default permissions.
- Switched current-user permission loading to a scoped RPC rather than direct effective-permission view access.
- Added Users and Roles administration pages, permission editing, role assignment, override editing, and effective-permission inspection.
- Kept role names out of frontend authorization decisions; navigation and management access use the effective `user_admin.manage` permission.

### Phase 2 verification

- `npm run build`: passed.
- `npm run lint`: passed.
- `git diff --check`: passed.
- Live migration application and authenticated browser behavior were not verified.

### Hardened after focused review

- Moved pathname/history synchronization out of `AuthGate` render and into an effect.
- Made session initialization settle safely if `getSession()` unexpectedly rejects while preserving auth-event race protection.
- Invalidated in-flight authorization work on every session change, including same-user session refreshes, and withheld previously loaded authorization synchronously while a new session is verified.
- Ensured sign-in submission always settles and added sanitized handling for unexpected sign-in and sign-out failures.
- Added live status semantics to authentication and authorization loading messages.

### Added

- Typed Supabase Auth context, provider, and `useAuth` hook with session initialization, auth-state subscription, sign-out, and subscription cleanup.
- Minimal email/password sign-in page and `/sign-in` pathname handling without a routing dependency.
- Typed, read-only authorization context, provider, and `useAuthorization` hook.
- Fail-closed loading and validation for the application user, authentication access gate, role names, and effective permission keys.
- Central `AuthGate` with distinct authentication and authorization loading states and a sanitized denied-access screen.

### Changed

- Wrapped the existing frontend with authentication, authorization, and application-entry gates.
- Sanitized the existing fleet-load failure message so raw backend errors are not shown.
- Updated the production security follow-up with the authorization contract grant discrepancy and required live follow-up.

### Verification

- `npm run build`: passed.
- `npm run lint`: passed.
- `git diff --check`: passed.
- The frontend source contains exactly one `createClient(` occurrence in the existing shared client.

### Intentionally unresolved

- No SQL, schema, migration, function, view, grant, policy, trigger, or seed changes were made.
- Live database access for the authenticated browser role was not verified.
- MFA, password reset, feature-level permission rules, navigation restrictions, and role-management UI were not implemented.

## 2026-08-04 — Billing Phase 3 rental rate administration implementation

- Recorded the already-applied live Phase 3 rental-rate contract in an idempotent repository migration without seeding or inventing business rates.
- Extended Rates, Fees & Billing Rules with RPC-only rental-rate administration for Admin-entered vehicle class/model identifiers, pay-type selection, daily rate, sort order, and Disable/Reactivate controls. Delete behavior was not added.
- Added focused structural tests for the Phase 3 schema/RPC/security/frontend contract. Live Supabase verification had already passed before this repository implementation; frontend deployment and browser verification remain **NOT VERIFIED**.

## 2026-08-05 — Extended Warranty live billing contract

- Recorded the already-verified Extended Warranty billing contract in one idempotent migration, including nullable/positive covered-day caps, nullable finite nonnegative daily amounts, required provider/rule relationships, one active rule per provider, normalized provider-name uniqueness, case snapshots, override permission assignment, owners, security modes, search paths, and grants.
- Added runtime RPC definitions for creating Extended Warranty cases, saving authorized covered-day overrides with audit logging, internal cap reconciliation, and browser-facing coverage state retrieval that keeps case-level coverage continuity separate from the current vehicle timer.
- Added Extended Warranty Providers administration to Rates, Fees & Billing Rules through the shared Supabase client and Admin RPCs only, with Add, focused Edit, Disable, and Reactivate; no Delete workflow was added.
- Preserved GM Warranty separation, existing pay types, historical provider/pay-type records, existing billing engines, and the no-cashiering boundary. Live contract/grants and static boundary checks passed; provider/rule/case/billing tables had zero rows. Real-session/browser verification remains open.

## 2026-08-06 — Billing Phase 4: authoritative loaner/rental tax

- Added the idempotent authoritative tax migration, exact numeric resolver, immutable billing snapshots, parent/child tax orchestration, secured Admin tax RPCs, fixed warranty exemptions, fixed pay-type taxability, and legacy low-level browser revocations.
- Added a focused Loaner & Rental Tax Admin view using RPC-only reads/writes and exact percentage-to-decimal conversion; pay-type taxability is now read-only.
- Recorded the verified live contract without touching live Supabase. Authenticated Admin mutation and browser verification remain **NOT VERIFIED / OPEN**.
- 2026-08-06: Corrected Phase 4 tax integration drift by using unrestricted numeric tax-rate snapshots and propagating omitted tax as `NULL` through all live start/bill and extension orchestration layers, preserving exact authoritative calculation and existing security/grant boundaries.

## 2026-08-06 — Correct Phase 4 pay-type taxability

- Added an idempotent follow-up migration matching the verified live synchronization constraint and resolver/create/update contracts. Stored Admin taxability is authoritative; no exemption is inferred from a pay-type name and no production rows are seeded or rewritten.
- Restored editable Taxable checkboxes to Add Pay Type and focused Edit Pay Type, submitting `p_is_taxable` with complete validated mutation payloads and retaining authoritative reload and sanitized feedback.
- Preserved exact no-rounding arithmetic, unrestricted numeric snapshots, separate tax child lines, null-tax propagation, the 10% Admin setting, owners/security/search paths/grants, immutable pay-type names, Disable/Reactivate, and Fleet Board colors.
- Real authenticated mutation/browser and full operational start/bill/extension verification remain **NOT VERIFIED / OPEN**. Live Supabase was not touched.

## 2026-08-07 — Operational Billing Dashboard

- Recorded the already-verified live billing preview/workspace RPCs in one idempotent migration with active-user/AAL2 enforcement, exact backend calculations, sanitized deterministic states, postgres ownership, restricted search paths, and authenticated-only execution.
- Made Dashboard open by default and added a focused read-only Billing workspace with strict whole-payload validation, exact-string totals, attention states, billing-segment details, Extended Warranty state, and authoritative Refresh.
- Added structural contract tests. Live Supabase was not touched; authenticated browser/deployment verification and every operational billing mutation remain **NOT VERIFIED**.

## 2026-08-07 — Operational Billing Dashboard read-only follow-up

- Added a drift-safe, idempotent migration matching the verified live removal of AAL2 from only the two read-only Billing RPCs and the addition of nullable reservation `ro_number`, while retaining active-user validation, exact function security/ownership/search-path/volatility, and authenticated-only grants.
- Redesigned active loaner and rental cases as tightly spaced, full-width keyboard/click navigation containers leading to an individual read-only detail destination with a clear return action.
- Added chronological closed-segment summaries, a deduplicated flat current segment, exact accumulated pre-tax and separate-tax rows, rental summaries, sanitized attention navigation, and distinct Extended Warranty/current-vehicle timers without frontend arithmetic or writes.
- Live Supabase was not changed. Real non-empty-case and browser behavior remain **NOT VERIFIED** because live currently has zero active transportation cases.

## 2026-08-10 — Authoritative Billing start and Tekion checkpoint

- Recorded the verified live permission-scoped authoritative case-start and billed-through contracts in one idempotent, data-free migration; restricted the obsolete caller-total wrapper and low-level billed-through engine.
- Added the selected-case “Mark billed through” Dashboard action with explicit user submission, deterministic response validation, sanitized messages, and authoritative reload that preserves selection when practical.
- Applied exact-string, non-rounding monetary formatting throughout Billing and recorded only the verified controlled Customer Pay path as complete. Other operational workflows remain explicitly open.

## 2026-08-10 — Verified Billing Complete / Return Case

- Added the idempotent repository migration for the verified `billing.case_complete` permission, name-based Dev assignment, and effective-permission-protected completion wrapper while preserving the internal completion engines and authenticated-only execution boundary.
- Added a focused selected-case Complete / Return screen with read-only case identity, local actual-return time, optional validated mileage and note, shared-client RPC-only submission, strict deterministic response checks, sanitized feedback, authoritative Billing reload, and focused success destination.
- Preserved Mark billed through, existing cards and selection behavior, exact-string monetary handling, and read-only functionality. Live Supabase was not touched; authenticated browser completion and final database readback remain **OPEN / NOT VERIFIED** until deployment and exercise.

## 2026-08-11 — Pay-type-independent rental rate cards

- Recorded the verified live rate-card contract in one data-free compatibility-preserving migration and moved only Rental Rates administration to the five new pay-type-independent RPCs.
- Added required daily and optional weekly/monthly focused Add/Edit controls, strict complete-payload validation, authoritative reloads, Disable/Reactivate, and no Delete action.
- Marked pricing-agreement and downstream Quote/Reservation/Walk-in conversion, insurance, discount, override, and ledger work OPEN; this change did not touch live Supabase or business values.

## 2026-08-12 — Shared rental-pricing-agreement foundation

- **VERIFIED LIVE CONTRACT / IMPLEMENTED IN REPOSITORY:** The data-free migration records the shared pricing agreement, one-Transportation-Event Quote/direct Reservation/Walk-in architecture, same-event Quote conversion, secured Dev/AAL2 RPC boundary, billing compatibility snapshots, monthly-requires-weekly prerequisite, central audit trail, and protected-table privilege corrections.
- **NOT APPLICABLE:** No live Supabase change or production seed was performed; no pickup, VIN, timer, contract-period, pricing activation, calculation, discount, insurance, payment, cashiering, allocation, or billing-line workflow was started.
- **OPEN / NOT IMPLEMENTED:** Frontend Quote/Reservation/Walk-in workflows and every post-pickup pricing and payment capability listed in the Billing Build Punchlist remain open.

## 2026-08-14 — Required TOTP MFA gate

- Added an auth-level, fail-closed Supabase TOTP enrollment/challenge flow after existing application authorization and before operational application rendering.
- Added QR and manual-secret setup, accessible six-digit verification, sanitized retry/sign-out handling, session refresh, and mandatory AAL2 re-checking.
- Preserved the shared Supabase client and server-side AAL2 RPC enforcement; no SQL, migration, business logic, or live Supabase change was made. Production-browser MFA and protected-workflow verification remain **NOT VERIFIED**.

## 2026-08-18 — Reservations vehicle-model and Rental pay-type invariant

- **VERIFIED LIVE:** Production MFA/AAL2 and Reservations authoritative intake succeeded in a real browser. Admin configured the canonical active/taxable `Rental` pay type with NULL default amount.
- **IMPLEMENTED:** User-facing Reservations uses Vehicle Model, while backend `vehicle_class` and `p_vehicle_class` compatibility names remain unchanged. Rental auto-selects and exclusively offers authoritative `Rental`; Loaner excludes it and switching clears the selection.
- **VERIFIED LIVE / REPOSITORY RECORD:** Live already has the `create_vehicle_state` `vin_last8` repair and bidirectional Rental/pay-type pricing-agreement trigger. One idempotent data-free migration records them without live application.
- **NOT SEEDED:** `TEST-STOCK-002` and `TEST-STOCK-003` are controlled live verification vehicles, not repository data.
- **OPEN:** Pickup/VIN frontend is next; weekly/monthly pickup billing remains unimplemented and fail-closed.

## 2026-08-19 — Closed Billing review

- Recorded the verified-live closed stored-snapshot preview and secured bounded wrapper, and added an RPC-only read-only Closed cases mode with complete segment history to Billing.
