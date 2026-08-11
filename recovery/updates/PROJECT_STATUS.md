# Project Status

Last updated: 2026-08-04

## Current focus

Billing is the active build track. The authoritative implementation sequence is maintained in `docs/BILLING_BUILD_PUNCHLIST.md`.

Phase 1's repository and live-database security checkpoints are reconciled. Billing Phase 2 pay-type editing is implemented in the repository and its live RPC is verified, but frontend deployment and real-session/browser behavior are not yet verified.

## Billing Phase 2 — pay-type editing status

- **VERIFIED live Supabase:** `update_admin_pay_type_rule_state(uuid, boolean, numeric, integer, text)` is owned by `postgres`, is `SECURITY DEFINER` with an empty `search_path`, denies `PUBLIC` and `anon`, and grants execution to `authenticated` and `service_role`.
- **VERIFIED live Supabase:** authorization follows the active app-user and existing `user_admin.manage` access path through `get_user_admin_setting_access_state(user_id, 'fleet_board.pay_type_colors')`.
- **IMPLEMENTED IN THE REPOSITORY / LIVE RPC VERIFIED:** the repository migration reproduces the live RPC, and Rates, Fees & Billing Rules adds validated editing for description, taxable status, nullable default daily amount, and sort order without rename/delete behavior.
- **NOT VERIFIED:** real-session authorization, browser behavior, deployed frontend behavior, and the overall Phase 2 exit remain open.

## Billing Phase 1 — live deployment status

- **VERIFIED GitHub:** The starting `main` SHA for this status update is `1847af4aa486868e35777e8d99c197f87ed1fae5`. It includes PR #11's start/assign/bill checkpoint, PR #12's continuation/reassignment checkpoint, and PR #13's PL/pgSQL terminator correction.
- **VERIFIED live Supabase:** The six top-level case-write RPCs for extension, cancellation, completion/return, start/assign/bill, same-vehicle continuation, and active-case reassignment exist with the expected ownership, security-definer configuration, restricted search path, and execution grants.
- **VERIFIED live Supabase:** Internal start/bill, continuation, and reassignment helpers are unavailable to browser roles and remain executable by `service_role` where required.
- **VERIFIED live Supabase:** Direct browser-role INSERT/UPDATE/DELETE access to the protected workflow tables is blocked.
- **VERIFIED live Supabase:** `ux_vehicle_events_one_open_per_vehicle` exists with the `is_open = true` predicate.
- **VERIFIED live Supabase:** `restart_same_vehicle_after_gap(uuid, uuid, timestamptz)` delegates to the existing `start_vehicle_use_state` engine.
- **NOT VERIFIED:** Real-session anonymous denial, unauthorized authenticated denial, authorized success, end-to-end RLS behavior, and browser workflow execution remain the Phase 1 exit tests.
- **UNRESOLVED:** No live Ontrac function or trigger applying staging odometer rows has been verified. Checkout and return mileage remain optional; excess-mile calculation remains future work.

## Fleet Board and Admin status

- The abandoned Vehicle Calendar has been removed. The Fleet Board remains a visualization of existing reservations, vehicles, capacity, and transportation-event state.
- Day view uses the 7:00 AM–7:00 PM operating window with 15-minute grid guidance, and Week view remains available.
- Fleet Board data loads through `get_fleet_board_state(timestamptz, timestamptz)`.
- Rates, Fees & Billing Rules supports pay-type creation, Disable/Reactivate, and Fleet Board colors.
- Existing pay-type editing is implemented in the repository and its live RPC is verified, but frontend deployment and real-session/browser behavior are not yet verified.
- Drag/drop and resize mutations remain intentionally disabled until extension, return, continuation, swap, conflict, and permission workflows are fully verified.

## Next step

Deploy and verify Phase 2 without advancing into Phase 3:

- Exercise authorized and unauthorized real application-user sessions.
- Verify editing, nullable default daily amounts, and backend/frontend validation failures in the browser.
- Verify Disable/Reactivate preserves pay-type identity and historical references.
- Verify Fleet Board color behavior is preserved.

Late fees, warranty-specific calculation, excess-mile billing, and broader reporting remain deferred until the normal billing workflow is complete.

## Billing Phase 3 — rental rate administration status

