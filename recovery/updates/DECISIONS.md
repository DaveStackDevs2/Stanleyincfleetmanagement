## 2026-08-24 — Hand immediate Walk-ins into existing Pickup

**Decision:** Continue creating Walk-ins exclusively through `create_walk_in_with_pricing_agreement_state`, then use its validated authoritative `reservation_id` only as selection context for the existing Pickup workspace after Pickup reloads `get_pricing_agreement_pickup_state`. Never fabricate a Pickup item, choose a VIN, or activate Pickup from intake. Loaner Walk-ins require a nonblank RO as friendly preflight, and weekly/monthly Walk-ins fail before creation with the existing Pickup-not-implemented message.

**Verified deployment context:** PR #42 is live from merged `main` SHA `627f6a61c2ef6e062c3978fd9be0124a915a7ad7` with Supabase migration `20260824180402 reconcile_rental_loaner_pickup_workflows`. Read-only production verification passed. There were zero legitimate pickup-ready records, so browser mutation verification was intentionally not manufactured.

## 2026-08-18 — Preserve pre-check-in Reservation identities

**Decision:** Pre-check-in Reservation edits preserve the existing Reservation, Transportation Event, and pricing agreement. Scheduled-return mirroring delegates to the existing expected-return engine; only scheduled start/return, service advisor, RO number, and notes are editable.

**Impact:** Editing does not assign a VIN or start continuity, a contract period, pricing, or billing. Model/workflow/pay/rate changes and the future penalty-free cutoff remain deferred.

# Decisions

## 2026-08-18 — Separate Reservation schedule, physical handoff, and Billing eligibility

**Decision:** Reservation creation reserves capacity and authoritative schedule/pricing snapshots only. Check-in / Pickup starts physical continuity at actual handoff, while the existing Billing engine starts billing and pricing at the Reservation scheduled start. Late arrival does not automatically change scheduled start or return.

**Decision:** Exclude normal pre-check-in Reservations from Billing by reusing the existing Transportation Event operational payload; skip only when both current continuity and current billing lines are empty. Do not invent a raw billing-table eligibility rule.

**Impact:** Pre-check-in Reservation editing is the next dedicated checkpoint. No verified browser-safe general edit RPC exists, so this work adds no direct table update. Future change-without-penalty rules remain TBD.


## 2026-08-18 — Enforce fleet compatibility at Pickup

**Decision:** Keep model-level Reservations and assign VIN only through the authoritative Pickup RPC. Candidate discovery matches normalized fleet type as well as model, while the invoker low-level start boundary independently rejects a reservation/vehicle fleet-type mismatch before continuity starts.

**Reason:** Production overlap testing after PR #31 proved model matching alone could offer Loaner vehicles for Rental pickup. Defense at both read and write boundaries prevents stale or bypassed candidate state from crossing fleet types.

**Impact:** Browser code receives candidates and activation/Billing results only from authoritative RPC payloads and performs no billing arithmetic. `vehicle_class` remains a backend compatibility identifier, with Vehicle model as product wording. Weekly/monthly activation remains fail-closed; “Now” and the Admin taxable-checkbox cosmetic adjustment remain deferred.


## 2026-07-29 — Fleet Board data and palette boundaries

**Decision:** Load all operational Fleet Board data through `get_fleet_board_state(timestamptz, timestamptz)` so authenticated access and visible-period filtering remain backend-owned. Store pay-type colors in the existing Admin settings system, protect writes with `user_admin.manage`, and render only valid six-digit hex values with one neutral fallback. The Admin palette editor is the next task.

## 2026-07-29 — Replace the abandoned calendar model with a read-only Fleet Board

**Decision:** Remove the branch-only Vehicle Calendar implementation and migration, then place the Fleet Board behind the existing authenticated application boundary without a new feature permission.

**Reason:** The repository proves that vehicles, reservations, rental capacity, transportation events, assignments, billing state, and conflicts already provide the operational source of truth. A separate calendar-event model and invented permission set would duplicate that state.

**Impact:** The Fleet Board foundation visualizes existing backend state only. Workflow handoffs and any least-privileged feature permission remain intentionally unresolved until existing backend contracts or an approved database change prove the correct enforcement boundary.

## 2026-07-28 — Calculate access from one role and explicit user overrides

**Decision:** Constrain each user to one role and calculate effective permissions as role defaults plus individual grants minus individual denies. A deny wins when the same permission is inherited or granted.

**Reason:** This directly implements the Phase 2 permission model while keeping authorization decisions based on permission keys rather than role-name checks.

**Impact:** Existing duplicate role assignments are deterministically reduced to the newest assignment when the migration is applied. Future role assignment replaces the current role. Overrides remain independent of role changes and are visible in the administration payload.

## 2026-07-28 — Protect user administration behind a backend permission check

**Decision:** Introduce the minimal `user_admin.manage` permission, grant it by default to the Dev Admin and Admin system roles, and require it inside security-definer management RPCs. The frontend uses that effective permission only for discoverability; the backend remains authoritative.

**Reason:** Role-name checks would violate centralized permission-based authorization, while exposing direct table writes would weaken the security boundary.

**Impact:** Authenticated users without the effective permission cannot load or mutate administration state even if they manually invoke an RPC. The connected database must receive the migration before the UI can operate.

## 2026-07-28 — Centralize application entry authorization

**Decision:** Place a read-only `AuthorizationProvider` beneath the shared `AuthProvider`, and allow application entry only when a validated gate payload reports exactly `auth_access_ready` for the resolved application user and current Supabase Auth identity.

**Reason:** Authentication proves the browser session identity but does not establish application access. Centralizing the backend contract checks gives the application one fail-closed entry decision without inventing frontend roles, permission keys, or feature-level rules.

