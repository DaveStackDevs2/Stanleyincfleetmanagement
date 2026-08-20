
## 2026-08-18 — Pre-check-in Reservation editing

- **VERIFIED LIVE / RECORDED:** The browser-safe five-field edit backend preserves the existing Reservation, Transportation Event, and pricing agreement, and delegates the Transportation Event schedule mirror to the existing expected-return engine.
- **VERIFIED LIVE:** A controlled scheduled start, scheduled return, service advisor, RO number, and notes edit produced exactly five matching audit rows without VIN, continuity, contract period, pricing, billing, snapshot, or identity changes.
- **VERIFIED LIVE:** The production Edit Reservation UI and Pickup activation have both been browser-tested successfully.
- **TBD / DEFERRED:** The future penalty-free edit cutoff remains TBD. Model, workflow, pay-type, and rate-plan edits remain deferred pending authoritative pricing and availability policy.

# Billing Build Punchlist

## 2026-08-18 — Check-in / Pickup lifecycle reconciliation

- **VERIFIED live / RECORDED:** Reservation creation reserves scheduled capacity and pricing state without starting continuity or Billing. Check-in starts continuity at actual handoff and Billing/pricing at the Reservation scheduled start; a late arrival does not slide scheduled return.
- **VERIFIED live / RECORDED HARDENING:** Authoritative pickup candidates exclude retired vehicles. Activation locks the selected non-retired vehicle and immediately revalidates `available` before assignment, continuity, or billing writes so stale candidate state cannot start continuity or Billing.
- **VERIFIED live / RECORDED:** Billing workspace reuses Transportation Event operational state and skips a pre-check-in Reservation only when both current continuity and current billing lines are empty.
- **VERIFIED LIVE:** Production Edit Reservation and Pickup were browser-tested. The future no-penalty cutoff is TBD; weekly/monthly and “Now” remain deferred.


## 2026-08-18 — Pickup / VIN activation checkpoint

- **VERIFIED live:** Rental intake and the pre-pickup no-VIN/no-continuity/no-billing boundary; fleet-type mismatch rejection before writes; model-plus-fleet-type candidates (controlled Rental case returns only `TEST-STOCK-003`, not seed data).
- **VERIFIED LIVE:** Reservations Pickup uses the authoritative read/activation RPCs, starts the existing billing path, and displays its exact returned preview without client arithmetic.
- **OPEN:** real production browser activation after merge. Weekly/monthly pickup stays fail-closed. “Now” and taxable-checkbox alignment remain deferred.


## Purpose

This is the authoritative implementation checklist for completing Stanley Fleet Management billing. It is based on the live Supabase schema and the current `main` frontend, not on assumed or redesigned behavior.

Every billing implementation commit must update this file. An item is marked complete only after its code is published to GitHub, required live SQL has been executed and verified, and the relevant build or browser checks pass.

## 2026-08-14 — Frontend AAL2 authentication blocker

- **IMPLEMENTED IN REPOSITORY:** The frontend now provides TOTP enrollment/challenge and requires a confirmed AAL2 session after existing application authorization before rendering operational workflows.
- **PRESERVED:** Operational Reservations/Billing RPCs continue to enforce AAL2 server-side. No billing, pricing, pickup, Extended Warranty, pay-type, rate, Admin, SQL, or live Supabase behavior changed.
- **NOT VERIFIED / OPEN:** Production-browser enrollment, later-login challenge, promoted-JWT RPC execution, and Reservations/pickup/billing end-to-end behavior remain to be exercised.

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

## Phase 3 — Establish the normal rental rate-card source of truth

- [ ] Verify the exact model/class keys already used by `reservations.requested_model`, `quotes.vehicle_class`, vehicles, and rental-capacity configuration.
- [ ] Document the required rate precedence: explicit authorized override, model/class rate, pay-type default, or a safe missing-rate failure.
- [x] Determine the smallest backend object needed for model/class pricing because no live model/class rate source currently exists.
- [x] Do not hardcode Chevrolet model prices; rates must be entered and maintained in Admin.
- [x] Add effective status and historical preservation so changing a rate does not rewrite prior billing lines.
- [x] Add an authorized read/write RPC contract rather than direct frontend table writes.
- [x] Extend the existing Rates, Fees & Billing Rules page with model/class rate administration.
- [x] Verify rate creation, update, disable/reactivate, missing-rate behavior, historical snapshots, and duplicate-key protection in the pre-existing live Phase 3 backend verification; browser verification remains open.
- [x] Update this punchlist and recovery documentation in the same commit.

**Phase 3 exit (superseded by the verified 2026-08-11 checkpoint):** The database resolves a pay-type-independent daily/weekly/monthly rate card for a normalized vehicle class without frontend business rules. The legacy daily resolver remains only for compatibility.

## Phase 4 — Establish authoritative tax calculation

