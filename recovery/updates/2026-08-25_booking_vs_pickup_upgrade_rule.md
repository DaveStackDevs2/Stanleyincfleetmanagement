# Rental Booking vs Pickup Upgrade Rule — 2026-08-25

## Purpose

Documentation-only continuity correction. This clarifies the owner's approved distinction between model availability at Quote/Reservation time and a free upgrade at Pickup. It supersedes any wording that could be read as allowing a free upgrade or downgrade during Quote/Reservation selection.

## Binding owner rule

### Quote / Reservation time

At Quote or Reservation time, Stanley TMS may only offer Rental models/classes that have authoritative capacity for the customer's complete requested date/time range.

If the customer's originally requested class is unavailable:

- do not quote or reserve that unavailable class;
- do not automatically upgrade or downgrade the customer;
- show the user/customer the other classes that actually have capacity for the requested period;
- the customer chooses among those available classes;
- the class the customer selects becomes the actual quoted/reserved class;
- the normal applicable price for that selected class becomes the quote/reservation price.

Example: customer asks for an Equinox but Equinox capacity is unavailable. If Traverse capacity is available and the customer chooses Traverse, the Reservation is for Traverse at the normal Traverse rate. This is not a free upgrade. If the customer instead chooses a lower available class, that lower class and its normal rate become the Reservation. There is no automatic free downgrade either.

If the customer declines all available alternatives, that can become a true lost-rental availability outcome.

Availability-driven reporting may record that the customer's first requested class was unavailable and another class was ultimately selected, but the actual Reservation/Pricing Agreement must reflect the class the customer chose and its normal applicable rate.

### Pickup time

A free upgrade is a different situation and occurs only after a valid Reservation already exists.

If Stanley had capacity for the reserved class when the Quote/Reservation was made, but at Pickup the reserved class cannot actually be supplied, Stanley may place the customer into the next appropriate higher Rental model/class without charging the higher class's normal rate.

For that Pickup-only free-upgrade situation:

- preserve the customer's already-agreed Reservation/Pricing Agreement rate;
- record the originally reserved class and the actual fulfilled/upgraded class;
- permit only an eligible Rental-fleet vehicle;
- make the cross-model fulfillment explicit, authorized, and audited;
- do not globally weaken normal exact-model Pickup rules.

The customer must not be repriced upward merely because Stanley could not supply the class it validly reserved.

## Implementation consequence

Capacity selection and Pickup upgrade handling are separate engines/workflows:

1. Capacity/Quote/Reservation must prevent unavailable classes from being selected and return available alternatives.
2. Choosing an alternative at booking time changes the actual Reservation class and pricing to that chosen class.
3. A Pickup-time free upgrade is an exception against an already-existing Reservation and preserves the original agreed price.

Do not implement booking-time alternative selection using the Pickup free-upgrade exception.
Do not implement Pickup free upgrades by rewriting the original pricing agreement to the upgraded class's normal rate.
