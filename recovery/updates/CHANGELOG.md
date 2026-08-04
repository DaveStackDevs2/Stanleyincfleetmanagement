# Changelog

## 2026-08-04 — Billing Phase 2 pay-type editing implementation

- Recorded the verified live ownership, security-definer/search-path configuration, authorization path, and restricted execution grants for `update_admin_pay_type_rule_state(uuid, boolean, numeric, integer, text)` in an idempotent repository migration.
- Added editing for existing enabled and disabled pay types to Rates, Fees & Billing Rules, limited to description, taxable status, nullable default daily amount, and sort order; pay-type identity remains read-only.
- Added strict mutation-response validation, authoritative rules-and-colors reload, sanitized success/failure states, uncertain-result guidance, cancellation, and duplicate-submission prevention.
- Added focused repository-native contract tests. Real-session/browser verification, merge, deployment, and the overall Phase 2 exit remain **NOT VERIFIED**.

## 2026-08-04 — Phase 1 live deployment reconciliation

- Verified that GitHub `main` includes the start/assign/bill, continuation/reassignment, and PL/pgSQL terminator checkpoint merges from PRs #11–#13.
- Verified that live Supabase contains the six secured top-level case-write RPCs and the expected browser-role, internal-helper, service-role, direct-table, unique-index, and same-vehicle restart boundaries.
- Removed stale documentation claiming the continuation/reassignment and start/assign/bill migrations were still waiting for live application.
- Kept broad Phase 1 open for real-session anonymous, unauthorized, authorized, RLS, and browser workflow tests.
- Recorded Phase 2 pay-type editing as the next implementation step and preserved the unresolved Ontrac import-path verification.
- Changed documentation only; no SQL, production data, frontend code, authorization behavior, or billing behavior changed.

## 2026-07-30 — Fleet Board Day timeline

- Added a horizontally scrollable Day timeline for the fixed 7:00 AM–7:00 PM operating window, with twelve hourly intervals, a final 7:00 PM boundary, and sticky hourly and VIN headers.
- Positioned and clamped assignments from actual operational timestamps, added deterministic overlap lanes, and expanded VIN rows when assignments overlap.
- Added adaptive pay type, transportation-event status, source type, and time details while preserving Admin-configured colors, neutral fallback colors, and conflict indicators.
- Added a once-per-minute current-time marker shown only for today's displayed operating window, and preserved Reservation Capacity and Week view behavior.
- Made no database, authorization, Supabase configuration, or workflow changes.

## 2026-07-29 — Admin pay-type management

- Connected Rates, Fees & Billing Rules to the live Admin pay-type RPC contracts.
- Added strict payload validation, pay-type creation, disable/reactivate actions, and authoritative reloads after successful mutations.
- Added explicit Fleet Board palette editing for active pay types with native color inputs, six-digit hex validation, and one neutral fallback pair.
- Added the idempotent repository migration for the three already-live Admin pay-type functions and their verified execution grants.
- Recorded the verified unique normalized pay-type index so case-insensitive uniqueness is enforced atomically.
- Added an accessible inline confirmation after Fleet Board colors save and reload successfully.

## 2026-07-29 — Fleet Board live read contracts

- Replaced Fleet Board table/view reads with the authenticated, visible-period `get_fleet_board_state` RPC.
- Added the idempotent repository migration for the already-live Fleet Board state and pay-type color functions, grants, Admin setting, and `user_admin.manage` mapping.
- Applied validated saved pay-type colors with a single neutral fallback; the Admin palette UI remains future work.

## 2026-07-29 — Fleet Board foundation

- Removed the Vehicle Calendar navigation, page state, component imports, calendar components, calendar-only CSS, and calendar permission references.
- Removed the unmerged branch-only calendar-foundation migration and its separate scheduling model.
- Added a read-only Fleet Board that visualizes existing vehicles, model-level reservations, rental capacity, and unified transportation-event operational state.
- Preserved the authenticated application boundary and did not invent a Fleet Board permission.
- Added no database objects, migrations, hardcoded production values, or frontend mutation rules.
- Corrected date navigation to use local calendar arithmetic and ignore invalid date-picker values.
- Excluded only the verified `cancelled` reservation status from displayed capacity and stopped treating resolved conflicts as active.
- Documented missing authenticated reads and a missing backend-supported assignment range boundary as backend blockers rather than adding unsafe frontend workarounds.

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
