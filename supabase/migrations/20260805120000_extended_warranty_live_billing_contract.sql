-- Extended Warranty live billing contract.
-- Idempotently records provider/rule administration, case snapshots, override permission,
-- and runtime reconciliation boundaries. Tekion remains cashiering source of truth.

alter table public.extended_warranty_rules alter column provider_id set not null;
alter table public.extended_warranty_rules alter column covered_days drop default;
alter table public.extended_warranty_rules alter column requires_approval set default false;
alter table public.extended_warranty_rules alter column requires_approval set not null;
alter table public.extended_warranty_rules alter column daily_rate type numeric(12,2) using daily_rate::numeric(12,2);
alter table public.extended_warranty_rules owner to postgres;

alter table public.extended_warranty_rules drop constraint if exists ck_extended_warranty_rules_covered_days_positive;
alter table public.extended_warranty_rules add constraint ck_extended_warranty_rules_covered_days_positive check (covered_days is null or covered_days > 0);
alter table public.extended_warranty_rules drop constraint if exists ck_extended_warranty_rules_daily_rate_nonnegative_finite;
alter table public.extended_warranty_rules add constraint ck_extended_warranty_rules_daily_rate_nonnegative_finite check (daily_rate is null or (daily_rate >= 0 and daily_rate not in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)));

alter table public.warranty_providers drop constraint if exists ck_warranty_providers_name_nonblank;
alter table public.warranty_providers add constraint ck_warranty_providers_name_nonblank check (btrim(name) <> '');
create unique index if not exists ux_warranty_providers_name_normalized on public.warranty_providers (lower(btrim(name)));
create unique index if not exists ux_extended_warranty_rules_one_active_per_provider on public.extended_warranty_rules (provider_id) where is_active = true;

do $$ begin
  if exists (select 1 from pg_constraint where conname='extended_warranty_rules_provider_id_fkey' and conrelid='public.extended_warranty_rules'::regclass) then
    alter table public.extended_warranty_rules drop constraint extended_warranty_rules_provider_id_fkey;
  end if;
  alter table public.extended_warranty_rules add constraint extended_warranty_rules_provider_id_fkey foreign key (provider_id) references public.warranty_providers(id) on delete restrict;
end $$;

alter table public.warranty_cases add column if not exists extended_warranty_rule_id uuid;
alter table public.warranty_cases add column if not exists default_covered_days_snapshot integer;
alter table public.warranty_cases add column if not exists default_daily_rate_snapshot numeric(12,2);
alter table public.warranty_cases add column if not exists coverage_started_at timestamptz;
alter table public.warranty_cases add column if not exists coverage_exhausted_at timestamptz;
alter table public.warranty_cases add column if not exists post_coverage_pay_type_rule_id uuid;
alter table public.warranty_cases add column if not exists override_reason text;
alter table public.warranty_cases add column if not exists override_authorized_by uuid;
alter table public.warranty_cases add column if not exists override_authorized_at timestamptz;
alter table public.warranty_cases add column if not exists updated_at timestamptz not null default now();
alter table public.warranty_cases alter column updated_at set default now();
alter table public.warranty_cases alter column updated_at set not null;
alter table public.warranty_cases alter column default_daily_rate_snapshot type numeric(12,2) using default_daily_rate_snapshot::numeric(12,2);
alter table public.warranty_cases owner to postgres;

create unique index if not exists ux_warranty_cases_transportation_event_id on public.warranty_cases (transportation_event_id);
create index if not exists ix_warranty_cases_extended_warranty_rule_id on public.warranty_cases (extended_warranty_rule_id);
create index if not exists ix_warranty_cases_post_coverage_pay_type_rule_id on public.warranty_cases (post_coverage_pay_type_rule_id);

