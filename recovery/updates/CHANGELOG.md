# Changelog

## 2026-07-29 — Fleet Board foundation

- Removed the Vehicle Calendar navigation, page state, component imports, calendar components, calendar-only CSS, and calendar permission references.
- Removed the unmerged branch-only calendar-foundation migration and its separate scheduling model.
- Added a read-only Fleet Board that visualizes existing vehicles, model-level reservations, rental capacity, and unified transportation-event operational state.
- Preserved the authenticated application boundary and did not invent a Fleet Board permission.
- Added no database objects, migrations, hardcoded production values, or frontend mutation rules.

## 2026-07-28

### Phase 2 — User and role management

- Added the seven required system roles and the minimal `user_admin.manage` administration permission.
- Added a single-role constraint and per-user permission overrides with `grant` and `deny` effects.
- Replaced effective-permission calculation with role defaults plus grants minus denies.
- Added permission-checking authenticated RPCs for management payloads, role assignment, user overrides, and role default permissions.
- Switched current-user permission loading to a scoped RPC rather than direct effective-permission view access.
- Added Users and Roles administration pages, permission editing, role assignment, override editing, and effective-permission inspection.
- Kept role names out of frontend authorization decisions; navigation and management access use the effective `user_admin.manage` permission.

### Phase 2 verification

- `npm run build`: passed.
- `npm run lint`: passed.
- `git diff --check`: passed.
- Live migration application and authenticated browser behavior were not verified.

### Hardened after focused review

- Moved pathname/history synchronization out of `AuthGate` render and into an effect.
- Made session initialization settle safely if `getSession()` unexpectedly rejects while preserving auth-event race protection.
- Invalidated in-flight authorization work on every session change, including same-user session refreshes, and withheld previously loaded authorization synchronously while a new session is verified.
- Ensured sign-in submission always settles and added sanitized handling for unexpected sign-in and sign-out failures.
- Added live status semantics to authentication and authorization loading messages.

### Added

- Typed Supabase Auth context, provider, and `useAuth` hook with session initialization, auth-state subscription, sign-out, and subscription cleanup.
- Minimal email/password sign-in page and `/sign-in` pathname handling without a routing dependency.
- Typed, read-only authorization context, provider, and `useAuthorization` hook.
- Fail-closed loading and validation for the application user, authentication access gate, role names, and effective permission keys.
- Central `AuthGate` with distinct authentication and authorization loading states and a sanitized denied-access screen.

### Changed

- Wrapped the existing frontend with authentication, authorization, and application-entry gates.
- Sanitized the existing fleet-load failure message so raw backend errors are not shown.
- Updated the production security follow-up with the authorization contract grant discrepancy and required live follow-up.

### Verification

- `npm run build`: passed.
- `npm run lint`: passed.
- `git diff --check`: passed.
- The frontend source contains exactly one `createClient(` occurrence in the existing shared client.

### Intentionally unresolved

- No SQL, schema, migration, function, view, grant, policy, trigger, or seed changes were made.
- Live database access for the authenticated browser role was not verified.
- MFA, password reset, feature-level permission rules, navigation restrictions, and role-management UI were not implemented.
