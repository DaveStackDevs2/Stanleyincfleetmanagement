# 2026-07-31 Phase 1 Start/Assign/Bill Security Checkpoint

## Scope and baseline

**VERIFIED:** Supabase project `ycwejunodgnnkickjvsk` stored the service action's 68-character function name as the truncated 63-character `create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_`. No current frontend code or deployed `fleet-constraint-engine` Edge Function calls this workflow. Live `reservations`, `vehicle_events`, `contract_periods`, and `billing_lines` contained zero rows.

**NOT APPLICABLE:** This database-only checkpoint was not connected or applied to live Supabase.

## Recovery contract

Apply `supabase/migrations/20260731120000_phase_1_start_assign_bill_security_checkpoint.sql` through the normal reviewed deployment process. It creates the exact stable contract `create_start_bill_case_and_get_payload_state`, upserts `case.create_start_bill_and_load`, and leaves `get_unified_case_payload_state` unchanged.

The browser boundary is owned by `postgres`, security definer with an empty search path, executable only by `authenticated` (plus its owner), and enforces active application identity, AAL2, and actor agreement. It calls the legacy state workflow directly, validates the returned reservation/vehicle-event/contract-period IDs, optionally writes checkout `start_mileage`, stamps the exact continuity rows, and only then loads the payload. Inventory/create `p_vehicle_mileage` retains its meaning.

The migration fails clearly if multiple open vehicle events already exist for one vehicle before adding the unique partial index. It restricts the old truncated wrapper and mutating helper chain to `service_role`, and revokes browser mutations on `customers`, `vehicles`, `transportation_events`, `reservations`, `vehicle_events`, `contract_periods`, and `billing_lines` while preserving reads.

## Unresolved work

**NOT VERIFIED / DEFERRED:** Billing amount and tax are still trusted legacy inputs. Authoritative rate and tax calculation must be designed in a future checkpoint; no rate, tax, late-fee, or UI work is included here.
