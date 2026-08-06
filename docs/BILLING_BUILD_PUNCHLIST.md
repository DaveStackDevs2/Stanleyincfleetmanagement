# Billing Build Punchlist

## Purpose

This is the authoritative implementation checklist for completing Stanley Fleet Management billing. It is based on the live Supabase schema and the current `main` frontend, not on assumed or redesigned behavior.

Every billing implementation commit must update this file. An item is marked complete only after its code is published to GitHub, required live SQL has been executed and verified, and the relevant build or browser checks pass.

## Non-negotiable boundaries

- Transportation Events remain the operational source of truth.
- Reservations remain model/class-level until VIN assignment at pickup.
- Reuse the existing billing-line, contract-period, vehicle-event, extension, return, renewal, and swap workflows.
- Business calculations and authorization remain in Supabase, not the React frontend.
- Use the existing shared Supabase client. Normal operational case-write RPCs require an active authenticated application user and AAL2, with no separate permission key; `user_admin.manage` remains required for the Admin/configuration workflows that use it.
- Do not expose low-level mutation functions directly to the frontend.
- Do not hardcode rates, taxes, pay types, or production values.
- Do not repurpose `rental_model_limits`; it controls reservation capacity, not pricing.
- Do not build against `billing_event_totals`, warranty ledgers, or other unused scaffolding unless live workflow usage is first proven.
- Execute live SQL one statement at a time, verify its result, then record the exact repository migration.
- Late fees remain disabled and deferred. Applicable dollar amounts must eventually be editable in Admin Rates, Fees & Billing Rules from `public.late_fee_rules.fee_amount`, but configuring an amount must not charge it automatically. Fees remain discretionary, staff-applied, waivable/reversible, and must preserve actor, reason, timestamp, and audit history.

## Status legend

- `[x]` Completed and verified.
- `[ ]` Not started or not yet fully verified.
- `BLOCKED` Cannot proceed without a verified dependency.
- `DEFERRED` Explicitly outside the core billing release.

## Verified baseline — 2026-07-30

- [x] Confirmed current GitHub `main` begins at `322de950314078c3c12e0f34397a64b3afe80bea`.
- [x] Confirmed the current checkpoint baseline is GitHub `main` at `0cb1ec43d50512500bbbe36382e33149d183c873`; the preceding SHA remains above as historical context.
- [x] Confirmed the Admin Console routes Rates, Fees & Billing Rules to the existing `PayTypeManagement` page.
- [x] Confirmed the frontend can list, create, disable/reactivate, and color pay types.
- [x] Confirmed the Add Pay Type form accepts `default_daily_amount`, but existing pay types cannot be edited.
- [x] Confirmed all eight live pay types are active and all eight `default_daily_amount` values are null.
- [x] Confirmed `billing_lines` and `contract_periods` currently contain no production rows.
- [x] Confirmed the live GM warranty rate, warranty provider, and extended-warranty rule tables are empty.
- [x] Confirmed late fees are disabled and the live placeholders are `grace_period` = null, `fixed_fee` = 0, and `full_day_trigger` = 0 in `public.late_fee_rules.fee_amount`.
- [x] Confirmed existing billing functions store parent lines, tax child lines, paid-through state, extensions, returns, renewals, and swaps.
- [x] Confirmed current billing functions accept amount and tax inputs; they do not calculate authoritative amounts from pay-type defaults.
- [x] Confirmed frontend-safe/AAL2 metadata is not itself an enforcement layer. Backend authorization and grants must be verified before frontend writes are enabled.

## Core billing release definition

The core billing release is complete when an authorized user can configure normal rates and tax behavior, start billing from an existing operational event, review an authoritative breakdown, extend or close billing, handle vehicle continuation or swap through existing workflows, and reopen the same state from the Fleet Board without duplicate frontend calculations.

## Phase 1 — Reconcile and secure existing billing contracts

