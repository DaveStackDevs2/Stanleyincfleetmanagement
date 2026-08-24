## 2026-08-24 — PR #42 live verification and immediate Walk-in handoff

- **VERIFIED LIVE / RECORDED:** PR #42 merged to `main` at `627f6a61c2ef6e062c3978fd9be0124a915a7ad7`; live Supabase migration `20260824180402 reconcile_rental_loaner_pickup_workflows` passed read-only production verification for the Rental/Loaner pickup branches, one-way fleet eligibility, Loaner RO guard, fail-closed normalized fleet types, and preserved security/grants. Zero legitimate pickup-ready production records existed, so no fake browser mutation case was manufactured.
- **IMPLEMENTED IN REPOSITORY / NOT PRODUCTION-BROWSER-VERIFIED:** A successful Walk-in still uses `create_walk_in_with_pricing_agreement_state`, validates its authoritative `reservation_id`, reloads authoritative state, and hands that ID directly into the existing Check-in / Pickup workspace. Pickup selects it only after `get_pricing_agreement_pickup_state` returns the matching item; no VIN is preselected and activation remains staff initiated.
- **PRESERVED / FAIL CLOSED:** Loaner Walk-ins require a nonblank RO frontend preflight and non-daily Walk-ins stop before creation because weekly/monthly Pickup is not implemented. No backend lifecycle, Pickup, pricing, assignment, or Billing engine was added.


## 2026-08-18 — Pre-check-in Reservation editing

- **VERIFIED LIVE / RECORDED:** The browser-safe five-field edit backend preserves the existing Reservation, Transportation Event, and pricing agreement, and delegates the Transportation Event schedule mirror to the existing expected-return engine.
- **VERIFIED LIVE:** A controlled scheduled start, scheduled return, service advisor, RO number, and notes edit produced exactly five matching audit rows without VIN, continuity, contract period, pricing, billing, snapshot, or identity changes.
- **IMPLEMENTED / NOT YET VERIFIED IN PRODUCTION BROWSER:** Reservations now includes an RPC-only Edit Reservation workspace. Check-in / Pickup browser activation also remains **NOT YET VERIFIED**.
- **TBD / DEFERRED:** The future penalty-free edit cutoff remains TBD. Model, workflow, pay-type, and rate-plan edits remain deferred pending authoritative pricing and availability policy.

# Project Status

## 2026-08-18 — Check-in / Pickup lifecycle correction

**VERIFIED live / IMPLEMENTED IN REPOSITORY:** Reservations reserve scheduled capacity, model/workflow, and pricing snapshots without VIN, continuity, contract period, or billing. At Check-in / Pickup, physical continuity uses actual handoff while billing and pricing begin at the Reservation scheduled start. Late arrival does not move scheduled start or expected return. Billing excludes pre-check-in Reservations by reusing authoritative current-continuity/current-billing operational state.

**VERIFIED live / RECORDED HARDENING:** The authoritative candidate view excludes retired vehicles. Activation locks the selected non-retired vehicle and revalidates that it is `available` before assignment, continuity, or billing writes, preventing stale candidate state from starting pickup or billing.

**NEXT / NOT IMPLEMENTED:** Reservation editing before Check-in is required, but no verified browser-safe general edit RPC exists. Scheduled start, expected return, advisor, RO number, and notes are expected fields; model/workflow/pay type/rate plan require authoritative pricing and availability. No direct table update or penalty cutoff was invented; the cutoff remains TBD. Weekly/monthly and “Now” remain deferred. Production browser Check-in activation is **NOT VERIFIED**.


## 2026-08-18 — Reservations Pickup checkpoint

**VERIFIED:** PR #31 is on main at `a910472a6b66e59c1959c0c0e9502b9da1d366cf`. Production Rental intake created one Reservation, pricing agreement, and Transportation Event without pre-pickup VIN/continuity/billing. Production overlap testing exposed and live repair closed a fleet-type compatibility hole: the write boundary rejects Rental-to-Loaner activation before writes and candidates now match model plus fleet type. The controlled Rental candidate list returns only `TEST-STOCK-003`; controlled records are not seeds.

