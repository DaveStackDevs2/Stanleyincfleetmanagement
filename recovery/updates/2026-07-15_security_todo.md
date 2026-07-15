# Production Security Follow-Up

Temporary development access was granted so the unauthenticated frontend could read the Fleet Administration data.

## Temporary development grants

```sql
grant select on public.v_admin_vehicle_master_state to anon;
grant select on public.vehicles to anon;
grant select on public.tags to anon;
```

These grants are