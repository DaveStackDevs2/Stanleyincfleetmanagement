# Project Status

Last updated: 2026-08-04

## Current focus

Billing is the active build track. The authoritative implementation sequence is maintained in `docs/BILLING_BUILD_PUNCHLIST.md`.

Phase 1's repository and live-database security checkpoints are reconciled. Billing Phase 2 pay-type editing is implemented in the current repository work but is not yet merged, deployed, or browser-verified.

## Billing Phase 2 — pay-type editing status

- **VERIFIED live Supabase:** `update_admin_pay_type_rule_state(uuid, boolean, numeric, integer, text)` is owned by `postgres`, is `SECURITY DEFINER` with an empty `search_path`, denies `PUBLIC` and `anon`, and grants execution to `authenticated` and `service_role`.
- **VERIFIED live Supabase:** authorization follows the active app-user and existing `user_admin.manage` access path through `get_user_admin_setting_access_state(user_id, 'fleet_board.pay_type_colors')`.
- **IMPLEMENTED / NOT YET MERGED OR DEPLOYED:** the repository migration reproduces the live RPC, and Rates, Fees & Billing Rules adds validated editing for description, taxable status, nullable default daily amount, and sort order without rename/delete behavior.
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
- Existing pay-type editing is implemented in the current repository work but is not yet merged, deployed, or browser-verified.
- Drag/drop and resize mutations remain intentionally disabled until extension, return, continuation, swap, conflict, and permission workflows are fully verified.

## Next implementation

Phase 2 — Complete existing pay-type administration:

- Add the authorized backend mutation for description, taxable status, default daily amount, and sort order.
- Add editing controls to the existing Rates, Fees & Billing Rules page.
- Preserve pay-type identity, historical references, Disable/Reactivate behavior, and Fleet Board colors.
- Validate and reload authoritative state through existing Supabase contracts.

Late fees, warranty-specific calculation, excess-mile billing, and broader reporting remain deferred until the normal billing workflow is complete.
