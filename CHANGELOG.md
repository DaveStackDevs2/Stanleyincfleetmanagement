
## 2026-08-18 — Pre-check-in Reservation editing

- **VERIFIED LIVE / RECORDED:** The browser-safe five-field edit backend preserves the existing Reservation, Transportation Event, and pricing agreement, and delegates the Transportation Event schedule mirror to the existing expected-return engine.
- **VERIFIED LIVE:** A controlled scheduled start, scheduled return, service advisor, RO number, and notes edit produced exactly five matching audit rows without VIN, continuity, contract period, pricing, billing, snapshot, or identity changes.
- **IMPLEMENTED / NOT YET VERIFIED IN PRODUCTION BROWSER:** Reservations now includes an RPC-only Edit Reservation workspace. Check-in / Pickup browser activation also remains **NOT YET VERIFIED**.
- **TBD / DEFERRED:** The future penalty-free edit cutoff remains TBD. Model, workflow, pay-type, and rate-plan edits remain deferred pending authoritative pricing and availability policy.

# Changelog

## 2026-08-18 — Check-in / Pickup scheduled-start billing reconciliation

- **VERIFIED live / RECORDED:** Check-in starts physical continuity at actual handoff but delegates initial billing to the established engine with no start override, so billing and `pricing_started_at` use the Reservation scheduled start. Late arrival does not slide scheduled start or scheduled return.
- **VERIFIED live / RECORDED HARDENING:** Authoritative pickup candidates exclude retired vehicles. Activation locks the selected non-retired vehicle and immediately revalidates `available` before assignment, continuity, or billing writes, protecting activation from stale candidate state.
- **VERIFIED live / RECORDED:** Billing workspace eligibility reuses the Transportation Event operational payload and excludes normal pre-check-in Reservations only when both current continuity and current billing lines are empty. Reservation creation itself does not start billing.
- **REQUIRED NEXT / NOT IMPLEMENTED:** pre-check-in Reservation editing must support scheduled start, expected return, service advisor, RO number, and notes; model, workflow type, pay type, and rate-plan changes require authoritative pricing/availability logic. No verified browser-safe general edit RPC exists, and the future penalty-free cutoff is TBD. Weekly/monthly pickup billing and the “Now” button remain deferred. Production browser Check-in activation is **NOT VERIFIED**.


## 2026-08-18 — Reservations Pickup / VIN activation

- **VERIFIED production context:** PR #31 is merged on `main` at `a910472a6b66e59c1959c0c0e9502b9da1d366cf`; Rental intake was browser-tested and created one Reservation, pricing agreement, and Transportation Event with no pre-pickup VIN, continuity, or billing.
- **VERIFIED live repair / RECORDED HERE:** overlap testing found same-model Loaner vehicles in Rental candidates. The low-level vehicle-start boundary now rejects normalized fleet-type mismatches, and the candidate view filters by model plus fleet type. The negative Rental-to-Loaner test wrote no continuity or billing; the controlled candidate list now contains only `TEST-STOCK-003` (an operational controlled record, not seed data).
- **IMPLEMENTED / NOT YET BROWSER-VERIFIED:** Reservations now has authoritative Pickup/VIN activation and renders the returned Billing preview without frontend arithmetic. Weekly/monthly pickup remains fail-closed; production browser activation is required after merge. The datetime “Now” button and Admin taxable-checkbox alignment remain deferred. `vehicle_class` remains a backend compatibility key displayed as “Vehicle model.”


## Unreleased

### 2026-08-14 — Required TOTP MFA gate

- Added a fail-closed auth-level TOTP enrollment and verification gate after existing application authorization, including QR/manual setup, sanitized retry states, sign out, session refresh, and an explicit AAL2 re-check before application entry.
- Continued using the shared Supabase client and preserved all server-side AAL2 checks. No backend, migration, pricing, pickup, billing, Extended Warranty, pay-type, rate, or Admin changes were made.
- This closes the frontend authentication blocker found during production Reservations review, but real production-browser MFA and protected-workflow verification remain open; Reservations/pickup/billing end-to-end is not complete.