do $$ begin
  alter table public.warranty_cases drop constraint if exists warranty_cases_transportation_event_id_fkey;
  alter table public.warranty_cases add constraint warranty_cases_transportation_event_id_fkey foreign key (transportation_event_id) references public.transportation_events(id) on delete restrict;
  alter table public.warranty_cases drop constraint if exists warranty_cases_provider_id_fkey;
  alter table public.warranty_cases add constraint warranty_cases_provider_id_fkey foreign key (provider_id) references public.warranty_providers(id) on delete restrict;
  alter table public.warranty_cases drop constraint if exists warranty_cases_extended_warranty_rule_id_fkey;
  alter table public.warranty_cases add constraint warranty_cases_extended_warranty_rule_id_fkey foreign key (extended_warranty_rule_id) references public.extended_warranty_rules(id) on delete restrict;
  alter table public.warranty_cases drop constraint if exists warranty_cases_post_coverage_pay_type_rule_id_fkey;
  alter table public.warranty_cases add constraint warranty_cases_post_coverage_pay_type_rule_id_fkey foreign key (post_coverage_pay_type_rule_id) references public.pay_type_rules(id) on delete restrict;
  alter table public.warranty_cases drop constraint if exists warranty_cases_override_authorized_by_fkey;
  alter table public.warranty_cases add constraint warranty_cases_override_authorized_by_fkey foreign key (override_authorized_by) references public.app_users(id) on delete set null;
end $$;

alter table public.warranty_cases drop constraint if exists ck_warranty_cases_default_covered_days_snapshot_positive;
alter table public.warranty_cases add constraint ck_warranty_cases_default_covered_days_snapshot_positive check (default_covered_days_snapshot is null or default_covered_days_snapshot > 0);
alter table public.warranty_cases drop constraint if exists ck_warranty_cases_approved_days_positive;
alter table public.warranty_cases add constraint ck_warranty_cases_approved_days_positive check (approved_days is null or approved_days > 0);
alter table public.warranty_cases drop constraint if exists ck_warranty_cases_default_daily_rate_snapshot_nonnegative_finite;
alter table public.warranty_cases add constraint ck_warranty_cases_default_daily_rate_snapshot_nonnegative_finite check (default_daily_rate_snapshot is null or (default_daily_rate_snapshot >= 0 and default_daily_rate_snapshot not in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)));

drop trigger if exists trg_warranty_cases_set_updated_at on public.warranty_cases;
create trigger trg_warranty_cases_set_updated_at before update on public.warranty_cases for each row execute function public.set_updated_at();

insert into public.permissions (permission_key, description)
values ('billing.extended_warranty_override', 'Can override the covered-day limit for an extended-warranty transportation case')
on conflict (permission_key) do update set description = excluded.description;
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.role_name in ('Admin','Dev') and p.permission_key = 'billing.extended_warranty_override'
on conflict (role_id, permission_id) do nothing;

create or replace function public.require_extended_warranty_actor_state(p_permission_key text default null)
returns uuid language plpgsql security invoker set search_path to '' as $function$
declare v_user_id uuid; begin
  select au.id into v_user_id from public.app_users au where au.auth_user_id = auth.uid() and au.is_active = true;
  if v_user_id is null then raise exception 'Active application user required' using errcode='42501'; end if;
  if coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then raise exception 'AAL2 verification required' using errcode='42501'; end if;
  if p_permission_key is not null and not exists (select 1 from public.v_user_effective_permissions p where p.user_id = v_user_id and p.permission_key = p_permission_key) then raise exception 'Permission denied' using errcode='42501'; end if;
  return v_user_id;
end;$function$;

create or replace function public.get_admin_billing_configuration_state()
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user_id uuid; v_rules jsonb; begin
  select au.id into v_user_id from public.app_users au where au.auth_user_id = auth.uid() and au.is_active = true;
  if v_user_id is null or not exists (select 1 from public.v_user_effective_permissions p where p.user_id=v_user_id and p.permission_key='user_admin.manage') then raise exception 'Billing administration access denied' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',wp.id,'provider_name',wp.name,'provider_type',wp.provider_type,'provider_default_daily_rate',wp.default_daily_rate,'is_enabled',wp.is_active,'rule_id',ewr.id,'covered_days',ewr.covered_days,'requires_approval',ewr.requires_approval,'rule_daily_rate',ewr.daily_rate,'resolved_daily_rate',coalesce(ewr.daily_rate,wp.default_daily_rate),'notes',ewr.notes,'rule_is_active',ewr.is_active,'created_at',ewr.created_at,'updated_at',ewr.updated_at) order by lower(btrim(wp.name)), ewr.id),'[]'::jsonb)
  into v_rules from public.warranty_providers wp join public.extended_warranty_rules ewr on ewr.provider_id=wp.id;
  return jsonb_build_object('status','admin_billing_configuration_ready','can_manage',true,'extended_warranty_provider_rules',v_rules);
