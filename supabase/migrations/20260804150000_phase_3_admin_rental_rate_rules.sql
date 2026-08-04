-- Billing Phase 3: admin-managed normal rental daily rates by vehicle class and pay type.
-- Records the live Supabase contract without seeding any business rates.

create table if not exists public.rental_rate_rules (
  id uuid primary key default gen_random_uuid(),
  vehicle_class text not null,
  pay_type_rule_id uuid not null references public.pay_type_rules(id) on delete restrict,
  daily_rate numeric(12,2) not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  effective_from timestamptz not null default now(),
  effective_to timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.app_users(id) on delete set null,
  updated_by uuid references public.app_users(id) on delete set null
);

alter table public.rental_rate_rules owner to postgres;
alter table public.rental_rate_rules alter column id set default gen_random_uuid();
alter table public.rental_rate_rules alter column vehicle_class set not null;
alter table public.rental_rate_rules alter column daily_rate type numeric(12,2) using daily_rate::numeric(12,2);
alter table public.rental_rate_rules alter column daily_rate set not null;
alter table public.rental_rate_rules alter column sort_order set default 0;
alter table public.rental_rate_rules alter column sort_order set not null;
alter table public.rental_rate_rules alter column is_active set default true;
alter table public.rental_rate_rules alter column is_active set not null;
alter table public.rental_rate_rules alter column effective_from set default now();
alter table public.rental_rate_rules alter column effective_from set not null;
alter table public.rental_rate_rules alter column created_at set default now();
alter table public.rental_rate_rules alter column created_at set not null;
alter table public.rental_rate_rules alter column updated_at set default now();
alter table public.rental_rate_rules alter column updated_at set not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'rental_rate_rules_pay_type_rule_id_fkey' and conrelid = 'public.rental_rate_rules'::regclass) then
    alter table public.rental_rate_rules add constraint rental_rate_rules_pay_type_rule_id_fkey foreign key (pay_type_rule_id) references public.pay_type_rules(id) on delete restrict;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rental_rate_rules_created_by_fkey' and conrelid = 'public.rental_rate_rules'::regclass) then
    alter table public.rental_rate_rules add constraint rental_rate_rules_created_by_fkey foreign key (created_by) references public.app_users(id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rental_rate_rules_updated_by_fkey' and conrelid = 'public.rental_rate_rules'::regclass) then
    alter table public.rental_rate_rules add constraint rental_rate_rules_updated_by_fkey foreign key (updated_by) references public.app_users(id) on delete set null;
  end if;
end $$;

alter table public.rental_rate_rules drop constraint if exists ck_rental_rate_rules_vehicle_class_nonblank;
alter table public.rental_rate_rules add constraint ck_rental_rate_rules_vehicle_class_nonblank check (btrim(vehicle_class) <> '');
alter table public.rental_rate_rules drop constraint if exists ck_rental_rate_rules_daily_rate_nonnegative;
alter table public.rental_rate_rules add constraint ck_rental_rate_rules_daily_rate_nonnegative check (daily_rate >= 0);
alter table public.rental_rate_rules drop constraint if exists ck_rental_rate_rules_daily_rate_finite;
alter table public.rental_rate_rules add constraint ck_rental_rate_rules_daily_rate_finite check (daily_rate not in ('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric));
alter table public.rental_rate_rules drop constraint if exists ck_rental_rate_rules_sort_order_nonnegative;
alter table public.rental_rate_rules add constraint ck_rental_rate_rules_sort_order_nonnegative check (sort_order >= 0);
alter table public.rental_rate_rules drop constraint if exists ck_rental_rate_rules_effective_range;
alter table public.rental_rate_rules add constraint ck_rental_rate_rules_effective_range check (effective_to is null or effective_to > effective_from);

create unique index if not exists ux_rental_rate_rules_current_class_pay_type on public.rental_rate_rules (lower(btrim(vehicle_class)), pay_type_rule_id) where is_active = true and effective_to is null;
create index if not exists ix_rental_rate_rules_pay_type_rule_id on public.rental_rate_rules (pay_type_rule_id);
create index if not exists ix_rental_rate_rules_created_by on public.rental_rate_rules (created_by);
create index if not exists ix_rental_rate_rules_updated_by on public.rental_rate_rules (updated_by);

drop trigger if exists trg_rental_rate_rules_set_updated_at on public.rental_rate_rules;
create trigger trg_rental_rate_rules_set_updated_at before update on public.rental_rate_rules for each row execute function public.set_updated_at();

alter table public.rental_rate_rules enable row level security;
revoke all on table public.rental_rate_rules from public, anon, authenticated;
grant all on table public.rental_rate_rules to service_role;

create or replace function public.authorize_rental_rate_admin()
returns uuid language plpgsql security definer set search_path to '' as $function$
declare v_user_id uuid;
begin
  select au.id into v_user_id from public.app_users au where au.auth_user_id = auth.uid() and au.is_active = true;
  if v_user_id is null or not exists (select 1 from public.v_user_effective_permissions p where p.user_id = v_user_id and p.permission_key = 'user_admin.manage') then
    raise exception 'Rental rate administration access denied' using errcode = '42501';
  end if;
  return v_user_id;
end;$function$;
alter function public.authorize_rental_rate_admin() owner to postgres;
revoke all on function public.authorize_rental_rate_admin() from public, anon, authenticated;

create or replace function public.rental_rate_rule_json(p_rule public.rental_rate_rules, p_observed_at timestamptz)
returns jsonb language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object(
    'rental_rate_rule_id', p_rule.id, 'vehicle_class', p_rule.vehicle_class,
    'pay_type_rule_id', p_rule.pay_type_rule_id, 'pay_type', ptr.pay_type,
    'daily_rate', p_rule.daily_rate, 'sort_order', p_rule.sort_order,
    'is_active', p_rule.is_active,
    'is_current', p_rule.is_active and p_rule.effective_from <= p_observed_at and (p_rule.effective_to is null or p_rule.effective_to > p_observed_at),
    'effective_from', p_rule.effective_from, 'effective_to', p_rule.effective_to,
    'created_at', p_rule.created_at, 'updated_at', p_rule.updated_at)
  from public.pay_type_rules ptr where ptr.id = p_rule.pay_type_rule_id;
$function$;
alter function public.rental_rate_rule_json(public.rental_rate_rules, timestamptz) owner to postgres;
revoke all on function public.rental_rate_rule_json(public.rental_rate_rules, timestamptz) from public, anon, authenticated;

create or replace function public.get_admin_rental_rate_rules_state()
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_observed_at timestamptz := clock_timestamp(); v_rates jsonb; v_pay_types jsonb;
begin
  perform public.authorize_rental_rate_admin();
  select coalesce(jsonb_agg(public.rental_rate_rule_json(r, v_observed_at) order by lower(btrim(r.vehicle_class)), ptr.sort_order, ptr.pay_type, r.effective_from desc, r.id), '[]'::jsonb)
    into v_rates from public.rental_rate_rules r join public.pay_type_rules ptr on ptr.id = r.pay_type_rule_id;
  select coalesce(jsonb_agg(jsonb_build_object('pay_type_rule_id', id, 'pay_type', pay_type, 'is_enabled', is_active and coalesce(active,false), 'sort_order', sort_order) order by sort_order, pay_type, id), '[]'::jsonb)
    into v_pay_types from public.pay_type_rules;
  return jsonb_build_object('status','admin_rental_rate_rules_ready','can_manage',true,'rate_rules',v_rates,'pay_types',v_pay_types);
end;$function$;

create or replace function public.create_admin_rental_rate_rule_state(p_vehicle_class text, p_pay_type_rule_id uuid, p_daily_rate numeric, p_sort_order integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user_id uuid; v_rule public.rental_rate_rules%rowtype;
begin
  v_user_id := public.authorize_rental_rate_admin();
  if p_vehicle_class is null or btrim(p_vehicle_class) = '' then raise exception 'Vehicle class cannot be blank' using errcode='22023'; end if;
  if p_pay_type_rule_id is null then raise exception 'Pay type rule ID is required' using errcode='22023'; end if;
  if p_daily_rate is null or p_daily_rate < 0 or p_daily_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Daily rate must be finite and zero or greater' using errcode='22023'; end if;
  if p_sort_order is null or p_sort_order < 0 then raise exception 'Sort order must be zero or greater' using errcode='22023'; end if;
  perform 1 from public.pay_type_rules p where p.id = p_pay_type_rule_id and p.is_active and coalesce(p.active,false) for share;
  if not found then raise exception 'Enabled pay type rule not found' using errcode='P0002'; end if;
  insert into public.rental_rate_rules(vehicle_class,pay_type_rule_id,daily_rate,sort_order,is_active,created_by,updated_by)
    values (btrim(p_vehicle_class),p_pay_type_rule_id,p_daily_rate,p_sort_order,true,v_user_id,v_user_id) returning * into v_rule;
  return jsonb_build_object('status','admin_rental_rate_rule_created','rental_rate_rule',public.rental_rate_rule_json(v_rule, clock_timestamp()));
exception when unique_violation then raise exception 'A current rental rate already exists for this vehicle class and pay type' using errcode='23505';
end;$function$;

create or replace function public.update_admin_rental_rate_rule_state(p_rental_rate_rule_id uuid, p_vehicle_class text, p_pay_type_rule_id uuid, p_daily_rate numeric, p_sort_order integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user_id uuid; v_existing public.rental_rate_rules%rowtype; v_rule public.rental_rate_rules%rowtype; v_pay_enabled boolean;
begin
  v_user_id := public.authorize_rental_rate_admin();
  if p_rental_rate_rule_id is null then raise exception 'Rental rate rule ID is required' using errcode='22023'; end if;
  if p_vehicle_class is null or btrim(p_vehicle_class) = '' then raise exception 'Vehicle class cannot be blank' using errcode='22023'; end if;
  if p_pay_type_rule_id is null then raise exception 'Pay type rule ID is required' using errcode='22023'; end if;
  if p_daily_rate is null or p_daily_rate < 0 or p_daily_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Daily rate must be finite and zero or greater' using errcode='22023'; end if;
  if p_sort_order is null or p_sort_order < 0 then raise exception 'Sort order must be zero or greater' using errcode='22023'; end if;
  select * into v_existing from public.rental_rate_rules where id = p_rental_rate_rule_id for update;
  if not found then raise exception 'Rental rate rule not found' using errcode='P0002'; end if;
  select p.is_active and coalesce(p.active,false) into v_pay_enabled from public.pay_type_rules p where p.id = p_pay_type_rule_id for share;
  if not found then raise exception 'Pay type rule not found' using errcode='P0002'; end if;
  if v_existing.is_active and not v_pay_enabled then raise exception 'Active rental rates require an enabled pay type' using errcode='22023'; end if;
  update public.rental_rate_rules set vehicle_class=btrim(p_vehicle_class), pay_type_rule_id=p_pay_type_rule_id, daily_rate=p_daily_rate, sort_order=p_sort_order, updated_by=v_user_id where id=p_rental_rate_rule_id returning * into v_rule;
  return jsonb_build_object('status','admin_rental_rate_rule_updated','rental_rate_rule',public.rental_rate_rule_json(v_rule, clock_timestamp()));
exception when unique_violation then raise exception 'A current rental rate already exists for this vehicle class and pay type' using errcode='23505';
end;$function$;

create or replace function public.set_admin_rental_rate_rule_enabled_state(p_rental_rate_rule_id uuid, p_is_enabled boolean)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user_id uuid; v_existing public.rental_rate_rules%rowtype; v_rule public.rental_rate_rules%rowtype; v_pay_enabled boolean; v_now timestamptz := clock_timestamp();
begin
  v_user_id := public.authorize_rental_rate_admin();
  if p_rental_rate_rule_id is null then raise exception 'Rental rate rule ID is required' using errcode='22023'; end if;
  if p_is_enabled is null then raise exception 'Enabled selection is required' using errcode='22023'; end if;
  select * into v_existing from public.rental_rate_rules where id = p_rental_rate_rule_id for update;
  if not found then raise exception 'Rental rate rule not found' using errcode='P0002'; end if;
  select p.is_active and coalesce(p.active,false) into v_pay_enabled from public.pay_type_rules p where p.id = v_existing.pay_type_rule_id for share;
  if p_is_enabled and not v_pay_enabled then raise exception 'Reactivated rental rates require an enabled pay type' using errcode='22023'; end if;
  update public.rental_rate_rules set is_active=p_is_enabled, effective_to=case when p_is_enabled then null when v_now <= effective_from then effective_from + interval '1 microsecond' else v_now end, effective_from=case when p_is_enabled and not is_active then v_now else effective_from end, updated_by=v_user_id where id=p_rental_rate_rule_id returning * into v_rule;
  return jsonb_build_object('status', case when p_is_enabled then 'admin_rental_rate_rule_enabled' else 'admin_rental_rate_rule_disabled' end, 'rental_rate_rule', public.rental_rate_rule_json(v_rule, clock_timestamp()));
exception when unique_violation then raise exception 'A current rental rate already exists for this vehicle class and pay type' using errcode='23505';
end;$function$;

create or replace function public.resolve_rental_daily_rate_state(p_vehicle_class text, p_pay_type_rule_id uuid, p_effective_at timestamptz)
returns jsonb language sql stable security invoker set search_path to '' as $function$
  with requested as (select btrim(p_vehicle_class) vehicle_class, coalesce(p_effective_at, now()) effective_at),
  pay as (select * from public.pay_type_rules p where p.id = p_pay_type_rule_id),
  matched as (
    select r.*, p.pay_type, (p.is_active and coalesce(p.active,false)) pay_type_is_enabled, req.effective_at
    from requested req join public.rental_rate_rules r on lower(btrim(r.vehicle_class)) = lower(req.vehicle_class)
    join public.pay_type_rules p on p.id = r.pay_type_rule_id
    where r.pay_type_rule_id = p_pay_type_rule_id and r.is_active and r.effective_from <= req.effective_at and (r.effective_to is null or r.effective_to > req.effective_at)
    order by r.effective_from desc, r.sort_order, r.id limit 1)
  select case when not exists (select 1 from pay) then jsonb_build_object('status','rental_daily_rate_pay_type_not_found')
    when not exists (select 1 from matched) then jsonb_build_object('status','rental_daily_rate_not_configured')
    else (select jsonb_build_object('status','rental_daily_rate_resolved','requested_vehicle_class',p_vehicle_class,'rental_rate_rule_id',id,'vehicle_class',vehicle_class,'pay_type_rule_id',pay_type_rule_id,'pay_type',pay_type,'pay_type_is_enabled',pay_type_is_enabled,'daily_rate',daily_rate,'effective_at',effective_at,'effective_from',effective_from,'effective_to',effective_to) from matched) end;
$function$;

alter function public.get_admin_rental_rate_rules_state() owner to postgres;
alter function public.create_admin_rental_rate_rule_state(text, uuid, numeric, integer) owner to postgres;
alter function public.update_admin_rental_rate_rule_state(uuid, text, uuid, numeric, integer) owner to postgres;
alter function public.set_admin_rental_rate_rule_enabled_state(uuid, boolean) owner to postgres;
alter function public.resolve_rental_daily_rate_state(text, uuid, timestamptz) owner to postgres;

revoke all on function public.get_admin_rental_rate_rules_state() from public, anon, authenticated;
revoke all on function public.create_admin_rental_rate_rule_state(text, uuid, numeric, integer) from public, anon, authenticated;
revoke all on function public.update_admin_rental_rate_rule_state(uuid, text, uuid, numeric, integer) from public, anon, authenticated;
revoke all on function public.set_admin_rental_rate_rule_enabled_state(uuid, boolean) from public, anon, authenticated;
revoke all on function public.resolve_rental_daily_rate_state(text, uuid, timestamptz) from public, anon, authenticated;

grant execute on function public.get_admin_rental_rate_rules_state() to authenticated, service_role;
grant execute on function public.create_admin_rental_rate_rule_state(text, uuid, numeric, integer) to authenticated, service_role;
grant execute on function public.update_admin_rental_rate_rule_state(uuid, text, uuid, numeric, integer) to authenticated, service_role;
grant execute on function public.set_admin_rental_rate_rule_enabled_state(uuid, boolean) to authenticated, service_role;
grant execute on function public.resolve_rental_daily_rate_state(text, uuid, timestamptz) to service_role;
