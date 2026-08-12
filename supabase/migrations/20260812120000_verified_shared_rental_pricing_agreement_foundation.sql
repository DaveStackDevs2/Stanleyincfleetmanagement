-- Verified-live shared rental-pricing-agreement foundation. Data-free repository record only.
-- Pickup, VIN assignment, pricing clocks, calculations, discounts, insurance, payments, and billing allocation remain out of scope.

alter table public.quotes add column if not exists reservation_type text;
update public.quotes set reservation_type = 'rental' where reservation_type is null;
alter table public.quotes alter column reservation_type set not null;
alter table public.quotes drop constraint if exists ck_quotes_reservation_type;
alter table public.quotes add constraint ck_quotes_reservation_type check (reservation_type in ('loaner','rental'));

create table if not exists public.rental_pricing_agreements (
 id uuid primary key default gen_random_uuid(), origin_type text not null,
 quote_id uuid null references public.quotes(id) on delete restrict,
 reservation_id uuid null references public.reservations(id) on delete restrict,
 transportation_event_id uuid not null references public.transportation_events(id) on delete restrict,
 vehicle_class text not null,
 rental_rate_rule_id uuid not null references public.rental_rate_rules(id) on delete restrict,
 pay_type_rule_id uuid not null references public.pay_type_rules(id) on delete restrict,
 initial_rate_plan text not null, current_rate_plan text not null,
 daily_rate_snapshot numeric(12,2) not null, weekly_rate_snapshot numeric(12,2), monthly_rate_snapshot numeric(12,2),
 pricing_started_at timestamptz, is_active boolean not null default true,
 created_by uuid references public.app_users(id) on delete set null,
 updated_by uuid references public.app_users(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_origin_type;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_origin_type check(origin_type in ('quote','reservation','walk_in'));
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_vehicle_class;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_vehicle_class check(btrim(vehicle_class) <> '');
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_rate_plans;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_rate_plans check(initial_rate_plan in ('daily','weekly','monthly') and current_rate_plan in ('daily','weekly','monthly'));
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_rates;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_rates check(
 daily_rate_snapshot >= 0 and daily_rate_snapshot not in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)
 and (weekly_rate_snapshot is null or weekly_rate_snapshot >= 0 and weekly_rate_snapshot not in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric))
 and (monthly_rate_snapshot is null or monthly_rate_snapshot >= 0 and monthly_rate_snapshot not in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)));
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_plan_snapshots;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_plan_snapshots check(
 (initial_rate_plan <> 'weekly' or weekly_rate_snapshot is not null) and (current_rate_plan <> 'weekly' or weekly_rate_snapshot is not null)
 and (initial_rate_plan <> 'monthly' or monthly_rate_snapshot is not null) and (current_rate_plan <> 'monthly' or monthly_rate_snapshot is not null));
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_origin_linkage;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_origin_linkage check(
 (origin_type='quote' and quote_id is not null)
 or (origin_type='reservation' and quote_id is null and reservation_id is not null)
 or (origin_type='walk_in' and quote_id is null and reservation_id is not null));
create unique index if not exists ux_rental_pricing_agreements_quote_id on public.rental_pricing_agreements(quote_id) where quote_id is not null;
create unique index if not exists ux_rental_pricing_agreements_reservation_id on public.rental_pricing_agreements(reservation_id) where reservation_id is not null;
create unique index if not exists ux_rental_pricing_agreements_transportation_event_id on public.rental_pricing_agreements(transportation_event_id) where transportation_event_id is not null;
drop trigger if exists trg_rental_pricing_agreements_updated_at on public.rental_pricing_agreements;
create trigger trg_rental_pricing_agreements_updated_at before update on public.rental_pricing_agreements for each row execute function public.set_updated_at();
alter table public.rental_pricing_agreements enable row level security;
revoke all on table public.rental_pricing_agreements from public,anon,authenticated;
grant select,insert,update on table public.rental_pricing_agreements to service_role;

