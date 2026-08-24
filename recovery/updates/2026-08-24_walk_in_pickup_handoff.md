# 2026-08-24 — PR #42 deployment and immediate Walk-in Pickup handoff

## Deployment record

- **VERIFIED LIVE:** PR #42 merged to `main` at `627f6a61c2ef6e062c3978fd9be0124a915a7ad7`.
- **VERIFIED LIVE:** Supabase migration `20260824180402 reconcile_rental_loaner_pickup_workflows` is deployed. Read-only production verification passed for Rental-only Rental candidates, Loaner-first plus Rental fallback candidates, Loaner-fleet exclusion from Rental, the pre-continuity Loaner RO guard, fail-closed blank/null fleet types, reserved-through Rental payment behavior, current-time Loaner Billing preview, and preserved security/grants.
- **NOT APPLICABLE:** Production had zero legitimate pickup-ready records. No fake browser mutation record was manufactured.

## Walk-in checkpoint

- **IMPLEMENTED IN REPOSITORY / NOT PRODUCTION-BROWSER-VERIFIED:** Reservations continues to call only `create_walk_in_with_pricing_agreement_state`. On success it validates the returned authoritative `reservation_id`, reloads Reservations state, and opens Check-in / Pickup with that ID.
- **IMPLEMENTED IN REPOSITORY:** Pickup retains ownership of `get_pricing_agreement_pickup_state`; the handoff ID selects only a matching item in that payload. A missing item fails visibly, vehicle selection is cleared, and neither a VIN nor activation is automatic.
- **IMPLEMENTED IN REPOSITORY:** Loaner Walk-in requires a nonblank RO frontend preflight. Rental Walk-in does not. Non-daily Walk-in fails before its create RPC with the existing weekly/monthly Pickup-not-implemented wording.
- **PRESERVED:** Quote and future Reservation behavior and the deployed Rental/Loaner Pickup branches are unchanged. No Supabase change, migration, or new lifecycle, Pickup, assignment, pricing, or Billing engine belongs to this checkpoint.
- **OPEN:** Weekly/monthly Pickup, Fleet Board integration, bulk Loaner billed-through, persisted repeated Rental Extension production proof, and the whole Billing release remain incomplete.