- [x] Capture the exact live definitions, ownership, security mode, grants, RLS dependencies, and callers for every high-level billing workflow used by the frontend.
- [x] Identify the smallest high-level RPC boundary for configuration reads, billing activation, extension, close/return, same-vehicle continuation, and vehicle swap.
- [x] Keep low-level line and continuity functions internal; revoke browser execution where direct access is unnecessary.
- [x] Enforce authenticated application-user identity inside every frontend-callable write RPC. The verified operational boundary uses an active application user plus AAL2 and does not invent a separate feature-permission key.
- [x] Enforce the required AAL2 rule in executable backend code rather than relying on service-action metadata.
- [x] Reconcile the live function/grant changes into idempotent repository migrations without redesigning the existing workflows.
- [x] Add sanitized, deterministic RPC status payloads that the frontend can structurally validate.
- [ ] Verify anonymous denial, unauthorized authenticated denial, authorized success, and RLS behavior end to end with real application-user sessions. Static live grants and role access are verified.
- [x] Update this punchlist, `PROJECT_STATUS.md`, and `CHANGELOG.md`. No new security-boundary decision was made, so `DECISIONS.md` is unchanged.

**Phase 1 exit:** The frontend has a verified secure boundary for existing billing workflows; no rates or billing UI are added prematurely.

The repository and live Supabase now match for extension, completion/return, cancellation, start/assign/bill, same-vehicle continuation, and active-case reassignment. All six top-level case-write RPCs have verified ownership, security-definer/search-path settings, and role grants; internal helpers and direct workflow-table mutations remain unavailable to browser roles. Broad Phase 1 remains open only until anonymous, unauthorized authenticated, authorized success, and RLS behavior are exercised end to end with real application-user sessions. Ontrac mileage application/import-path verification remains unresolved: no live function or trigger applying staging odometer rows has been verified. Optional return and checkout mileage behavior is preserved. Excess-mile calculation remains future work.

## Phase 2 — Complete existing pay-type administration

**2026-08-04 checkpoint:** The live RPC and grants are verified. The repository migration, focused contract tests, and frontend editing workflow are implemented. Deployment and real-session/browser verification remain open.

- [x] Add an authorized backend mutation for editing an existing pay type's description, taxable flag, default daily amount, and sort order.
- [x] Preserve pay-type identity and historical references; do not rename or delete pay types through an unsafe replacement workflow.
- [ ] Keep Disable/Reactivate behavior and Fleet Board color behavior intact.
- [x] Add editing controls to the existing Rates, Fees & Billing Rules page.
- [x] Validate nonnegative currency and whole-number sort order in the backend; frontend validation is only user guidance.
- [x] Reload authoritative state after every successful mutation and show explicit success/failure feedback.
- [ ] Verify editing, disabling, reactivating, duplicate-name protection, invalid input rejection, and historical retention.
- [ ] Update this punchlist and recovery documentation in the same commit.

**Phase 2 exit:** Dave can configure and maintain every existing pay type, including its default daily amount.

## Phase 3 — Establish the normal rental-rate source of truth

- [ ] Verify the exact model/class keys already used by `reservations.requested_model`, `quotes.vehicle_class`, vehicles, and rental-capacity configuration.
- [ ] Document the required rate precedence: explicit authorized override, model/class rate, pay-type default, or a safe missing-rate failure.
- [x] Determine the smallest backend object needed for model/class pricing because no live model/class rate source currently exists.
- [x] Do not hardcode Chevrolet model prices; rates must be entered and maintained in Admin.
- [x] Add effective status and historical preservation so changing a rate does not rewrite prior billing lines.
- [x] Add an authorized read/write RPC contract rather than direct frontend table writes.
- [x] Extend the existing Rates, Fees & Billing Rules page with model/class rate administration.
- [x] Verify rate creation, update, disable/reactivate, missing-rate behavior, historical snapshots, and duplicate-key protection in the pre-existing live Phase 3 backend verification; browser verification remains open.
- [x] Update this punchlist and recovery documentation in the same commit.

**Phase 3 exit:** The database can resolve the correct configurable daily rate for a requested model/class and pay type without frontend business rules.

## Phase 4 — Establish authoritative tax calculation

- [ ] Verify the dealership's required taxable base and current tax configuration source; do not infer a percentage from the pay-type taxable flag.
- [ ] Add the minimum Admin-managed tax configuration only if no existing live source is found.
- [ ] Calculate tax in a backend resolver using the selected pay type's taxable status and the authoritative rate configuration.
- [ ] Preserve the existing separate tax child-line design.
- [ ] Snapshot the applied tax result so later configuration changes do not alter historical billing.
- [ ] Support a safe, explicit non-taxable result for GM Warranty and Extended Warranty pay types as currently configured.
- [ ] Verify taxable, non-taxable, zero-dollar, rounding, missing-configuration, and historical cases.
- [ ] Update this punchlist and recovery documentation in the same commit.

