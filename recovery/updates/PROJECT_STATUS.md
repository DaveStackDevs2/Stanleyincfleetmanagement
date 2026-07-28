# Project Status

Last updated: 2026-07-28

## Current phase

Authentication foundation and centralized authorization Phase 1 are implemented in the frontend.

## Completed

- A single application-level `AuthProvider` initializes Supabase Auth session state, subscribes to auth changes, exposes the current session and user, and supports sign-out.
- Unauthenticated entry is directed to the minimal `/sign-in` experience, which uses Supabase email/password authentication.
- A read-only `AuthorizationProvider` resolves the signed-in identity to `public.app_users` by `auth_user_id`, then loads and validates the access gate, role names, and effective permission contracts.
- Application content is rendered only when the verified access-gate status is exactly `auth_access_ready`.
- Missing, malformed, mismatched, stale, inaccessible, failed, and non-ready authorization states deny access without exposing backend error details.
- Authentication loading, authorization loading, sign-in, and denied-access states have separate minimal user interfaces.
- A focused correctness review moved history updates into React effects, made authorization fail closed immediately across session changes, ensured authentication actions settle safely, and added accessible loading announcements.

## Verification

- `npm run build`: passed on 2026-07-28.
- `npm run lint`: passed on 2026-07-28.
- `git diff --check`: passed on 2026-07-28.
- `rg -n 'createClient\(' frontend/src`: found one shared client creation.
- Live authentication and authorization behavior was not browser-tested because no test account or verified live-database connection was used in this task.

## Known issue

The repository migration snapshot grants `get_user_auth_access_gate_state` and `v_user_effective_permissions` only to `service_role`. This is not proof of live-database state, but an authenticated browser may be unable to access these required contracts. The frontend intentionally denies access if that occurs. Required authenticated-role grants and policies remain unresolved live-database work; no database objects or credentials were changed.

## Next recommended task

Verify the authentication and authorization contracts in the connected Supabase project with an approved test user, then separately review the authenticated-role grants and row-level security policies through an authorized database change process.
