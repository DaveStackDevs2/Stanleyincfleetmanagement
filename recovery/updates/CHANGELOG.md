# Changelog

## 2026-07-28

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