**Impact:** Every authenticated session must resolve a matching `app_users` record and successfully return structurally valid, identity-matched gate, role, and permission payloads. Any unavailable or invalid dependency produces a sanitized denied state.

**Alternatives rejected:**

- A service-role browser client was rejected because it would expose privileged credentials and bypass the intended security boundary.
- A second Supabase client was rejected because the repository requires one shared client.
- Client-defined role or permission rules were rejected because Phase 1 does not authorize inventing business rules.
- A routing dependency was rejected because minimal pathname/history handling is sufficient for the single sign-in path.

## 2026-07-28 — Treat repository-only grant discrepancy as unresolved

**Decision:** Do not change database files as part of the frontend authentication task. Document the snapshot discrepancy and fail closed if the browser cannot read the contracts.

**Reason:** The snapshot is not verified live-database state, and database changes are explicitly outside this task. Frontend access must not be obtained by weakening security.

## 2026-08-12 — Preserve one Transportation Event and pricing agreement

**VERIFIED:** Quotes, direct Reservations, Walk-ins, and Loaners begin one Transportation Event. Quote conversion creates its Reservation in that same event and attaches the existing pricing agreement. Pickup remains the boundary for VIN assignment, timers, pricing activation, and committed billing.

## 2026-08-14 — Require frontend AAL2 application entry

**Decision:** After the existing password authentication and application-authorization gates pass, require the shared Supabase client to confirm AAL2 before rendering the operational application. Use TOTP enrollment when no verified TOTP factor exists and challenge the first verified TOTP factor in stable creation order otherwise.

**Reason:** Existing protected Reservations and Billing RPCs correctly require an AAL2 JWT, but the frontend previously offered no way for an authorized password-authenticated user to promote an AAL1 session.

**Impact:** The application fails closed while MFA state is unknown or unavailable, and successful verification is followed by session refresh and an explicit assurance-level re-check. Server-side authorization and AAL2 checks remain unchanged and authoritative.

## 2026-08-18 — Treat Vehicle Model and Rental pay type as intake invariants

**Decision:** The Reservations user-facing concept is Vehicle Model. Existing database columns, RPC arguments, and JSON keys named `vehicle_class` remain compatibility identifiers for now and continue carrying model values.

**Decision:** Rental transportation must use the single active, Admin-managed pay type whose trimmed name is `Rental` case-insensitively. The Rental pay type cannot be used for non-Rental intake. The frontend fails closed and the pricing-agreement trigger remains the final authority in both directions; no UUID or price is hardcoded.

**Verified context and impact:** Production MFA/AAL2 and authoritative Reservations intake were exercised successfully in a real browser. Admin configured Rental with a NULL default amount. Live Supabase already has the `create_vehicle_state` `vin_last8` repair and invariant trigger; the repository migration only records them. Controlled live vehicles `TEST-STOCK-002` and `TEST-STOCK-003` are not seeds. Pickup/VIN remains the next frontend checkpoint, and weekly/monthly pickup billing remains unimplemented and fail-closed.

## 2026-08-19 — Closed Billing historical boundary

**Decision:** Closed-case filtering uses `transportation_events.closed_at`. `p_closed_from` is inclusive and `p_closed_before` is exclusive. Historical money always comes from stored billing-line and tax snapshots, never current rate or tax configuration. The browser only supplies query boundaries and renders returned exact strings; closed review is read-only Tekion reconciliation, not cashiering.

## 2026-08-21 — Rental Billing correction
**IMPLEMENTED / NOT DEPLOYED / NOT LIVE-VERIFIED:** Rental original and Extension charges independently record external Tekion Rental Sale Paid in Full state. Pickup remains allowed unpaid and active unpaid Rentals appear once in the existing Warning category. Rental Extension is independent from Loaner billed-through, uses separate same-vehicle lines, and preserves Days in Vehicle. SO number is deferred; mass/bulk Loaner billed-through remains separate and planned because no verified live engine exists.
- **CORRECTED LOCALLY / NOT DEPLOYED:** The pre-push audit correction preserves the existing Extension engine chain and authoritative tax/preview/continuity/Warning engines while adding the required Rental payment presentation and Loaner two-step preview. Production application and browser verification remain pending.

## 2026-08-21 — Rental / Loaner Pickup reconciliation

**IMPLEMENTED / NOT YET DEPLOYED OR PRODUCTION-VERIFIED:** Pickup now preserves two distinct workflows while reusing the existing continuity, pricing-agreement, Billing, tax, Rental payment, and Loaner billed-through engines.

- **Rental:** Quote / Reservation / Walk-in → Rental pickup → reserved-through Rental charge → external Tekion Rental Sale Paid / Not Paid → Rental Extensions → Return. Rental pickup remains Rental-fleet-only, persists the original charge and synchronized tax through expected return, and returns authoritative Rental payment state.
- **Loaner:** Quote / Reservation / Walk-in → Loaner pickup with required RO → initial/open Loaner Billing → Tekion Mark billed through progression → warranty/pay-type segmentation as applicable → Return. Loaner pickup uses the scheduled Billing start, previews at current/effective time, and does not invoke or display Rental payment state.
- **One-way fleet rule:** a Loaner-fleet vehicle cannot serve a Rental; a Rental-fleet vehicle may serve a Loaner as a fallback, with native Loaner candidates ordered first.
- **Assignment boundary:** `public.start_reservation_vehicle_use_state` rejects a null/blank Loaner RO before `public.start_vehicle_use_state` can begin continuity. Rental has no RO requirement.
- **Still NOT IMPLEMENTED:** Fleet Board click integration, Fleet Board Loaner reservation rendering, and immediate Walk-in activation remain later checkpoints. Nothing in this checkpoint claims those surfaces complete.