**Phase 4 exit:** Backend calculations return a reproducible amount, tax amount, rate source, and explanation.

## Phase 5 — Build the billing calculation/preview contract

- [ ] Add one backend calculation/preview RPC that accepts verified operational identifiers and dates—not arbitrary trusted frontend totals.
- [ ] Resolve reservation/event, assigned vehicle, model/class, pay type, contract period, dates, rate, and tax from existing state.
- [ ] Return a validated preview containing line type, start/end, billable duration, daily rate, subtotal, tax, total, and any missing dependency.
- [ ] Reject impossible ranges, inactive pay types, missing operational records, missing rates, and unauthorized overrides.
- [ ] Ensure preview calculation and committed billing use the same backend resolver.
- [ ] Add contract tests or repeatable SQL verification for representative rental, loaner, taxable, and warranty pay types.
- [ ] Update this punchlist and recovery documentation in the same commit.

**Phase 5 exit:** The frontend can preview the exact authoritative billing result that will be committed.

## Phase 6 — Build the operational Billing Workspace

- [ ] Open the workspace from an existing Transportation Event or reservation context.
- [ ] Display customer, reservation/event, vehicle, model/class, pay type, contract period, expected return, actual return, billed-through state, and current billing segments.
- [ ] Display the backend-calculated subtotal, tax, total, rate source, and missing-configuration warnings.
- [ ] Permit only actions supported by verified high-level backend contracts.
- [ ] Keep raw PostgreSQL/Supabase errors out of the UI.
- [ ] Preserve read-only behavior when the user lacks mutation permission.
- [ ] Verify loading, empty state, missing configuration, permission denial, and real authenticated payload rendering.
- [ ] Update this punchlist and recovery documentation in the same commit.

**Phase 6 exit:** Staff can inspect complete authoritative billing state without changing it.

## Phase 7 — Start/activate billing at vehicle pickup

- [ ] Connect Rent Now and Loan Now to the existing case/transportation-event and VIN-assignment workflow.
- [ ] Keep future reservations model-level until pickup.
- [ ] Require authoritative billing preview before commit.
- [ ] Commit billing through the secured high-level activation workflow; do not insert billing lines from React.
- [ ] Prevent duplicate active parent lines for the same operational segment.
- [ ] Reload the authoritative event, assignment, contract, and billing state after success.
- [ ] Verify rental, loaner, taxable, non-taxable, missing-rate, duplicate-submit, and permission-denied cases.
- [ ] Update this punchlist and recovery documentation in the same commit.

**Phase 7 exit:** Pickup creates the correct VIN assignment, contract period, and initial billing segment exactly once.

## Phase 8 — Extensions and billed-through changes

- [ ] Use the existing extension acceptance and extension-line workflows.
- [ ] Calculate extension amount and tax through the same authoritative resolver used at activation.
- [ ] Close the prior segment at the verified paid-through boundary and create the next segment without overlap or gaps.
- [ ] Preserve parent/tax-child linkage and extension ancestry.
- [ ] Require confirmation and show the before/after return date and billing breakdown.
- [ ] Verify same-day, multi-day, repeated, invalid-date, duplicate-submit, and unauthorized extension cases.
- [ ] Update this punchlist and recovery documentation in the same commit.

**Phase 8 exit:** Authorized staff can extend a rental/loaner with correct, auditable billing segments.

## Phase 9 — Return and close billing

- [ ] Use the existing return, contract-period close, vehicle-event close, and billing-line close workflows.
- [ ] Record actual return independently from the scheduled Fleet Board display boundary.
- [ ] Allow after-hours actual drop-off timestamps while keeping scheduled return times within operational scheduling rules.
- [ ] Calculate the final segment through the authoritative resolver.
- [ ] Close parent and tax child consistently and return the vehicle to the verified operational status.
- [ ] Verify normal return, early return, after-hours return, already-closed, invalid timestamp, and unauthorized cases.
- [ ] Update this punchlist and recovery documentation in the same commit.

**Phase 9 exit:** Return closes operational and billing state together without losing after-hours facts.

## Phase 10 — Same-vehicle continuation and vehicle swap

