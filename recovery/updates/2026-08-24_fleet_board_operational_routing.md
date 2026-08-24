# Fleet Board operational routing checkpoint — 2026-08-24

## Starting point

- **VERIFIED:** `origin/main` was `06b2dd8f74b48d218a24d016116f8b1a9389cf35`, merge of PR #43 “Hand Walk-ins directly into Pickup.”
- PR #43 was frontend-only and required no Supabase migration.

## Engine-first result

- Extended the existing `public.get_fleet_board_state(timestamptz,timestamptz)` engine; no parallel Fleet Board engine was created.
- `rental_model_limits` remains Rental-only. Loaner Reservations are operationally visible but do not consume Rental capacity.
- Existing pricing intake, Reservation/Edit, Pickup/activation, and Billing engines remain authoritative. Fleet Board only routes one-time context into them.
- Empty Day slots provide type/model/start context only, never VIN or an invented expected return.

## Verification boundary

- **NOT VERIFIED:** This migration has not been applied to production.
- **NOT VERIFIED:** Production browser workflow has not been exercised.
- Weekly/monthly Pickup, bulk Loaner billed-through, repeated Rental Extension persisted proof, and complete Billing release status are unchanged and not claimed.
