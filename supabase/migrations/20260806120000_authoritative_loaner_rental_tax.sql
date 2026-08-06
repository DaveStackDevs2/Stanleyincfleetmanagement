-- Billing Phase 4: authoritative, exact loaner/rental tax and immutable snapshots.
-- Exact arithmetic contract example: 69.95 * 0.10 = 6.995 (never rounded).

update public.pay_type_rules
set tax_applicable = is_taxable, updated_at = clock_timestamp()
where tax_applicable is distinct from is_taxable;

insert into public.admin_settings (setting_key, setting_value, description)
values ('billing.loaner_rental_tax_rate', '0.10'::jsonb,
  'Administrative loaner and rental tax rate stored as a decimal fraction; 0.10 represents 10 percent.')
on conflict (setting_key) do update set setting_value = excluded.setting_value, description = excluded.description;

alter table public.pay_type_rules alter column tax_applicable set not null;
alter table public.pay_type_rules drop constraint if exists ck_pay_type_rules_only_warranty_tax_exempt;
alter table public.pay_type_rules add constraint ck_pay_type_rules_only_warranty_tax_exempt check (
  tax_applicable = is_taxable and
  is_taxable = (pay_type not in ('GM Warranty', 'Extended Warranty'))
);

alter table public.billing_lines add column if not exists tax_rate_snapshot numeric(7,6);
alter table public.billing_lines add column if not exists is_taxable_snapshot boolean;
alter table public.billing_lines add column if not exists tax_rate_source_snapshot text;
alter table public.billing_lines alter column tax_rate_snapshot set not null;
alter table public.billing_lines alter column is_taxable_snapshot set not null;
alter table public.billing_lines alter column tax_rate_source_snapshot set not null;
alter table public.billing_lines drop constraint if exists ck_billing_lines_tax_rate_snapshot;
alter table public.billing_lines add constraint ck_billing_lines_tax_rate_snapshot check (tax_rate_snapshot between 0 and 1);
alter table public.billing_lines drop constraint if exists ck_billing_lines_tax_rate_source_snapshot;
alter table public.billing_lines add constraint ck_billing_lines_tax_rate_source_snapshot check (btrim(tax_rate_source_snapshot) <> '');