insert into public.permissions(permission_key,description) values('billing.pricing_agreement_manage','Can create and convert Quotes, Reservations, and Walk-ins with shared rental pricing agreements')
on conflict(permission_key) do update set description=excluded.description;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p where r.role_name='Dev' and p.permission_key='billing.pricing_agreement_manage' on conflict do nothing;

alter table public.billing_lines add column if not exists pricing_agreement_id uuid;
alter table public.billing_lines add column if not exists rate_plan_snapshot text;
alter table public.billing_lines add column if not exists rate_amount_snapshot numeric;
alter table public.billing_lines drop constraint if exists fk_billing_lines_pricing_agreement;
alter table public.billing_lines add constraint fk_billing_lines_pricing_agreement foreign key(pricing_agreement_id) references public.rental_pricing_agreements(id) on delete restrict;
alter table public.billing_lines drop constraint if exists ck_billing_lines_rate_plan_snapshot;
alter table public.billing_lines add constraint ck_billing_lines_rate_plan_snapshot check(rate_plan_snapshot is null or rate_plan_snapshot in ('daily','weekly','monthly'));
alter table public.billing_lines drop constraint if exists ck_billing_lines_rate_amount_snapshot;
alter table public.billing_lines add constraint ck_billing_lines_rate_amount_snapshot check(rate_amount_snapshot is null or rate_amount_snapshot >= 0 and rate_amount_snapshot not in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric));
alter table public.billing_lines drop constraint if exists ck_billing_lines_pricing_snapshot_all_or_none;
alter table public.billing_lines add constraint ck_billing_lines_pricing_snapshot_all_or_none check(num_nonnulls(pricing_agreement_id,rate_plan_snapshot,rate_amount_snapshot) in (0,3));
create index if not exists ix_billing_lines_pricing_agreement_id on public.billing_lines(pricing_agreement_id);

alter table public.rental_rate_rules drop constraint if exists ck_rental_rate_rules_monthly_requires_weekly;
alter table public.rental_rate_rules add constraint ck_rental_rate_rules_monthly_requires_weekly check(monthly_rate is null or weekly_rate is not null);

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
 if p_monthly_rate is not null and p_weekly_rate is null then raise exception 'Weekly rate is required when a monthly rate is configured' using errcode='22023'; end if;
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
 if p_monthly_rate is not null and p_weekly_rate is null then raise exception 'Weekly rate is required when a monthly rate is configured' using errcode='22023'; end if;
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
 if v_at<=v_rule.effective_from then v_at:=v_rule.effective_from+interval '1 microsecond'; end if;
 update public.rental_rate_rules set is_active=p_is_enabled,
 effective_to=case when p_is_enabled then null when is_active then v_at else effective_to end,
 effective_from=case when p_is_enabled and not is_active then v_at else effective_from end,updated_by=v_user where id=p_rental_rate_rule_id returning * into v_rule;
 return jsonb_build_object('status',case when p_is_enabled then 'admin_rental_rate_card_enabled' else 'admin_rental_rate_card_disabled' end,'rental_rate_card',jsonb_build_object('rental_rate_rule_id',v_rule.id,'vehicle_class',v_rule.vehicle_class,'daily_rate',v_rule.daily_rate,'weekly_rate',v_rule.weekly_rate,'monthly_rate',v_rule.monthly_rate,'sort_order',v_rule.sort_order,'is_active',v_rule.is_active,'is_current',v_rule.is_active and v_rule.effective_from<=clock_timestamp() and (v_rule.effective_to is null or v_rule.effective_to>clock_timestamp()),'effective_from',v_rule.effective_from,'effective_to',v_rule.effective_to,'created_at',v_rule.created_at,'updated_at',v_rule.updated_at));
exception when unique_violation then raise exception 'A current rental rate card already exists for this vehicle class' using errcode='23505'; end;$function$;