- [ ] Use `renew_same_vehicle`/continuation workflows for a new contract period on the same VIN.
- [ ] Use the existing swap workflow for reassignment to a different VIN.
- [ ] End the prior billing segment at the verified transition time and create the new segment through the authoritative resolver.
- [ ] Preserve reservation/event continuity and billing ancestry.
- [ ] Prevent overlap, gap, duplicate assignment, and unavailable-vehicle commits.
- [ ] Verify same-VIN renewal, different-VIN swap, pay-type continuity/change, conflicts, and unauthorized cases.
- [ ] Update this punchlist and recovery documentation in the same commit.

**Phase 10 exit:** Continuations and swaps remain one auditable operational case with correct segment boundaries.

## Phase 11 — Fleet Board workflow handoffs

- [ ] Existing assignment blocks open the Billing/Transportation Event workspace.
- [ ] Empty reservation time offers Quote or Reservation through existing workflows.
- [ ] Empty VIN time offers Rent Now, Loan Now, or Vehicle Details through existing workflows.
- [ ] Completed actions reload Fleet Board state through `get_fleet_board_state`.
- [ ] Do not add drag/drop or resize mutations until extension, swap, return, conflict, and permission workflows are fully verified.
- [ ] Verify day/week navigation, block reopening, stale-state reload, mobile layout, and large-fleet scrolling.
- [ ] Update this punchlist and recovery documentation in the same commit.

**Phase 11 exit:** The Fleet Board is the operational entry point without becoming a separate scheduling system.

## Phase 12 — Core release verification

- [ ] Run frontend build, lint, diff check, and task-specific tests.
- [ ] Run live anonymous, unauthorized authenticated, authorized Admin, and authorized staff contract tests.
- [ ] Browser-test pay-type edits, rates, tax preview, pickup, extension, return, continuation, swap, and Fleet Board reopening.
- [ ] Verify DST/day-boundary behavior, 7:00 AM–7:00 PM display clamping, and after-hours actual returns.
- [ ] Verify no raw database errors, duplicate clients, service-role credentials, hardcoded rates/taxes, or frontend-only calculations.
- [ ] Run Supabase security/performance advisors and resolve relevant findings.
- [ ] Confirm GitHub migration files match the exact live definitions and grants.
- [ ] Confirm this punchlist and recovery documents accurately reflect completed and unresolved work.

**Phase 12 exit:** The normal billing workflow is production-ready and independently verified.

## Deferred follow-up — not part of the core release

- [ ] `DEFERRED` Discretionary late-fee entry.
- [ ] `DEFERRED` Make applicable `public.late_fee_rules.fee_amount` dollar amounts editable in Admin Rates, Fees & Billing Rules; configuration must not automatically apply a charge.
- [ ] `DEFERRED` Explicit late-fee waiver/reversal with actor, reason, timestamp, and preserved audit history.
- [ ] `DEFERRED` GM warranty rate administration and calculation.
- [ ] `DEFERRED` Extended-warranty provider/rule administration and calculation.
- [ ] `DEFERRED` Warranty day-ledger and alert workflows.
- [ ] `DEFERRED` Billing totals/reporting objects not proven to be used by active workflows.

## Required update record

Whenever an item is checked, add a dated entry below containing the GitHub PR/commit, live SQL verification when applicable, tests performed, and any limitation.

### 2026-07-30 — Punchlist established

- Live Supabase billing configuration and current GitHub `main` were inspected.

### 2026-08-04 — Phase 1 live deployment reconciliation

- **VERIFIED GitHub:** `main` includes PR #11's start/assign/bill checkpoint, PR #12's continuation/reassignment checkpoint, and PR #13's PL/pgSQL terminator correction.
- **VERIFIED live Supabase:** The six top-level case-write RPCs for extension, cancellation, completion/return, start/assign/bill, same-vehicle continuation, and active-case reassignment exist with the expected ownership, security-definer configuration, restricted search path, and execution grants.
- **VERIFIED live Supabase:** Browser roles cannot directly execute the internal start/bill, continuation, or reassignment helpers or directly mutate the protected workflow tables; `service_role` retains the required internal access.
- **VERIFIED live Supabase:** `ux_vehicle_events_one_open_per_vehicle` exists with the `is_open = true` predicate, and `restart_same_vehicle_after_gap(uuid, uuid, timestamptz)` delegates to the existing `start_vehicle_use_state` engine.
- **NOT VERIFIED:** Real-session anonymous denial, unauthorized authenticated denial, authorized success, and end-to-end RLS/browser behavior remain the Phase 1 exit test.
- **UNRESOLVED:** No live Ontrac function or trigger applying staging odometer rows has been verified. Optional checkout and return mileage behavior remains preserved; excess-mile calculation remains future work.
- **NEXT:** Phase 2 pay-type editing. Late fees remain disabled and deferred.
- This reconciliation changed documentation only; it did not execute SQL or change production behavior.

