# Phase 1 Operational RPC Security Checkpoint

**Date:** 2026-07-30

**Live Supabase project:** `ycwejunodgnnkickjvsk`
**Verified GitHub baseline:** `0cb1ec43d50512500bbbe36382e33149d183c873`

## Verified state

Production SQL was applied and verified manually before this repository checkpoint. The three secured top-level RPCs are:

1. `public.accept_case_extension_and_get_unified_payload_state`
2. `public.complete_case_and_get_unified_payload_state`
3. `public.cancel_case_and_get_unified_payload_state`

They enforce an active authenticated application user and AAL2, validate any supplied actor ID, and stamp the authenticated application-user ID. The top-level operational wrappers grant execution to `authenticated` only, plus owner `postgres`. Listed internal helpers remain denied to browser roles and retain `service_role` execution.

**VERIFIED:** Return mileage is optional. When `p_end_mileage` is omitted, completion preserves the existing `reservations.end_mileage`.

**NOT VERIFIED / REQUIRED:** Checkout mileage must remain optional, but its implementation has not yet been verified because start/assign/bill remains outstanding. Excess-mile calculation remains future work.

## Remaining Phase 1 operational contracts

- **NOT VERIFIED:** same-vehicle continuation
- **NOT VERIFIED:** start/assign/bill
- **NOT VERIFIED:** vehicle reassignment/swap

## Ontrac limitation

**NOT VERIFIED:** No live function or trigger applying Ontrac staging odometer rows has been verified, so the mileage application/import path remains unresolved.

## Deferred late-fee requirement

Applicable late-fee dollar amounts must eventually be editable in the Admin Rates, Fees & Billing Rules area using the existing `public.late_fee_rules.fee_amount` source. Verified live placeholders are `grace_period` = null, `fixed_fee` = 0, and `full_day_trigger` = 0. Configuring an amount must not automatically charge it. Late fees remain deferred, discretionary, staff-applied, waivable/reversible, and must preserve actor, reason, timestamp, and audit history.

## Frontend impact

No frontend code or frontend behavior was changed by this checkpoint.
