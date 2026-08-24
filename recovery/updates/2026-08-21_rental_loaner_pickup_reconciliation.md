
## 2026-08-21 — Rental / Loaner Pickup reconciliation

**IMPLEMENTED / NOT YET DEPLOYED OR PRODUCTION-VERIFIED:** Pickup now preserves two distinct workflows while reusing the existing continuity, pricing-agreement, Billing, tax, Rental payment, and Loaner billed-through engines.

- **Rental:** Quote / Reservation / Walk-in → Rental pickup → reserved-through Rental charge → external Tekion Rental Sale Paid / Not Paid → Rental Extensions → Return. Rental pickup remains Rental-fleet-only, persists the original charge and synchronized tax through expected return, and returns authoritative Rental payment state.
- **Loaner:** Quote / Reservation / Walk-in → Loaner pickup with required RO → initial/open Loaner Billing → Tekion Mark billed through progression → warranty/pay-type segmentation as applicable → Return. Loaner pickup uses the scheduled Billing start, previews at current/effective time, and does not invoke or display Rental payment state.
- **One-way fleet rule:** a Loaner-fleet vehicle cannot serve a Rental; a Rental-fleet vehicle may serve a Loaner as a fallback, with native Loaner candidates ordered first.
- **Assignment boundary:** `public.start_reservation_vehicle_use_state` rejects a null/blank Loaner RO before `public.start_vehicle_use_state` can begin continuity. Rental has no RO requirement.
- **Still NOT IMPLEMENTED:** Fleet Board click integration, Fleet Board Loaner reservation rendering, and immediate Walk-in activation remain later checkpoints. Nothing in this checkpoint claims those surfaces complete.
