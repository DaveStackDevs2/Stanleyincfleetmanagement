# Decisions

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

## 2026-07-28 — Use a protected calendar projection and mutation boundary

**Decision:** Add dedicated calendar event/type/color objects and expose them through visible-range and permission-protected RPCs. Revoke direct authenticated writes and keep all field, time-range, overlap, vehicle-availability, and permission validation in the backend.

**Reason:** The calendar must remain reusable across reservation, quote, and maintenance foundations without coupling the UI to future business workflows or allowing the browser to bypass conflict rules.

**Impact:** The UI loads no more than 32 days per request and reads configured block colors from the payload. Full reservation, quote, and maintenance workflows remain intentionally deferred. The migration must be applied and tested against the connected database before production use.