- [x] Verify the dealership's required taxable base and current tax configuration source; the stored pay-type Taxable field and the 10% Admin setting are authoritative.
- [x] Add the minimum Admin-managed tax configuration after verifying no existing live rate source.
- [x] Calculate tax in a backend resolver using the selected pay type's stored taxable status and the authoritative rate configuration.
- [x] Preserve the existing separate tax child-line design.
- [x] Snapshot the applied tax result so later configuration changes do not alter historical billing.
- [x] Support a safe, explicit non-taxable result for any pay type configured non-taxable; GM Warranty and Extended Warranty are currently the only exempt rows.
- [x] Verify taxable, non-taxable, zero-dollar, exact no-rounding, missing-configuration, and historical snapshot contracts; real authenticated operational/browser verification remains open.
- [x] Update this punchlist and recovery documentation in the same commit.

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

### Phase 6 completion gate — verify the first real active Billing case before beginning another product area

This gate is part of completing Billing. Reservations, Quotes, Walk-ins, calendar integration, closed-case reporting, and additional Billing mutations must not begin merely to make the Dashboard appear populated. The first populated card must be created through an existing verified operational workflow using explicitly approved business or controlled verification data, and the resulting transportation event must remain the source of truth.

#### Verified live readiness as of 2026-08-07

- [x] The authenticated production Billing Dashboard loads successfully for an active application user without requiring an Admin role or AAL2.
- [x] The production empty state matches live Supabase: zero active transportation events, zero reservations, zero open vehicle events, and zero open contract periods.
- [x] Live contains one customer record, one non-retired vehicle whose current status is `available`, and eight active pay-type rules.
- [ ] Live contains no active rental-rate rule and no active pay type with a non-null default daily amount. A ready Billing preview cannot calculate a vehicle charge until Dave enters an actual dealership-approved rate through Rates, Fees & Billing Rules. No test rate may be invented or seeded.
- [ ] Dave must identify whether the existing customer and available vehicle are safe controlled-test records or provide the actual customer, vehicle, repair-order or rental context, dates, and pay type for the first legitimate case. Repository maintainers and automation must not infer consent to repurpose the existing production records.
- [x] The secured top-level `create_start_bill_case_and_get_payload_state` wrapper exists live. It must remain the only permitted creation boundary for this verification unless a subsequently verified higher-level wrapper delegates to the same engine.
- [ ] The exact wrapper inputs, permission path, AAL requirements, active-user behavior, conflict checks, rate resolution, tax resolution, created-record identifiers, and cleanup/closure path must be re-inspected immediately before creating the verification case.
- [ ] No browser, SQL, service-role, or test harness may directly insert or update `transportation_events`, `reservations`, `vehicle_events`, `contract_periods`, or `billing_lines` to manufacture a passing card.

#### Controlled creation and authoritative reload

- [ ] Configure one real daily-rate path using an actual dealership-approved value: either a matching active rental-rate rule or the intended pay type's real default daily amount. Record which rule supplied the rate and verify the resolver returns it at the intended effective timestamp.
- [ ] Select one explicit verification scenario: a repair-order loaner with a real RO number, or a customer rental identified as Rental. Record the expected pay type, taxable status, daily rate, start timestamp, expected-return timestamp, and vehicle VIN before execution.
- [ ] Execute the secured high-level case-start workflow exactly once from an authorized application-user context. Do not submit trusted frontend totals and do not bypass its permission, conflict, reservation, VIN-assignment, contract-period, billing-line, or tax-child orchestration.
- [ ] Verify directly in live Supabase that exactly one active transportation event, one intended reservation relationship, one open vehicle assignment, one open contract period, and one current parent billing segment were created for the returned identifiers.
- [ ] Verify the selected vehicle is no longer presented as available for another overlapping assignment and that the one-open-use constraints remain satisfied.
- [ ] Reload `get_billing_workspace_state` through the authenticated production browser rather than relying on the case-start response or a database query alone.

#### At-a-glance case-card acceptance criteria

- [ ] The active case appears as one full-width, tightly spaced navigation container beneath the summary tiles; the entire container is operable with a pointer, Enter, and Space.
- [ ] A repair-order loaner displays the actual reservation `ro_number` as `RO #…`, the customer name, actual out timestamp, expected-return timestamp, chronological pay-type segments, exact authoritative contract days, stored or resolved daily rates, accumulated pre-tax amount, and one separate accumulated-tax row.
- [ ] A rental displays `Rental`, the customer name, actual out timestamp, expected-return timestamp, current pre-tax daily rate, exact accumulated pre-tax rental charges, and a separate exact accumulated-tax row.
- [ ] The card never substitutes a transportation-event UUID, reservation UUID, source UUID, VIN, stock number, or customer number for a missing RO number.
- [ ] Historical segment days come only from the backend-provided segment `contract_days`, calculated by `public.business_contract_days`; Extended Warranty covered-day limits and overrides are never presented as historical billed days.
- [ ] The current open segment uses the flat preview's `contract_days`, `daily_rate`, `subtotal`, and `pay_type`, and is not duplicated when the stored segment array also contains the open parent line.
- [ ] Vehicle charges, tax, and combined values remain exact PostgreSQL numeric strings. The frontend performs no rounding, floating-point conversion, multiplication, addition, or recomputation.
- [ ] The page describes accumulated operational charges for Tekion entry and never implies that this application collected, cashiered, deposited, refunded, or settled money.

#### Individual case-detail acceptance criteria