alter function public.resolve_rental_rate_card_state(text,timestamptz) owner to postgres;
alter function public.get_admin_rental_rate_cards_state() owner to postgres;

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
 if p_monthly_rate is not null and p_weekly_rate is null then raise exception 'Weekly rate is required when a monthly rate is configured' using errcode='22023'; end if;
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
 if v_at<=v_rule.effective_from then v_at:=v_rule.effective_from+interval '1 microsecond'; end if;
 update public.rental_rate_rules set is_active=p_is_enabled,
 effective_to=case when p_is_enabled then null when is_active then v_at else effective_to end,
 effective_from=case when p_is_enabled and not is_active then v_at else effective_from end,updated_by=v_user where id=p_rental_rate_rule_id returning * into v_rule;
 return jsonb_build_object('status',case when p_is_enabled then 'admin_rental_rate_card_enabled' else 'admin_rental_rate_card_disabled' end,'rental_rate_card',jsonb_build_object('rental_rate_rule_id',v_rule.id,'vehicle_class',v_rule.vehicle_class,'daily_rate',v_rule.daily_rate,'weekly_rate',v_rule.weekly_rate,'monthly_rate',v_rule.monthly_rate,'sort_order',v_rule.sort_order,'is_active',v_rule.is_active,'is_current',v_rule.is_active and v_rule.effective_from<=clock_timestamp() and (v_rule.effective_to is null or v_rule.effective_to>clock_timestamp()),'effective_from',v_rule.effective_from,'effective_to',v_rule.effective_to,'created_at',v_rule.created_at,'updated_at',v_rule.updated_at));
exception when unique_violation then raise exception 'A current rental rate card already exists for this vehicle class' using errcode='23505'; end;$function$;

alter function public.resolve_rental_rate_card_state(text,timestamptz) owner to postgres;
alter function public.get_admin_rental_rate_cards_state() owner to postgres;
alter function public.create_admin_rental_rate_card_state(text,numeric,numeric,numeric,integer) owner to postgres;

alter function public.create_admin_rental_rate_card_state(text,numeric,numeric,numeric,integer) owner to postgres;
alter function public.update_admin_rental_rate_card_state(uuid,text,numeric,numeric,numeric,integer) owner to postgres;
revoke all on function public.create_admin_rental_rate_card_state(text,numeric,numeric,numeric,integer) from public,anon;
revoke all on function public.update_admin_rental_rate_card_state(uuid,text,numeric,numeric,numeric,integer) from public,anon;
grant execute on function public.create_admin_rental_rate_card_state(text,numeric,numeric,numeric,integer) to authenticated,service_role;
grant execute on function public.update_admin_rental_rate_card_state(uuid,text,numeric,numeric,numeric,integer) to authenticated,service_role;

create or replace function public.audit_rental_pricing_agreement_state() returns trigger language plpgsql security definer set search_path to '' as $function$
declare v_action text; v_old jsonb; v_new jsonb;
begin
 v_old:=case when tg_op='UPDATE' then to_jsonb(old)-array['updated_at','updated_by'] else null end;
 v_new:=to_jsonb(new)-array['updated_at','updated_by'];
 if tg_op='UPDATE' and v_old=v_new then return new; end if;
 v_action:=case when tg_op='INSERT' then 'creation' when old.reservation_id is null and new.reservation_id is not null and new.origin_type='quote' then 'quote_conversion'
  when old.pricing_started_at is null and new.pricing_started_at is not null then 'pricing_activation'
  when old.current_rate_plan is distinct from new.current_rate_plan then 'plan_change'
  when old.is_active and not new.is_active then 'deactivation' when not old.is_active and new.is_active then 'reactivation' else 'material_update' end;
 insert into public.audit_log(entity_type,entity_id,action_type,field_name,old_value,new_value,metadata,actor_user_id)
 values('rental_pricing_agreement',new.id::text,v_action,'pricing_terms',v_old::text,v_new::text,
 jsonb_build_object('origin_type',new.origin_type,'quote_id',new.quote_id,'reservation_id',new.reservation_id,'transportation_event_id',new.transportation_event_id,'old',v_old,'new',v_new),coalesce(auth.uid()::text,'postgres'));
 return new;
