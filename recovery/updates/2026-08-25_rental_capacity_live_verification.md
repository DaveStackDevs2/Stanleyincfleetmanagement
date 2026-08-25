# 2026-08-25 — Authoritative Rental Reservation Capacity live verification

## Repository checkpoints

- PR #48, **Authoritative Rental Reservation Capacity: evaluator, enforcement, Fleet Board & Admin UI**, merged to `main` at `3fa208383d6e8523bd1a943f25383de171940c7b`.
- The first live Supabase application attempt failed transactionally because the Quote -> Reservation conversion wrapper used an ambiguous PL/pgSQL `CASE ... END IS NULL` expression. PostgreSQL rejected the migration with a syntax error and the whole attempt rolled back. Production remained unchanged: no capacity RPCs, renamed intake engines, normalized index, capacity rows, or migration-ledger entry were left behind.
- PR #49, **Fix capacity conversion migration syntax**, changed only that PL/pgSQL expression to `(CASE ... END) IS NULL` and added a focused regression. It merged to `main` at `52c52946c691e505096677ff2961134fac36b673`.

## Live Supabase deployment

- Project: `ycwejunodgnnkickjvsk`.
- Live migration ledger now contains `20260825161110 authoritative_rental_reservation_capacity`.
- `public.rental_model_limits` still contains **zero rows**. No capacity values were seeded or invented.
- `ck_rental_model_limits_daily_limit` exists and is validated, enforcing nonnegative limits.
- `ux_rental_model_limits_normalized_vehicle_class` exists as a unique index on `lower(btrim(vehicle_class))`.

## Verified live behavior

- `public.get_rental_reservation_capacity_state(text,timestamptz,timestamptz,uuid)` is live and fail-closed. With no configured capacity, a read-only AAL2 application-user verification returned:
  - `status = not_configured`
  - `available = false`
  - `capacity_configured = false`
  - no alternatives, because no Rental model currently has configured Reservation Capacity.
- `public.get_admin_rental_reservation_capacity_state()` is live and returned `admin_rental_reservation_capacity_ready`; every active Rental rate-card model was reported unconfigured at verification time.
- Quote creation and direct Reservation creation both call the authoritative capacity evaluator server-side.
- Quote -> Reservation conversion accepts the optional staff-selected class, rechecks authoritative capacity, and uses the existing `resolve_rental_rate_card_state(...)` engine when the selected conversion class differs from the original Quote class.
- `public.get_fleet_board_capacity_state(...)` delegates to `get_rental_reservation_capacity_state(...)`; Fleet Board does not own a second capacity calculation.

## Security verification

- New/updated controlled RPCs are owned by `postgres`, use `SECURITY DEFINER`, and have an empty `search_path`.
- Anonymous EXECUTE is denied on the new capacity/Admin/intake wrapper RPCs.
- Authenticated users can execute the controlled wrappers, which retain active-user/AAL2/permission checks where required.
- Renamed underlying Quote/Reservation/conversion/edit engines are not executable by the authenticated browser role; service-role access remains available for internal/server use.
- `rental_model_limits` keeps RLS enabled with no browser mutation policy, so direct browser table mutation remains fail-closed; Admin writes go through the controlled capacity RPCs.
- The post-DDL Supabase Security Advisor reported the project's existing broad advisory set, including expected generic warnings for authenticated `SECURITY DEFINER` application RPCs and pre-existing unrelated findings. No new anonymous-executable warning was introduced for the capacity RPCs.

## Frontend/deployment verification

- Vercel checks are green for all three configured projects on merged `main` commit `52c52946c691e505096677ff2961134fac36b673`.
- Authenticated production-browser interaction with the new Reservation Capacity Admin surface and Quote/Reservation capacity UX is **not yet visually verified** in this checkpoint.

## Product rule preserved

- Quote and Reservation time: only classes with authoritative capacity for the complete requested period may be selected. If the requested class is unavailable, the customer chooses another available class and that class's normal rate becomes the Quote/Reservation price.
- Quotes do not hold capacity; conversion rechecks availability.
- Pickup-time free upgrade remains a separate future workflow: if an already-reserved class cannot be supplied at Pickup, Stanley may supply the next model up without increasing the customer's already-agreed rate.

## Still deferred

- No Lost Rental write/classification engine was implemented here.
- No alternative-model/free-upgrade outcome tracking was implemented here.
- No cross-model Pickup free-upgrade exception was implemented here.
- Admin limit reductions do not yet persist/refresh capacity conflicts for existing Reservations.
- Bulk Updating and weekly/monthly Billing remain separate checkpoints.

## Operational consequence

Until Reservation Capacity values are deliberately configured through Admin, Rental Quotes and Reservations correctly fail closed as unavailable. The next operational step is to enter the real per-model capacity values before production booking use or browser verification of available alternatives.
