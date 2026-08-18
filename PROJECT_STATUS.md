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

### 2026-07-31 follow-up — PR #11 manual deployment

**VERIFIED:** After the repository checkpoint above, Dave manually applied PR #11's migration to live Supabase and all six live verification checks passed. This dated follow-up does not imply that Codex applied production SQL.

## 2026-07-31 — Phase 1 continuation/reassignment database checkpoint

**VERIFIED baseline:** The continuation and reassignment/swap engines already existed and are being secured and reconciled, not replaced. The required `restart_same_vehicle_after_gap` dependency was absent both live and in the repository; the checkpoint reuses `start_vehicle_use_state` as the existing event/contract creation engine. No React frontend or deployed `fleet-constraint-engine` caller currently exists. The seven relevant live tables—`reservations`, `vehicle_events`, `contract_periods`, `reservation_vehicle_dependencies`, `reservation_conflicts`, `vehicle_swaps`, and `billing_lines`—were empty.

**NOT APPLICABLE:** No frontend changes were made and Codex did not connect to or apply SQL to live Supabase. **NOT VERIFIED / REQUIRED:** The new migration is pending manual review, application, and live verification; broad Phase 1 and Phase 10 must remain open until then. **UNRESOLVED:** Authoritative amount/tax calculation remains unresolved. Pay-type administration Phase 2 is next after Phase 1 closes. **DEFERRED:** Late fees remain disabled; eventual Admin-editable dollar amounts must not automatically apply charges.

## 2026-08-11 — Rental rate-card checkpoint

- **VERIFIED LIVE / IMPLEMENTED IN REPOSITORY:** the pay-type-independent rental rate-card schema and five new RPC contracts are recorded in an idempotent, data-free migration; the Rental Rates Admin UI calls the new Admin RPCs and supports required daily plus optional weekly/monthly rates.
- **NOT APPLICABLE:** this repository work did not apply migrations to live Supabase, seed or rewrite business values, change billing snapshots, or remove legacy compatibility contracts.
- **OPEN / NOT IMPLEMENTED:** Quote/Reservation/Walk-in pricing agreements and all conversion, insurance, discount, override, paid-through, allocation, credit, expected-balance, and ledger runtime behavior.

## 2026-08-12 — Shared rental-pricing-agreement foundation

- **VERIFIED LIVE CONTRACT / IMPLEMENTED IN REPOSITORY:** The data-free migration records the shared pricing agreement, one-Transportation-Event Quote/direct Reservation/Walk-in architecture, same-event Quote conversion, secured Dev/AAL2 RPC boundary, billing compatibility snapshots, monthly-requires-weekly prerequisite, central audit trail, and protected-table privilege corrections.
- **NOT APPLICABLE:** No live Supabase change or production seed was performed; no pickup, VIN, timer, contract-period, pricing activation, calculation, discount, insurance, payment, cashiering, allocation, or billing-line workflow was started.
- **OPEN / NOT IMPLEMENTED:** Frontend Quote/Reservation/Walk-in workflows and every post-pickup pricing and payment capability listed in the Billing Build Punchlist remain open.

## 2026-08-13 — Operational Reservations intake workspace

- **VERIFIED LIVE CONTRACT / RECORDED IN REPOSITORY:** The secured intake read and daily-only pickup read/activation RPCs are recorded with their postgres ownership, security-definer empty-search-path boundary, authenticated/service-role grants, active-user/AAL2/permission enforcement, and weekly/monthly pickup fail-closed rule.
- **IMPLEMENTED IN REPOSITORY:** Reservations is an operational sidebar destination for existing-customer Quote, direct Reservation, and Walk-in creation, active Quote review, and same-event Quote conversion. It uses only the shared Supabase client and verified pricing-agreement RPCs, reloads authoritative intake after writes, and displays returned exact pricing snapshots.
- **OPEN / NOT IMPLEMENTED:** Pickup UI, VIN assignment, pricing activation from the browser, and weekly/monthly pickup Billing calculation remain open. No live Supabase change was performed.

## 2026-08-14 — Frontend TOTP MFA gate

- **IMPLEMENTED IN REPOSITORY:** After password authentication and existing application authorization, the frontend now fails closed until Supabase reports the current session at AAL2. It supports deterministic verified-TOTP challenge and first-time TOTP enrollment through the shared client.
- **PRESERVED:** AAL2 enforcement for operational Reservations/Billing RPCs remains server-side. No SQL, migration, pricing, pickup, billing, Extended Warranty, pay-type, rate, or Admin behavior changed.
- **NOT VERIFIED:** Enrollment, later-login challenge, session promotion, and protected-RPC success still require real production-browser verification. Reservations/pickup/billing end-to-end completion is not claimed.