- [ ] Opening the case replaces the active-case list with that transportation event's focused read-only Billing detail and provides an obvious return action that restores the authoritative active list.
- [ ] The detail shows the reservation and transportation-event context, pay type, vehicle context, billed-through state, chronological stored segments, current preview, separate tax, accumulated totals, and sanitized missing-configuration or missing-dependency states.
- [ ] For Extended Warranty, the case-level coverage timer remains continuous across vehicle swaps, the effective covered-day limit is shown separately, authorized case-specific overrides remain auditable, and the current-vehicle timer is displayed independently because it resets when the vehicle changes.
- [ ] A non-Extended-Warranty case shows a clear not-configured state and is not forced through an Extended Warranty branch.
- [ ] Returning to the list and pressing Refresh both reload authoritative RPC state; neither action retains fabricated or frontend-calculated billing values.

#### Permission and failure verification

- [ ] Verify anonymous execution denial.
- [ ] Verify a signed-in person without an active `app_users` record is denied.
- [ ] Verify an active authenticated application user can read the workspace without being assigned an Admin role.
- [ ] Before Billing mutations are exposed, define and verify specific permission keys for each action. Do not implement a blanket “Admin can bill” rule and do not infer mutation access from read-only workspace access.
- [ ] Verify missing rate, unavailable vehicle, conflicting assignment, duplicate submission, invalid timestamp, and unauthorized mutation paths return sanitized failures without partial operational or billing writes.
- [ ] Confirm browser-role users still cannot directly mutate the protected workflow tables or execute service-role-only internal helpers.

#### Verification-case closure and evidence

- [ ] Capture the production browser result for the populated list card and the individual detail view without exposing unnecessary customer information in repository documentation.
- [ ] Close or cancel the controlled case only through the verified high-level operational workflow appropriate to the scenario. Never delete the transportation event or its billing history merely to clean up a test.
- [ ] Verify the vehicle assignment, contract period, parent billing segment, and tax child reach their intended closed states; verify the vehicle returns to the correct operational status.
- [ ] Verify the closed case leaves the active Billing list and remains available for the later historical Billing views.
- [ ] Add the GitHub merge commit, exact live verification results, authenticated browser evidence, and any remaining limitation to the Required update record before marking Phase 6 complete.

**Phase 6 populated-case exit:** One real or explicitly approved controlled loaner or rental has been created through the secured operational engine, rendered accurately in the active Billing list, opened successfully as an individual case, and closed or cancelled through an auditable high-level workflow without direct table writes or invented business values.

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

## Ordered product work after the populated Billing-case exit

The following work is deliberately ordered. It does not authorize implementation before the Phase 6 populated-case exit is satisfied. Each product area must reuse the live operational engines and permission model rather than creating parallel customer, reservation, transportation-event, vehicle-assignment, contract-period, or billing records.

### Current Billing workstream — planned Reservations through pickup

A Reservation represents a future transportation need. It may identify a requested model or class, customer, repair-order context, pay type, expected pickup, and expected return, but it must remain model-level until an authorized person assigns a specific VIN at pickup. Creating a Reservation must not start a transportation event, start a vehicle-use timer, start an Extended Warranty coverage timer, create a contract period, or create a billing segment.

- [ ] Inspect the exact live `reservations` schema, status values, constraints, relationships, RLS policies, grants, triggers, lifecycle RPCs, dependency/conflict engines, and all repository callers before changing anything.
- [ ] Inspect the existing Reservations frontend and determine which create, edit, cancel, search, list, detail, dependency, conflict, and VIN-assignment behaviors already work and which are only visual placeholders.
- [ ] Define explicit reservation permissions by action, including view, create, edit, cancel, resolve conflict, assign VIN, and activate pickup. Reuse existing verified permission keys when they exist; do not invent duplicate keys or use an Admin-role shortcut.
- [ ] Create Reservations only through a secured high-level RPC that validates the active application user, customer reference, requested model or class, pay type, start timestamp, expected-return timestamp, repair-order number when applicable, status, and optional notes.
- [ ] Preserve the actual RO number in `reservations.ro_number`. Do not substitute a UUID or create a second RO-number field.
- [ ] Keep the reservation model-level before pickup. A future reservation may display candidate vehicles or availability guidance, but it must not reserve a specific VIN through an unverified frontend-only assumption.
- [ ] Surface verified conflicts and dependencies without silently overriding them. Any permitted override must require a specific permission, reason, actor, and timestamp.
- [ ] At pickup, require the authorized user to select the actual available VIN and confirm the authoritative customer, pay type, actual out timestamp, expected return, optional mileage, and rate/tax preview.
- [ ] Delegate pickup to the existing secured case-start and billing engine so the transportation event, VIN assignment, vehicle event, contract period, initial parent billing segment, tax snapshot, and returned unified payload are created atomically.
- [ ] Reload the authoritative Reservation, Transportation Event, Fleet Board, and Billing workspace states after activation. Do not stitch together a successful-looking frontend state from the submitted form.
- [ ] Prevent repeated clicks, stale reservation activation, overlapping VIN use, duplicate open transportation events, duplicate open contract periods, and duplicate open parent billing segments.
- [ ] Verify normal planned loaner pickup, planned rental pickup, taxable and non-taxable pay types, missing rate, missing customer, invalid date range, unavailable VIN, conflicting assignment, duplicate submission, unauthorized user, and sanitized failure behavior.
- [ ] Verify the newly activated case appears in the active Billing workspace with the exact RO/rental summary and opens into the individual case detail.
- [ ] Update this punchlist and required recovery documents only after the live contract, deployed frontend, real-session permissions, and browser workflow have been verified.