**IMPLEMENTED / NOT VERIFIED IN PRODUCTION BROWSER:** the Reservations Pickup tab reads and activates only through authoritative pickup RPCs, then reloads state and presents the returned Billing preview. Weekly/monthly activation remains unimplemented and fail-closed. A real production browser activation remains required after merge. The “Now” datetime convenience and taxable-checkbox alignment are intentionally deferred. Product wording is Vehicle model while `vehicle_class` remains the compatibility identifier.


## 2026-07-30 Phase 1 checkpoint

- **VERIFIED:** Live Supabase project `ycwejunodgnnkickjvsk` has the operational RPC security state captured by this checkpoint, and production SQL was already applied and verified manually.
- **VERIFIED:** Extension, completion/return, and cancellation top-level RPCs require an active authenticated application user and AAL2, stamp that user's application ID, and keep internal helpers unavailable to browser roles.
- **VERIFIED:** Return mileage is optional; omitting `p_end_mileage` preserves the existing `reservations.end_mileage`.
- **NOT VERIFIED / REQUIRED:** Checkout mileage must remain optional when the outstanding start/assign/bill workflow is reconciled; its implementation has not yet been verified.
- **NOT VERIFIED:** Same-vehicle continuation, start/assign/bill, and vehicle reassignment/swap remain Phase 1 operational contracts to reconcile and secure.
- **NOT VERIFIED:** No live function or trigger applying Ontrac staging odometer rows has been verified.
- **DEFERRED:** Excess-mile calculation remains future work.
- **DEFERRED:** Applicable late-fee dollar amounts must eventually be editable in Admin Rates, Fees & Billing Rules from `public.late_fee_rules.fee_amount`. Verified live placeholders are `grace_period` = null, `fixed_fee` = 0, and `full_day_trigger` = 0. Configuration must not automatically charge a fee; late fees remain discretionary, staff-applied, waivable/reversible, and auditable with actor, reason, timestamp, and preserved history.

Repository baseline for this checkpoint: GitHub `main` at `0cb1ec43d50512500bbbe36382e33149d183c873`.

## 2026-07-31 — Phase 1 start/assign/bill database checkpoint

**VERIFIED:** The repository now defines the stable, non-overloaded browser contract `create_start_bill_case_and_get_payload_state` for `case.create_start_bill_and_load`; the prior 68-character configured name was stored by PostgreSQL as the truncated 63-character `create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_`. The new boundary requires an active application user and AAL2, stamps the created continuity rows, keeps checkout mileage optional and distinct from vehicle inventory mileage, and enforces one open vehicle event per vehicle. Internal mutation helpers and direct operational-table writes are restricted while the unified payload read contract is unchanged.

**VERIFIED live baseline supplied for this checkpoint:** no current frontend or deployed `fleet-constraint-engine` dependency; `reservations`, `vehicle_events`, `contract_periods`, and `billing_lines` each had zero rows. **NOT APPLICABLE:** no live SQL was applied. **UNRESOLVED:** authoritative amount and tax calculation remains future work; legacy values remain trusted inputs.

### 2026-07-31 follow-up — PR #11 manual deployment

**VERIFIED:** After the repository checkpoint above, Dave manually applied PR #11's migration to live Supabase and all six live verification checks passed. This dated follow-up does not imply that Codex applied production SQL.

## 2026-07-31 — Phase 1 continuation/reassignment database checkpoint

**VERIFIED baseline:** The continuation and reassignment/swap engines already existed and are being secured and reconciled, not replaced. The required `restart_same_vehicle_after_gap` dependency was absent both live and in the repository; the checkpoint reuses `start_vehicle_use_state` as the existing event/contract creation engine. No React frontend or deployed `fleet-constraint-engine` caller currently exists. The seven relevant live tables—`reservations`, `vehicle_events`, `contract_periods`, `reservation_vehicle_dependencies`, `reservation_conflicts`, `vehicle_swaps`, and `billing_lines`—were empty.

