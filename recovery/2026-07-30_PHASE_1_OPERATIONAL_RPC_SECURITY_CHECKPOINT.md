# Phase 1 Operational RPC Security Checkpoint

**Date:** 2026-07-30

**Live Supabase project:** `ycwejunodgnnkickjvsk`
**Verified GitHub baseline:** `0cb1ec43d50512500bbbe36382e33149d183c873`

## Verified state

Production SQL was applied and verified manually before this repository checkpoint. The three secured top-level RPCs are:

1. `public.accept_case_extension_and_get_unified_payload_state`
2. `public.complete_case_and_get_unified_payload_state`
3. `public.cancel_case_and_get_unified_payload_state`

They enforce an active authenticated application user and AAL2, validate any supplied actor ID, stamp the authenticated application-user ID, and expose only the top-level wrappers to `authenticated` and `service_role`. Listed internal helpers remain denied to browser roles and executable by `service_role`.

Return mileage is optional. When `p_end_mileage` is omitted, completion preserves the existing `reservations.end_mileage`. Checkout mileage is also optional, and excess-mile calculation remains future work.

## Remaining Phase 1 operational contracts

- **NOT VERIFIED:** same-vehicle continuation
- **NOT VERIFIED:** start/assign/bill
- **NOT VERIFIED:** vehicle reassignment/swap

## Ontrac limitation

**NOT VERIFIED:** No live function or trigger applying Ontrac staging odometer rows has been verified, so the mileage application/import path remains unresolved.

## Frontend impact

No frontend code or frontend behavior was changed by this checkpoint.