**Reservations exit:** Staff can create and maintain model-level planned reservations, then activate one at pickup through the shared secured operational engine with one VIN, one transportation event, one open contract period, and one authoritative Billing case.

### Second post-Billing product area — Walk-ins through the same activation engine

A Walk-in is an unscheduled customer who needs a vehicle immediately. It is not a different kind of transportation engine. It skips advance scheduling but must reuse the same customer validation, availability, pay-type, rate, tax, permission, conflict, VIN-assignment, contract-period, transportation-event, and Billing orchestration used when a planned Reservation is picked up.

- [ ] Inspect whether live schema or functions already represent Walk-ins through `source_type`, reservation type, transportation-event source fields, or another verified mechanism. Reuse the existing representation and do not add a new table or status merely because the frontend needs a label.
- [ ] Provide a focused Walk-in intake action from the appropriate operational surface, not from Rates, Fees & Billing Rules and not from the read-only Billing summary.
- [ ] Require an existing customer selection or a separately authorized customer-creation workflow. Do not create duplicate customers from free text without verified matching behavior.
- [ ] Capture the real repair-order number for a repair-order loaner, or the explicit Rental classification for a customer rental.
- [ ] Require the actual VIN because a Walk-in is starting immediately. Validate availability and conflicts through the existing backend engines at commit time.
- [ ] Resolve the pay type, configured rate, taxable state, expected return, optional mileage, and exact preview before activation.
- [ ] Delegate the final commit to the same secured case-start RPC used by planned pickup. Do not maintain separate SQL or React implementations for Walk-ins.
- [ ] Return and reload the same unified operational and Billing payloads used by Reservation activation.
- [ ] Verify loaner Walk-in, rental Walk-in, taxable, non-taxable, missing-rate, unavailable-vehicle, duplicate-customer, duplicate-submit, unauthorized, and sanitized failure cases.
- [ ] Confirm Walk-in cases are indistinguishable from planned cases after activation except for their verified source/context fields; extensions, swaps, returns, Billing, and history must use the same engines.

**Walk-ins exit:** Staff can start an unscheduled loaner or rental immediately without bypassing Reservations-era validation or creating a second transportation-event implementation.

### Current Billing workstream — non-operational Quotes that convert into Reservations

A Quote is an estimate. It may use current configured rates and tax rules to explain an expected charge, but it does not represent a vehicle leaving the dealership. It must not start timers, assign a VIN, create a transportation event, create a contract period, or create committed billing lines.

- [ ] Inspect the repository and live database for any existing quote tables, RPCs, status values, permissions, or frontend work before designing a new contract.
- [ ] Define quote permissions separately for view, create, edit, expire, cancel, and convert. Do not infer Quote mutation access from Billing read access or an Admin role.
- [ ] Capture the customer, requested model or class, anticipated dates, intended pay type, notes, and any verified dealership context required for the estimate.
- [ ] Resolve the displayed daily rate and tax only through the same authoritative backend rate and tax resolvers used by Billing. Keep exact numeric values as strings and do not calculate totals in React.
- [ ] Clearly label all Quote amounts as estimates based on the selected dates and current configuration. A Quote must not imply that a vehicle is assigned, charges are accumulating, or payment was collected.
- [ ] Store enough rate/tax/source context to explain the estimate while defining whether later configuration changes should refresh an unaccepted Quote or remain visible as a prior estimate. Do not choose this historical behavior without an explicit product decision.
- [ ] Convert an accepted Quote into a model-level Reservation through one secured high-level workflow. Preserve traceability from Quote to Reservation without copying frontend totals into committed Billing state.
- [ ] At later pickup, recalculate and confirm the authoritative live Billing preview; the accepted Quote must not override the actual pickup timestamp, assigned VIN, current pay-type configuration, authorized exception, or committed historical snapshots unless an explicit verified contract says so.
- [ ] Verify quote creation, revision, expiration, cancellation, conversion, changed-rate behavior, taxable and non-taxable estimates, invalid dates, missing rate, unauthorized user, duplicate conversion, and sanitized failures.

**Quotes exit:** Staff can prepare a traceable non-operational estimate and convert it into a planned Reservation without starting transportation or Billing prematurely.

### Fourth post-Billing product area — calendar integration across Reservations and active transportation

The calendar is a visualization and navigation surface over authoritative Reservation and Transportation Event state. It is not a separate scheduling database and must not create its own interpretations of vehicle availability, Billing dates, or event status.