### 2026-08-13 — Operational Reservations workspace

- Recorded the verified-live pricing-agreement intake and pickup contracts in one data-free, idempotent migration; daily pickup remains the only supported activation plan and the frontend does not call pickup.
- Wired the existing Reservations navigation to an operational RPC-only workspace for existing-customer Quote, direct Reservation, and Walk-in creation, active Quote listing, and same-Transportation-Event conversion.
- Added strict pre-submit validation, configured-plan gating, exact snapshot display without frontend arithmetic, sanitized error categories, authoritative post-write reloads, and focused result screens.
- Live Supabase was not changed. Pickup UI and weekly/monthly pickup calculation remain open.

### 2026-07-30 — Phase 1 operational RPC security checkpoint

- Added an idempotent migration recording the live-verified security definitions and grants for extension, completion/return, and cancellation operational RPCs.
- Recorded browser denial and `service_role` execution for their internal helpers.
- Documented optional return-mileage preservation and the remaining Phase 1 contracts.
- Production SQL was already applied and verified manually; this repository checkpoint did not apply SQL to live Supabase.
- Corrected the repository checkpoint to match the verified live grants: top-level operational wrappers are executable by `authenticated` only (plus owner `postgres`), while internal helpers retain `service_role` execution.
- Recorded, without implementation, that late-fee amounts sourced from `public.late_fee_rules.fee_amount` must eventually be editable in Admin Rates, Fees & Billing Rules. Live placeholders remain `grace_period` = null, `fixed_fee` = 0, and `full_day_trigger` = 0; configuration does not itself charge a fee, and fees remain discretionary, staff-applied, waivable/reversible, and fully auditable.

## 2026-07-31

- Added one idempotent Phase 1 migration introducing the stable authenticated/AAL2 start/assign/bill browser RPC, optional checkout mileage, exact created-row actor stamping, and final-payload loading after those writes.
- Added a preconditioned unique partial index for one open vehicle event per vehicle; restricted the legacy truncated wrapper, internal mutation chain, and direct mutations on the seven workflow tables while retaining service-role helper/table access.
- Updated `case.create_start_bill_and_load` metadata to the exact new function name. No frontend or Edge caller exists, the live four-table baseline was empty, no production SQL was applied, and authoritative amount/tax calculation remains unresolved.
- Recorded the later manual deployment of PR #11 by Dave and the successful completion of all six live verification checks; Codex did not perform that deployment.
- Added one pending, idempotent database migration that repairs the missing `restart_same_vehicle_after_gap` helper by delegating to `start_vehicle_use_state`, secures the existing continuation and reassignment wrappers with authenticated active-user/AAL2 enforcement and exact actor stamping, and restricts their mutating helper chain and dependency tables.
- Preserved the existing service-action names and operational behavior: no billing segmentation, `vehicle_swaps` insert, frontend, or Edge Function caller was added. The seven relevant live operational tables were empty, and no live SQL was applied by this task.
- Broad Phase 1/Phase 10 remain incomplete pending manual live application and verification. Amount/tax calculation remains unresolved; Phase 2 pay-type administration is next after Phase 1; late fees remain disabled and deferred with future Admin-editable amounts that must not auto-charge.

## 2026-08-11 — Verified-live pay-type-independent rental rate cards

- Added one idempotent, data-free migration recording the verified live nullable legacy pay-type link, optional weekly/monthly rates, normalized vehicle-class current-card uniqueness, and five secured rate-card RPCs while preserving legacy functions, FK/index, data, and billing snapshots.
- Updated only Rental Rates administration to use the new shared-client RPCs, remove Pay Type, validate complete card payloads, and present focused Add/Edit for daily, optional weekly, and optional monthly rates with authoritative reloads and no Delete action.
- Updated the Billing punchlist to distinguish verified engines from the approved but **OPEN / NOT IMPLEMENTED** Quote/Reservation/Walk-in pricing-agreement and downstream block/discount/insurance/ledger work. Live Supabase was not changed by this repository implementation.