create or replace function public.resolve_billing_tax_state(p_pay_type text, p_taxable_base numeric) returns jsonb
language plpgsql security invoker set search_path to '' as $function$
declare v_rule public.pay_type_rules%rowtype; v_rate numeric; v_taxable boolean; v_source text; v_explanation text; v_pay_type text := btrim(p_pay_type);
begin
  if p_pay_type is null or v_pay_type = '' then raise exception 'Pay type is required' using errcode='22023'; end if;
  if p_taxable_base is null or p_taxable_base < 0 or p_taxable_base in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then
    raise exception 'Taxable base must be a finite amount zero or greater' using errcode='22023';
  end if;
  select * into v_rule from public.pay_type_rules where pay_type=v_pay_type;
  if not found then raise exception 'Pay type not found' using errcode='22023'; end if;
  if v_rule.is_active is distinct from true or coalesce(v_rule.active,false) is distinct from true then
    raise exception 'Pay type is inactive' using errcode='22023';
  end if;
  v_taxable := v_rule.pay_type not in ('GM Warranty','Extended Warranty');
  if v_rule.is_taxable is distinct from v_taxable or v_rule.tax_applicable is distinct from v_taxable then
    raise exception 'Pay type tax configuration violates the fixed exemption rule' using errcode='22023';
  end if;
  if not v_taxable then v_rate:=0; v_source:='pay_type_exemption'; v_explanation:=v_rule.pay_type || ' is exempt from loaner and rental tax.';
  else
    select case when jsonb_typeof(setting_value) = 'number' then (setting_value #>> '{}')::numeric end
      into v_rate from public.admin_settings where setting_key='billing.loaner_rental_tax_rate';
    if v_rate is null or v_rate < 0 or v_rate > 1 or v_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Loaner and rental tax rate is invalid' using errcode='22023'; end if;
    v_source:='admin_settings:billing.loaner_rental_tax_rate'; v_explanation:='Loaner and rental tax is calculated exactly without rounding and transferred as a separate tax line.';
  end if;
  return jsonb_build_object('status','billing_tax_resolved','pay_type_rule_id',v_rule.id,'pay_type',v_rule.pay_type,
    'taxable_base',p_taxable_base,'is_taxable',v_taxable,'tax_rate',v_rate,'tax_amount',p_taxable_base*v_rate,
    'tax_rate_source',v_source,'explanation',v_explanation);
end $function$;
alter function public.resolve_billing_tax_state(text,numeric) owner to postgres;
revoke all on function public.resolve_billing_tax_state(text,numeric) from public, anon, authenticated;
grant execute on function public.resolve_billing_tax_state(text,numeric) to service_role;

create or replace function public.ensure_tax_child_line_state(p_parent_billing_line_id uuid) returns jsonb
language plpgsql security invoker set search_path to '' as $function$
declare v_parent record; v_child record; v_id uuid;
begin
 select * into v_parent from public.billing_lines where id=p_parent_billing_line_id and line_type is distinct from 'tax' for update;
 if not found then raise exception 'Parent billing line does not exist or is itself a tax line' using errcode='22023'; end if;
 select * into v_child from public.billing_lines where parent_billing_line_id=p_parent_billing_line_id and line_type='tax' for update;
 if coalesce(v_parent.tax_amount,0)<=0 then
   if found then delete from public.billing_lines where id=v_child.id; return jsonb_build_object('status','tax_child_removed','parent_billing_line_id',p_parent_billing_line_id); end if;
   return jsonb_build_object('status','no_tax_child_needed','parent_billing_line_id',p_parent_billing_line_id);
 end if;
 if found then
   update public.billing_lines set transportation_event_id=v_parent.transportation_event_id,reservation_id=v_parent.reservation_id,vehicle_id=v_parent.vehicle_id,
    vehicle_event_id=v_parent.vehicle_event_id,contract_period_id=v_parent.contract_period_id,pay_type=v_parent.pay_type,pay_type_rule_id=v_parent.pay_type_rule_id,
    amount=v_parent.tax_amount,tax_amount=0,start_time=v_parent.start_time,end_time=v_parent.end_time,source_rule=v_parent.source_rule,is_open=v_parent.is_open,
    tax_rate_snapshot=v_parent.tax_rate_snapshot,is_taxable_snapshot=v_parent.is_taxable_snapshot,tax_rate_source_snapshot=v_parent.tax_rate_source_snapshot,updated_at=clock_timestamp()
   where id=v_child.id;
   return jsonb_build_object('status','tax_child_updated','parent_billing_line_id',p_parent_billing_line_id,'tax_billing_line_id',v_child.id);
 end if;
 insert into public.billing_lines (transportation_event_id,reservation_id,vehicle_id,pay_type,amount,tax_amount,start_time,end_time,source_rule,vehicle_event_id,
 contract_period_id,pay_type_rule_id,line_type,parent_billing_line_id,warranty_provider_id,default_covered_days_snapshot,covered_days_override,is_open,updated_at,
 paid_through_at,extended_from_billing_line_id,default_daily_rate_snapshot,daily_rate_override,tax_rate_snapshot,is_taxable_snapshot,tax_rate_source_snapshot)
 values(v_parent.transportation_event_id,v_parent.reservation_id,v_parent.vehicle_id,v_parent.pay_type,v_parent.tax_amount,0,v_parent.start_time,v_parent.end_time,v_parent.source_rule,
 v_parent.vehicle_event_id,v_parent.contract_period_id,v_parent.pay_type_rule_id,'tax',v_parent.id,v_parent.warranty_provider_id,v_parent.default_covered_days_snapshot,
 v_parent.covered_days_override,v_parent.is_open,clock_timestamp(),v_parent.paid_through_at,v_parent.extended_from_billing_line_id,v_parent.default_daily_rate_snapshot,
 v_parent.daily_rate_override,v_parent.tax_rate_snapshot,v_parent.is_taxable_snapshot,v_parent.tax_rate_source_snapshot) returning id into v_id;
 return jsonb_build_object('status','tax_child_created','parent_billing_line_id',p_parent_billing_line_id,'tax_billing_line_id',v_id);
end $function$;
alter function public.ensure_tax_child_line_state(uuid) owner to postgres;
revoke all on function public.ensure_tax_child_line_state(uuid) from public,anon,authenticated;
grant execute on function public.ensure_tax_child_line_state(uuid) to service_role;

create or replace function public.create_billing_parent_line_state(p_transportation_event_id uuid,p_reservation_id uuid,p_vehicle_id uuid,p_pay_type text,p_amount numeric,p_tax_amount numeric,p_start_time timestamptz,p_end_time timestamptz default null,p_source_rule text default null,p_vehicle_event_id uuid default null,p_contract_period_id uuid default null,p_line_type text default 'initial_assignment',p_warranty_provider_id uuid default null,p_default_covered_days_snapshot integer default null,p_covered_days_override integer default null,p_is_open boolean default true,p_paid_through_at timestamptz default null,p_extended_from_billing_line_id uuid default null,p_default_daily_rate_snapshot numeric default null,p_daily_rate_override numeric default null) returns jsonb
language plpgsql security invoker set search_path to '' as $function$
declare v_tax jsonb; v_id uuid; v_child jsonb; v_base numeric:=coalesce(p_amount,0); v_resolved numeric; v_rule_id uuid;
begin
 if p_start_time is null then raise exception 'Billing start time is required' using errcode='22023'; end if;
 if not exists(select 1 from public.transportation_events where id=p_transportation_event_id) then raise exception 'Transportation event does not exist' using errcode='22023'; end if;
 if p_vehicle_id is not null and not exists(select 1 from public.vehicles where id=p_vehicle_id) then raise exception 'Vehicle does not exist' using errcode='22023'; end if;
 if p_vehicle_event_id is not null and not exists(select 1 from public.vehicle_events where id=p_vehicle_event_id) then raise exception 'Vehicle event does not exist' using errcode='22023'; end if;
 if p_contract_period_id is not null and not exists(select 1 from public.contract_periods where id=p_contract_period_id) then raise exception 'Contract period does not exist' using errcode='22023'; end if;
 if p_end_time is not null and p_end_time<p_start_time then raise exception 'End time cannot precede start time' using errcode='22023'; end if;
 if p_paid_through_at is not null and p_paid_through_at<p_start_time then raise exception 'Paid-through time cannot precede start time' using errcode='22023'; end if;
 select id into v_rule_id from public.pay_type_rules where pay_type=btrim(p_pay_type);
 v_tax:=public.resolve_billing_tax_state(p_pay_type,v_base);
 if jsonb_typeof(v_tax) <> 'object'
    or v_tax->>'status' <> 'billing_tax_resolved'
    or jsonb_typeof(v_tax->'pay_type_rule_id') <> 'string'
    or (v_tax->>'pay_type_rule_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or (v_tax->>'pay_type_rule_id')::uuid is distinct from v_rule_id
    or jsonb_typeof(v_tax->'tax_amount') <> 'number'
    or jsonb_typeof(v_tax->'tax_rate') <> 'number'
    or jsonb_typeof(v_tax->'is_taxable') <> 'boolean'
    or jsonb_typeof(v_tax->'tax_rate_source') <> 'string' or btrim(v_tax->>'tax_rate_source') = ''
    or jsonb_typeof(v_tax->'explanation') <> 'string' or btrim(v_tax->>'explanation') = '' then
   raise exception 'Billing tax resolution returned an invalid result' using errcode='22023';
 end if;
 v_resolved:=(v_tax->>'tax_amount')::numeric;
 if p_tax_amount is not null and p_tax_amount is distinct from v_resolved then raise exception 'Submitted tax amount does not match the authoritative calculation' using errcode='22023'; end if;
 insert into public.billing_lines(transportation_event_id,reservation_id,vehicle_id,pay_type,amount,tax_amount,start_time,end_time,source_rule,vehicle_event_id,contract_period_id,pay_type_rule_id,line_type,parent_billing_line_id,warranty_provider_id,default_covered_days_snapshot,covered_days_override,is_open,updated_at,paid_through_at,extended_from_billing_line_id,default_daily_rate_snapshot,daily_rate_override,tax_rate_snapshot,is_taxable_snapshot,tax_rate_source_snapshot)
 values(p_transportation_event_id,p_reservation_id,p_vehicle_id,p_pay_type,v_base,v_resolved,p_start_time,p_end_time,p_source_rule,p_vehicle_event_id,p_contract_period_id,(v_tax->>'pay_type_rule_id')::uuid,p_line_type,null,p_warranty_provider_id,p_default_covered_days_snapshot,p_covered_days_override,p_is_open,clock_timestamp(),p_paid_through_at,p_extended_from_billing_line_id,p_default_daily_rate_snapshot,p_daily_rate_override,(v_tax->>'tax_rate')::numeric,(v_tax->>'is_taxable')::boolean,v_tax->>'tax_rate_source') returning id into v_id;
 v_child:=public.ensure_tax_child_line_state(v_id);
 return jsonb_build_object('status','parent_billing_line_created','parent_billing_line_id',v_id,'pay_type_rule_id',v_tax->'pay_type_rule_id','amount',v_base,'tax_amount',v_resolved,'total_amount',v_base+v_resolved,'tax_rate',v_tax->'tax_rate','is_taxable',v_tax->'is_taxable','tax_rate_source',v_tax->'tax_rate_source','tax_explanation',v_tax->'explanation','tax_result',v_child);
end $function$;
alter function public.create_billing_parent_line_state(uuid,uuid,uuid,text,numeric,numeric,timestamptz,timestamptz,text,uuid,uuid,text,uuid,integer,integer,boolean,timestamptz,uuid,numeric,numeric) owner to postgres;
revoke all on function public.create_billing_parent_line_state(uuid,uuid,uuid,text,numeric,numeric,timestamptz,timestamptz,text,uuid,uuid,text,uuid,integer,integer,boolean,timestamptz,uuid,numeric,numeric) from public,anon,authenticated;
grant execute on function public.create_billing_parent_line_state(uuid,uuid,uuid,text,numeric,numeric,timestamptz,timestamptz,text,uuid,uuid,text,uuid,integer,integer,boolean,timestamptz,uuid,numeric,numeric) to service_role;

create or replace function public.get_admin_loaner_rental_tax_state() returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_rate numeric;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='user_admin.manage') then raise exception 'Loaner and rental tax administration access denied' using errcode='42501'; end if;
 begin select (setting_value#>>'{}')::numeric into v_rate from public.admin_settings where setting_key='billing.loaner_rental_tax_rate'; exception when others then raise exception 'Loaner and rental tax rate is invalid' using errcode='22023'; end;
 if v_rate is null or v_rate<0 or v_rate>1 or v_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Loaner and rental tax rate is invalid' using errcode='22023'; end if;
 return jsonb_build_object('status','admin_loaner_rental_tax_ready','can_manage',true,'setting_key','billing.loaner_rental_tax_rate','tax_rate',v_rate,'tax_percentage',v_rate*100,'calculation_mode','exact_no_rounding','tax_line_mode','separate_child_line','exempt_pay_types',jsonb_build_array('GM Warranty','Extended Warranty'));
end $function$;

create or replace function public.set_admin_loaner_rental_tax_rate_state(p_tax_rate numeric) returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_previous numeric;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null or not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='user_admin.manage') then raise exception 'Loaner and rental tax administration access denied' using errcode='42501'; end if;
 if p_tax_rate is null or p_tax_rate<=0 or p_tax_rate>1 or p_tax_rate in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Tax rate must be finite, greater than zero, and no greater than one' using errcode='22023'; end if;
 select (setting_value#>>'{}')::numeric into v_previous from public.admin_settings where setting_key='billing.loaner_rental_tax_rate' for update;
 insert into public.admin_settings(setting_key,setting_value,description) values('billing.loaner_rental_tax_rate',to_jsonb(p_tax_rate),'Administrative loaner and rental tax rate stored as a decimal fraction; 0.10 represents 10 percent.') on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description;
 return jsonb_build_object('status','admin_loaner_rental_tax_updated','setting_key','billing.loaner_rental_tax_rate','previous_tax_rate',v_previous,'tax_rate',p_tax_rate,'tax_percentage',p_tax_rate*100,'calculation_mode','exact_no_rounding','tax_line_mode','separate_child_line');
end $function$;
alter function public.get_admin_loaner_rental_tax_state() owner to postgres; alter function public.set_admin_loaner_rental_tax_rate_state(numeric) owner to postgres;
revoke all on function public.get_admin_loaner_rental_tax_state() from public,anon; revoke all on function public.set_admin_loaner_rental_tax_rate_state(numeric) from public,anon;
grant execute on function public.get_admin_loaner_rental_tax_state() to authenticated,service_role; grant execute on function public.set_admin_loaner_rental_tax_rate_state(numeric) to authenticated,service_role;

-- Browser callers must use authoritative orchestration rather than supplying amounts/tax.
revoke all on function public.create_transportation_event_billing_line_state(uuid,text,numeric,numeric,timestamptz,timestamptz,text,timestamptz,text) from public,anon,authenticated;
grant execute on function public.create_transportation_event_billing_line_state(uuid,text,numeric,numeric,timestamptz,timestamptz,text,timestamptz,text) to service_role;
revoke all on function public.accept_transportation_event_extension_state(uuid,timestamptz,numeric,numeric,text,text,uuid,boolean) from public,anon,authenticated;
grant execute on function public.accept_transportation_event_extension_state(uuid,timestamptz,numeric,numeric,text,text,uuid,boolean) to service_role;

CREATE OR REPLACE FUNCTION public.create_admin_pay_type_rule_state(p_pay_type text, p_is_taxable boolean, p_default_daily_amount numeric, p_sort_order integer, p_description text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid;
  v_access jsonb;
  v_rule public.pay_type_rules%rowtype;
begin
  select au.id
    into v_user_id
  from public.app_users au
  where au.auth_user_id = auth.uid()
    and au.is_active = true;

  if v_user_id is null then
    raise exception 'Pay type administration access denied'
      using errcode = '42501';
  end if;

  v_access :=
    public.get_user_admin_setting_access_state(
      v_user_id,
      'fleet_board.pay_type_colors'
    );

  if coalesce((v_access ->> 'allowed')::boolean, false) is not true then
    raise exception 'Pay type administration access denied'
      using errcode = '42501';
  end if;

  if p_pay_type is null or btrim(p_pay_type) = '' then
    raise exception 'Pay type name cannot be blank'
      using errcode = '22023';
  end if;

  if p_is_taxable is distinct from true then
    raise exception 'New pay types must be taxable; only GM Warranty and Extended Warranty are tax-exempt'
      using errcode = '22023';
  end if;

  if p_sort_order is null or p_sort_order < 0 then
    raise exception 'Sort order must be zero or greater'
      using errcode = '22023';
  end if;

  if p_default_daily_amount is not null
     and p_default_daily_amount < 0
  then
    raise exception 'Default daily amount must be zero or greater'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.pay_type_rules rule
    where lower(btrim(rule.pay_type)) = lower(btrim(p_pay_type))
  ) then
    raise exception 'Pay type already exists'
      using errcode = '23505';
  end if;

  insert into public.pay_type_rules (
    pay_type,
    tax_applicable,
    active,
    is_active,
    is_taxable,
    default_daily_amount,
    sort_order,
    description
  )
  values (
    btrim(p_pay_type),
    true,
    true,
    true,
    true,
    p_default_daily_amount,
    p_sort_order,
    nullif(btrim(p_description), '')
  )
  returning *
    into v_rule;

  return jsonb_build_object(
    'status', 'admin_pay_type_rule_created',
    'pay_type_rule', jsonb_build_object(
      'pay_type_rule_id', v_rule.id,
      'pay_type', v_rule.pay_type,
      'is_enabled', v_rule.is_active and coalesce(v_rule.active, false),
      'is_active', v_rule.is_active,
      'active', coalesce(v_rule.active, false),
      'is_taxable', v_rule.is_taxable,
      'tax_applicable', coalesce(v_rule.tax_applicable, false),
      'default_daily_amount', v_rule.default_daily_amount,
      'sort_order', v_rule.sort_order,
      'description', v_rule.description
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_admin_pay_type_rule_state(p_pay_type_rule_id uuid, p_is_taxable boolean, p_default_daily_amount numeric, p_sort_order integer, p_description text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid;
  v_access jsonb;
  v_rule public.pay_type_rules%rowtype;
  v_required_taxability boolean;
begin
  select au.id
    into v_user_id
  from public.app_users au
  where au.auth_user_id = auth.uid()
    and au.is_active = true;

  if v_user_id is null then
    raise exception 'Pay type administration access denied'
      using errcode = '42501';
  end if;

  v_access :=
    public.get_user_admin_setting_access_state(
      v_user_id,
      'fleet_board.pay_type_colors'
    );

  if coalesce((v_access ->> 'allowed')::boolean, false) is not true then
    raise exception 'Pay type administration access denied'
      using errcode = '42501';
  end if;

  if p_pay_type_rule_id is null then
    raise exception 'Pay type rule ID is required'
      using errcode = '22023';
  end if;

  select * into v_rule from public.pay_type_rules where id = p_pay_type_rule_id for update;
  if not found then raise exception 'Pay type rule not found' using errcode = 'P0002'; end if;
  v_required_taxability := v_rule.pay_type not in ('GM Warranty', 'Extended Warranty');
  if v_required_taxability and p_is_taxable is distinct from true then
    raise exception 'Only GM Warranty and Extended Warranty can be tax-exempt' using errcode = '22023';
  elsif not v_required_taxability and p_is_taxable is distinct from false then
    raise exception 'GM Warranty and Extended Warranty must remain tax-exempt' using errcode = '22023';
  end if;

  if p_sort_order is null or p_sort_order < 0 then
    raise exception 'Sort order must be zero or greater'
      using errcode = '22023';
  end if;

  if p_default_daily_amount is not null
     and p_default_daily_amount < 0
  then
    raise exception 'Default daily amount must be zero or greater'
      using errcode = '22023';
  end if;

  update public.pay_type_rules
  set
    is_taxable = v_required_taxability,
    tax_applicable = v_required_taxability,
    default_daily_amount = p_default_daily_amount,
    sort_order = p_sort_order,
    description = nullif(btrim(p_description), ''),
    updated_at = clock_timestamp()
  where id = p_pay_type_rule_id
  returning *
    into v_rule;

  if not found then
    raise exception 'Pay type rule not found'
      using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'status', 'admin_pay_type_rule_updated',
    'pay_type_rule', jsonb_build_object(
      'pay_type_rule_id', v_rule.id,
      'pay_type', v_rule.pay_type,
      'is_enabled', v_rule.is_active and coalesce(v_rule.active, false),
      'is_active', v_rule.is_active,
      'active', coalesce(v_rule.active, false),
      'is_taxable', v_rule.is_taxable,
      'tax_applicable', coalesce(v_rule.tax_applicable, false),
      'default_daily_amount', v_rule.default_daily_amount,
      'sort_order', v_rule.sort_order,
      'description', v_rule.description
    )
  );
end;
$function$;


alter function public.create_admin_pay_type_rule_state(text,boolean,numeric,integer,text) owner to postgres;
alter function public.update_admin_pay_type_rule_state(uuid,boolean,numeric,integer,text) owner to postgres;
revoke all on function public.create_admin_pay_type_rule_state(text,boolean,numeric,integer,text) from public,anon,authenticated;
revoke all on function public.update_admin_pay_type_rule_state(uuid,boolean,numeric,integer,text) from public,anon,authenticated;
grant execute on function public.create_admin_pay_type_rule_state(text,boolean,numeric,integer,text) to authenticated,service_role;
grant execute on function public.update_admin_pay_type_rule_state(uuid,boolean,numeric,integer,text) to authenticated,service_role;
