# 2026-08-25 — Rental Capacity Admin: Fixed Limits and Impact Rules

## Owner-approved current behavior

For now, Rental Reservation Capacity is a simple fixed current capacity per Rental model/class.

- Admin must be able to add a model/class directly from the Reservation Capacity screen and assign its fixed capacity.
- Capacity is a whole number `>= 0`.
- Saving a new or changed capacity takes effect immediately.
- Missing capacity remains fail-closed / unavailable.
- Existing Reservations or Quotes are never automatically cancelled, modified, repriced, or moved because capacity is reduced.
- Reducing capacity is allowed even when it creates future pressure/conflicts; the save must return and display the affected future records.

## Admin model creation

The existing `public.rental_model_limits` table remains the authoritative current fixed capacity store. No parallel model catalog is introduced for this checkpoint.

The Admin screen must no longer be limited to models that already have an active Rental rate card.

- Add an `Add Model Capacity` control with model/class name plus fixed capacity.
- The backend accepts any nonblank normalized model/class name and keeps the existing normalized uniqueness rule.
- The Admin list is the union of configured capacity models and active Rental rate-card models, so configured models remain visible even if no active rate card exists.
- If a capacity model has no active Rental rate card, show that state clearly. Capacity may be configured, but the model cannot be offered for Quote/Reservation until authoritative Rental pricing exists.
- Removing capacity remains allowed and returns the model to fail-closed `not_configured` behavior.

## Capacity reduction impact semantics

Reservations and Quotes must remain distinct:

### Reservation hard conflicts

Future pre-pickup Rental Reservations are capacity commitments and continue to use the same counting semantics as `get_rental_reservation_capacity_state`:

- Rental only.
- active Transportation Event.
- active pricing agreement.
- `pricing_started_at is null`.
- non-cancelled Reservation.
- same normalized requested model/class.
- dealership-local `America/New_York` calendar days.
- half-open `[start,end)` overlap semantics.

A future local date is a hard capacity conflict when:

`reservation_count > saved_capacity`

The Admin warning must show:

- affected local date(s),
- saved capacity,
- reservation count,
- overage amount,
- all Reservations overlapping those conflict date(s), including Reservation ID, customer identity when available, model, start, expected return, and status.

Do not choose or imply which Reservation should be displaced. All overlapping committed Reservations on an over-capacity day are shown for staff review.

### Quote at-risk pressure

Quotes do **not** hold or consume capacity and must not be counted as Reservations.

A future active/unconverted Rental Quote becomes `at risk` when the saved capacity would not be sufficient if the currently active Quotes for that model/date were converted in addition to existing committed Reservations.

For each future local date:

`reservation_count + active_quote_count > saved_capacity`

The Admin warning must separately show affected active/unconverted Rental Quotes for those dates, including Quote ID, customer identity when available, model, start, expected return, and status.

The UI must explicitly label these as **at-risk Quotes / capacity pressure**, not hard Reservation conflicts, because Quotes remain non-binding and do not reserve a slot.

If committed Reservations already equal or exceed the saved capacity, overlapping active Quotes are at risk as well.

## Save behavior

No separate preview/confirmation workflow is required for this checkpoint.

One Save action must:

1. validate Admin authorization and capacity input;
2. take the existing normalized model advisory lock;
3. persist the new fixed capacity immediately;
4. evaluate future Reservation conflicts and Quote pressure against the newly saved value using one authoritative backend impact evaluator;
5. return the saved capacity plus impact payload;
6. reload/display the same authoritative impact state in Admin so warnings remain visible after page refresh until the underlying future records/capacity no longer conflict.

Increasing capacity should simply save and normally return no conflicts if the new capacity accommodates the existing records.

Saving `0` is valid and means intentionally zero capacity; all overlapping future committed Reservations are hard conflicts and overlapping active Quotes are at risk.

Removing capacity is equivalent to returning the model to unavailable/not configured. If Remove remains in the UI, it should surface the same future impact information rather than silently hiding it.

## Engine-first implementation rule

Reuse and extend the live capacity foundation delivered by PRs #48/#49:

- `public.rental_model_limits`
- `public.get_rental_reservation_capacity_state(...)`
- `public.get_admin_rental_reservation_capacity_state()`
- `public.upsert_admin_rental_reservation_capacity_state(...)`
- `public.remove_admin_rental_reservation_capacity_state(...)`
- existing normalized model advisory-lock convention

Do not create a second Reservation-capacity counter in React.

Do not force this workflow into `public.reservation_conflicts`: the live conflict writer is dependency/VIN-oriented and requires a reservation vehicle dependency. Capacity-impact warnings should be derived from authoritative Reservation/Quote state and therefore naturally disappear when records are cancelled, converted, dates change, or capacity increases.

## Deferred seasonal capacity

Later, Admin should support future dated capacity increases/decreases for seasonal fleet changes.

That scheduling behavior is explicitly deferred from this checkpoint. The current fixed `rental_model_limits.daily_limit` remains the baseline/current-capacity source. Future implementation should add an effective-dated capacity schedule/resolver and extend the existing per-day evaluator rather than replacing the capacity engine.

No seasonal schedule table, effective-date UI, or future-capacity mutation behavior is implemented in this checkpoint.