### 2026-07-31 — Continuation/reassignment security checkpoint prepared

- **VERIFIED:** Dave manually applied PR #11's preceding start/assign/bill migration after its repository checkpoint, and all six live verification checks passed.
- **VERIFIED baseline:** continuation and reassignment engines already existed; no React or deployed Edge Function caller existed; and `reservations`, `vehicle_events`, `contract_periods`, `reservation_vehicle_dependencies`, `reservation_conflicts`, `vehicle_swaps`, and `billing_lines` were empty.
- **VERIFIED gap:** `restart_same_vehicle_after_gap` was absent live and in the repository even though the existing reservation restart workflow called it. The pending migration repairs that dependency by delegating to the existing `start_vehicle_use_state` engine.
- **SUPERSEDED 2026-08-04:** The migration was subsequently applied and verified live. Broad Phase 1 remains open only for real-session end-to-end authorization and RLS tests; Phase 10 product workflows remain future implementation work.
- **UNRESOLVED / NEXT:** authoritative amount/tax calculation remains unresolved. Pay-type administration Phase 2 is next after Phase 1 closes. Late fees remain disabled and deferred; eventual Admin-editable dollar amounts must not automatically charge a fee.
- No production SQL, schema, data, frontend code, or billing behavior was changed.
- Historical next step at this checkpoint was Phase 1 reconciliation; the current next implementation step is **Phase 2 — Complete existing pay-type administration**.

### 2026-07-30 — Operational RPC security checkpoint

- VERIFIED: Secured the extension, completion/return, and cancellation top-level operational RPC contracts with active application-user lookup, AAL2 enforcement, authenticated actor validation/stamping, and restricted grants.
- VERIFIED: Revoked browser-role execution from the listed internal helpers while retaining `service_role` execution.
- VERIFIED: Return mileage remains optional; omission preserves the reservation's existing `end_mileage`.
- VERIFIED: Production SQL for this checkpoint was applied and verified manually before this repository migration was recorded.
- SUPERSEDED 2026-08-04: The same-vehicle continuation, start/assign/bill, and active-case reassignment security contracts were subsequently applied and verified live.
- NOT VERIFIED: No live Ontrac function or trigger applying staging odometer rows has been verified. Checkout mileage is required to remain optional, but its handling remains part of the unverified start/assign/bill work. Return mileage is verified as optional, with omitted `p_end_mileage` preserving the existing `end_mileage`. Excess-mile calculation is future work.
- No broad Phase 1 item is marked complete by this granular checkpoint.

### 2026-07-31 — Start/assign/bill security checkpoint

- [x] Added the stable browser RPC `create_start_bill_case_and_get_payload_state` to replace the 68-character service contract name that PostgreSQL stored as the truncated 63-character `create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_`.
- [x] Preserved inventory/create `p_vehicle_mileage`; checkout `p_start_mileage` is separate, optional, non-negative when supplied, and does not overwrite `reservations.start_mileage` when omitted.
- [x] Added active-app-user/AAL2 enforcement, actor stamping for the exact created vehicle event and contract period, one-open-use-per-vehicle enforcement, and restricted internal helper/direct-table mutations.
- [ ] Authoritative billing amount and tax calculation remains unresolved future work; this legacy boundary continues to accept trusted amount and tax inputs.
- **VERIFIED historical baseline:** At this checkpoint, no frontend or deployed `fleet-constraint-engine` caller existed and `reservations`, `vehicle_events`, `contract_periods`, and `billing_lines` were empty. **SUPERSEDED 2026-08-04:** The migration was subsequently applied and verified live.


### 2026-08-04 — Phase 3 rental-rate source-of-truth implementation