**NOT APPLICABLE:** No frontend changes were made and Codex did not connect to or apply SQL to live Supabase. **NOT VERIFIED / REQUIRED:** The new migration is pending manual review, application, and live verification; broad Phase 1 and Phase 10 must remain open until then. **UNRESOLVED:** Authoritative amount/tax calculation remains unresolved. Pay-type administration Phase 2 is next after Phase 1 closes. **DEFERRED:** Late fees remain disabled; eventual Admin-editable dollar amounts must not automatically apply charges.

## 2026-08-11 — Rental rate-card checkpoint

- **VERIFIED LIVE / IMPLEMENTED IN REPOSITORY:** the pay-type-independent rental rate-card schema and five new RPC contracts are recorded in an idempotent, data-free migration; the Rental Rates Admin UI calls the new Admin RPCs and supports required daily plus optional weekly/monthly rates.
- **NOT APPLICABLE:** this repository work did not apply migrations to live Supabase, seed or rewrite business values, change billing snapshots, or remove legacy compatibility contracts.
- **OPEN / NOT IMPLEMENTED:** Quote/Reservation/Walk-in pricing agreements and all conversion, insurance, discount, override, paid-through, allocation, credit, expected-balance, and ledger runtime behavior.

## 2026-08-12 — Shared rental-pricing-agreement foundation

- **VERIFIED LIVE CONTRACT / IMPLEMENTED IN REPOSITORY:** The data-free migration records the shared pricing agreement, one-Transportation-Event Quote/direct Reservation/Walk-in architecture, same-event Quote conversion, secured Dev/AAL2 RPC boundary, billing compatibility snapshots, monthly-requires-weekly prerequisite, central audit trail, and protected-table privilege corrections.
- **NOT APPLICABLE:** No live Supabase change or production seed was performed; no pickup, VIN, timer, contract-period, pricing activation, calculation, discount, insurance, payment, cashiering, allocation, or billing-line workflow was started.
- **OPEN / NOT IMPLEMENTED:** Frontend Quote/Reservation/Walk-in workflows and every post-pickup pricing and payment capability listed in the Billing Build Punchlist remain open.

## 2026-08-13 — Operational Reservations intake workspace

- **VERIFIED LIVE CONTRACT / RECORDED IN REPOSITORY:** The secured intake read and daily-only pickup read/activation RPCs are recorded with their postgres ownership, security-definer empty-search-path boundary, authenticated/service-role grants, active-user/AAL2/permission enforcement, and weekly/monthly pickup fail-closed rule.
- **IMPLEMENTED IN REPOSITORY:** Reservations is an operational sidebar destination for existing-customer Quote, direct Reservation, and Walk-in creation, active Quote review, and same-event Quote conversion. It uses only the shared Supabase client and verified pricing-agreement RPCs, reloads authoritative intake after writes, and displays returned exact pricing snapshots.
- **OPEN / NOT IMPLEMENTED:** Pickup UI, VIN assignment, pricing activation from the browser, and weekly/monthly pickup Billing calculation remain open. No live Supabase change was performed.

## 2026-08-14 — Frontend TOTP MFA gate

- **IMPLEMENTED IN REPOSITORY:** After password authentication and existing application authorization, the frontend now fails closed until Supabase reports the current session at AAL2. It supports deterministic verified-TOTP challenge and first-time TOTP enrollment through the shared client.
- **PRESERVED:** AAL2 enforcement for operational Reservations/Billing RPCs remains server-side. No SQL, migration, pricing, pickup, billing, Extended Warranty, pay-type, rate, or Admin behavior changed.
- **NOT VERIFIED:** Enrollment, later-login challenge, session promotion, and protected-RPC success still require real production-browser verification. Reservations/pickup/billing end-to-end completion is not claimed.

## 2026-08-18 — Reservations model/Rental invariant checkpoint