## 2026-08-12 — Shared rental-pricing-agreement foundation

- **VERIFIED LIVE CONTRACT / IMPLEMENTED IN REPOSITORY:** The data-free migration records the shared pricing agreement, one-Transportation-Event Quote/direct Reservation/Walk-in architecture, same-event Quote conversion, secured Dev/AAL2 RPC boundary, billing compatibility snapshots, monthly-requires-weekly prerequisite, central audit trail, and protected-table privilege corrections.
- **NOT APPLICABLE:** No live Supabase change or production seed was performed; no pickup, VIN, timer, contract-period, pricing activation, calculation, discount, insurance, payment, cashiering, allocation, or billing-line workflow was started.
- **OPEN / NOT IMPLEMENTED:** Frontend Quote/Reservation/Walk-in workflows and every post-pickup pricing and payment capability listed in the Billing Build Punchlist remain open.

### 2026-08-18 — Reservations vehicle-model and Rental pay-type checkpoint

- **VERIFIED LIVE:** Production TOTP MFA/AAL2 was successfully exercised in a real browser, and Reservations authoritative intake loaded successfully under AAL2. The canonical Admin-managed `Rental` pay type is active, taxable, and configured with a NULL default amount.
- **IMPLEMENTED IN REPOSITORY:** Reservations now presents the user-facing concept as Vehicle Model while retaining backend `vehicle_class` compatibility identifiers. Rental intake derives and exclusively selects the authoritative active `Rental` pay type by name; Loaner intake excludes it and all mismatches fail closed.
- **VERIFIED LIVE / RECORDED ONLY:** Live Supabase already contains the `create_vehicle_state` `vin_last8` repair and the bidirectional Rental-workflow/pay-type pricing-agreement trigger. The new idempotent, data-free migration records that state and was not applied to live Supabase here.
- **NOT REPOSITORY SEED DATA:** `TEST-STOCK-002` (loaner) and `TEST-STOCK-003` (rental) remain controlled live verification vehicles only.
- **OPEN / NOT IMPLEMENTED:** Pickup/VIN frontend is the next checkpoint. Weekly/monthly pickup billing remains unimplemented and must fail closed.

## 2026-08-19 — Closed Billing review

- Reconciled the verified-live stored-snapshot branch in the existing Billing preview and the secured four-argument closed workspace wrapper without changing data or active Billing calculation behavior.
- Added bounded All/Rental/Loaner and closed-date filtering plus read-only historical cards and complete stored segment detail to the existing Billing Dashboard. Production browser verification remains pending.

### 2026-08-19 — Return/Complete final Billing persistence

- Reconciled the verified live completion engine fix discovered during closed-review inspection: authoritative return-time preview subtotal/tax are persisted to the existing parent and its tax child before the normal return and close helpers run.
- Recorded read-only verification for active multi-day TE `a5757d9d-8234-40bf-86e3-9d02d70e28dc` / line `db1c4f05-7c38-40a1-a0ae-13d463bfae95`: stored `$400 + $40`; same-line 19-contract-day preview `$760 + $76 = $836`.
- The live function definition, order, owner, invoker security, null `proconfig`, and postgres/service-role-only ACL were verified. No production multi-day Return mutation/browser test has yet been completed. Closed Cases browser verification remains pending; controlled closed Rental `$40 + $4 = $44` remains verified, and closed Loaner browser verification has not occurred.

## 2026-08-20 — Phase 8 Extensions

- Reconciled the verified-live Extension boundary behavior into the existing authoritative Billing preview and compatibility wrapper without adding an engine, calculator, or preview RPC.
- Added the Billing case-detail Preview Extension / Confirm Extension flow using backend-returned money only, duplicate-submit protection, sanitized errors, and authoritative reload.
- Recorded runtime persisted Extension as still pending: a controlled SQL `DO` reported success, but later live inspection found no new reservation, pricing agreement, billing line, or audit rows. The next proof is the deployed production-browser Reservation → Pickup → Mark billed through → Extension flow.
