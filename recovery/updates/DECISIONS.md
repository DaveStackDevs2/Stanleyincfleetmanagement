# Decisions

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
