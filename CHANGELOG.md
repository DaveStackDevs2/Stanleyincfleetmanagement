# Changelog

## Unreleased

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