- **VERIFIED live Supabase before repository implementation:** Project `ycwejunodgnnkickjvsk` passed table ownership/RLS/grants checks, exact RPC ownership/security/search-path/grants checks, anon resolver denial, unauthorized authenticated Admin denial, authorized create/edit/Disable/Reactivate/Admin reload/resolver flow, duplicate/current-rate protection, and rollback left zero persisted test rows.
- **IMPLEMENTED IN THE REPOSITORY:** Added an idempotent Phase 3 migration for `public.rental_rate_rules`, exact constraints/indexes/trigger/RLS/grants, Admin RPCs, and the service-role-only resolver.
- **IMPLEMENTED IN THE FRONTEND:** Rates, Fees & Billing Rules now includes Rental Rates with empty-state handling, Admin free-text vehicle class/model identifiers, enabled pay-type options from the RPC, Add/Edit/Disable/Reactivate controls, mutation-response validation, authoritative reloads, and sanitized messages. Delete is not provided.
- **VERIFIED live data state:** Live currently contains zero actual rate rows. No business rates, vehicle classes, taxes, or billing rules were invented or seeded.
- **NOT VERIFIED:** Frontend deployment, browser verification after merge, Vercel verification, and integration of this resolver into future billing preview/pickup workflows remain open.

## 2026-08-05 — Extended Warranty live billing contract checkpoint

- [x] Implemented the Extended Warranty provider/rule administration contract in one idempotent migration without seeding provider names, rates, caps, pay-type UUIDs, or production values.
- [x] Added case-level Extended Warranty snapshot fields to the legacy `warranty_cases` table while preserving the existing table name and separating this work from GM Warranty and `gm_warranty_rates`.
- [x] Recorded runtime RPC contracts for case creation, authorized covered-day override, internal coverage reconciliation, and browser-facing coverage state retrieval using case-level coverage days and the existing billing engines.
- [x] Extended Rates, Fees & Billing Rules with a visually separate Extended Warranty Providers section that uses Admin RPCs only and offers Add, focused Edit, Disable, and Reactivate with no Delete action.
- [x] VERIFIED: live contract/grants and static boundary checks passed before repository capture; all provider/rule/case/billing tables had zero rows, so no business rates or historical billing rows were rewritten.
- [ ] NOT VERIFIED: real-session/browser verification remains open and must not be marked complete until exercised with real authenticated sessions.

### 2026-08-05 — Extended Warranty mandatory provider cap follow-up

- **VERIFIED before repository work:** the live mandatory-cap contract was verified before repository work: `public.extended_warranty_rules.covered_days` is `NOT NULL`, provider-level approval is disabled by constraint, the compatible Admin create/update RPC signatures require positive covered days, reject provider approval, store `requires_approval = false`, and keep the verified owner/security/search-path/grant boundaries.
- **IMPLEMENTED IN THE REPOSITORY:** added an idempotent follow-up migration after `20260805120000_extended_warranty_live_billing_contract.sql` and updated Rates, Fees & Billing Rules so Extended Warranty providers require a positive covered-day cap and always send `p_requires_approval: false` through the existing RPC signatures.
- **PRESERVED:** case-level `billing.extended_warranty_override` remains the only exceptional coverage-extension workflow; GM Warranty behavior, pay-type behavior, rate behavior, coverage timer, VIN-swap continuity, and other billing engines were not changed.
- **NOT VERIFIED:** real authenticated mutation/browser verification remains open. This repository migration has not been claimed as applied live by this commit.

## Billing Phase 4 — Authoritative loaner/rental tax (2026-08-06)

- **VERIFIED (live contract, recorded only; live Supabase was not touched in this implementation):** all eight pay types passed. The six taxable types returned exact `6.995` for a `69.95` base; GM Warranty and Extended Warranty returned zero. Zero-dollar returned zero; blank pay type and negative base returned sanitized `22023`; snapshot columns were mandatory; relevant grants passed; `billing_lines` remained empty.
- **IMPLEMENTED LOCALLY:** one idempotent migration records the authoritative rate, fixed exemptions, exact resolver, mandatory historical snapshots, separate child tax line, secured Admin RPCs, fixed pay-type mutations, and legacy browser revocations.
- **NOT VERIFIED / OPEN:** real authenticated Admin mutation and browser testing remain open until performed against an authorized environment.
- [x] Phase 4 nullable-tax propagation drift resolved live: unrestricted `numeric` tax-rate snapshots and exact authoritative tax now flow through start/bill and extension engines without legacy zero defaults or coercion.
- [ ] Complete real authenticated start/bill and extension browser verification for taxable and warranty-exempt cases.
