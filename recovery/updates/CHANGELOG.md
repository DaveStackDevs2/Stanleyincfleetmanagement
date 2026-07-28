# Changelog

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

## 2026-07-28 — Phase 3 Vehicle Calendar Foundation

- Added a permission-gated vehicle calendar as the primary fleet workspace with Rental, Loaner, and combined collapsible sections.
- Added day and seven-day week timelines, monthly navigation, frozen resource/date headers, current-time marker, visible-range loading, persisted controls, filters, dark mode, event details, hover summaries, confirmed drag moves, and vehicle action placeholders.
- Added reusable reservation, quote, and maintenance event types and backend-configurable event/pay colors.
- Added protected calendar read/create/update/delete/color RPC contracts with backend range, field, overlap, availability, and permission validation.
- Repository build, lint, and diff checks were run; live migration and authenticated browser behavior remain unverified.

### Phase 3 final defect review

- Removed role-name-based calendar default assignment in favor of inheriting defaults from the existing `user_admin.manage` permission relationship.
- Made calendar objects and seed operations safely repeatable where practical.
- Closed concurrent overlap and edit-as-create gaps with per-vehicle transaction locks and existing-event validation.
- Added audit-log records for event create/update/delete and color changes.
- Corrected day-view event positioning, 15-minute snapping and resizing, empty/error presentation, and separately permission-gated deletion.
