# Project Status

## 2026-07-30 Phase 1 checkpoint

- **VERIFIED:** Live Supabase project `ycwejunodgnnkickjvsk` has the operational RPC security state captured by this checkpoint, and production SQL was already applied and verified manually.
- **VERIFIED:** Extension, completion/return, and cancellation top-level RPCs require an active authenticated application user and AAL2, stamp that user's application ID, and keep internal helpers unavailable to browser roles.
- **VERIFIED:** Return mileage is optional; omitting `p_end_mileage` preserves the existing `reservations.end_mileage`.
- **NOT VERIFIED / REQUIRED:** Checkout mileage must remain optional when the outstanding start/assign/bill workflow is reconciled; its implementation has not yet been verified.
- **NOT VERIFIED:** Same-vehicle continuation, start/assign/bill, and vehicle reassignment/swap remain Phase 1 operational contracts to reconcile and secure.
- **NOT VERIFIED:** No live function or trigger applying Ontrac staging odometer rows has been verified.
- **DEFERRED:** Excess-mile calculation remains future work.
- **DEFERRED:** Applicable late-fee dollar amounts must eventually be editable in Admin Rates, Fees & Billing Rules from `public.late_fee_rules.fee_amount`. Verified live placeholders are `grace_period` = null, `fixed_fee` = 0, and `full_day_trigger` = 0. Configuration must not automatically charge a fee; late fees remain discretionary, staff-applied, waivable/reversible, and auditable with actor, reason, timestamp, and preserved history.

Repository baseline for this checkpoint: GitHub `main` at `0cb1ec43d50512500bbbe36382e33149d183c873`.

## 2026-07-31 — Phase 1 start/assign/bill database checkpoint

**VERIFIED:** The repository now defines the stable, non-overloaded browser contract `create_start_bill_case_and_get_payload_state` for `case.create_start_bill_and_load`; the prior 68-character configured name was stored by PostgreSQL as the truncated 63-character `create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_`. The new boundary requires an active application user and AAL2, stamps the created continuity rows, keeps checkout mileage optional and distinct from vehicle inventory mileage, and enforces one open vehicle event per vehicle. Internal mutation helpers and direct operational-table writes are restricted while the unified payload read contract is unchanged.

**VERIFIED live baseline supplied for this checkpoint:** no current frontend or deployed `fleet-constraint-engine` dependency; `reservations`, `vehicle_events`, `contract_periods`, and `billing_lines` each had zero rows. **NOT APPLICABLE:** no live SQL was applied. **UNRESOLVED:** authoritative amount and tax calculation remains future work; legacy values remain trusted inputs.