- **VERIFIED live Supabase before repository implementation:** Project `ycwejunodgnnkickjvsk` passed table ownership/RLS/grants checks, exact RPC ownership/security/search-path/grants checks, anon resolver denial, unauthorized authenticated Admin denial, authorized create/edit/Disable/Reactivate/Admin reload/resolver flow, duplicate/current-rate protection, and rollback left zero persisted test rows.
- **IMPLEMENTED IN THE REPOSITORY / LIVE CONTRACT VERIFIED:** An idempotent migration now records `public.rental_rate_rules`, its constraints, indexes, updated-at trigger, RLS/table grants, Admin RPCs, and service-role-only resolver. The frontend uses RPCs only and validates payloads and mutation confirmations before rendering success.
- **VERIFIED live data state:** Live currently contains zero actual rental-rate rows. No vehicle classes, model identifiers, daily rates, taxes, or other business values were invented or seeded.
- **NOT VERIFIED:** Frontend deployment, browser verification after merge, and Vercel production verification remain open.

## Billing Extended Warranty — live billing contract status

- **VERIFIED live Supabase before repository follow-up:** the live mandatory-cap contract was verified before repository work. Every Extended Warranty provider now requires a positive whole-number covered-day cap, provider-level approval is disabled, compatible Admin create/update RPC signatures reject blank/nonpositive caps and provider approval, store `requires_approval = false`, and retain the verified owner/security/search-path/grant boundaries.
- **IMPLEMENTED IN THE REPOSITORY:** a follow-up migration and Admin UI update now mirror that mandatory-cap contract without changing the existing case-level `billing.extended_warranty_override` workflow.
- **NOT VERIFIED:** real authenticated mutation/browser verification remains open. The repository migration is not itself proof of live application.
- **IMPLEMENTED IN THE REPOSITORY / LIVE CONTRACT VERIFIED:** Extended Warranty provider/rule administration is no longer deferred. The migration records the verified provider/rule constraints, Admin RPCs, low-level service-role boundary, case snapshot fields, override permission, runtime case/reconciliation RPC signatures, ownership, security modes, restricted search paths, and role grants.
- **VERIFIED live/static boundary:** live contract/grants and static boundary checks passed, all provider/rule/case/billing tables had zero rows, and no provider names, rates, caps, pay-type UUIDs, GM Warranty behavior, tax calculation, cashiering, reporting, reservations, quotes, or Fleet Board mutation workflows were introduced.
- **NOT VERIFIED:** real-session/browser verification remains open. Runtime browser verification is not complete.

## 2026-08-06 — Billing Phase 4 authoritative tax

**VERIFIED live contract (historical verification recorded; no live database change in this work):** eight pay types passed; `69.95` produced exact `6.995` for all six taxable types; GM Warranty and Extended Warranty produced zero; zero-dollar produced zero; blank/negative inputs produced sanitized `22023`; mandatory snapshots and relevant grants passed; billing lines remained empty.

**IMPLEMENTED LOCALLY:** migration and Admin Rates, Fees & Billing Rules UI now encode exact, separate-line loaner/rental tax with RPC-only administration. **NOT VERIFIED / OPEN:** authenticated Admin mutation and browser testing.
- 2026-08-06: Phase 4 nullable-tax propagation drift was resolved and verified directly in live Supabase across both start/bill and extension engine chains. `tax_rate_snapshot` is unrestricted `numeric`; no public function retains a tax-parameter zero default or zero coercion. Real authenticated operational/browser verification remains open.

### 2026-08-06 — Phase 4 pay-type taxability correction

- **VERIFIED live:** stored synchronized `is_taxable`/`tax_applicable` is authoritative. The name-based hard lock was removed; GM Warranty and Extended Warranty remain exempt because of current stored data, not their names. The exact resolver and Admin create/update contracts preserve their verified security boundaries.
- **IMPLEMENTED IN THE REPOSITORY:** a follow-up migration records the verified live contract without seeding or rewriting rows, and Add/Edit Pay Type again allow authorized Admins to choose Taxable Yes/No. Rename/delete remain unavailable; Disable/Reactivate and Fleet Board color behavior are preserved.
- **NOT VERIFIED / OPEN:** authenticated Admin mutation/browser testing and full operational start/bill/extension verification. This work did not touch live Supabase.

## 2026-08-07 — Operational Billing Dashboard

- **VERIFIED live contract / IMPLEMENTED IN REPOSITORY:** The read-only preview and workspace RPC definitions record the already-verified live active-user plus AAL2 boundary, authoritative rate/tax resolution, historical snapshots, exact text money, deterministic attention states, empty workspace, and sanitized per-item failures.
- **IMPLEMENTED IN REPOSITORY:** Dashboard is now the default operational Billing workspace. It loads only `get_billing_workspace_state` through the shared Supabase client, validates the complete payload, displays exact strings, and provides read-only case, segment, and Extended Warranty inspection.
- **NOT VERIFIED:** authenticated browser behavior, deployment, and live-session denial/success remain unverified. No operational mutation, cashiering, reporting, or browser-verification milestone is complete.

## 2026-08-07 — Focused operational Billing workspace follow-up

