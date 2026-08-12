-- Verified-live shared rental-pricing-agreement foundation. Data-free repository record only.
-- Pickup, VIN assignment, pricing clocks, calculations, discounts, insurance, payments, and billing allocation remain out of scope.

alter table public.quotes add column if not exists reservation_type text;
-- Fail closed: the verified database contained no Quotes when this became required.
-- PostgreSQL's SET NOT NULL validation intentionally rejects incompatible replay data.
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
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_origin;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_origin check(origin_type in ('quote','reservation','walk_in'));
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_vehicle_class;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_vehicle_class check(btrim(vehicle_class) <> '');
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_initial_plan;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_initial_plan check(initial_rate_plan in ('daily','weekly','monthly'));
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_current_plan;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_current_plan check(current_rate_plan in ('daily','weekly','monthly'));
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_daily_rate;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_daily_rate check(daily_rate_snapshot >= 0 and daily_rate_snapshot not in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric));
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_weekly_rate;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_weekly_rate check(weekly_rate_snapshot is null or weekly_rate_snapshot >= 0 and weekly_rate_snapshot not in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric));
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_monthly_rate;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_monthly_rate check(monthly_rate_snapshot is null or monthly_rate_snapshot >= 0 and monthly_rate_snapshot not in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric));
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_initial_plan_rate;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_initial_plan_rate check((initial_rate_plan <> 'weekly' or weekly_rate_snapshot is not null) and (initial_rate_plan <> 'monthly' or monthly_rate_snapshot is not null));
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_current_plan_rate;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_current_plan_rate check((current_rate_plan <> 'weekly' or weekly_rate_snapshot is not null) and (current_rate_plan <> 'monthly' or monthly_rate_snapshot is not null));
alter table public.rental_pricing_agreements drop constraint if exists ck_rental_pricing_agreements_origin_link;
alter table public.rental_pricing_agreements add constraint ck_rental_pricing_agreements_origin_link check(
 (origin_type='quote' and quote_id is not null)
 or (origin_type='reservation' and quote_id is null and reservation_id is not null)
 or (origin_type='walk_in' and quote_id is null and transportation_event_id is not null));
create unique index if not exists ux_rental_pricing_agreements_quote on public.rental_pricing_agreements(quote_id) where quote_id is not null;
create unique index if not exists ux_rental_pricing_agreements_reservation on public.rental_pricing_agreements(reservation_id) where reservation_id is not null;
create unique index if not exists ux_rental_pricing_agreements_transportation_event on public.rental_pricing_agreements(transportation_event_id) where transportation_event_id is not null;
drop trigger if exists trg_rental_pricing_agreements_set_updated_at on public.rental_pricing_agreements;
create trigger trg_rental_pricing_agreements_set_updated_at before update on public.rental_pricing_agreements for each row execute function public.set_updated_at();
alter table public.rental_pricing_agreements enable row level security;
revoke all on table public.rental_pricing_agreements from public,anon,authenticated;
grant all privileges on table public.rental_pricing_agreements to service_role;

insert into public.permissions(permission_key,description) values('billing.pricing_agreement_manage','Can create and convert Quotes, Reservations, and Walk-ins with shared rental pricing agreements')
on conflict(permission_key) do update set description=excluded.description;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p where r.role_name='Dev' and p.permission_key='billing.pricing_agreement_manage' on conflict do nothing;

alter table public.billing_lines add column if not exists pricing_agreement_id uuid;
alter table public.billing_lines add column if not exists rate_plan_snapshot text;
alter table public.billing_lines add column if not exists rate_amount_snapshot numeric;
alter table public.billing_lines drop constraint if exists billing_lines_pricing_agreement_id_fkey;
alter table public.billing_lines add constraint billing_lines_pricing_agreement_id_fkey foreign key(pricing_agreement_id) references public.rental_pricing_agreements(id) on delete restrict;
alter table public.billing_lines drop constraint if exists ck_billing_lines_rate_plan_snapshot;
alter table public.billing_lines add constraint ck_billing_lines_rate_plan_snapshot check(rate_plan_snapshot is null or rate_plan_snapshot in ('daily','weekly','monthly'));
alter table public.billing_lines drop constraint if exists ck_billing_lines_rate_amount_snapshot;
alter table public.billing_lines add constraint ck_billing_lines_rate_amount_snapshot check(rate_amount_snapshot is null or rate_amount_snapshot >= 0 and rate_amount_snapshot not in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric));
alter table public.billing_lines drop constraint if exists ck_billing_lines_pricing_snapshot_complete;
alter table public.billing_lines add constraint ck_billing_lines_pricing_snapshot_complete check(
 (pricing_agreement_id is null and rate_plan_snapshot is null and rate_amount_snapshot is null)
 or (pricing_agreement_id is not null and rate_plan_snapshot is not null and rate_amount_snapshot is not null));