end;$function$;
alter function public.audit_rental_pricing_agreement_state() owner to postgres;
revoke all on function public.audit_rental_pricing_agreement_state() from public,anon,authenticated,service_role;
grant execute on function public.audit_rental_pricing_agreement_state() to postgres;
drop trigger if exists trg_rental_pricing_agreements_audit on public.rental_pricing_agreements;
create trigger trg_rental_pricing_agreements_audit after insert or update on public.rental_pricing_agreements for each row execute function public.audit_rental_pricing_agreement_state();
revoke insert,update,delete,truncate,references,trigger on table public.audit_log from public,anon,authenticated;

revoke insert,update,delete,truncate,references,trigger on table public.quotes from public,anon,authenticated;
revoke truncate,references,trigger on table public.transportation_events,public.reservations,public.vehicle_events,public.contract_periods,public.billing_lines from public,anon,authenticated;
revoke all on function public.create_transportation_event_state(text,uuid,uuid,timestamptz,text,text) from public,anon,authenticated;
grant execute on function public.create_transportation_event_state(text,uuid,uuid,timestamptz,text,text) to service_role;

create or replace function public.create_quote_with_pricing_agreement_state(p_customer_id uuid,p_reservation_type text,p_start_at timestamptz,p_expected_return_at timestamptz,p_vehicle_class text,p_pay_type_rule_id uuid,p_initial_rate_plan text,p_notes text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_quote uuid; v_event uuid; v_rate jsonb; v_pay public.pay_type_rules%rowtype; v_agreement uuid;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null or coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement access denied' using errcode='42501'; end if;
 if p_reservation_type not in ('loaner','rental') or p_start_at is null or p_expected_return_at is null or p_expected_return_at<p_start_at or p_vehicle_class is null or btrim(p_vehicle_class)='' or p_initial_rate_plan not in ('daily','weekly','monthly') then raise exception 'Invalid Quote pricing request' using errcode='22023'; end if;
 select * into v_pay from public.pay_type_rules where id=p_pay_type_rule_id and is_active=true; if not found then raise exception 'Active pay type not found' using errcode='P0002'; end if;
 v_rate:=public.resolve_rental_rate_card_state(btrim(p_vehicle_class),p_start_at); if v_rate->>'status'<>'rental_rate_card_resolved' then raise exception 'Rental rate card not configured' using errcode='P0002'; end if;
 insert into public.quotes(customer_id,reservation_type,vehicle_class,start_date,expected_return_datetime,status,notes,is_active) values(p_customer_id,p_reservation_type,btrim(p_vehicle_class),p_start_at,p_expected_return_at,'quote',nullif(btrim(p_notes),''),true) returning id into v_quote;
 v_event:=(public.create_transportation_event_state('quote',v_quote,p_customer_id,p_expected_return_at,nullif(btrim(p_notes),''),'active')->>'transportation_event_id')::uuid;
 insert into public.rental_pricing_agreements(origin_type,quote_id,transportation_event_id,vehicle_class,rental_rate_rule_id,pay_type_rule_id,initial_rate_plan,current_rate_plan,daily_rate_snapshot,weekly_rate_snapshot,monthly_rate_snapshot,created_by,updated_by)
 values('quote',v_quote,v_event,btrim(p_vehicle_class),(v_rate->>'rental_rate_rule_id')::uuid,v_pay.id,p_initial_rate_plan,p_initial_rate_plan,(v_rate->>'daily_rate')::numeric,(v_rate->>'weekly_rate')::numeric,(v_rate->>'monthly_rate')::numeric,v_user,v_user) returning id into v_agreement;
 return jsonb_build_object('status','quote_with_pricing_agreement_created','quote_id',v_quote,'transportation_event_id',v_event,'pricing_agreement_id',v_agreement);
end;$function$;

create or replace function public.create_reservation_with_pricing_agreement_state(p_customer_id uuid,p_reservation_type text,p_start_at timestamptz,p_expected_return_at timestamptz,p_vehicle_class text,p_pay_type_rule_id uuid,p_initial_rate_plan text,p_notes text,p_service_advisor text,p_ro_number text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_created jsonb; v_rate jsonb; v_pay public.pay_type_rules%rowtype; v_agreement uuid;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null or coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement access denied' using errcode='42501'; end if;
 if p_reservation_type not in ('loaner','rental') or p_initial_rate_plan not in ('daily','weekly','monthly') then raise exception 'Invalid Reservation pricing request' using errcode='22023'; end if;
 select * into v_pay from public.pay_type_rules where id=p_pay_type_rule_id and is_active=true; if not found then raise exception 'Active pay type not found' using errcode='P0002'; end if;
 v_rate:=public.resolve_rental_rate_card_state(btrim(p_vehicle_class),p_start_at); if v_rate->>'status'<>'rental_rate_card_resolved' then raise exception 'Rental rate card not configured' using errcode='P0002'; end if;
 v_created:=public.create_reservation_with_transportation_event_state(p_start_at,p_expected_return_at,btrim(p_vehicle_class),p_reservation_type,'quote',nullif(btrim(p_notes),''),p_customer_id,nullif(btrim(p_service_advisor),''),nullif(btrim(p_ro_number),''),v_pay.pay_type,null);
 insert into public.rental_pricing_agreements(origin_type,reservation_id,transportation_event_id,vehicle_class,rental_rate_rule_id,pay_type_rule_id,initial_rate_plan,current_rate_plan,daily_rate_snapshot,weekly_rate_snapshot,monthly_rate_snapshot,created_by,updated_by)
 values('reservation',(v_created->>'reservation_id')::uuid,(v_created->>'transportation_event_id')::uuid,btrim(p_vehicle_class),(v_rate->>'rental_rate_rule_id')::uuid,v_pay.id,p_initial_rate_plan,p_initial_rate_plan,(v_rate->>'daily_rate')::numeric,(v_rate->>'weekly_rate')::numeric,(v_rate->>'monthly_rate')::numeric,v_user,v_user) returning id into v_agreement;
 return v_created||jsonb_build_object('status','reservation_with_pricing_agreement_created','pricing_agreement_id',v_agreement);
end;$function$;

create or replace function public.convert_quote_to_reservation_with_pricing_agreement_state(p_quote_id uuid,p_service_advisor text,p_ro_number text,p_notes text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_quote public.quotes%rowtype; v_agreement public.rental_pricing_agreements%rowtype; v_event public.transportation_events%rowtype; v_reservation uuid; v_pay public.pay_type_rules%rowtype;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null or coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement access denied' using errcode='42501'; end if;
 select * into v_quote from public.quotes where id=p_quote_id for update; if not found then raise exception 'Quote not found' using errcode='P0002'; end if;
 if v_quote.converted_to_reservation_id is not null then return jsonb_build_object('status','quote_already_converted','quote_id',v_quote.id,'reservation_id',v_quote.converted_to_reservation_id); end if;
 select * into v_agreement from public.rental_pricing_agreements where quote_id=v_quote.id for update; if not found then raise exception 'Quote pricing agreement not found' using errcode='P0002'; end if;
 select * into v_event from public.transportation_events where id=v_agreement.transportation_event_id and status='active' for update; if not found then raise exception 'Active Quote Transportation Event not found' using errcode='P0002'; end if;
 select * into v_pay from public.pay_type_rules where id=v_agreement.pay_type_rule_id and is_active=true;
 insert into public.reservations(vehicle_id,start_date,expected_return_datetime,status,reservation_type,notes,service_advisor,ro_number,pay_type,transportation_event_id,customer_id,requested_model)
 values(null,v_quote.start_date,v_quote.expected_return_datetime,'quote',v_quote.reservation_type,coalesce(nullif(btrim(p_notes),''),v_quote.notes),nullif(btrim(p_service_advisor),''),nullif(btrim(p_ro_number),''),v_pay.pay_type,v_event.id,v_quote.customer_id,v_quote.vehicle_class) returning id into v_reservation;
 update public.quotes set status='converted',is_active=false,converted_to_reservation_id=v_reservation where id=v_quote.id;
 update public.rental_pricing_agreements set reservation_id=v_reservation,updated_by=v_user where id=v_agreement.id;
 return jsonb_build_object('status','quote_converted_to_reservation','quote_id',v_quote.id,'reservation_id',v_reservation,'transportation_event_id',v_event.id,'pricing_agreement_id',v_agreement.id);
end;$function$;

create or replace function public.create_walk_in_with_pricing_agreement_state(p_customer_id uuid,p_reservation_type text,p_start_at timestamptz,p_expected_return_at timestamptz,p_vehicle_class text,p_pay_type_rule_id uuid,p_initial_rate_plan text,p_notes text,p_service_advisor text,p_ro_number text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_event uuid; v_reservation uuid; v_rate jsonb; v_pay public.pay_type_rules%rowtype; v_agreement uuid;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null or coalesce(auth.jwt()->>'aal','')<>'aal2' or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement access denied' using errcode='42501'; end if;
 if p_reservation_type not in ('loaner','rental') or p_initial_rate_plan not in ('daily','weekly','monthly') then raise exception 'Invalid Walk-in pricing request' using errcode='22023'; end if;
 select * into v_pay from public.pay_type_rules where id=p_pay_type_rule_id and is_active=true; if not found then raise exception 'Active pay type not found' using errcode='P0002'; end if;
 v_rate:=public.resolve_rental_rate_card_state(btrim(p_vehicle_class),p_start_at); if v_rate->>'status'<>'rental_rate_card_resolved' then raise exception 'Rental rate card not configured' using errcode='P0002'; end if;
 v_event:=(public.create_transportation_event_state('walk_in',null,p_customer_id,p_expected_return_at,nullif(btrim(p_notes),''),'active')->>'transportation_event_id')::uuid;
 insert into public.reservations(vehicle_id,start_date,expected_return_datetime,status,reservation_type,notes,service_advisor,ro_number,pay_type,transportation_event_id,customer_id,requested_model)
 values(null,p_start_at,p_expected_return_at,'quote',p_reservation_type,nullif(btrim(p_notes),''),nullif(btrim(p_service_advisor),''),nullif(btrim(p_ro_number),''),v_pay.pay_type,v_event,p_customer_id,btrim(p_vehicle_class)) returning id into v_reservation;
 update public.transportation_events set source_id=v_reservation,updated_at=now() where id=v_event;
 insert into public.rental_pricing_agreements(origin_type,reservation_id,transportation_event_id,vehicle_class,rental_rate_rule_id,pay_type_rule_id,initial_rate_plan,current_rate_plan,daily_rate_snapshot,weekly_rate_snapshot,monthly_rate_snapshot,created_by,updated_by)
 values('walk_in',v_reservation,v_event,btrim(p_vehicle_class),(v_rate->>'rental_rate_rule_id')::uuid,v_pay.id,p_initial_rate_plan,p_initial_rate_plan,(v_rate->>'daily_rate')::numeric,(v_rate->>'weekly_rate')::numeric,(v_rate->>'monthly_rate')::numeric,v_user,v_user) returning id into v_agreement;
 return jsonb_build_object('status','walk_in_with_pricing_agreement_created','reservation_id',v_reservation,'transportation_event_id',v_event,'pricing_agreement_id',v_agreement);
end;$function$;

alter function public.create_quote_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text) owner to postgres;
alter function public.create_reservation_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) owner to postgres;
alter function public.convert_quote_to_reservation_with_pricing_agreement_state(uuid,text,text,text) owner to postgres;
alter function public.create_walk_in_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) owner to postgres;
revoke all on function public.create_quote_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text) from public,anon;
revoke all on function public.create_reservation_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) from public,anon;
revoke all on function public.convert_quote_to_reservation_with_pricing_agreement_state(uuid,text,text,text) from public,anon;
revoke all on function public.create_walk_in_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) from public,anon;
grant execute on function public.create_quote_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text) to authenticated,service_role;
grant execute on function public.create_reservation_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) to authenticated,service_role;
grant execute on function public.convert_quote_to_reservation_with_pricing_agreement_state(uuid,text,text,text) to authenticated,service_role;
grant execute on function public.create_walk_in_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) to authenticated,service_role;
