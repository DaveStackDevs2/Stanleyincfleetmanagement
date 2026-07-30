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
- Late fees remain disabled and deferred. They will eventually be discretionary, staff-applied, and waivable—not an automatic penalty engine.

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
- [x] Confirmed late fees are disabled and the three active late-fee rows are zero-dollar/null placeholders.
- [x] Confirmed existing billing functions store parent lines, tax child lines, paid-through state, extensions, returns, renewals, and swaps.
- [x] Confirmed current billing functions accept amount and tax inputs; they do not calculate authoritative amounts from pay-type defaults.
- [x] Confirmed frontend-safe/AAL2 metadata is not itself an enforcement layer. Backend authorization and grants must be verified before frontend writes are enabled.

## Core billing release definition

The core billing release is complete when an authorized user can configure normal rates and tax behavior, start billing from an existing operational event, review an authoritative breakdown, extend or close billing, handle vehicle continuation or swap through existing workflows, and reopen the same state from the Fleet Board without duplicate frontend calculations.

## Phase 1 — Reconcile and secure existing billing contracts

- [ ] Capture the exact live definitions, ownership, security mode, grants, RLS dependencies, and callers for every high-level billing workflow used by the frontend.
- [ ] Identify the smallest high-level RPC boundary for configuration reads, billing activation, extension, close/return, same-vehicle continuation, and vehicle swap.
- [ ] Keep low-level line and continuity functions internal; revoke browser execution where direct access is unnecessary.
- [ ] Enforce authenticated application-user identity and the verified permission inside every frontend-callable write RPC.
- [ ] Enforce any required AAL2 rule in executable backend code rather than relying on service-action metadata.
- [ ] Reconcile recent live-only function/grant changes into idempotent repository migrations without reapplying or redesigning them.
- [ ] Add sanitized, deterministic RPC status payloads that the frontend can structurally validate.
- [ ] Verify anonymous denial, unauthorized authenticated denial, authorized success, RLS behavior, and grants.
- [ ] Update this punchlist, `PROJECT_STATUS.md`, `CHANGELOG.md`, and `DECISIONS.md` if a security boundary decision changes.

**Phase 1 exit:** The frontend has a verified secure boundary for existing billing workflows; no rates or billing UI are added prematurely.

Remaining Phase 1 operational contracts are same-vehicle continuation, start/assign/bill, and vehicle reassignment/swap. Ontrac mileage application/import-path verification remains unresolved: no live function or trigger applying staging odometer rows has been verified. Checkout and return mileage are optional; excess-mile calculation remains future work.

## Phase 2 — Complete existing pay-type administration

- [ ] Add an authorized backend mutation for editing an existing pay type's description, taxable flag, default daily amount, and sort order.
- [ ] Preserve pay-type identity and historical references; do not rename or delete pay types through an unsafe replacement workflow.
- [ ] Keep Disable/Reactivate behavior and Fleet Board color behavior intact.
- [ ] Add editing controls to the existing Rates, Fees & Billing Rules page.
- [ ] Validate nonnegative currency and whole-number sort order in the backend; frontend validation is only user guidance.
- [ ] Reload authoritative state after every successful mutation and show explicit success/failure feedback.
- [ ] Verify editing, disabling, reactivating, duplicate-name protection, invalid input rejection, and historical retention.
- [ ] Update this punchlist and recovery documentation in the same commit.

**Phase 2 exit:** Dave can configure and maintain every existing pay type, including its default daily amount.

## Phase 3 — Establish the normal rental-rate source of truth

- [ ] Verify the exact model/class keys already used by `reservations.requested_model`, `quotes.vehicle_class`, vehicles, and rental-capacity configuration.
- [ ] Document the required rate precedence: explicit authorized override, model/class rate, pay-type default, or a safe missing-rate failure.
- [ ] Determine the smallest backend object needed for model/class pricing because no live model/class rate source currently exists.
- [ ] Do not hardcode Chevrolet model prices; rates must be entered and maintained in Admin.
- [ ] Add effective status and historical preservation so changing a rate does not rewrite prior billing lines.
- [ ] Add an authorized read/write RPC contract rather than direct frontend table writes.
- [ ] Extend the existing Rates, Fees & Billing Rules page with model/class rate administration.
- [ ] Verify rate creation, update, disable/reactivate, missing-rate behavior, historical snapshots, and duplicate-key protection.
- [ ] Update this punchlist and recovery documentation in the same commit.

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
- [ ] `DEFERRED` Explicit late-fee waiver/reversal with actor, reason, timestamp, and preserved audit history.
- [ ] `DEFERRED` GM warranty rate administration and calculation.
- [ ] `DEFERRED` Extended-warranty provider/rule administration and calculation.
- [ ] `DEFERRED` Warranty day-ledger and alert workflows.
- [ ] `DEFERRED` Billing totals/reporting objects not proven to be used by active workflows.

## Required update record

Whenever an item is checked, add a dated entry below containing the GitHub PR/commit, live SQL verification when applicable, tests performed, and any limitation.

### 2026-07-30 — Punchlist established

- Live Supabase billing configuration and current GitHub `main` were inspected.
- No production SQL, schema, data, frontend code, or billing behavior was changed.
- Next implementation phase: **Phase 1 — Reconcile and secure existing billing contracts**.

### 2026-07-30 — Operational RPC security checkpoint

- VERIFIED: Secured the extension, completion/return, and cancellation top-level operational RPC contracts with active application-user lookup, AAL2 enforcement, authenticated actor validation/stamping, and restricted grants.
- VERIFIED: Revoked browser-role execution from the listed internal helpers while retaining `service_role` execution.
- VERIFIED: Return mileage remains optional; omission preserves the reservation's existing `end_mileage`.
- VERIFIED: Production SQL for this checkpoint was applied and verified manually before this repository migration was recorded.
- NOT VERIFIED: Same-vehicle continuation, start/assign/bill, and vehicle reassignment/swap remain Phase 1 work.
- NOT VERIFIED: No live Ontrac function or trigger applying staging odometer rows has been verified. Checkout and return mileage remain optional, and excess-mile calculation is future work.
- No broad Phase 1 item is marked complete by this granular checkpoint.
