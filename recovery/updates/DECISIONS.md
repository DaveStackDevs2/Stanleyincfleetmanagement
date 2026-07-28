# Decisions

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
