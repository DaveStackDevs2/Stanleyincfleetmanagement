-- Verified-live checkpoint: pay-type-independent daily/weekly/monthly rental rate cards.
-- Data-free and compatibility preserving: legacy pay-type RPCs, FK, index, and values remain.

alter table public.rental_rate_rules alter column pay_type_rule_id drop not null;
alter table public.rental_rate_rules add column if not exists weekly_rate numeric(12,2) null;
alter table public.rental_rate_rules add column if not exists monthly_rate numeric(12,2) null;
alter table public.rental_rate_rules alter column weekly_rate type numeric(12,2) using weekly_rate::numeric(12,2);
alter table public.rental_rate_rules alter column monthly_rate type numeric(12,2) using monthly_rate::numeric(12,2);

alter table public.rental_rate_rules drop constraint if exists ck_rental_rate_rules_weekly_rate_valid;
alter table public.rental_rate_rules add constraint ck_rental_rate_rules_weekly_rate_valid check
  (weekly_rate is null or (weekly_rate >= 0 and weekly_rate not in ('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)));
alter table public.rental_rate_rules drop constraint if exists ck_rental_rate_rules_monthly_rate_valid;
alter table public.rental_rate_rules add constraint ck_rental_rate_rules_monthly_rate_valid check
  (monthly_rate is null or (monthly_rate >= 0 and monthly_rate not in ('NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric)));

drop index if exists public.ux_rental_rate_rules_current_class_pay_type;
create unique index if not exists ux_rental_rate_rules_current_class
  on public.rental_rate_rules (lower(btrim(vehicle_class)))
  where is_active = true and effective_to is null;

create or replace function public.resolve_rental_rate_card_state(p_vehicle_class text, p_effective_at timestamptz)
returns jsonb language plpgsql stable security invoker set search_path to '' as $function$
declare v_class text; v_rule public.rental_rate_rules%rowtype;
begin
  if p_vehicle_class is null or btrim(p_vehicle_class) = '' then raise exception 'Vehicle class cannot be blank' using errcode='22023'; end if;
  if p_effective_at is null then raise exception 'Effective timestamp is required' using errcode='22023'; end if;
  v_class := btrim(p_vehicle_class);
  select r.* into v_rule from public.rental_rate_rules r
   where lower(btrim(r.vehicle_class)) = lower(v_class)
     and r.effective_from <= p_effective_at and (r.effective_to is null or r.effective_to > p_effective_at)
     and (r.is_active or r.effective_to is not null)
   order by r.effective_from desc, r.updated_at desc, r.id limit 1;
  if not found then return jsonb_build_object('status','rental_rate_card_not_configured','requested_vehicle_class',v_class,'effective_at',p_effective_at); end if;
  return jsonb_build_object('status','rental_rate_card_resolved','requested_vehicle_class',v_class,'effective_at',p_effective_at,
    'rental_rate_rule_id',v_rule.id,'vehicle_class',v_rule.vehicle_class,'daily_rate',v_rule.daily_rate,
    'weekly_rate',v_rule.weekly_rate,'monthly_rate',v_rule.monthly_rate,'effective_from',v_rule.effective_from,'effective_to',v_rule.effective_to);
end;$function$;

create or replace function public.get_admin_rental_rate_cards_state()
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_now timestamptz := clock_timestamp(); v_cards jsonb;
begin
  select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='user_admin.manage') then raise exception 'Rental rate administration access denied' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('rental_rate_rule_id',r.id,'vehicle_class',r.vehicle_class,'daily_rate',r.daily_rate,
    'weekly_rate',r.weekly_rate,'monthly_rate',r.monthly_rate,'sort_order',r.sort_order,'is_active',r.is_active,
    'is_current',r.is_active and r.effective_from<=v_now and (r.effective_to is null or r.effective_to>v_now),
    'effective_from',r.effective_from,'effective_to',r.effective_to,'created_at',r.created_at,'updated_at',r.updated_at)
    order by r.sort_order,lower(btrim(r.vehicle_class)),r.effective_from desc,r.id),'[]'::jsonb) into v_cards from public.rental_rate_rules r;
  return jsonb_build_object('status','admin_rental_rate_cards_ready','can_manage',true,'rate_cards',v_cards);
end;$function$;

create or replace function public.create_admin_rental_rate_card_state(p_vehicle_class text,p_daily_rate numeric,p_weekly_rate numeric,p_monthly_rate numeric,p_sort_order integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_rule public.rental_rate_rules%rowtype;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='user_admin.manage') then raise exception 'Rental rate administration access denied' using errcode='42501'; end if;
 if p_vehicle_class is null or btrim(p_vehicle_class)='' then raise exception 'Vehicle class cannot be blank' using errcode='22023'; end if;
 if p_daily_rate is null or p_daily_rate<0 or p_daily_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Daily rate must be finite and zero or greater' using errcode='22023'; end if;
 if p_weekly_rate is not null and (p_weekly_rate<0 or p_weekly_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Weekly rate must be finite and zero or greater' using errcode='22023'; end if;
 if p_monthly_rate is not null and (p_monthly_rate<0 or p_monthly_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Monthly rate must be finite and zero or greater' using errcode='22023'; end if;
 if p_sort_order is null or p_sort_order<0 then raise exception 'Sort order must be zero or greater' using errcode='22023'; end if;
 insert into public.rental_rate_rules(vehicle_class,pay_type_rule_id,daily_rate,weekly_rate,monthly_rate,sort_order,is_active,created_by,updated_by)
 values(btrim(p_vehicle_class),null,p_daily_rate,p_weekly_rate,p_monthly_rate,p_sort_order,true,v_user,v_user) returning * into v_rule;
 return jsonb_build_object('status','admin_rental_rate_card_created','rental_rate_card',jsonb_build_object('rental_rate_rule_id',v_rule.id,'vehicle_class',v_rule.vehicle_class,'daily_rate',v_rule.daily_rate,'weekly_rate',v_rule.weekly_rate,'monthly_rate',v_rule.monthly_rate,'sort_order',v_rule.sort_order,'is_active',v_rule.is_active,'is_current',v_rule.is_active and v_rule.effective_from<=clock_timestamp() and (v_rule.effective_to is null or v_rule.effective_to>clock_timestamp()),'effective_from',v_rule.effective_from,'effective_to',v_rule.effective_to,'created_at',v_rule.created_at,'updated_at',v_rule.updated_at));
exception when unique_violation then raise exception 'A current rental rate card already exists for this vehicle class' using errcode='23505'; end;$function$;

create or replace function public.update_admin_rental_rate_card_state(p_rental_rate_rule_id uuid,p_vehicle_class text,p_daily_rate numeric,p_weekly_rate numeric,p_monthly_rate numeric,p_sort_order integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_rule public.rental_rate_rules%rowtype;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='user_admin.manage') then raise exception 'Rental rate administration access denied' using errcode='42501'; end if;
 if p_rental_rate_rule_id is null then raise exception 'Rental rate rule ID is required' using errcode='22023'; end if;
 if p_vehicle_class is null or btrim(p_vehicle_class)='' then raise exception 'Vehicle class cannot be blank' using errcode='22023'; end if;
 if p_daily_rate is null or p_daily_rate<0 or p_daily_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Daily rate must be finite and zero or greater' using errcode='22023'; end if;
 if p_weekly_rate is not null and (p_weekly_rate<0 or p_weekly_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Weekly rate must be finite and zero or greater' using errcode='22023'; end if;
 if p_monthly_rate is not null and (p_monthly_rate<0 or p_monthly_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Monthly rate must be finite and zero or greater' using errcode='22023'; end if;
 if p_sort_order is null or p_sort_order<0 then raise exception 'Sort order must be zero or greater' using errcode='22023'; end if;
 select * into v_rule from public.rental_rate_rules where id=p_rental_rate_rule_id for update;
 if not found then raise exception 'Rental rate card not found' using errcode='P0002'; end if;
 update public.rental_rate_rules set vehicle_class=btrim(p_vehicle_class),daily_rate=p_daily_rate,weekly_rate=p_weekly_rate,monthly_rate=p_monthly_rate,sort_order=p_sort_order,updated_by=v_user where id=p_rental_rate_rule_id returning * into v_rule;
 return jsonb_build_object('status','admin_rental_rate_card_updated','rental_rate_card',jsonb_build_object('rental_rate_rule_id',v_rule.id,'vehicle_class',v_rule.vehicle_class,'daily_rate',v_rule.daily_rate,'weekly_rate',v_rule.weekly_rate,'monthly_rate',v_rule.monthly_rate,'sort_order',v_rule.sort_order,'is_active',v_rule.is_active,'is_current',v_rule.is_active and v_rule.effective_from<=clock_timestamp() and (v_rule.effective_to is null or v_rule.effective_to>clock_timestamp()),'effective_from',v_rule.effective_from,'effective_to',v_rule.effective_to,'created_at',v_rule.created_at,'updated_at',v_rule.updated_at));
exception when unique_violation then raise exception 'A current rental rate card already exists for this vehicle class' using errcode='23505'; end;$function$;

create or replace function public.set_admin_rental_rate_card_enabled_state(p_rental_rate_rule_id uuid,p_is_enabled boolean)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_rule public.rental_rate_rules%rowtype; v_at timestamptz;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='user_admin.manage') then raise exception 'Rental rate administration access denied' using errcode='42501'; end if;
 if p_rental_rate_rule_id is null then raise exception 'Rental rate rule ID is required' using errcode='22023'; end if;
 if p_is_enabled is null then raise exception 'Enabled selection is required' using errcode='22023'; end if;
 select * into v_rule from public.rental_rate_rules where id=p_rental_rate_rule_id for update;
 if not found then raise exception 'Rental rate card not found' using errcode='P0002'; end if;
 v_at:=clock_timestamp();
 update public.rental_rate_rules set is_active=p_is_enabled,
 effective_to=case when p_is_enabled then null when effective_to is not null then effective_to when v_at<=effective_from then effective_from+interval '1 microsecond' else v_at end,
 effective_from=case when p_is_enabled and not is_active then v_at else effective_from end,updated_by=v_user where id=p_rental_rate_rule_id returning * into v_rule;
 return jsonb_build_object('status',case when p_is_enabled then 'admin_rental_rate_card_enabled' else 'admin_rental_rate_card_disabled' end,'rental_rate_card',jsonb_build_object('rental_rate_rule_id',v_rule.id,'vehicle_class',v_rule.vehicle_class,'daily_rate',v_rule.daily_rate,'weekly_rate',v_rule.weekly_rate,'monthly_rate',v_rule.monthly_rate,'sort_order',v_rule.sort_order,'is_active',v_rule.is_active,'is_current',v_rule.is_active and v_rule.effective_from<=clock_timestamp() and (v_rule.effective_to is null or v_rule.effective_to>clock_timestamp()),'effective_from',v_rule.effective_from,'effective_to',v_rule.effective_to,'created_at',v_rule.created_at,'updated_at',v_rule.updated_at));
exception when unique_violation then raise exception 'A current rental rate card already exists for this vehicle class' using errcode='23505'; end;$function$;

alter function public.resolve_rental_rate_card_state(text,timestamptz) owner to postgres;
alter function public.get_admin_rental_rate_cards_state() owner to postgres;
alter function public.create_admin_rental_rate_card_state(text,numeric,numeric,numeric,integer) owner to postgres;
alter function public.update_admin_rental_rate_card_state(uuid,text,numeric,numeric,numeric,integer) owner to postgres;
alter function public.set_admin_rental_rate_card_enabled_state(uuid,boolean) owner to postgres;
revoke all on function public.resolve_rental_rate_card_state(text,timestamptz) from public,anon,authenticated;
grant execute on function public.resolve_rental_rate_card_state(text,timestamptz) to postgres,service_role;
revoke all on function public.get_admin_rental_rate_cards_state() from public,anon,authenticated;
revoke all on function public.create_admin_rental_rate_card_state(text,numeric,numeric,numeric,integer) from public,anon,authenticated;
revoke all on function public.update_admin_rental_rate_card_state(uuid,text,numeric,numeric,numeric,integer) from public,anon,authenticated;
revoke all on function public.set_admin_rental_rate_card_enabled_state(uuid,boolean) from public,anon,authenticated;
grant execute on function public.get_admin_rental_rate_cards_state() to authenticated,service_role;
grant execute on function public.create_admin_rental_rate_card_state(text,numeric,numeric,numeric,integer) to authenticated,service_role;
grant execute on function public.update_admin_rental_rate_card_state(uuid,text,numeric,numeric,numeric,integer) to authenticated,service_role;
grant execute on function public.set_admin_rental_rate_card_enabled_state(uuid,boolean) to authenticated,service_role;