end;$function$;

create or replace function public.create_admin_extended_warranty_provider_rule_state(p_provider_name text, p_default_daily_amount numeric, p_covered_days integer, p_requires_approval boolean, p_notes text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user_id uuid; v_provider public.warranty_providers%rowtype; v_rule public.extended_warranty_rules%rowtype; begin
  select au.id into v_user_id from public.app_users au where au.auth_user_id = auth.uid() and au.is_active = true;
  if v_user_id is null or not exists (select 1 from public.v_user_effective_permissions p where p.user_id=v_user_id and p.permission_key='user_admin.manage') then raise exception 'Billing administration access denied' using errcode='42501'; end if;
  if p_provider_name is null or btrim(p_provider_name)='' then raise exception 'Extended Warranty provider name is required' using errcode='22023'; end if;
  if p_default_daily_amount is not null and (p_default_daily_amount < 0 or p_default_daily_amount in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Daily amount must be finite and zero or greater' using errcode='22023'; end if;
  if p_covered_days is not null and p_covered_days <= 0 then raise exception 'Covered-day cap must be a positive whole number' using errcode='22023'; end if;
  if p_requires_approval is null then raise exception 'Requires-approval selection is required' using errcode='22023'; end if;
  insert into public.warranty_providers(name, provider_type, default_daily_rate, is_active) values (btrim(p_provider_name),'Extended Warranty',p_default_daily_amount,true) returning * into v_provider;
  insert into public.extended_warranty_rules(provider_id, covered_days, requires_approval, daily_rate, is_active, notes) values (v_provider.id,p_covered_days,p_requires_approval,p_default_daily_amount,true,nullif(btrim(coalesce(p_notes,'')),'')) returning * into v_rule;
  return jsonb_build_object('status','admin_extended_warranty_provider_rule_created','provider_rule',jsonb_build_object('provider_id',v_provider.id,'provider_name',v_provider.name,'is_enabled',v_provider.is_active,'rule_id',v_rule.id,'covered_days',v_rule.covered_days,'requires_approval',v_rule.requires_approval,'rule_daily_rate',v_rule.daily_rate,'resolved_daily_rate',coalesce(v_rule.daily_rate,v_provider.default_daily_rate),'notes',v_rule.notes));
exception when unique_violation then raise exception 'An Extended Warranty provider with this name or active rule already exists' using errcode='23505'; end;$function$;

create or replace function public.update_admin_extended_warranty_provider_rule_state(p_rule_id uuid, p_provider_name text, p_default_daily_amount numeric, p_covered_days integer, p_requires_approval boolean, p_notes text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user_id uuid; v_rule public.extended_warranty_rules%rowtype; v_provider public.warranty_providers%rowtype; begin
  select au.id into v_user_id from public.app_users au where au.auth_user_id = auth.uid() and au.is_active = true;
  if v_user_id is null or not exists (select 1 from public.v_user_effective_permissions p where p.user_id=v_user_id and p.permission_key='user_admin.manage') then raise exception 'Billing administration access denied' using errcode='42501'; end if;
  if p_rule_id is null then raise exception 'Extended Warranty rule ID is required' using errcode='22023'; end if;
  if p_provider_name is null or btrim(p_provider_name)='' then raise exception 'Extended Warranty provider name is required' using errcode='22023'; end if;
  if p_default_daily_amount is not null and (p_default_daily_amount < 0 or p_default_daily_amount in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Daily amount must be finite and zero or greater' using errcode='22023'; end if;
  if p_covered_days is not null and p_covered_days <= 0 then raise exception 'Covered-day cap must be a positive whole number' using errcode='22023'; end if;
  if p_requires_approval is null then raise exception 'Requires-approval selection is required' using errcode='22023'; end if;
  select * into v_rule from public.extended_warranty_rules where id=p_rule_id for update; if not found then raise exception 'Extended Warranty rule not found' using errcode='P0002'; end if;
  update public.warranty_providers set name=btrim(p_provider_name), default_daily_rate=p_default_daily_amount where id=v_rule.provider_id returning * into v_provider;
  update public.extended_warranty_rules set covered_days=p_covered_days, requires_approval=p_requires_approval, daily_rate=p_default_daily_amount, notes=nullif(btrim(coalesce(p_notes,'')),'') where id=p_rule_id returning * into v_rule;
  return jsonb_build_object('status','admin_extended_warranty_provider_rule_updated','provider_rule',jsonb_build_object('provider_id',v_provider.id,'provider_name',v_provider.name,'is_enabled',v_provider.is_active,'rule_id',v_rule.id,'covered_days',v_rule.covered_days,'requires_approval',v_rule.requires_approval,'rule_daily_rate',v_rule.daily_rate,'resolved_daily_rate',coalesce(v_rule.daily_rate,v_provider.default_daily_rate),'notes',v_rule.notes));
exception when unique_violation then raise exception 'An Extended Warranty provider with this name already exists' using errcode='23505'; end;$function$;

create or replace function public.set_admin_extended_warranty_provider_enabled_state(p_rule_id uuid, p_is_enabled boolean)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user_id uuid; v_rule public.extended_warranty_rules%rowtype; v_provider public.warranty_providers%rowtype; begin
  select au.id into v_user_id from public.app_users au where au.auth_user_id = auth.uid() and au.is_active = true;
  if v_user_id is null or not exists (select 1 from public.v_user_effective_permissions p where p.user_id=v_user_id and p.permission_key='user_admin.manage') then raise exception 'Billing administration access denied' using errcode='42501'; end if;
  if p_rule_id is null or p_is_enabled is null then raise exception 'Rule ID and enabled state are required' using errcode='22023'; end if;
  select * into v_rule from public.extended_warranty_rules where id=p_rule_id for update; if not found then raise exception 'Extended Warranty rule not found' using errcode='P0002'; end if;
  update public.warranty_providers set is_active=p_is_enabled where id=v_rule.provider_id returning * into v_provider;
  update public.extended_warranty_rules set is_active=p_is_enabled where id=p_rule_id returning * into v_rule;
  return jsonb_build_object('status',case when p_is_enabled then 'admin_extended_warranty_provider_rule_enabled' else 'admin_extended_warranty_provider_rule_disabled' end,'provider_rule',jsonb_build_object('provider_id',v_provider.id,'provider_name',v_provider.name,'is_enabled',v_provider.is_active,'rule_id',v_rule.id,'covered_days',v_rule.covered_days,'requires_approval',v_rule.requires_approval,'rule_daily_rate',v_rule.daily_rate,'resolved_daily_rate',coalesce(v_rule.daily_rate,v_provider.default_daily_rate),'notes',v_rule.notes));
end;$function$;

create or replace function public.create_extended_warranty_case_and_get_state(p_transportation_event_id uuid, p_provider_id uuid)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_actor uuid; v_event public.transportation_events%rowtype; v_rule record; v_ext_pay public.pay_type_rules%rowtype; v_customer_pay public.pay_type_rules%rowtype; v_pickup timestamptz; v_line public.billing_lines%rowtype; v_case public.warranty_cases%rowtype; begin
  v_actor := public.require_extended_warranty_actor_state(null);
  select * into v_event from public.transportation_events where id=p_transportation_event_id and status <> 'cancelled'; if not found then raise exception 'Active Transportation Event required' using errcode='P0002'; end if;
  select * into v_ext_pay from public.pay_type_rules where pay_type='Extended Warranty' and is_active and coalesce(active,false); if not found then raise exception 'Enabled Extended Warranty pay type required' using errcode='P0002'; end if;
  select * into v_customer_pay from public.pay_type_rules where pay_type='Customer Pay' and is_active and coalesce(active,false) order by sort_order, id limit 1; if not found then raise exception 'Enabled Customer Pay pay type required' using errcode='P0002'; end if;
  if (select count(*) from public.reservations r where r.transportation_event_id=p_transportation_event_id and r.pay_type='Extended Warranty') <> 1 then raise exception 'Exactly one Extended Warranty reservation required' using errcode='22023'; end if;
  select min(ve.actual_out_at) into v_pickup from public.vehicle_events ve where ve.transportation_event_id=p_transportation_event_id and ve.actual_out_at is not null; if v_pickup is null then raise exception 'First vehicle pickup required' using errcode='P0002'; end if;
  select wp.id provider_id, wp.name provider_name, ewr.id rule_id, ewr.covered_days, ewr.requires_approval, coalesce(ewr.daily_rate, wp.default_daily_rate) resolved_daily_rate into v_rule from public.warranty_providers wp join public.extended_warranty_rules ewr on ewr.provider_id=wp.id and ewr.is_active where wp.id=p_provider_id and wp.is_active; if not found then raise exception 'Active Extended Warranty provider/rule required' using errcode='P0002'; end if;
  if v_rule.resolved_daily_rate is null then raise exception 'Extended Warranty provider daily amount must be configured' using errcode='22023'; end if;
  select * into v_line from public.billing_lines where transportation_event_id=p_transportation_event_id and pay_type='Extended Warranty' and parent_billing_line_id is null and is_open order by start_time nulls last, created_at limit 1 for update; if not found then raise exception 'Open Extended Warranty parent billing line required' using errcode='P0002'; end if;
  insert into public.warranty_cases(transportation_event_id,reservation_id,provider_id,provider_name,extended_warranty_rule_id,default_covered_days_snapshot,default_daily_rate_snapshot,coverage_started_at,post_coverage_pay_type_rule_id,approval_status,approved_days,last_checked_at,metadata)
  values(p_transportation_event_id,v_line.reservation_id,v_rule.provider_id,v_rule.provider_name,v_rule.rule_id,v_rule.covered_days,v_rule.resolved_daily_rate,v_pickup,v_customer_pay.id,'approved',v_rule.covered_days,clock_timestamp(),jsonb_build_object('created_by',v_actor))
  on conflict (transportation_event_id) do update set reservation_id=excluded.reservation_id, provider_id=excluded.provider_id, provider_name=excluded.provider_name, extended_warranty_rule_id=excluded.extended_warranty_rule_id, default_covered_days_snapshot=excluded.default_covered_days_snapshot, default_daily_rate_snapshot=excluded.default_daily_rate_snapshot, coverage_started_at=excluded.coverage_started_at, post_coverage_pay_type_rule_id=excluded.post_coverage_pay_type_rule_id returning * into v_case;
  update public.billing_lines set warranty_provider_id=v_rule.provider_id, default_covered_days_snapshot=v_rule.covered_days, covered_days_override=v_rule.covered_days, default_daily_rate_snapshot=v_rule.resolved_daily_rate where id=v_line.id;
  return jsonb_build_object('status','extended_warranty_case_ready','case_id',v_case.id,'transportation_event_id',v_case.transportation_event_id,'provider_id',v_case.provider_id,'extended_warranty_rule_id',v_case.extended_warranty_rule_id,'default_covered_days_snapshot',v_case.default_covered_days_snapshot,'default_daily_rate_snapshot',v_case.default_daily_rate_snapshot,'coverage_started_at',v_case.coverage_started_at,'post_coverage_pay_type_rule_id',v_case.post_coverage_pay_type_rule_id);
end;$function$;

create or replace function public.set_extended_warranty_case_override_and_get_state(p_warranty_case_id uuid, p_covered_days_override integer, p_post_coverage_pay_type_rule_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_actor uuid; v_case public.warranty_cases%rowtype; v_old jsonb; v_new jsonb; v_pay public.pay_type_rules%rowtype; begin
  v_actor := public.require_extended_warranty_actor_state('billing.extended_warranty_override');
  if p_reason is null or btrim(p_reason)='' then raise exception 'Override reason is required' using errcode='22023'; end if;
  if p_covered_days_override is not null and p_covered_days_override <= 0 then raise exception 'Covered-day override must be positive' using errcode='22023'; end if;
  select * into v_case from public.warranty_cases where id=p_warranty_case_id for update; if not found then raise exception 'Extended Warranty case not found' using errcode='P0002'; end if;
  v_old := jsonb_build_object('approved_days',v_case.approved_days,'post_coverage_pay_type_rule_id',v_case.post_coverage_pay_type_rule_id);
  if p_post_coverage_pay_type_rule_id is null then select * into v_pay from public.pay_type_rules where pay_type='Customer Pay' and is_active and coalesce(active,false) order by sort_order, id limit 1; else select * into v_pay from public.pay_type_rules where id=p_post_coverage_pay_type_rule_id and is_active and coalesce(active,false); end if;
  if not found then raise exception 'Active post-cap pay type required' using errcode='P0002'; end if;
  if v_pay.pay_type='Extended Warranty' then raise exception 'Extended Warranty cannot be its own post-cap fallback' using errcode='22023'; end if;
  update public.warranty_cases set approved_days=coalesce(p_covered_days_override, default_covered_days_snapshot), post_coverage_pay_type_rule_id=v_pay.id, override_reason=btrim(p_reason), override_authorized_by=v_actor, override_authorized_at=clock_timestamp() where id=p_warranty_case_id returning * into v_case;
  update public.billing_lines set covered_days_override=v_case.approved_days where transportation_event_id=v_case.transportation_event_id and pay_type='Extended Warranty' and parent_billing_line_id is null;
  v_new := jsonb_build_object('approved_days',v_case.approved_days,'post_coverage_pay_type_rule_id',v_case.post_coverage_pay_type_rule_id);
  insert into public.audit_log(entity_type,entity_id,action_type,field_name,old_value,new_value,metadata,actor_user_id) values('warranty_cases',v_case.id::text,'extended_warranty_override','approved_days',v_old::text,v_new::text,jsonb_build_object('reason',btrim(p_reason),'actor',v_actor,'changed_at',v_case.override_authorized_at),v_actor::text);
  return jsonb_build_object('status','extended_warranty_case_override_saved','case_id',v_case.id,'approved_days',v_case.approved_days,'post_coverage_pay_type_rule_id',v_case.post_coverage_pay_type_rule_id,'override_authorized_by',v_case.override_authorized_by,'override_reason',v_case.override_reason);
end;$function$;

create or replace function public.reconcile_extended_warranty_coverage_state(p_warranty_case_id uuid, p_effective_at timestamptz)
returns jsonb language plpgsql security invoker set search_path to '' as $function$
declare v_case public.warranty_cases%rowtype; v_days integer; v_parent public.billing_lines%rowtype; v_split_count integer; v_boundary timestamptz; v_current_vehicle_event public.vehicle_events%rowtype; v_create jsonb; begin
  if p_effective_at is null then raise exception 'Effective timestamp is required' using errcode='22023'; end if;
  select * into v_case from public.warranty_cases where id=p_warranty_case_id for update; if not found then return jsonb_build_object('status','extended_warranty_case_not_found','manual_review',true); end if;
  if v_case.coverage_started_at is null or v_case.approved_days is null then return jsonb_build_object('status','extended_warranty_no_cap_configured','manual_review',false,'case_id',v_case.id); end if;
  v_days := public.business_contract_days(v_case.coverage_started_at, p_effective_at);
  if v_days < v_case.approved_days then return jsonb_build_object('status','extended_warranty_coverage_active','case_id',v_case.id,'continuous_case_contract_day',v_days,'covered_days',v_case.approved_days); end if;
  select * into v_parent from public.billing_lines where transportation_event_id=v_case.transportation_event_id and pay_type='Extended Warranty' and parent_billing_line_id is null order by start_time nulls last, created_at limit 1 for update;
  if not found then return jsonb_build_object('status','extended_warranty_manual_review_missing_parent_line','manual_review',true,'case_id',v_case.id); end if;
  v_boundary := v_case.coverage_started_at + ((v_case.approved_days)::text || ' days')::interval;
  select count(*) into v_split_count from public.billing_lines where extended_from_billing_line_id=v_parent.id and line_type='pay_type_split';
  if v_split_count > 1 then return jsonb_build_object('status','extended_warranty_manual_review_duplicate_split','manual_review',true,'case_id',v_case.id); end if;
  if v_split_count = 0 then
    perform public.close_billing_line_state(v_parent.id, v_boundary);
    update public.billing_lines set end_time=v_boundary,is_open=false where parent_billing_line_id=v_parent.id and line_type='tax' and is_open;
    select * into v_current_vehicle_event from public.vehicle_events where transportation_event_id=v_case.transportation_event_id and actual_out_at <= p_effective_at and (actual_in_at is null or actual_in_at > p_effective_at) order by actual_out_at desc, id limit 1;
    v_create := public.create_billing_parent_line_state(v_case.transportation_event_id,v_parent.reservation_id,coalesce(v_current_vehicle_event.vehicle_id,v_parent.vehicle_id),(select pay_type from public.pay_type_rules where id=v_case.post_coverage_pay_type_rule_id),null,null,v_boundary,null,'extended_warranty_coverage_cap',coalesce(v_current_vehicle_event.id,v_parent.vehicle_event_id),v_parent.contract_period_id,'pay_type_split',null,null,null,true,null,v_parent.id,null,null);
    update public.warranty_cases set coverage_exhausted_at=v_boundary,last_checked_at=p_effective_at where id=v_case.id;
    return jsonb_build_object('status','extended_warranty_coverage_split_created','manual_review',false,'case_id',v_case.id,'coverage_exhausted_at',v_boundary,'create_result',v_create);
  end if;
  return jsonb_build_object('status','extended_warranty_coverage_split_already_exists','manual_review',false,'case_id',v_case.id,'coverage_exhausted_at',coalesce(v_case.coverage_exhausted_at,v_boundary));
end;$function$;

create or replace function public.reconcile_extended_warranty_coverage_and_get_state(p_warranty_case_id uuid)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_actor uuid; v_now timestamptz := clock_timestamp(); v_reconcile jsonb; v_case public.warranty_cases%rowtype; v_segments jsonb; v_can_override boolean; v_case_day integer; v_vehicle_day integer; v_vehicle_event public.vehicle_events%rowtype; begin
  v_actor := public.require_extended_warranty_actor_state(null);
  v_reconcile := public.reconcile_extended_warranty_coverage_state(p_warranty_case_id, v_now);
  select * into v_case from public.warranty_cases where id=p_warranty_case_id;
  select coalesce(jsonb_agg(jsonb_build_object('billing_line_id',id,'pay_type',pay_type,'line_type',line_type,'start_time',start_time,'end_time',end_time,'is_open',is_open,'vehicle_event_id',vehicle_event_id,'extended_from_billing_line_id',extended_from_billing_line_id) order by start_time nulls last, created_at, id),'[]'::jsonb) into v_segments from public.billing_lines where transportation_event_id=v_case.transportation_event_id;
  select exists(select 1 from public.v_user_effective_permissions p where p.user_id=v_actor and p.permission_key='billing.extended_warranty_override') into v_can_override;
  v_case_day := case when v_case.coverage_started_at is null then null else public.business_contract_days(v_case.coverage_started_at, v_now) end;
  select * into v_vehicle_event from public.vehicle_events where transportation_event_id=v_case.transportation_event_id and actual_out_at <= v_now and (actual_in_at is null or actual_in_at > v_now) order by actual_out_at desc, id limit 1;
  v_vehicle_day := case when v_vehicle_event.actual_out_at is null then null else public.business_contract_days(v_vehicle_event.actual_out_at, v_now) end;
  return jsonb_build_object('status','extended_warranty_coverage_state_ready','case',to_jsonb(v_case),'billing_segments',v_segments,'reconciliation',v_reconcile,'can_override',v_can_override,'continuous_case_contract_day',v_case_day,'current_vehicle_contract_day',v_vehicle_day);
end;$function$;

alter function public.require_extended_warranty_actor_state(text) owner to postgres;
alter function public.get_admin_billing_configuration_state() owner to postgres;
alter function public.create_admin_extended_warranty_provider_rule_state(text,numeric,integer,boolean,text) owner to postgres;
alter function public.update_admin_extended_warranty_provider_rule_state(uuid,text,numeric,integer,boolean,text) owner to postgres;
alter function public.set_admin_extended_warranty_provider_enabled_state(uuid,boolean) owner to postgres;
alter function public.create_extended_warranty_case_and_get_state(uuid,uuid) owner to postgres;
alter function public.set_extended_warranty_case_override_and_get_state(uuid,integer,uuid,text) owner to postgres;
alter function public.reconcile_extended_warranty_coverage_state(uuid,timestamptz) owner to postgres;
alter function public.reconcile_extended_warranty_coverage_and_get_state(uuid) owner to postgres;

revoke all on function public.create_extended_warranty_rule_state(uuid,integer,boolean,numeric,text) from public, anon, authenticated;
revoke all on function public.update_extended_warranty_rule_state(uuid,integer,boolean,numeric,text) from public, anon, authenticated;
revoke all on function public.set_extended_warranty_rule_active_state(uuid,boolean) from public, anon, authenticated;
revoke all on function public.resolve_extended_warranty_provider_default_state(uuid) from public, anon, authenticated;
grant execute on function public.create_extended_warranty_rule_state(uuid,integer,boolean,numeric,text) to service_role;
grant execute on function public.update_extended_warranty_rule_state(uuid,integer,boolean,numeric,text) to service_role;
grant execute on function public.set_extended_warranty_rule_active_state(uuid,boolean) to service_role;
grant execute on function public.resolve_extended_warranty_provider_default_state(uuid) to service_role;

revoke all on function public.require_extended_warranty_actor_state(text) from public, anon, authenticated;
revoke all on function public.get_admin_billing_configuration_state() from public, anon, authenticated;
revoke all on function public.create_admin_extended_warranty_provider_rule_state(text,numeric,integer,boolean,text) from public, anon, authenticated;
revoke all on function public.update_admin_extended_warranty_provider_rule_state(uuid,text,numeric,integer,boolean,text) from public, anon, authenticated;
revoke all on function public.set_admin_extended_warranty_provider_enabled_state(uuid,boolean) from public, anon, authenticated;
revoke all on function public.create_extended_warranty_case_and_get_state(uuid,uuid) from public, anon, authenticated;
revoke all on function public.set_extended_warranty_case_override_and_get_state(uuid,integer,uuid,text) from public, anon, authenticated;
revoke all on function public.reconcile_extended_warranty_coverage_state(uuid,timestamptz) from public, anon, authenticated;
revoke all on function public.reconcile_extended_warranty_coverage_and_get_state(uuid) from public, anon, authenticated;

grant execute on function public.get_admin_billing_configuration_state() to authenticated, service_role;
grant execute on function public.create_admin_extended_warranty_provider_rule_state(text,numeric,integer,boolean,text) to authenticated, service_role;
grant execute on function public.update_admin_extended_warranty_provider_rule_state(uuid,text,numeric,integer,boolean,text) to authenticated, service_role;
grant execute on function public.set_admin_extended_warranty_provider_enabled_state(uuid,boolean) to authenticated, service_role;
grant execute on function public.create_extended_warranty_case_and_get_state(uuid,uuid) to authenticated, service_role;
grant execute on function public.set_extended_warranty_case_override_and_get_state(uuid,integer,uuid,text) to authenticated, service_role;
grant execute on function public.reconcile_extended_warranty_coverage_and_get_state(uuid) to authenticated, service_role;
grant execute on function public.reconcile_extended_warranty_coverage_state(uuid,timestamptz) to service_role;