- [ ] Preserve the 7:00 AM–7:00 PM Day timeline, 15-minute grid guidance, hover feedback, collapsible navigation panel, and model-level future Reservation behavior already established for the Fleet Board.
- [ ] Display future Reservations using their requested model or class until pickup assigns a VIN.
- [ ] Display active Transportation Events using their actual assigned VIN, actual out timestamp, expected return, and verified operational status.
- [ ] Link a future Reservation block to its Reservation detail and authorized pickup workflow.
- [ ] Link an active assignment block to its Transportation Event and individual Billing detail.
- [ ] Link suitable empty time to the Quote, Reservation, or Walk-in entry points only after those workflows are operational and permission-verified.
- [ ] Reload calendar state from the authoritative Fleet Board RPC after every successful Reservation or Transportation Event mutation.
- [ ] Do not enable drag, drop, or resize writes until extension, return, same-vehicle continuation, different-vehicle reassignment, conflict handling, stale-state rejection, and action-specific permissions are fully operational and browser-verified.
- [ ] Verify overlapping requests, model-level reservations, pickup VIN assignment, expected-return changes, after-hours actual return facts, day/week navigation, stale reload, mobile layout, and large-fleet scrolling.

**Calendar integration exit:** Staff can move from calendar context into the correct Reservation, pickup, Walk-in, Quote, Transportation Event, or Billing workflow without the calendar becoming a competing source of truth.

### Fifth post-Billing product area — closed-case Billing review

Closed-case review is historical operational reporting for dealership reconciliation with Tekion. It is not cashiering, accounts receivable, payment processing, or a replacement dealership ledger.

- [x] Define a secured read-only backend query for closed Transportation Events that reuses stored Billing snapshots and does not recalculate historical charges from current rate or tax configuration.
- [x] Provide explicit views for all closed rentals, all closed loaners, a user-selected closed-date range, and all closed cases.
- [x] Define whether the date filter applies to actual return, transportation-event closure, billed-through, or another verified business timestamp before implementation. Display the selected meaning clearly.
- [x] Return the RO number for repair-order loaners, Rental classification for rentals, customer context, out and return dates, pay-type segments, exact historical contract days, stored rates, pre-tax amounts, separate tax, and exact accumulated totals.
- [x] Preserve split pay types, Extended Warranty exhaustion and override history, vehicle swaps, same-vehicle continuations, and historical segment boundaries without collapsing them into a misleading single current pay type.
- [x] Allow each historical row or card to open the same read-only individual Billing detail structure used by active cases, with closed-state context and no active-case mutation controls.
- [x] Add pagination or bounded result loading before supporting an unrestricted All view on material production history.
- [ ] Define export requirements only after the on-screen historical contract is verified. Do not assume CSV, spreadsheet, PDF, or Tekion integration requirements.
- [ ] Verify empty results, single and multiple segments, rentals, loaners, taxable and non-taxable lines, Extended Warranty split, vehicle swap, date boundaries, unauthorized access, large result sets, exact no-rounding display, and sanitized failures.

**Closed-case review exit:** Staff can locate and inspect the exact stored Billing history needed for Tekion reconciliation across rentals, loaners, selected dates, or all closed cases without modifying history or implying cashiering.


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
- **IMPLEMENTED IN THE REPOSITORY / VERIFIED LIVE CONTRACT:** the follow-up removes the name-based exemption lock. The synchronized stored Admin Taxable value is authoritative for the exact resolver and create/update mutations; current production values are unchanged and no rows are seeded or rewritten.
- **NOT VERIFIED / OPEN:** real authenticated Admin mutation/browser testing and full operational start/bill/extension verification remain open until performed against an authorized environment.
- [x] Phase 4 nullable-tax propagation drift resolved live: unrestricted `numeric` tax-rate snapshots and exact authoritative tax now flow through start/bill and extension engines without legacy zero defaults or coercion.
- [ ] Complete real authenticated start/bill and extension browser verification for taxable and warranty-exempt cases.

### 2026-08-06 — Phase 4 pay-type taxability correction

- **VERIFIED live before repository work:** removed the name-based exemption constraint, added `ck_pay_type_rules_tax_fields_synchronized`, and corrected the resolver and Admin create/update RPCs while preserving owners, security modes, empty search paths, and grants. All eight existing rows remained unchanged.
- **IMPLEMENTED:** Add and focused Edit Pay Type expose Taxable controls and submit the selected boolean. Rename/delete remain unavailable; Disable/Reactivate and Fleet Board colors remain intact.
- **NOT VERIFIED / OPEN:** real authenticated Admin mutations/browser behavior and full operational start/bill/extension cases. No live Supabase changes were made by this repository work.

### 2026-08-07 — Operational Billing Dashboard

- **VERIFIED live before repository work:** `get_billing_preview_state(uuid,timestamptz)` and `get_billing_workspace_state(timestamptz)` are deployed with the active-user/AAL2, exact-numeric, sanitized-state, owner/search-path, and authenticated-only execution contracts recorded by this migration. Live operational and billing source tables are empty; live Supabase was not changed during this work.
- **IMPLEMENTED IN THE REPOSITORY:** Phases 5 and the read-only inspection portion of Phase 6 now have an idempotent migration, focused contract tests, and an operational Dashboard using only the shared client and workspace RPC. Exact monetary text is rendered without frontend arithmetic.
- **NOT VERIFIED:** real authenticated browser rendering, mutation workflows, operational start/extension/return/swap, and production deployment remain open. No Phase 7+ mutation or Phase 12 browser completion is claimed.

