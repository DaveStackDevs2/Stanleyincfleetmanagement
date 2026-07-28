# Project Status

Last updated: 2026-07-28

## Current phase

Phase 2 user and role management is implemented on top of the authentication and centralized authorization foundation.

## Completed

- A single application-level `AuthProvider` initializes Supabase Auth session state, subscribes to auth changes, exposes the current session and user, and supports sign-out.
- Unauthenticated entry is directed to the minimal `/sign-in` experience, which uses Supabase email/password authentication.
- A read-only `AuthorizationProvider` resolves the signed-in identity to `public.app_users` by `auth_user_id`, then loads and validates the access gate, role names, and effective permission contracts.
- Application content is rendered only when the verified access-gate status is exactly `auth_access_ready`.
- Missing, malformed, mismatched, stale, inaccessible, failed, and non-ready authorization states deny access without exposing backend error details.
- Authentication loading, authorization loading, sign-in, and denied-access states have separate minimal user interfaces.
- A focused correctness review moved history updates into React effects, made authorization fail closed immediately across session changes, ensured authentication actions settle safely, and added accessible loading announcements.
- Seven system roles are established: Dev Admin, Admin, CTP Staff, Service Manager, Sales Management, Service Advisor, and Sales Staff.
- Every user is constrained to one role. Role defaults combine with individual grants and denies to produce effective permissions, with denies taking precedence.
- Permission-gated Users and Roles pages allow administrators to assign roles, edit role defaults, set per-user grant/deny/inherit overrides, and inspect each user's effective permissions.
- User administration reads and writes through authenticated, permission-checking RPC contracts. Backend errors are not exposed in the interface.

## Verification

- `npm run build`: passed on 2026-07-28.
- `npm run lint`: passed on 2026-07-28.
- `git diff --check`: passed on 2026-07-28.
- `rg -n 'createClient\(' frontend/src`: found one shared client creation.
- Live authentication and authorization behavior was not browser-tested because no test account or verified live-database connection was used in this task.
- `npm run build`, `npm run lint`, and `git diff --check` passed for Phase 2 on 2026-07-28.

## Known issue

The new migration has not been applied to or verified against a connected live Supabase project. Until it is applied, the Phase 2 RPC contracts and override table will not exist remotely. Existing Phase 1 access-gate grant and policy discrepancies also remain subject to live verification.

## Next recommended task

Apply the reviewed Phase 2 migration in the connected Supabase project, then browser-test role assignment and grant/deny precedence with approved Admin and non-admin test users.
