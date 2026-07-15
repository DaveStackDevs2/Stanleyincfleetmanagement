# Production Security Follow-Up

Temporary development access was granted so the unauthenticated frontend could read:

```sql
grant select on public.v_admin_vehicle_master_state to anon;
```

Before production:

- Enable Supabase authentication.
- Grant SELECT only to the required authenticated roles.
- Remove anonymous access:

```sql
revoke select on public.v_admin_vehicle_master_state from anon;
```

Do not ship to production with the anonymous SELECT grant still enabled.