## 2026-08-07 — Focused read-only workspace follow-up

- **VERIFIED LIVE BEFORE THIS REPOSITORY WORK:** both Billing read RPCs accept active authenticated application users without AAL2, retain their authenticated-only security boundary, and the workspace reservation payload includes nullable `ro_number`. Live currently has zero active transportation cases. No SQL was applied to live Supabase in this work.
- **IMPLEMENTED IN THE REPOSITORY:** an idempotent, drift-safe follow-up migration records only those verified RPC changes. Active cases are compact, full-width keyboard/click navigation objects with RO/rental context, chronological closed segments, one nonduplicated current segment, exact accumulated pre-tax and separate-tax values, rental and attention summaries, and an individual read-only case destination with distinct Extended Warranty and current-vehicle timers.
- **NOT VERIFIED:** real non-empty-case rendering and navigation, authenticated browser behavior, deployment, and production browser behavior remain open because live has zero active transportation cases. Billing mutations and billing-specific permissions remain future work.


### 2026-08-07 — Billing completion gate and ordered post-Billing product sequence recorded

- **VERIFIED LIVE:** Production currently has zero active transportation events, zero reservations, zero open vehicle events, zero open contract periods, one customer record, one non-retired available vehicle, eight active pay-type rules, zero active rental-rate rules, and zero active pay types with a configured default daily amount.
- **VERIFIED PRODUCTION BROWSER:** An active authenticated application user can load the deployed Billing Dashboard without an Admin role or AAL2; the authoritative empty state and exact zero totals render successfully.
- **DECISION:** The first populated Billing card and detail view must be verified and the controlled case must be closed or cancelled through high-level operational workflows before implementation begins in another product area. No production customer, vehicle, rate, reservation, or transportation event may be invented or repurposed without Dave's explicit approval.
- **CORRECTED CURRENT BILLING WORKSTREAM:** Define the shared Quote/Walk-in pricing agreement and carry it through planned Reservations, pickup/VIN assignment, Transportation Events, renewals/swaps, and Billing. These pricing workflows must not wait for a separate Billing exit. Calendar visualization remains downstream of authoritative shared operational state.
- This update records sequencing and acceptance criteria only. It does not change live Supabase, production data, application code, permissions, or billing behavior.

## 2026-08-10 — Verified Customer Pay authoritative start/checkpoint path

- [x] **VERIFIED CONTROLLED PATH:** one Customer Pay loaner was authoritatively created and started using the adjustable rental-rate configuration, then checkpointed through the verified billed-through contract. The checkpoint stored 7 contract days, $280.00 pre-tax, exact $28.0000 tax, and exact $308.0000 total; the still-open case later accumulated to 10 days, $400.00 pre-tax, exact $40.0000 tax, and exact $440.0000 total.
- [x] **VERIFIED:** reservation, open parent line, and separate tax line share the checkpoint timestamp; the stored period ends at that checkpoint while the open calculation continues beyond it. Browser verification covered active status, dates, rate, current timer, checkpoint, stored period/amounts, and card/detail navigation.
- [x] **IMPLEMENTED IN REPOSITORY:** authoritative UUID-based case start, permission-scoped billed-through checkpoint, Dashboard action, authoritative reload, and exact-string monetary presentation.
- [ ] **OPEN / NOT VERIFIED:** split pay types, Extended Warranty runtime exhaustion/override, vehicle swaps, returns, extensions, closure, unauthorized real-session testing, and all other workflows remain open. The checkpoint records manual Tekion progress; it is not cashiering or a transfer of money.

## 2026-08-10 — Verified Extended Warranty reconciliation integration

- [x] **VERIFIED LIVE CONTRACT:** the internal reconciliation boundary, explicit browser wrapper, automatic Billing workspace orchestrator, permission boundary, and Zurich provider/rule creation through the existing Admin workflow were inspected and verified before this repository integration. Zurich's operational rate and covered-day cap remain live Admin-entered data and are intentionally not migration seeds.
- [x] **IMPLEMENTED IN REPOSITORY:** `billing.extended_warranty_reconcile` is assigned to the existing Dev role by role name. Browser execution of the established payload engine is revoked while its existing authentication/AAL2 behavior remains unchanged; the explicit wrapper adds the effective-permission boundary. The non-AAL2 workspace orchestrator validates its timestamp, calls the established lower-level reconciliation engine directly for active warranty cases in deterministic order, then returns the unchanged authoritative workspace payload.
- [x] **IMPLEMENTED IN REPOSITORY:** Billing Dashboard now loads exclusively through `get_reconciled_billing_workspace_state` with the shared client and a current ISO timestamp. Existing complete payload validation, exact string money, case selection, billed-through action, sanitized messages, separate case/vehicle timers, and read-only presentation are preserved.
- [ ] **OPEN / NOT VERIFIED:** authenticated split-boundary browser behavior, vehicle-swap continuity, case-specific override behavior, and unauthorized-session denial have not yet been exercised. These remain open until actual browser/session tests are performed.
- **NOT APPLICABLE:** this repository work did not modify live Supabase, seed operational values, alter GM Warranty, or begin Reservations or Quotes.