- **VERIFIED LIVE:** Production MFA/AAL2 completed in a real browser and the authoritative Reservations intake loaded under AAL2. Admin configured the canonical active, taxable `Rental` pay type with a NULL default amount.
- **IMPLEMENTED IN REPOSITORY:** User-facing Reservations terminology is Vehicle Model. Existing `vehicle_class` response keys, pricing-agreement fields, and `p_vehicle_class` RPC arguments remain compatibility contracts. Rental requires the authoritative name-matched Rental pay type; non-Rental intake cannot use it.
- **VERIFIED LIVE / RECORDED IN REPOSITORY:** The live `create_vehicle_state` repair populates `vin_last8`, and a pricing-agreement trigger enforces both directions of the transportation/pay-type invariant. This repository migration records rather than applies those definitions.
- **NOT APPLICABLE AS SEEDS:** Controlled live vehicles `TEST-STOCK-002` (loaner) and `TEST-STOCK-003` (rental) are not fixtures or migration data.
- **OPEN / FAIL CLOSED:** Pickup/VIN frontend is next. Weekly/monthly pickup billing is not implemented and continues to fail closed.

## 2026-08-19 — Closed Billing review

- **VERIFIED LIVE BACKEND:** Late Rental pickup, production Edit Reservation, Pickup, Return/Completion, the stored-history closed preview, and the secured closed workspace filters are verified. The controlled closed Rental stored total is exactly 40 + 4 = 44.
- **IMPLEMENTED / BROWSER VERIFICATION PENDING:** The existing Billing Dashboard now includes an RPC-only, read-only Closed cases mode. A controlled closed Loaner is not available and no Loaner browser verification is claimed.

## 2026-08-19 — Verified Return/Complete final amount reconciliation

- Closed-review inspection found that Return/Complete could close an uncheckpointed multi-day parent with stale stored money. The verified live completion definition now persists the authoritative return-time preview subtotal/tax and reconciles its tax child before the established return/close sequence.
- Read-only verification on active TE `a5757d9d-8234-40bf-86e3-9d02d70e28dc` / line `db1c4f05-7c38-40a1-a0ae-13d463bfae95` compared the `$400 + $40` stored checkpoint with the same-line 19-day preview of `$760 + $76 = $836`.
- Live order and metadata are verified. Production multi-day Return mutation/browser verification remains pending after deployment; Closed Cases browser verification remains pending. The controlled closed Rental `$40 + $4 = $44` is verified; no closed Loaner browser verification has occurred.

## 2026-08-20 — Phase 8 authoritative Extension reconciliation

- **VERIFIED LIVE / RECONCILED:** live authoritative Extension definitions are patched and verified. Repository SQL preserves the post-PR34 closed stored-money behavior while applying the shared-boundary day rule only to Extension current/segment calculations.
- **IMPLEMENTED:** the existing Extension engine and Billing preview are reused; no second calculator or preview RPC was added. Billing case detail now provides backend-only preview and confirmation after a real Mark billed through checkpoint.
- **NOT VERIFIED / STILL PENDING:** runtime persistence of an Extension. A controlled SQL `DO` workflow reported success, but live inspection afterward found no new reservation, pricing agreement, billing line, or audit rows, so it is not runtime proof.
- **NEXT:** verify the deployed production-browser Reservation → Pickup → Mark billed through → Extension flow and read back the persisted records.

### 2026-08-20 — Phase 8 Extension production proof and UX correction

- **VERIFIED PRODUCTION:** The first production Extension confirmation rolled back cleanly because the note helper referenced stale `transportation_event_notes.old_expected_return_at` / `new_expected_return_at` columns. The live helper was corrected to use `old_estimated_return` / `new_estimated_return`, after which the production Extension succeeded.
- **VERIFIED PRODUCTION:** The original Billing segment closed with `$40 + $4` tax, and the Extension recorded `$80 + $8` tax. The AAL2 preview returned an accumulated `$120 + $12 = $132`; the shared boundary was verified without double-counting.
- **IMPLEMENTED IN REPOSITORY / NOT YET BROWSER-VERIFIED:** Billing navigation persistence and the staff-facing Extension UX cleanup are implemented, but browser verification remains pending deployment.
- **NOT VERIFIED / STILL PENDING:** Repeated-Extension rejection and a subsequent successful repeated Extension remain pending. Phase 8 Extension is **not complete**.

### 2026-08-20 — Phase 8 repeated-Extension contract-day anchor follow-up