- **VERIFIED LIVE INPUT:** `get_billing_preview_state` and `get_billing_workspace_state` no longer require AAL2, while retaining active-application-user validation and authenticated-only execution; workspace reservations now include nullable `ro_number`. Live has zero active transportation cases.
- **IMPLEMENTED IN REPOSITORY:** the follow-up migration records that live contract without applying SQL. The Dashboard list now uses each full-width case as accessible navigation into a read-only detail destination, presents exact stored loaner/rental amounts and separate tax without frontend arithmetic, preserves attention cases, and keeps Extended Warranty and current-vehicle timers distinct.
- **NOT VERIFIED:** non-empty live case presentation, browser navigation, deployment, and real-session behavior. No live Supabase change or billing mutation was performed.

## 2026-08-10 — Authoritative case start and billed-through checkpoint

- **VERIFIED CONTROLLED CUSTOMER PAY PATH:** authoritative adjustable-rate start and a 7-day checkpoint were verified live; the open case continued accumulating correctly through day 10. Parent, tax child, and reservation checkpoint timestamps were synchronized, while the segment remained open.
- **IMPLEMENTED IN REPOSITORY:** permission-scoped start/checkpoint RPC contracts, restricted legacy execution, a focused Billing Dashboard checkpoint action, authoritative workspace reload with preserved selection, and non-rounding exact-string monetary display.
- **OPEN / NOT VERIFIED:** split pay types, Extended Warranty runtime exhaustion/override, swaps, returns, extensions, closure, unauthorized real-session behavior, and other workflows. No live Supabase change was made by this repository work.

## 2026-08-10 — Verified Extended Warranty reconciliation integration

- **VERIFIED LIVE CONTRACT / IMPLEMENTED IN REPOSITORY:** the verified reconciliation permission and callable boundaries are recorded in a new data-free migration. The Dev role receives `billing.extended_warranty_reconcile` by role name. Browser execution of the established payload engine is revoked without changing its retained authentication/AAL2 enforcement; the explicit wrapper adds the effective-permission boundary, and the Billing workspace calls the established lower-level reconciliation engine directly for active warranty cases in transportation-event UUID order before returning the existing workspace state. No Admin-role gate was added.
- **VERIFIED LIVE OPERATIONAL INPUT:** Zurich was created through the existing Admin workflow. Its live rate and covered-day cap are operational configuration, not repository seed data.
- **IMPLEMENTED IN REPOSITORY:** Billing Dashboard exclusively calls `get_reconciled_billing_workspace_state` through the shared Supabase client while preserving strict payload validation, exact numeric strings, selection/reload, billed-through behavior, sanitized messages, separate timers, and the read-only presentation.
- **OPEN / NOT VERIFIED:** authenticated split-boundary browser verification, vehicle-swap verification, override verification, and unauthorized-session denial remain open until actually tested.
- **NOT APPLICABLE:** this work did not touch live Supabase, seed operational data, begin Reservations or Quotes, or affect GM Warranty.

## 2026-08-10 — Billing Complete / Return Case integration

- **VERIFIED LIVE CONTRACT:** the `billing.case_complete` permission, Dev assignment, and effective-permission check for the established completion wrapper were verified. The wrapper contract continues to enforce active app-user resolution, AAL2, authenticated actor identity, existing-mileage preservation when omitted, and delegation to the existing completion and unified-payload engines.
- **IMPLEMENTED IN REPOSITORY:** the verified contract is recorded in one idempotent migration, and BillingWorkspace now has a focused Complete / Return flow using only the shared-client wrapper RPC. It validates optional mileage, the full deterministic completion result, and reloads `get_reconciled_billing_workspace_state` before showing success.
- **OPEN / NOT VERIFIED:** authenticated browser completion and final database readback remain open until deployed and exercised. Live Supabase was not changed by this task.
- **NOT APPLICABLE:** no new completion engine, direct workflow-table write/delete, controlled production fixture, reservation/quote/swap/extension feature, or billing-money coercion was introduced.

## 2026-08-11 — Pay-type-independent rental rate-card checkpoint

- **VERIFIED LIVE CONTRACT / IMPLEMENTED IN REPOSITORY:** the new vehicle-class rate-card schema and five RPC signatures are recorded without data mutation; Rental Rates now uses the new Admin contracts with daily/weekly/monthly presentation and focused Add/Edit.
- **NOT APPLICABLE:** no live Supabase application, value seeding/rewriting, billing snapshot change, or legacy contract removal occurred.
- **OPEN / NOT IMPLEMENTED:** the Quote/Walk-in through Reservation, pickup, Transportation Event, renewal/swap, and Billing pricing agreement and all approved conversion, insurance, discount, override, allocation, credit, balance, and ledger behavior.
