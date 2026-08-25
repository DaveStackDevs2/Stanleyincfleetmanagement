# 2026-08-25 — Rental Capacity Admin Production Verification

## Checkpoint

The fixed current Rental Reservation Capacity Admin workflow from PR #53 is merged, deployed, and production-verified.

- PR #53 merge commit: `d008b92711d5257f339bfafb182ba8a500efb4d6`.
- Live Supabase migration: `20260825171051 rental_capacity_admin_impact_warnings`.
- The repository migration remains `supabase/migrations/20260825180000_rental_capacity_admin_impact_warnings.sql`.
- The exact final migration was compiled against production PostgreSQL inside an explicit transaction and rolled back successfully before merge.
- All three Vercel deployments reported success on the final PR head and on the merged `main` commit.

## Verified Admin behavior

The Admin Reservation Capacity workflow now supports the owner-approved fixed-capacity baseline:

- Admin can add a nonblank Rental model/class directly, even when no active Rental rate card exists.
- Capacity is a whole number `>= 0`; zero is valid and means intentionally zero reservable capacity.
- Save takes effect immediately; no preview/confirmation step is required.
- Missing capacity remains fail-closed / unavailable.
- Configured-only models remain visible without an active rate card.
- Active-rate-card models remain visible even when capacity is not configured.
- A future-referenced model remains visible after capacity removal, even with no active rate card, while qualifying future Reservations or active unconverted Quotes still create capacity impact.
- Once the model is unconfigured, has no active rate card, and has no qualifying future Reservation/Quote references, it may disappear naturally from the Admin list.

A live authenticated/AAL2 Admin RPC smoke test verified that a temporary capacity-only model with no rate card could be saved at capacity `0`, appeared as configured in the Admin state, could be removed, and left zero rows behind.

## Verified impact behavior

Capacity impact is backend-derived from authoritative Reservation/Quote state using `America/New_York` local calendar days and half-open `[start,end)` semantics.

- Future pre-pickup Rental Reservations are committed capacity.
- Active unconverted Rental Quotes remain non-binding and do not consume committed Reservation capacity.
- Hard Reservation conflicts and at-risk Quote pressure are returned separately.
- The Admin UI consumes backend per-day impact values rather than recalculating capacity in React.
- Per-day output includes effective/saved capacity, Reservation count and overage, active Quote count, combined pressure, and Quote-pressure overage.
- Affected Reservation and Quote records include operational identifiers, customer name when available, model/class, timestamps/status, and affected local dates.
- Existing Reservations and Quotes are never automatically cancelled, moved, repriced, or changed by a capacity reduction.

## Security verification

The new impact evaluator and Admin wrappers were verified live after deployment.

- `public.evaluate_admin_rental_reservation_capacity_impact(text,integer)` is `SECURITY DEFINER`, owned by `postgres`, uses an empty `search_path`, and is executable only by `postgres`/`service_role`.
- `public.get_admin_rental_reservation_capacity_state()` is callable by authenticated/service-role paths but enforces active app user, AAL2, and `user_admin.manage` internally.
- `public.upsert_admin_rental_reservation_capacity_state(text,integer)` uses the same Admin/AAL2/permission boundary and normalized model advisory lock.
- `public.remove_admin_rental_reservation_capacity_state(text)` uses the same boundary and normalized model advisory lock.
- Direct browser mutation of `public.rental_model_limits` remains blocked by the existing RLS/no-policy boundary.

The post-DDL Supabase security advisor continues to report broad pre-existing project findings, including generic warnings for authenticated `SECURITY DEFINER` wrappers and legacy project-wide RLS/search-path items. No new mutable-search-path finding was introduced for this checkpoint, and the new internal evaluator is not exposed to authenticated users.

## Production data state

No model capacities were seeded or invented during deployment or verification.

At verification time:

- `public.rental_model_limits` contained `0` configured capacity rows.
- The Admin read model returned one active Rental rate-card model, unconfigured for capacity.
- No current capacity-impact warnings existed because there were no qualifying future records creating pressure.

Real capacities must therefore be entered by an authorized Admin through **Admin Console → Reservation Capacity** before new Rental Quotes/Reservations can use those models.

## Deferred

Seasonal/effective-dated future capacity changes remain intentionally deferred. The current fixed `rental_model_limits.daily_limit` is the baseline that a later dated-capacity schedule/resolver should extend rather than replace.