- **VERIFIED PRODUCTION PASS:** The first repeated Extension rejected before Tekion Billing advanced. Mark Tekion updated at `2026-08-20T19:43:00Z` correctly persisted the point-in-time zero-day, `$0/$0` Extension checkpoint and reconciled away the zero-tax child.
- **IMPLEMENTED LOCALLY / NOT DEPLOYED OR BROWSER-VERIFIED:** Production testing exposed the three segment-relative Extension contract-day branches as the defect, not the Tekion checkpoint. The follow-up preserves the Reservation's scheduled-start Billing anchor across mid-day checkpoints.
- **NOT VERIFIED / STILL PENDING:** Successful repeated Extension after the correction remains pending deployment and production verification. Phase 8 Extension remains **not complete**.

## 2026-08-21 — Rental Billing correction — deployed and live-verified

- **VERIFIED LIVE / RECORDED:** PR #39 merged at `5aca4682368bc8d6945bd33f49d139a374ff0bc1`; Supabase migration `20260821185156 correct_rental_payment_and_extension_workflow` is applied. Original Rental charging, durable per-line external Tekion Rental Sale payment state, active-only unpaid Rental Warning behavior, future-start Extension preview, and existing Extension-chain reuse are live.
- **VERIFIED LIVE / READ-ONLY:** The current active Rental has three parent billing lines totaling `$160 + $16 tax = $176`; all three are Not Paid, including a `$0/$0` Extension. `get_rental_payment_state` returns the same stored totals and line statuses under authenticated AAL2.
- **VERIFIED LIVE / READ-ONLY:** One active Rental with unpaid parent lines produces exactly one unpaid-Rental Warning. Warning membership, Balance Due, and vehicle ID match authoritative billing data. A one-day Rental Extension preview returns `$40 + $4 tax = $44`, exactly matching the delta between authoritative Billing previews. The future-start guard clamps an earlier preview to the current Extension start and returns `$0/$0`.
- **VERIFIED SECURITY FOLLOW-UP:** PR #40 merged at `d4485f2796c3229bc34f7fcabc36b54c6ad985f4`; Supabase migration `20260821185849 secure_warning_center_counts` restricts the existing `get_warning_center_counts_state()` helper to `service_role` only. Its function body, owner, `SECURITY DEFINER`, and empty-search-path contract are preserved, and the specific anonymous SECURITY DEFINER advisor finding is cleared.
- **NOT MUTATION-VERIFIED IN THIS CHECKPOINT:** No production Rental payment line was marked Paid solely for testing. Browser payment-write interaction remains to be verified when a real Tekion Rental Sale should be recorded.
- **DEFERRED:** SO number and mass/bulk Loaner billed-through remain deferred. No bulk Loaner engine is claimed.

## 2026-08-21 — Rental / Loaner Pickup reconciliation

**IMPLEMENTED / NOT YET DEPLOYED OR PRODUCTION-VERIFIED:** Pickup now preserves two distinct workflows while reusing the existing continuity, pricing-agreement, Billing, tax, Rental payment, and Loaner billed-through engines.

- **Rental:** Quote / Reservation / Walk-in → Rental pickup → reserved-through Rental charge → external Tekion Rental Sale Paid / Not Paid → Rental Extensions → Return. Rental pickup remains Rental-fleet-only, persists the original charge and synchronized tax through expected return, and returns authoritative Rental payment state.
- **Loaner:** Quote / Reservation / Walk-in → Loaner pickup with required RO → initial/open Loaner Billing → Tekion Mark billed through progression → warranty/pay-type segmentation as applicable → Return. Loaner pickup uses the scheduled Billing start, previews at current/effective time, and does not invoke or display Rental payment state.
- **One-way fleet rule:** a Loaner-fleet vehicle cannot serve a Rental; a Rental-fleet vehicle may serve a Loaner as a fallback, with native Loaner candidates ordered first.
- **Assignment boundary:** `public.start_reservation_vehicle_use_state` rejects a null/blank Loaner RO before `public.start_vehicle_use_state` can begin continuity. Rental has no RO requirement.
- **Still NOT IMPLEMENTED:** Fleet Board click integration, Fleet Board Loaner reservation rendering, and immediate Walk-in activation remain later checkpoints. Nothing in this checkpoint claims those surfaces complete.