create index if not exists ix_billing_lines_pricing_agreement_id on public.billing_lines(pricing_agreement_id);

alter table public.rental_rate_rules drop constraint if exists ck_rental_rate_rules_monthly_requires_weekly;
alter table public.rental_rate_rules add constraint ck_rental_rate_rules_monthly_requires_weekly check(monthly_rate is null or weekly_rate is not null);

create or replace function public.create_admin_rental_rate_card_state(p_vehicle_class text,p_daily_rate numeric,p_weekly_rate numeric,p_monthly_rate numeric,p_sort_order integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_rule public.rental_rate_rules%rowtype; v_observed_at timestamptz;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='user_admin.manage') then raise exception 'Rental rate administration access denied' using errcode='42501'; end if;
 if p_vehicle_class is null or btrim(p_vehicle_class)='' then raise exception 'Vehicle class cannot be blank' using errcode='22023'; end if;
 if p_daily_rate is null or p_daily_rate<0 or p_daily_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Daily rate must be a finite amount zero or greater' using errcode='22023'; end if;
 if p_weekly_rate is not null and (p_weekly_rate<0 or p_weekly_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Weekly rate must be a finite amount zero or greater' using errcode='22023'; end if;
 if p_monthly_rate is not null and (p_monthly_rate<0 or p_monthly_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Monthly rate must be a finite amount zero or greater' using errcode='22023'; end if;
 if p_monthly_rate is not null and p_weekly_rate is null then raise exception 'Weekly rate is required when a monthly rate is configured' using errcode='22023'; end if;
 if p_sort_order is null or p_sort_order<0 then raise exception 'Sort order must be zero or greater' using errcode='22023'; end if;
 insert into public.rental_rate_rules(vehicle_class,pay_type_rule_id,daily_rate,weekly_rate,monthly_rate,sort_order,is_active,effective_from,created_by,updated_by)
 values(btrim(p_vehicle_class),null,p_daily_rate,p_weekly_rate,p_monthly_rate,p_sort_order,true,clock_timestamp(),v_user,v_user) returning * into v_rule;
 v_observed_at:=clock_timestamp();
 return jsonb_build_object('status','admin_rental_rate_card_created','rental_rate_card',jsonb_build_object('rental_rate_rule_id',v_rule.id,'vehicle_class',v_rule.vehicle_class,'daily_rate',v_rule.daily_rate,'weekly_rate',v_rule.weekly_rate,'monthly_rate',v_rule.monthly_rate,'sort_order',v_rule.sort_order,'is_active',v_rule.is_active,'is_current',v_rule.is_active and v_rule.effective_from<=v_observed_at and (v_rule.effective_to is null or v_rule.effective_to>v_observed_at),'effective_from',v_rule.effective_from,'effective_to',v_rule.effective_to,'created_at',v_rule.created_at,'updated_at',v_rule.updated_at));
exception when unique_violation then raise exception 'A current rental rate card already exists for this vehicle class' using errcode='23505'; end;$function$;

create or replace function public.update_admin_rental_rate_card_state(p_rental_rate_rule_id uuid,p_vehicle_class text,p_daily_rate numeric,p_weekly_rate numeric,p_monthly_rate numeric,p_sort_order integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_rule public.rental_rate_rules%rowtype; v_observed_at timestamptz;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='user_admin.manage') then raise exception 'Rental rate administration access denied' using errcode='42501'; end if;
 if p_rental_rate_rule_id is null then raise exception 'Rental rate rule ID is required' using errcode='22023'; end if;
 if p_vehicle_class is null or btrim(p_vehicle_class)='' then raise exception 'Vehicle class cannot be blank' using errcode='22023'; end if;
 if p_daily_rate is null or p_daily_rate<0 or p_daily_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Daily rate must be a finite amount zero or greater' using errcode='22023'; end if;
 if p_weekly_rate is not null and (p_weekly_rate<0 or p_weekly_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Weekly rate must be a finite amount zero or greater' using errcode='22023'; end if;
 if p_monthly_rate is not null and (p_monthly_rate<0 or p_monthly_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Monthly rate must be a finite amount zero or greater' using errcode='22023'; end if;
 if p_monthly_rate is not null and p_weekly_rate is null then raise exception 'Weekly rate is required when a monthly rate is configured' using errcode='22023'; end if;
 if p_sort_order is null or p_sort_order<0 then raise exception 'Sort order must be zero or greater' using errcode='22023'; end if;
 select * into v_rule from public.rental_rate_rules where id=p_rental_rate_rule_id for update;
 if not found then raise exception 'Rental rate card not found' using errcode='P0002'; end if;
 update public.rental_rate_rules set vehicle_class=btrim(p_vehicle_class),daily_rate=p_daily_rate,weekly_rate=p_weekly_rate,monthly_rate=p_monthly_rate,sort_order=p_sort_order,updated_by=v_user where id=p_rental_rate_rule_id returning * into v_rule;
 v_observed_at:=clock_timestamp();
 return jsonb_build_object('status','admin_rental_rate_card_updated','rental_rate_card',jsonb_build_object('rental_rate_rule_id',v_rule.id,'vehicle_class',v_rule.vehicle_class,'daily_rate',v_rule.daily_rate,'weekly_rate',v_rule.weekly_rate,'monthly_rate',v_rule.monthly_rate,'sort_order',v_rule.sort_order,'is_active',v_rule.is_active,'is_current',v_rule.is_active and v_rule.effective_from<=v_observed_at and (v_rule.effective_to is null or v_rule.effective_to>v_observed_at),'effective_from',v_rule.effective_from,'effective_to',v_rule.effective_to,'created_at',v_rule.created_at,'updated_at',v_rule.updated_at));
exception when unique_violation then raise exception 'A current rental rate card already exists for this vehicle class' using errcode='23505'; end;$function$;

alter function public.create_admin_rental_rate_card_state(text,numeric,numeric,numeric,integer) owner to postgres;
alter function public.update_admin_rental_rate_card_state(uuid,text,numeric,numeric,numeric,integer) owner to postgres;
revoke all on function public.create_admin_rental_rate_card_state(text,numeric,numeric,numeric,integer) from public,anon;
revoke all on function public.update_admin_rental_rate_card_state(uuid,text,numeric,numeric,numeric,integer) from public,anon;
grant execute on function public.create_admin_rental_rate_card_state(text,numeric,numeric,numeric,integer) to authenticated,service_role;
grant execute on function public.update_admin_rental_rate_card_state(uuid,text,numeric,numeric,numeric,integer) to authenticated,service_role;

create or replace function public.audit_rental_pricing_agreement_state() returns trigger
language plpgsql security definer set search_path to '' as $function$
declare v_action text; v_old jsonb; v_new jsonb; v_actor text;
begin
 v_old:=case when tg_op='UPDATE' then jsonb_build_object(
  'origin_type',old.origin_type,'quote_id',old.quote_id,'reservation_id',old.reservation_id,
  'transportation_event_id',old.transportation_event_id,'vehicle_class',old.vehicle_class,
  'rental_rate_rule_id',old.rental_rate_rule_id,'pay_type_rule_id',old.pay_type_rule_id,
  'initial_rate_plan',old.initial_rate_plan,'current_rate_plan',old.current_rate_plan,
  'daily_rate_snapshot',old.daily_rate_snapshot::text,'weekly_rate_snapshot',old.weekly_rate_snapshot::text,
  'monthly_rate_snapshot',old.monthly_rate_snapshot::text,'pricing_started_at',old.pricing_started_at,
  'is_active',old.is_active) else null end;
 v_new:=jsonb_build_object(
  'origin_type',new.origin_type,'quote_id',new.quote_id,'reservation_id',new.reservation_id,
  'transportation_event_id',new.transportation_event_id,'vehicle_class',new.vehicle_class,
  'rental_rate_rule_id',new.rental_rate_rule_id,'pay_type_rule_id',new.pay_type_rule_id,
  'initial_rate_plan',new.initial_rate_plan,'current_rate_plan',new.current_rate_plan,
  'daily_rate_snapshot',new.daily_rate_snapshot::text,'weekly_rate_snapshot',new.weekly_rate_snapshot::text,
  'monthly_rate_snapshot',new.monthly_rate_snapshot::text,'pricing_started_at',new.pricing_started_at,
  'is_active',new.is_active);
 if tg_op='UPDATE' and v_old=v_new then return new; end if;
 v_action:=case when tg_op='INSERT' then 'pricing_agreement_created'
  when old.reservation_id is null and new.reservation_id is not null and new.origin_type='quote' then 'quote_converted_to_reservation'
  when old.pricing_started_at is null and new.pricing_started_at is not null then 'pricing_agreement_activated'
  when old.current_rate_plan is distinct from new.current_rate_plan then 'pricing_plan_changed'
  when old.is_active and not new.is_active then 'pricing_agreement_deactivated'
  when not old.is_active and new.is_active then 'pricing_agreement_reactivated'
  else 'pricing_agreement_updated' end;
 v_actor:=coalesce(new.updated_by::text,new.created_by::text,auth.uid()::text,'system:rental_pricing_agreement');
 insert into public.audit_log(entity_type,entity_id,action_type,field_name,old_value,new_value,metadata,actor_user_id)
 values('rental_pricing_agreement',new.id::text,v_action,'pricing_terms',v_old::text,v_new::text,
 jsonb_build_object('quote_id',new.quote_id,'reservation_id',new.reservation_id,'transportation_event_id',new.transportation_event_id),v_actor);
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

create or replace function public.create_quote_with_pricing_agreement_state(
 p_customer_id uuid,p_vehicle_class text,p_start_date timestamptz,p_expected_return_datetime timestamptz,
 p_reservation_type text,p_pay_type_rule_id uuid,p_initial_rate_plan text,p_notes text default null)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_quote uuid; v_event uuid; v_rate jsonb; v_event_result jsonb; v_pay public.pay_type_rules%rowtype; v_agreement public.rental_pricing_agreements%rowtype; v_at timestamptz:=clock_timestamp(); v_rate_rule uuid;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null then raise exception 'Active application user required' using errcode='42501'; end if;
 if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication required' using errcode='42501'; end if;
 if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement management permission required' using errcode='42501'; end if;
 if p_customer_id is null then raise exception 'Customer ID is required' using errcode='22023'; end if;
 if not exists(select 1 from public.customers where id=p_customer_id) then raise exception 'Customer not found' using errcode='P0002'; end if;
 if p_vehicle_class is null or btrim(p_vehicle_class)='' then raise exception 'Vehicle class cannot be blank' using errcode='22023'; end if;
 if p_start_date is null then raise exception 'Start timestamp is required' using errcode='22023'; end if;
 if p_expected_return_datetime is null then raise exception 'Expected return timestamp is required' using errcode='22023'; end if;
 if p_expected_return_datetime<=p_start_date then raise exception 'Expected return must be after start' using errcode='22023'; end if;
 if p_reservation_type is null or p_reservation_type not in ('loaner','rental') then raise exception 'Reservation type must be loaner or rental' using errcode='22023'; end if;
 if p_initial_rate_plan is null or p_initial_rate_plan not in ('daily','weekly','monthly') then raise exception 'Initial rate plan must be daily, weekly, or monthly' using errcode='22023'; end if;
 if p_pay_type_rule_id is null then raise exception 'Pay type rule ID is required' using errcode='22023'; end if;
 select * into v_pay from public.pay_type_rules where id=p_pay_type_rule_id and is_active=true for share;
 if not found then raise exception 'Active pay type not found' using errcode='P0002'; end if;
 v_rate:=public.resolve_rental_rate_card_state(btrim(p_vehicle_class),v_at);
 if v_rate->>'status'<>'rental_rate_card_resolved' or nullif(v_rate->>'rental_rate_rule_id','') is null then raise exception 'Rental rate card not configured' using errcode='P0001'; end if;
 begin
  v_rate_rule:=(v_rate->>'rental_rate_rule_id')::uuid;
 exception when invalid_text_representation then
  raise exception 'Rental rate card resolution failed' using errcode='P0001';
 end;
 if p_initial_rate_plan='weekly' and (v_rate->>'weekly_rate') is null then raise exception 'Weekly rate is not configured' using errcode='22023'; end if;
 if p_initial_rate_plan='monthly' and (v_rate->>'monthly_rate') is null then raise exception 'Monthly rate is not configured' using errcode='22023'; end if;
 insert into public.quotes(customer_id,reservation_type,vehicle_class,start_date,expected_return_datetime,status,notes,is_active) values(p_customer_id,p_reservation_type,btrim(p_vehicle_class),p_start_date,p_expected_return_datetime,'active',nullif(btrim(p_notes),''),true) returning id into v_quote;
 v_event_result:=public.create_transportation_event_state('quote',v_quote,p_customer_id,p_expected_return_datetime,nullif(btrim(p_notes),''),'active');
 if v_event_result->>'status'<>'transportation_event_created' or nullif(v_event_result->>'transportation_event_id','') is null then raise exception 'Transportation Event creation failed' using errcode='P0001'; end if;
 begin
  v_event:=(v_event_result->>'transportation_event_id')::uuid;
 exception when invalid_text_representation then
  raise exception 'Transportation Event creation failed' using errcode='P0001';
 end;
 insert into public.rental_pricing_agreements(origin_type,quote_id,transportation_event_id,vehicle_class,rental_rate_rule_id,pay_type_rule_id,initial_rate_plan,current_rate_plan,daily_rate_snapshot,weekly_rate_snapshot,monthly_rate_snapshot,created_by,updated_by)
 values('quote',v_quote,v_event,btrim(p_vehicle_class),v_rate_rule,v_pay.id,p_initial_rate_plan,p_initial_rate_plan,(v_rate->>'daily_rate')::numeric,(v_rate->>'weekly_rate')::numeric,(v_rate->>'monthly_rate')::numeric,v_user,v_user) returning * into v_agreement;
 return jsonb_build_object('status','quote_pricing_agreement_created','quote_id',v_quote,'reservation_type',p_reservation_type,'transportation_event_id',v_event,'pricing_agreement_id',v_agreement.id,'origin_type',v_agreement.origin_type,'vehicle_class',v_agreement.vehicle_class,'pay_type_rule_id',v_pay.id,'pay_type',v_pay.pay_type,'initial_rate_plan',v_agreement.initial_rate_plan,'current_rate_plan',v_agreement.current_rate_plan,'daily_rate',v_agreement.daily_rate_snapshot,'weekly_rate',v_agreement.weekly_rate_snapshot,'monthly_rate',v_agreement.monthly_rate_snapshot,'pricing_started_at',v_agreement.pricing_started_at);
end;$function$;

create or replace function public.create_reservation_with_pricing_agreement_state(
 p_customer_id uuid,p_vehicle_class text,p_start_date timestamptz,p_expected_return_datetime timestamptz,
 p_reservation_type text,p_pay_type_rule_id uuid,p_initial_rate_plan text,p_service_advisor text default null,
 p_ro_number text default null,p_notes text default null)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_created jsonb; v_rate jsonb; v_pay public.pay_type_rules%rowtype; v_agreement public.rental_pricing_agreements%rowtype; v_at timestamptz:=clock_timestamp(); v_rate_rule uuid; v_reservation uuid; v_event uuid;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null then raise exception 'Active application user required' using errcode='42501'; end if;
 if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication required' using errcode='42501'; end if;
 if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement management permission required' using errcode='42501'; end if;
 if p_customer_id is null then raise exception 'Customer ID is required' using errcode='22023'; end if;
 if not exists(select 1 from public.customers where id=p_customer_id) then raise exception 'Customer not found' using errcode='P0002'; end if;
 if p_vehicle_class is null or btrim(p_vehicle_class)='' then raise exception 'Vehicle class cannot be blank' using errcode='22023'; end if;
 if p_start_date is null or p_expected_return_datetime is null then raise exception 'Start and expected return timestamps are required' using errcode='22023'; end if;
 if p_expected_return_datetime<=p_start_date then raise exception 'Expected return must be after start' using errcode='22023'; end if;
 if p_reservation_type is null or p_reservation_type not in ('loaner','rental') then raise exception 'Reservation type must be loaner or rental' using errcode='22023'; end if;
 if p_initial_rate_plan is null or p_initial_rate_plan not in ('daily','weekly','monthly') then raise exception 'Initial rate plan must be daily, weekly, or monthly' using errcode='22023'; end if;
 if p_pay_type_rule_id is null then raise exception 'Pay type rule ID is required' using errcode='22023'; end if;
 select * into v_pay from public.pay_type_rules where id=p_pay_type_rule_id and is_active=true for share; if not found then raise exception 'Active pay type not found' using errcode='P0002'; end if;
 v_rate:=public.resolve_rental_rate_card_state(btrim(p_vehicle_class),v_at);
 if v_rate->>'status'<>'rental_rate_card_resolved' or nullif(v_rate->>'rental_rate_rule_id','') is null then raise exception 'Rental rate card not configured' using errcode='P0001'; end if;
 begin
  v_rate_rule:=(v_rate->>'rental_rate_rule_id')::uuid;
 exception when invalid_text_representation then
  raise exception 'Rental rate card resolution failed' using errcode='P0001';
 end;
 if p_initial_rate_plan='weekly' and (v_rate->>'weekly_rate') is null then raise exception 'Weekly rate is not configured' using errcode='22023'; end if;
 if p_initial_rate_plan='monthly' and (v_rate->>'monthly_rate') is null then raise exception 'Monthly rate is not configured' using errcode='22023'; end if;
 v_created:=public.create_reservation_with_transportation_event_state(p_start_date,p_expected_return_datetime,btrim(p_vehicle_class),p_reservation_type,'quote',nullif(btrim(p_notes),''),p_customer_id,nullif(btrim(p_service_advisor),''),nullif(btrim(p_ro_number),''),v_pay.pay_type,null);
 if v_created->>'status'<>'reservation_with_transportation_event_created' or nullif(v_created->>'reservation_id','') is null or nullif(v_created->>'transportation_event_id','') is null then raise exception 'Reservation creation failed' using errcode='P0001'; end if;
 begin
  v_reservation:=(v_created->>'reservation_id')::uuid;
  v_event:=(v_created->>'transportation_event_id')::uuid;
 exception when invalid_text_representation then
  raise exception 'Reservation creation failed' using errcode='P0001';
 end;
 insert into public.rental_pricing_agreements(origin_type,reservation_id,transportation_event_id,vehicle_class,rental_rate_rule_id,pay_type_rule_id,initial_rate_plan,current_rate_plan,daily_rate_snapshot,weekly_rate_snapshot,monthly_rate_snapshot,created_by,updated_by)
 values('reservation',v_reservation,v_event,btrim(p_vehicle_class),v_rate_rule,v_pay.id,p_initial_rate_plan,p_initial_rate_plan,(v_rate->>'daily_rate')::numeric,(v_rate->>'weekly_rate')::numeric,(v_rate->>'monthly_rate')::numeric,v_user,v_user) returning * into v_agreement;
 return jsonb_build_object('status','reservation_pricing_agreement_created','reservation_id',v_reservation,'reservation_status','quote','reservation_type',p_reservation_type,'transportation_event_id',v_event,'pricing_agreement_id',v_agreement.id,'origin_type',v_agreement.origin_type,'vehicle_class',v_agreement.vehicle_class,'pay_type_rule_id',v_pay.id,'pay_type',v_pay.pay_type,'initial_rate_plan',v_agreement.initial_rate_plan,'current_rate_plan',v_agreement.current_rate_plan,'daily_rate',v_agreement.daily_rate_snapshot,'weekly_rate',v_agreement.weekly_rate_snapshot,'monthly_rate',v_agreement.monthly_rate_snapshot,'pricing_started_at',v_agreement.pricing_started_at);
end;$function$;

create or replace function public.create_walk_in_with_pricing_agreement_state(
 p_customer_id uuid,p_vehicle_class text,p_start_date timestamptz,p_expected_return_datetime timestamptz,
 p_reservation_type text,p_pay_type_rule_id uuid,p_initial_rate_plan text,p_service_advisor text default null,
 p_ro_number text default null,p_notes text default null)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_event_result jsonb; v_rate jsonb; v_pay public.pay_type_rules%rowtype; v_agreement public.rental_pricing_agreements%rowtype; v_at timestamptz:=clock_timestamp(); v_rate_rule uuid; v_reservation uuid; v_event uuid;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null then raise exception 'Active application user required' using errcode='42501'; end if;
 if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication required' using errcode='42501'; end if;
 if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement management permission required' using errcode='42501'; end if;
 if p_customer_id is null then raise exception 'Customer ID is required' using errcode='22023'; end if;
 if not exists(select 1 from public.customers where id=p_customer_id) then raise exception 'Customer not found' using errcode='P0002'; end if;
 if p_vehicle_class is null or btrim(p_vehicle_class)='' then raise exception 'Vehicle class cannot be blank' using errcode='22023'; end if;
 if p_start_date is null or p_expected_return_datetime is null then raise exception 'Start and expected return timestamps are required' using errcode='22023'; end if;
 if p_expected_return_datetime<=p_start_date then raise exception 'Expected return must be after start' using errcode='22023'; end if;
 if p_reservation_type is null or p_reservation_type not in ('loaner','rental') then raise exception 'Reservation type must be loaner or rental' using errcode='22023'; end if;
 if p_initial_rate_plan is null or p_initial_rate_plan not in ('daily','weekly','monthly') then raise exception 'Initial rate plan must be daily, weekly, or monthly' using errcode='22023'; end if;
 if p_pay_type_rule_id is null then raise exception 'Pay type rule ID is required' using errcode='22023'; end if;
 select * into v_pay from public.pay_type_rules where id=p_pay_type_rule_id and is_active=true for share; if not found then raise exception 'Active pay type not found' using errcode='P0002'; end if;
 v_rate:=public.resolve_rental_rate_card_state(btrim(p_vehicle_class),v_at);
 if v_rate->>'status'<>'rental_rate_card_resolved' or nullif(v_rate->>'rental_rate_rule_id','') is null then raise exception 'Rental rate card not configured' using errcode='P0001'; end if;
 begin
  v_rate_rule:=(v_rate->>'rental_rate_rule_id')::uuid;
 exception when invalid_text_representation then
  raise exception 'Rental rate card resolution failed' using errcode='P0001';
 end;
 if p_initial_rate_plan='weekly' and (v_rate->>'weekly_rate') is null then raise exception 'Weekly rate is not configured' using errcode='22023'; end if;
 if p_initial_rate_plan='monthly' and (v_rate->>'monthly_rate') is null then raise exception 'Monthly rate is not configured' using errcode='22023'; end if;
 v_event_result:=public.create_transportation_event_state('walk_in',null,p_customer_id,p_expected_return_datetime,nullif(btrim(p_notes),''),'active');
 if v_event_result->>'status'<>'transportation_event_created' or nullif(v_event_result->>'transportation_event_id','') is null then raise exception 'Transportation Event creation failed' using errcode='P0001'; end if;
 begin
  v_event:=(v_event_result->>'transportation_event_id')::uuid;
 exception when invalid_text_representation then
  raise exception 'Transportation Event creation failed' using errcode='P0001';
 end;
 insert into public.reservations(vehicle_id,start_date,expected_return_datetime,status,reservation_type,notes,service_advisor,ro_number,pay_type,transportation_event_id,customer_id,requested_model)
 values(null,p_start_date,p_expected_return_datetime,'quote',p_reservation_type,nullif(btrim(p_notes),''),nullif(btrim(p_service_advisor),''),nullif(btrim(p_ro_number),''),v_pay.pay_type,v_event,p_customer_id,btrim(p_vehicle_class)) returning id into v_reservation;
 update public.transportation_events set source_id=v_reservation,updated_at=v_at where id=v_event;
 insert into public.rental_pricing_agreements(origin_type,reservation_id,transportation_event_id,vehicle_class,rental_rate_rule_id,pay_type_rule_id,initial_rate_plan,current_rate_plan,daily_rate_snapshot,weekly_rate_snapshot,monthly_rate_snapshot,created_by,updated_by)
 values('walk_in',v_reservation,v_event,btrim(p_vehicle_class),v_rate_rule,v_pay.id,p_initial_rate_plan,p_initial_rate_plan,(v_rate->>'daily_rate')::numeric,(v_rate->>'weekly_rate')::numeric,(v_rate->>'monthly_rate')::numeric,v_user,v_user) returning * into v_agreement;
 return jsonb_build_object('status','walk_in_pricing_agreement_created','reservation_id',v_reservation,'reservation_status','quote','reservation_type',p_reservation_type,'transportation_event_id',v_event,'pricing_agreement_id',v_agreement.id,'origin_type',v_agreement.origin_type,'vehicle_class',v_agreement.vehicle_class,'pay_type_rule_id',v_pay.id,'pay_type',v_pay.pay_type,'initial_rate_plan',v_agreement.initial_rate_plan,'current_rate_plan',v_agreement.current_rate_plan,'daily_rate',v_agreement.daily_rate_snapshot,'weekly_rate',v_agreement.weekly_rate_snapshot,'monthly_rate',v_agreement.monthly_rate_snapshot,'pricing_started_at',v_agreement.pricing_started_at);
end;$function$;

create or replace function public.convert_quote_to_reservation_with_pricing_agreement_state(
 p_quote_id uuid,p_service_advisor text default null,p_ro_number text default null,p_notes text default null)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_quote public.quotes%rowtype; v_agreement public.rental_pricing_agreements%rowtype; v_event public.transportation_events%rowtype; v_reservation public.reservations%rowtype; v_pay public.pay_type_rules%rowtype; v_status text;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null then raise exception 'Active application user required' using errcode='42501'; end if;
 if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication required' using errcode='42501'; end if;
 if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing agreement management permission required' using errcode='42501'; end if;
 if p_quote_id is null then raise exception 'Quote ID is required' using errcode='22023'; end if;
 select * into v_quote from public.quotes where id=p_quote_id for update; if not found then raise exception 'Quote not found' using errcode='P0002'; end if;
 select * into v_agreement from public.rental_pricing_agreements where quote_id=v_quote.id for update;
 if not found or v_agreement.origin_type<>'quote' or not v_agreement.is_active then raise exception 'Active Quote pricing agreement not found' using errcode='P0002'; end if;
 select * into v_pay from public.pay_type_rules where id=v_agreement.pay_type_rule_id for share; if not found then raise exception 'Pricing agreement pay type not found' using errcode='P0002'; end if;
 select * into v_event from public.transportation_events where id=v_agreement.transportation_event_id for update;
 if not found or v_event.source_type<>'quote' or v_event.source_id is distinct from v_quote.id or v_event.status<>'active' then raise exception 'Active Quote Transportation Event is inconsistent' using errcode='P0002'; end if;
 if v_quote.converted_to_reservation_id is not null then
  if v_agreement.reservation_id is distinct from v_quote.converted_to_reservation_id then raise exception 'Converted Quote pricing agreement is inconsistent' using errcode='P0001'; end if;
  select * into v_reservation from public.reservations where id=v_quote.converted_to_reservation_id for share;
  if not found or v_reservation.transportation_event_id is distinct from v_event.id then raise exception 'Converted Quote Reservation is inconsistent' using errcode='P0001'; end if;
  v_status:='quote_already_converted';
 else
  if not v_quote.is_active or v_quote.status<>'active' then raise exception 'Quote is not active' using errcode='P0001'; end if;
  if v_quote.customer_id is null then raise exception 'Quote customer is required' using errcode='P0001'; end if;
  if v_agreement.reservation_id is not null then raise exception 'Quote pricing agreement conversion is inconsistent' using errcode='P0001'; end if;
  insert into public.reservations(vehicle_id,start_date,expected_return_datetime,status,reservation_type,notes,service_advisor,ro_number,pay_type,transportation_event_id,customer_id,requested_model)
  values(null,v_quote.start_date,v_quote.expected_return_datetime,'quote',v_quote.reservation_type,coalesce(nullif(btrim(p_notes),''),v_quote.notes),nullif(btrim(p_service_advisor),''),nullif(btrim(p_ro_number),''),v_pay.pay_type,v_event.id,v_quote.customer_id,v_agreement.vehicle_class) returning * into v_reservation;
  update public.quotes set status='converted',is_active=false,converted_to_reservation_id=v_reservation.id where id=v_quote.id;
  update public.rental_pricing_agreements set reservation_id=v_reservation.id,updated_by=v_user where id=v_agreement.id returning * into v_agreement;
  v_status:='quote_converted_to_reservation';
 end if;
 return jsonb_build_object('status',v_status,'quote_id',v_quote.id,'reservation_id',v_reservation.id,'reservation_status','quote','reservation_type',v_quote.reservation_type,'transportation_event_id',v_event.id,'pricing_agreement_id',v_agreement.id,'origin_type','quote','vehicle_class',v_agreement.vehicle_class,'pay_type_rule_id',v_agreement.pay_type_rule_id,'pay_type',v_pay.pay_type,'initial_rate_plan',v_agreement.initial_rate_plan,'current_rate_plan',v_agreement.current_rate_plan,'daily_rate',v_agreement.daily_rate_snapshot,'weekly_rate',v_agreement.weekly_rate_snapshot,'monthly_rate',v_agreement.monthly_rate_snapshot,'pricing_started_at',v_agreement.pricing_started_at);
end;$function$;

alter function public.create_quote_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text) owner to postgres;
alter function public.create_reservation_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) owner to postgres;
alter function public.create_walk_in_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) owner to postgres;
alter function public.convert_quote_to_reservation_with_pricing_agreement_state(uuid,text,text,text) owner to postgres;
revoke all on function public.create_quote_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text) from public,anon;
revoke all on function public.create_reservation_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) from public,anon;
revoke all on function public.create_walk_in_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) from public,anon;
revoke all on function public.convert_quote_to_reservation_with_pricing_agreement_state(uuid,text,text,text) from public,anon;
grant execute on function public.create_quote_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text) to authenticated,service_role;
grant execute on function public.create_reservation_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) to authenticated,service_role;
grant execute on function public.create_walk_in_with_pricing_agreement_state(uuid,text,timestamptz,timestamptz,text,uuid,text,text,text,text) to authenticated,service_role;
grant execute on function public.convert_quote_to_reservation_with_pricing_agreement_state(uuid,text,text,text) to authenticated,service_role;