## 2026-08-10 — Complete / Return Case integration

- **VERIFIED LIVE CONTRACT:** `billing.case_complete`, its Dev-role assignment by role name, and the effective-permission boundary on `complete_case_and_get_unified_payload_state` were verified before this repository update. The wrapper retains active-user resolution through `auth.uid()`, AAL2, actor-mismatch rejection, nullable-mileage preservation, delegation to the existing completion engine, unified-payload reload, deterministic status, postgres ownership, empty search path, and authenticated-only browser execution.
- **IMPLEMENTED IN REPOSITORY:** one idempotent, data-free migration records that exact authorization change. Billing now offers a selected-case focused Complete / Return screen with read-only identity, local return time, optional whole-number mileage and note, strict response validation, sanitized feedback, and authoritative reconciled-workspace reload before a focused success view.
- **PRESERVED:** Mark billed through, exact-string money, Billing cards and selection, read-only inspection, and the established return/billing-close/transportation-event-close engines. No protected workflow-table write or separate completion engine was added.
- **OPEN / NOT VERIFIED:** authenticated browser completion and final database readback remain open until the migration and frontend are deployed and exercised. This repository work did not modify live Supabase.

## 2026-08-11 verified-live pay-type-independent rental rate-card checkpoint

### VERIFIED existing database engines

- Transportation Events remain the operational source of truth. Contract-period creation and continuation, renewal, vehicle swap, day 20/25/30 reminders, parent billing lines and separate tax children, billed-through progression, case completion/return, Extended Warranty reconciliation, and `daily_rate_override` groundwork are existing verified engines. This checkpoint does not replace or recalculate them.
- Normal rental rate cards are keyed by normalized vehicle class, **not pay type**. The verified card supplies required daily and optional weekly/monthly values. The legacy pay-type FK/index, historical data, five pay-type-dependent RPCs, and old billing daily resolver remain for compatibility pending shared pricing-agreement migration.
- **IMPLEMENTED IN REPOSITORY / VERIFIED LIVE CONTRACT:** one data-free migration records the verified schema, rate-card resolver and Admin contracts. Rental Rates now uses those Admin RPCs, without seeding values or changing billing snapshots.

### Approved Billing workstream — OPEN / NOT IMPLEMENTED

Pricing-related **Quotes, Reservations, and Walk-ins are part of the current Billing workstream**; they are not postponed until Billing is finished. The approved future contract is a Quote/Walk-in pricing agreement carried unchanged through Reservation, pickup, Transportation Event, renewals and swaps, and Billing.

The following remain **OPEN / NOT IMPLEMENTED**: daily/weekly/monthly block rules; quoted-monthly early-return fallback; first manual conversion followed by automatic future blocks; retroactive monthly restructuring with preserved audit history; Corporate Rates; Military/Veterans discount; rental-only insurance caps and authorized days; permission-based overrides; exact paid-through dollar recalculation; Paid/Partial/Unpaid allocation by line; credit advancing only over complete blocks/full days; expected-return balance; and all Quote/Reservation/Walk-in/conversion/insurance/discount/ledger runtime work. There is no cashiering scope.

### Sequence correction

1. Preserve and verify the existing operational and billing engines.
2. Build the shared pricing-agreement contract across Quote/Walk-in and Reservation before migrating pickup, renewals/swaps, and Billing callers.
3. Implement and verify block conversion, insurance/discount/override policy, and ledger allocation together with their audit requirements.
4. Cashiering remains out of scope.

## 2026-08-12 — Shared rental-pricing-agreement foundation

- [x] **VERIFIED LIVE CONTRACT / RECORDED IN REPOSITORY:** A Quote, direct Reservation, Walk-in, and Loaner begin with one active Transportation Event. One pricing agreement follows that event; Quote conversion attaches its planned Reservation to the same event and agreement. Pre-pickup Reservation status remains `quote`.
- [x] **VERIFIED LIVE CONTRACT / RECORDED IN REPOSITORY:** Pricing agreements snapshot the vehicle-class rate card separately from pay type, are mutation-protected behind the Dev permission and AAL2 RPC boundary, and use the central audit log. Billing-line compatibility fields remain nullable, so the two existing lines retain three null pricing fields.
- [x] **VERIFIED LIVE CONTRACT / RECORDED IN REPOSITORY:** A configured monthly rate requires a weekly fallback. Admin create/update RPCs and the Rental Rates form return matching guidance.
- [ ] **OPEN:** Frontend Quote, Reservation, and Walk-in workflows; pickup and VIN assignment; pricing activation; weekly/monthly block calculations; early-return fallback; manual/automatic plan conversion; Corporate Rates; Military/Veterans discount; insurance caps; authorized overrides; payments; cashiering; paid-through allocation; balance calculation; and ledger allocation.
- **NOT APPLICABLE:** This checkpoint does not apply SQL to Supabase, seed values, start timers, assign a VIN, create a contract period, or create/modify billing lines.

## 2026-08-13 — Operational Reservations intake checkpoint

