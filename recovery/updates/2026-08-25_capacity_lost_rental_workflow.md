# Rental Capacity / Lost Rental Workflow — 2026-08-25

## Purpose

Documentation-only continuity checkpoint. This records owner-approved Rental capacity behavior and the live engine audit completed before implementation. No application code, Supabase schema, production data, or deployed behavior is changed by this file.

Read together with `recovery/2026-08-25_ACTIVE_WORKFLOW_CHECKPOINT.md` and the Recovery Bible.

## Owner-approved capacity behavior

Rental Reservation Capacity is authoritative. A missing capacity configuration is **not** unlimited availability.

When staff enters a requested Rental model and requested start/end date-time range, if that model has no configured capacity for the requested period or its configured capacity is already exhausted, Stanley TMS must:

- warn the user clearly that the requested model has no capacity for the entered period;
- not silently create an over-capacity Rental Reservation;
- suggest other Rental models that have capacity for the complete entered date range;
- allow staff/customer to choose an available alternative rather than starting the search over.

Alternative suggestions must be authoritative backend results, not frontend guesses. A model should be suggested only when its configured capacity is available across the full requested date range it would need to cover.

The Fleet Board remains the primary scheduling/front-door surface and must use the same authoritative capacity engine as Reservations/intake. Do not create separate Fleet Board and Reservations availability calculations.

## Existing capacity state verified live

- `public.rental_model_limits` already exists and is the intended Rental Reservation Capacity store.
- As of this audit, the live table has zero configured rows. Do not invent capacity numbers.
- `get_fleet_board_state(...)` reads and displays `rental_model_limits` but the current intake mutation engines do not enforce those limits.
- No separate live capacity helper/RPC was found beyond the Fleet Board read.
- `create_or_update_reservation_conflict_state(...)` is specifically tied to a VIN-level `reservation_vehicle_dependencies` record and is not the correct engine to force model/day capacity conflicts through.

Implementation must therefore add one narrow authoritative model/date capacity engine and reuse it from every mutation/read path that requires capacity knowledge, instead of duplicating SQL checks.

## Lost Rentals / availability-impact tracking

The owner requires Stanley TMS to track not only rentals that are completely lost because the requested model is unavailable, but also availability-driven situations where:

1. the customer cannot be accommodated and the Rental is lost;
2. the requested model is unavailable and the customer accepts a different model;
3. the requested model is unavailable and Stanley gives the customer a free upgrade.

These are related availability outcomes but they are not all true lost rentals. Reporting must preserve that distinction.

### Existing backend verified live

The backend already contains:

- `public.lost_rentals`;
- trigger `trg_lost_rentals_set_updated_at`;
- `get_lost_rentals_summary_state(p_start_at,p_end_at)`;
- Lost Rentals visibility in the dashboard payload/access engine.

`lost_rentals` already stores useful historical context including requested model/class, requested start/end, requested days, quoted daily rate, customer, Transportation Event, Reservation, reason, notes, and actor IDs.

As of the audit, live `lost_rentals` contains **zero rows**.

No authoritative Lost Rental write RPC was found. The existing summary currently counts every `lost_rentals` row as a lost rental, so it must not simply begin receiving substitution/free-upgrade rows without being extended to classify outcomes correctly.

Reuse/extend this existing foundation; do not create a parallel lost-rental table or reporting system.

## Required availability outcome information

The existing Lost Rentals foundation must be extended narrowly enough to preserve at least:

- requested model/class;
- requested start/end date-time;
- requested duration;
- requested/quoted rate;
- final outcome: true lost rental, alternative model accepted, or free upgrade;
- fulfilled model/class when a Rental is still booked;
- actual customer rate when relevant;
- linked customer / Reservation / Transportation Event when those records exist;
- reason and notes;
- actor/audit information.

Dashboard reporting must continue to report **true lost rentals** separately from model substitutions and free upgrades. Availability-impact metrics may additionally show substitutions/upgrades, but those must not inflate lost-rental count or estimated lost revenue.

