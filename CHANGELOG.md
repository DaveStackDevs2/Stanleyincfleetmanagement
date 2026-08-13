# Changelog

## Unreleased

### 2026-08-13 — Operational Reservations workspace

- Recorded the verified-live pricing-agreement intake and pickup contracts in one data-free, idempotent migration; daily pickup remains the only supported activation plan and the frontend does not call pickup.
- Wired the existing Reservations navigation to an operational RPC-only workspace for existing-customer Quote, direct Reservation, and Walk-in creation, active Quote listing, and same-Transportation-Event conversion.
- Added strict pre-submit validation, configured-plan gating, exact snapshot display without frontend arithmetic, sanitized error categories, authoritative post-write reloads, and focused result screens.
- Live Supabase was not changed. Pickup UI and weekly/monthly pickup calculation remain open.

### 2026-07-30 — Phase 1 operational RPC security checkpoint

- Added an idempotent migration recording the live-verified security definitions and grants for extension, completion/return, and cancellation operational RPCs.
- Recorded browser denial and `service_role` execution for their internal helpers.
- Documented optional return-mileage preservation and the remaining Phase 1 contracts.
- Production SQL was already applied and verified manually; this repository checkpoint did not apply SQL to live Supabase.
- Corrected the repository checkpoint to match the verified live grants: top-level operational wrappers are executable by `authenticated` only (plus owner `postgres`), while internal helpers retain `service_role` execution.
- Recorded, without implementation, that late-fee amounts sourced from `public.late_fee_rules.fee_amount` must eventually be editable in Admin Rates, Fees & Billing Rules. Live placeholders remain `grace_period` = null, `fixed_fee` = 0, and `full_day_trigger` = 0; configuration does not itself charge a fee, and fees remain discretionary, staff-applied, waivable/reversible, and fully auditable.

## 2026-07-31

- Added one idempotent Phase 1 migration introducing the stable authenticated/AAL2 start/assign/bill browser RPC, optional checkout mileage, exact created-row actor stamping, and final-payload loading after those writes.
- Added a preconditioned unique partial index for one open vehicle event per vehicle; restricted the legacy truncated wrapper, internal mutation chain, and direct mutations on the seven workflow tables while retaining service-role helper/table access.
- Updated `case.create_start_bill_and_load` metadata to the exact new function name. No frontend or Edge caller exists, the live four-table baseline was empty, no production SQL was applied, and authoritative amount/tax calculation remains unresolved.
- Recorded the later manual deployment of PR #11 by Dave and the successful completion of all six live verification checks; Codex did not perform that deployment.
- Added one pending, idempotent database migration that repairs the missing `restart_same_vehicle_after_gap` helper by delegating to `start_vehicle_use_state`, secures the existing continuation and reassignment wrappers with authenticated active-user/AAL2 enforcement and exact actor stamping, and restricts their mutating helper chain and dependency tables.
- Preserved the existing service-action names and operational behavior: no billing segmentation, `vehicle_swaps` insert, frontend, or Edge Function caller was added. The seven relevant live operational tables were empty, and no live SQL was applied by this task.
- Broad Phase 1/Phase 10 remain incomplete pending manual live application and verification. Amount/tax calculation remains unresolved; Phase 2 pay-type administration is next after Phase 1; late fees remain disabled and deferred with future Admin-editable amounts that must not auto-charge.

## 2026-08-11 — Verified-live pay-type-independent rental rate cards

- Added one idempotent, data-free migration recording the verified live nullable legacy pay-type link, optional weekly/monthly rates, normalized vehicle-class current-card uniqueness, and five secured rate-card RPCs while preserving legacy functions, FK/index, data, and billing snapshots.
- Updated only Rental Rates administration to use the new shared-client RPCs, remove Pay Type, validate complete card payloads, and present focused Add/Edit for daily, optional weekly, and optional monthly rates with authoritative reloads and no Delete action.
- Updated the Billing punchlist to distinguish verified engines from the approved but **OPEN / NOT IMPLEMENTED** Quote/Reservation/Walk-in pricing-agreement and downstream block/discount/insurance/ledger work. Live Supabase was not changed by this repository implementation.

## 2026-08-12 — Shared rental-pricing-agreement foundation

- **VERIFIED LIVE CONTRACT / IMPLEMENTED IN REPOSITORY:** The data-free migration records the shared pricing agreement, one-Transportation-Event Quote/direct Reservation/Walk-in architecture, same-event Quote conversion, secured Dev/AAL2 RPC boundary, billing compatibility snapshots, monthly-requires-weekly prerequisite, central audit trail, and protected-table privilege corrections.
- **NOT APPLICABLE:** No live Supabase change or production seed was performed; no pickup, VIN, timer, contract-period, pricing activation, calculation, discount, insurance, payment, cashiering, allocation, or billing-line workflow was started.
- **OPEN / NOT IMPLEMENTED:** Frontend Quote/Reservation/Walk-in workflows and every post-pickup pricing and payment capability listed in the Billing Build Punchlist remain open.
