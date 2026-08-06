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
