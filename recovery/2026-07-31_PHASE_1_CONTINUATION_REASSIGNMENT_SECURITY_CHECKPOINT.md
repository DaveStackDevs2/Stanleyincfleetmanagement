# 2026-07-31 Phase 1 Continuation/Reassignment Security Checkpoint

## Verified baseline

**VERIFIED:** Dave manually applied PR #11's preceding migration after that repository checkpoint, and all six live verification checks passed. Codex did not perform or claim that deployment.

**VERIFIED:** The same-vehicle continuation and active-case reassignment/swap engines already existed. No React frontend caller or deployed `fleet-constraint-engine` caller currently invokes them. Live `reservations`, `vehicle_events`, `contract_periods`, `reservation_vehicle_dependencies`, `reservation_conflicts`, `vehicle_swaps`, and `billing_lines` were empty.

**VERIFIED:** `restart_reservation_same_vehicle_after_gap_state` called `restart_same_vehicle_after_gap`, but that helper was absent live and in the repository. `start_vehicle_use_state(uuid, uuid, timestamptz)` is the existing engine that creates the required vehicle event and contract period.

## Recovery contract

After review, manually apply `supabase/migrations/20260731170000_phase_1_continuation_reassignment_security_checkpoint.sql` one statement at a time. It adds the missing internal helper as a delegate to `start_vehicle_use_state`; it does not duplicate insertion logic. It converts the two existing browser wrappers to postgres-owned, empty-search-path security definers that require an active `app_users` identity and AAL2. Reassignment also requires any supplied actor to agree with the authenticated application user and passes that resolved actor through dependency resolution.

The wrappers validate exact workflow identifiers, preserve `created_by` on closed rows, stamp `updated_by` on those rows, stamp both actor columns on newly created continuity rows, and load unified state only after successful writes. Only `authenticated` can execute the browser wrappers; the complete mutation chain remains service-role-only. Direct browser mutations on dependency/conflict tables are denied. Existing read contracts remain unchanged.

The service-action mappings remain `case.continue_same_vehicle_and_load` and `case.reassign_to_vehicle_and_load`. This checkpoint adds no billing calculation or segmentation, no `vehicle_swaps` write, and no frontend, Fleet Board, or Edge Function behavior.

## Deployment and remaining work

**NOT APPLICABLE:** This Codex task made no frontend changes, did not connect to live Supabase, and applied no live SQL.

**NOT VERIFIED / REQUIRED:** The new migration remains pending Dave's manual live review, application, and verification. Do not mark broad Phase 1 or Phase 10 complete before that succeeds.

**UNRESOLVED:** Authoritative amount and tax calculation remains unresolved. Pay-type administration Phase 2 is next after Phase 1 closes.

**DEFERRED:** Late fees remain disabled. Their eventual dollar amounts must be editable in Admin without configuration automatically charging a fee.