## Alternative-model behavior

If the requested model has no capacity and the customer accepts another available model, record the originally requested model and the model ultimately selected so Stanley can measure demand that could not be fulfilled as requested.

If the alternative is taken at that alternative model's normal applicable price, this is an availability-driven model substitution, not a lost rental and not a free upgrade.

## Free-upgrade behavior

A free upgrade means the customer receives a higher/different Rental model because the requested class is unavailable **without being charged the higher model's normal rate**.

The customer's original quoted/agreed rate must be preserved. The event must record the requested model, fulfilled/upgraded model, and the pricing impact so Stanley can measure how often capacity shortages require free upgrades.

### Existing Pickup constraint verified live

The current Rental Pickup engine requires the selected vehicle model to match the pricing agreement's `vehicle_class`. `v_reservation_vehicle_candidates` is also exact-model for Rental reservations.

Therefore a real free upgrade cannot be implemented as reporting-only. The implementation needs a narrow, authorized, audited cross-model Rental fulfillment exception that:

- preserves the original pricing-agreement rate snapshots/customer price;
- permits the approved upgraded Rental vehicle/model;
- does not weaken the rule that public Rentals may only use Rental-fleet vehicles;
- does not silently rewrite ordinary reservations into another pricing agreement;
- leaves normal exact-model Pickup behavior unchanged when no exception is present.

Do not solve this by changing the Rental's rate to the upgraded model's rate or by weakening all model-match validation globally.

## Security / engine boundary note

`lost_rentals` currently has RLS enabled but broad authenticated CRUD policies. New application behavior should use controlled RPC boundaries with active-user/AAL2/permission checks consistent with current pricing-agreement/Fleet Board patterns, rather than adding new direct frontend table mutation.

Review and narrow legacy mutation exposure as part of the implementation if it can be done without breaking a verified caller.

## Implementation sequencing

Before coding, re-check live state and repository migrations. Then:

1. Add/reuse one authoritative Rental model/date capacity evaluator that returns requested-model availability plus available alternatives.
2. Use it for the Rental intake/Fleet Board warning and authoritative Reservation enforcement; do not allow silent overbooking.
3. Extend the existing Lost Rentals foundation into a classified availability-outcome ledger/reporting engine.
4. Add the controlled record-outcome path for true lost Rental / alternate accepted / free upgrade.
5. Add the narrow free-upgrade fulfillment exception while preserving the original pricing agreement and Rental-fleet eligibility.
6. Wire the frontend to authoritative results only.
7. Test missing capacity, full capacity, multi-day availability, alternative suggestions, true lost rental, accepted alternative, free upgrade, exact-model normal Pickup, and security boundaries.
8. Update Recovery/Status/Decisions/Changelog as part of the implementation PR.

Do not invent capacity values and do not create fake production Rental/lost-rental records merely for proof.
## Engineering checkpoint implementation — Authoritative Rental Reservation Capacity

**IMPLEMENTED / REPOSITORY VERIFIED:** The existing `rental_model_limits` store now has a single fail-closed evaluator for Maine dealership calendar days, complete-period alternatives, and edit exclusion. Direct Rental Reservation creation, Quote conversion, and pre-check-in date editing recheck capacity under their established authorization boundary and serialize same-model decisions. Quotes still consume no capacity; Loaner and Walk-in semantics are preserved. Fleet Board and the staff Reservations UI consume backend capacity state, and Admin configuration is RPC-only with AAL2 plus `user_admin.manage`. No limits were seeded.

**NOT VERIFIED LIVE:** This migration was not applied to Supabase and no production-browser mutation was performed.

**DEFERRED:** Persisted capacity-conflict refresh after Admin reductions is the immediate Fleet Board capacity follow-up. Lost Rental write behavior/classification, alternative-model acceptance, free upgrades/cross-model Pickup, Bulk Billing, and weekly/monthly Billing remain unimplemented and outside this checkpoint.
