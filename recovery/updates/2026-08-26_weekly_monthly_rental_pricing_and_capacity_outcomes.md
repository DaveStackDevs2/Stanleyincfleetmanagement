# 2026-08-26 — Owner-approved weekly/monthly Rental pricing, renewal, early-return, and capacity outcome rules

## Purpose

This checkpoint records binding owner decisions made immediately after Bulk Updating (PR #60 / Issue #59) went live. These rules close the prior weekly/monthly Rental Pickup/Billing business-rule blocker and define the previously deferred Lost Rental, paid alternative-model, and free-upgrade revenue outcomes.

A successor AI/developer MUST read this file together with `docs/BILLING_BUILD_PUNCHLIST.md`, `recovery/2026-08-25_ACTIVE_WORKFLOW_CHECKPOINT.md`, `recovery/updates/2026-08-25_capacity_lost_rental_workflow.md`, and `recovery/updates/2026-08-25_booking_vs_pickup_upgrade_rule.md` before changing Rental pricing, capacity outcomes, Pickup, or Billing.

ENGINE-FIRST remains binding: inspect live Supabase before implementation, reuse existing pricing-agreement, rate-card, Billing preview, Return/Complete, renewal, swap, capacity, Quote/Reservation, Pickup, tax, and audit engines. Do not create frontend monetary calculations or a parallel lifecycle engine.

---

## 1. Weekly and monthly Rental pricing qualification

Weekly and monthly discounts are earned only by completing the applicable block.

Pricing decomposition uses the largest completed block first:

1. 28-day Monthly blocks
2. 7-day Weekly blocks
3. remaining Daily days

Examples:

- 1–6 days: Daily only.
- 7 days: one Weekly block.
- 10 days: one Weekly block + 3 Daily days.
- 14 days: two Weekly blocks.
- 27 days: three Weekly blocks + 6 Daily days; it does NOT qualify for Monthly.
- 28 days: one Monthly block.
- 30 days: one Monthly block + 2 Daily days.
- 35 days: one Monthly block + one Weekly block.
- 38 days: one Monthly block + one Weekly block + 3 Daily days.

The configured model/class rate card remains authoritative for Daily, Weekly, and Monthly rates. No rates may be hardcoded in frontend or SQL.

---

## 2. 28-day contract and renewal rule

A Rental contract may run for a maximum of 28 days before renewal is required.

The system may accept an intended Reservation/rental period of up to two consecutive 28-day contract periods (maximum 56 days on the same vehicle), but must surface the operational/legal renewal boundary:

- Contract #1 expires at 28 days and requires customer renewal.
- One renewal may continue the same vehicle for Contract #2.
- At the end of the second 28-day contract period, the same vehicle may not simply be renewed again; a vehicle swap is required for continued Rental use.

The 28-day renewal boundary is an operational contract boundary, NOT a pricing reset. Pricing qualification continues across the overall continuous Rental period. Example: a 38-day intended Rental still prices as 28 Monthly + 7 Weekly + 3 Daily even though a renewal is required at day 28.

The implementation must reuse existing renewal/continuation/swap engines where applicable and must not invent a second contract lifecycle.

---

## 3. Early Return mandatory repricing

When a Rental vehicle is returned earlier than the reserved/expected period, the application MUST recalculate the Rental charge from the authoritative contract start through the authoritative actual return using the same completed-block rules:

28-day Monthly blocks -> 7-day Weekly blocks -> Daily remainder.

The customer does not retain a discounted block that was not actually completed.

The Return/Complete workflow must compare the recalculated actual Rental obligation with the previously expected/charged Rental amount and clearly surface the difference as one of:

- Refund due
- Customer owes
- No difference

The application is not the cashier. It records/calculates the authoritative amount and difference for Tekion handling; it does not automatically issue a refund, collect payment, or settle accounting.

Tax must remain authoritative through the existing tax engine and follow the recalculated Rental charge.

---

## 4. Late/partial-day rules remain OFF and deferred

Do NOT tie weekly/monthly pricing to unfinished lateness or exact pickup/return clock-time penalties.

The existing late-rule/late-fee area remains disabled/deferred for now. The owner will manually handle late charges and loan/rental extensions when needed.

Do not automatically:

- add partial-day late charges,
- add late fees,
- extend a Rental because it passed an expected return time,
- create penalty charges from pickup/return clock-time drift.

When the separate late-rule system is implemented later, it must remain independently configurable/on-off and must not rewrite these completed-block pricing rules.

---

## 5. Lost Rental definition

A Lost Rental occurs only when:

1. the requested Rental model/class has no authoritative Reservation capacity for the requested period,
2. staff offers or presents available alternative model(s), and
3. the customer does NOT accept an alternative.

Only that outcome counts as a Lost Rental.

Lost Rental reporting should preserve the requested model/class, requested period, requested authoritative pricing context, and lost revenue attributable to the unfulfilled requested Rental.

Do not classify an accepted alternate model as a Lost Rental.

---

## 6. Paid alternative-model outcome at Quote/Reservation

If the requested model/class has no capacity at Quote or Reservation time but the customer accepts a different available model/class, the booking proceeds at the accepted model's normal authoritative rate.

Track both requested and accepted model/class and the revenue difference for the same requested period:

- accepted lower-priced model -> `Downsize Lost Revenue`
- accepted higher-priced model -> `Upgrade Gained Revenue`
- equal value -> zero revenue difference

This is NOT a free upgrade and NOT a Lost Rental.

Quote conversion must continue to recheck authoritative capacity. Quotes do not hold capacity.

---

## 7. Free Upgrade at Pickup

Free Upgrade is a separate Pickup-only outcome.

It applies when:

1. the customer already has a valid Reservation,
2. the reserved model/class cannot actually be supplied at Pickup,
3. Stanley supplies a higher/different Rental-fleet model/class without increasing the customer's already-agreed Rental price.

The original agreed pricing snapshots remain authoritative for what the customer pays.

Track the normal authoritative value of the actual upgraded model for the same period and record the difference as `Free Upgrade Lost Revenue`.

Preserve both:

- reserved/requested model/class,
- actual fulfilled/upgraded model/class.

This exception is Pickup-only. Do not provide a booking-time free upgrade and do not reprice the customer upward during a free upgrade.

Rental fleet eligibility remains binding; do not use Loaner-only vehicles for Rental fulfillment.

---

## 8. Reporting outcome categories

Capacity/pricing reporting must distinguish at least:

- Lost Rental
- Downsize Lost Revenue
- Upgrade Gained Revenue
- Free Upgrade Lost Revenue

Do not collapse these into one generic lost-revenue metric.

Historical reporting values should use authoritative pricing snapshots appropriate to the outcome and preserve enough source context to explain the calculation later.

---

## 9. Immediate implementation order

The next implementation workstream should proceed engine-first in this order unless live inspection proves a safer dependency order:

1. Audit current live/repository Rental pricing-agreement, Pickup, Billing preview, Return/Complete, renewal, swap, Lost Rental, and capacity-outcome engines.
2. Add one authoritative Rental block-pricing resolver shared by Quote/Reservation pricing presentation, Pickup activation, active/closed Rental Billing, and Return repricing; do not duplicate math in React.
3. Remove the current weekly/monthly Pickup fail-closed guard only after the shared resolver and contract-boundary behavior are verified.
4. Add 28-day renewal-required state and second-period/swap-required state without resetting pricing qualification.
5. Add early-return authoritative repricing and Refund due / Customer owes / No difference output through existing Return/Complete.
6. Implement Lost Rental outcome recording only after confirming the existing `lost_rentals` table/read contracts and correcting any security/outcome-classification gaps.
7. Implement paid alternate-model gain/loss tracking at Quote/Reservation capacity fallback.
8. Implement the narrow Pickup-only free-upgrade exception and Free Upgrade Lost Revenue.
9. Wire outcome visibility into Fleet Board/Reservations/Billing/reporting only from authoritative backend state.
10. Real-PostgreSQL preflight every migration before merge; do not claim SQL validity from source tests alone.

---

## 10. Punchlist status

These rules are owner-approved and no longer `TBD`:

- Weekly Rental qualification: DEFINED.
- Monthly Rental qualification: DEFINED as 28 days.
- Mixed Monthly/Weekly/Daily decomposition: DEFINED.
- Early-return repricing: DEFINED and REQUIRED.
- 28-day renewal requirement: DEFINED.
- One same-vehicle renewal / swap after second 28-day period: DEFINED.
- Late/partial-day automatic charges: DEFERRED/OFF.
- Lost Rental outcome: DEFINED.
- Paid alternative downsize/upgrade revenue: DEFINED.
- Pickup-only Free Upgrade Lost Revenue: DEFINED.

Implementation and live verification remain OPEN until completed and recorded in `docs/BILLING_BUILD_PUNCHLIST.md` and project recovery/status documentation.