- [x] **VERIFIED LIVE CONTRACT / RECORDED IN REPOSITORY:** `get_pricing_agreement_intake_state()`, `get_pricing_agreement_pickup_state(timestamptz)`, and `activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer)` are recorded with the verified security boundary. Activation remains daily-only and fails closed for weekly/monthly plans.
- [x] **IMPLEMENTED IN REPOSITORY:** The existing operational Reservations navigation now supports existing-customer Quote, direct Reservation, and Walk-in creation; active Quote listing; and Quote conversion through the verified pricing-agreement RPCs. Every successful write reloads authoritative intake and shows returned identifiers and exact pricing snapshots.
- [x] **PRESERVED:** Pre-pickup frontend work does not assign a VIN, begin vehicle use, create a contract period, start pricing, create billing, calculate rates/tax, mutate protected tables, or create a second Transportation Event.
- [ ] **OPEN:** Pickup UI and authenticated production browser verification. Weekly/monthly pickup remains blocked on extension of the existing Billing calculation engine; that restriction was not loosened.
- **NOT APPLICABLE:** No SQL was applied to live Supabase by this repository checkpoint.

## 2026-08-18 — Reservations semantics checkpoint

- [x] **VERIFIED LIVE:** Production browser MFA/AAL2 and authoritative Reservations intake loading succeeded.
- [x] **IMPLEMENTED:** Reservations displays Vehicle Model while preserving backend `vehicle_class` compatibility names.
- [x] **IMPLEMENTED / VERIFIED-LIVE CONTRACT:** Rental intake exclusively uses the active canonical Admin-managed `Rental` pay type; Loaner excludes it, and the database trigger rejects both mismatch directions.
- [x] **RECORDED ONLY:** The data-free migration records the already-live `create_vehicle_state` `vin_last8` repair and Rental/pay-type trigger. It does not seed the live Rental configuration or controlled `TEST-STOCK-002`/`TEST-STOCK-003` verification vehicles.
- [ ] **NEXT:** Implement and verify Pickup/VIN frontend without moving VIN assignment, use start, timers, contract periods, or billing into Reservations intake.
- [ ] **OPEN / MUST FAIL CLOSED:** Implement authoritative weekly/monthly pickup billing; it remains unavailable.


### 2026-08-19 — Closed Billing review repository checkpoint

- **VERIFIED LIVE BACKEND:** The existing preview has a stored closed-history branch and the secured wrapper supports All/Rental/Loaner plus inclusive `closed_at` from and exclusive before filtering. The controlled closed Rental returns stored 40 + 4 = 44.
- **IMPLEMENTED / BROWSER VERIFICATION PENDING:** The closed-cases Billing UI is read-only, bounded to 50, RPC-only, and preserves every returned segment. No controlled closed Loaner exists, so Loaner browser behavior is not claimed.

## 2026-08-19 — Return/Complete final-charge persistence and closed review

- **VERIFIED LIVE / RECONCILED:** Closed-review inspection exposed a stale-final-amount defect in Return/Complete: an uncheckpointed multi-day case could close with the parent line's earlier stored amount. The authoritative live completion engine now obtains the existing Billing preview at the actual return timestamp and persists its current-segment subtotal and tax before synchronizing the existing tax child and closing continuity, Billing, and the Transportation Event. It does not add a calculator or require `billing.mark_billed_through`.
- **VERIFIED LIVE READ-ONLY:** Active multi-day Transportation Event `a5757d9d-8234-40bf-86e3-9d02d70e28dc`, billing line `db1c4f05-7c38-40a1-a0ae-13d463bfae95`, has a stored checkpoint of `$400 + $40`; its authoritative 19-contract-day preview is `$760 + $76 = $836` and identifies that same current billing line.
- **VERIFIED LIVE DEFINITION:** Completion ordering and metadata are verified: final preview persistence precedes Return/Complete closure; the function remains owned by `postgres`, `SECURITY INVOKER`, has no function search-path override, and remains executable only by `postgres` and `service_role`.
- **OPEN PRODUCTION VERIFICATION:** No production multi-day Return mutation/browser test has been completed. That is the next production verification after deployment/reconciliation. Closed Cases browser verification also remains pending; the controlled closed Rental `$40 + $4 = $44` is verified, and no closed Loaner browser verification has been completed.

### 2026-08-20 — Phase 8 Extension reconciliation

- **VERIFIED LIVE / RECONCILED IN REPOSITORY:** the authoritative Extension definitions are patched and verified. The existing Billing preview and Extension acceptance/commit/line engines are reused; no second calculator or preview RPC was added.
- **IMPLEMENTED IN REPOSITORY:** Billing case detail now requires Mark billed through, previews through the existing authoritative Billing preview, and confirms through the compatibility Extension wrapper. Submitted client amount/tax values are ignored and final Extension money is calculated server-side.
- **NOT VERIFIED / STILL PENDING:** a runtime-persisted Extension. A controlled SQL `DO` workflow returned success, but subsequent live inspection showed no new reservation, pricing agreement, billing line, or audit rows; it is not runtime proof.
- **NEXT VERIFICATION:** exercise the real deployed production-browser Reservation → Pickup → Mark billed through → Extension flow and inspect persisted operational, Billing, tax-child, ancestry, and audit state.
