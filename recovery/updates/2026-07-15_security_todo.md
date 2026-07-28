# Production Security Follow-Up

Temporary development access was granted so the unauthenticated frontend could read the Fleet Administration data.

## Temporary development grants

```sql
grant select on public.v_admin_vehicle_master_state to anon;
grant select on public.vehicles to anon;
grant select on public.tags to anon;
```

These grants are temporary and must be reviewed and removed before production use once authenticated access is available.

## 2026-07-28 authorization follow-up

Authentication and centralized, fail-closed authorization are now implemented in the frontend. The frontend does not use a service-role key and continues to use exactly one shared Supabase client.

The repository migration snapshot grants the following required Phase 1 authorization contracts only to `service_role`:

- `public.get_user_auth_access_gate_state(uuid, text, timestamptz)`
- `public.v_user_effective_permissions`

The snapshot grants `public.get_user_role_names_state(uuid)` to `authenticated`, and contains an `authenticated` table grant for `public.app_users`. Repository grants do not verify the connected live database or confirm effective row-level security behavior.

Before production use, an authorized database review must verify and, if necessary, provide the least-privileged `authenticated` access and policies required for a signed-in user to:

1. resolve only the appropriate `app_users` identity through `auth_user_id`;
2. invoke the access-gate and role-name contracts for the appropriate application user; and
3. read only the appropriate effective-permission rows.

Until that work is verified, an inaccessible contract safely results in denied application entry. Do not work around this by exposing a service-role key or adding a privileged browser client.
