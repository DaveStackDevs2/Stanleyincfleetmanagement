
## 2026-08-25 — Authoritative Reservation Capacity dependency

Fleet Board Reservation Capacity uses `get_fleet_board_capacity_state`, which delegates every configured model/range to the same `get_rental_reservation_capacity_state` engine used by Reservations. React displays returned per-day booked/limit values and does not recount Reservation rows. Capacity is Rental-only, dealership-local (`America/New_York`), and half-open. Existing Reservation conflict persistence after an Admin limit reduction is explicitly deferred; no existing Reservation is cancelled or reassigned. Lost Rental classification and free-upgrade Pickup are not part of this checkpoint. **NOT VERIFIED LIVE:** migration deployment and production browser behavior.
