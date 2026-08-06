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

alter table public.billing_lines add column if not exists tax_rate_snapshot numeric;
alter table public.billing_lines add column if not exists is_taxable_snapshot boolean;
alter table public.billing_lines add column if not exists tax_rate_source_snapshot text;
alter table public.billing_lines alter column tax_rate_snapshot type numeric using tax_rate_snapshot::numeric;
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


-- Live-verified nullable-tax propagation through operational start/bill and extension engines.

CREATE OR REPLACE FUNCTION public.accept_case_extension_and_get_unified_payload_state(p_reservation_id uuid, p_new_expected_return_at timestamp with time zone, p_extension_amount numeric, p_extension_tax_amount numeric DEFAULT NULL::numeric, p_reason_code text DEFAULT NULL::text, p_optional_note text DEFAULT NULL::text, p_entered_by_user_id uuid DEFAULT NULL::uuid, p_escalate_current_dependency boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_user_id uuid;
    v_action_result jsonb;
    v_unified_payload jsonb;
BEGIN
    SELECT au.id
    INTO v_user_id
    FROM public.app_users au
    WHERE au.auth_user_id = auth.uid()
      AND au.is_active = true;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Billing action access denied'
            USING ERRCODE = '42501';
    END IF;

    IF coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' THEN
        RAISE EXCEPTION 'Billing action requires AAL2'
            USING ERRCODE = '42501';
    END IF;

    IF p_entered_by_user_id IS NOT NULL
       AND p_entered_by_user_id <> v_user_id THEN
        RAISE EXCEPTION 'Billing actor mismatch'
            USING ERRCODE = '42501';
    END IF;

    v_action_result :=
        public.accept_reservation_extension_state(
            p_reservation_id,
            p_new_expected_return_at,
            p_extension_amount,
            p_extension_tax_amount,
            p_reason_code,
            p_optional_note,
            v_user_id,
            p_escalate_current_dependency
        );

    v_unified_payload :=
        public.get_unified_case_payload_state(p_reservation_id);

    RETURN jsonb_build_object(
        'status',
        'case_extension_accepted_and_loaded',
        'reservation_id',
        p_reservation_id,
        'action_result',
        v_action_result,
        'unified_case_payload',
        v_unified_payload
    );
END;
$function$;
alter function public.accept_case_extension_and_get_unified_payload_state(uuid,timestamp with time zone,numeric,numeric,text,text,uuid,boolean) owner to postgres;
revoke all on function public.accept_case_extension_and_get_unified_payload_state(uuid,timestamp with time zone,numeric,numeric,text,text,uuid,boolean) from public, anon, authenticated, service_role;
grant execute on function public.accept_case_extension_and_get_unified_payload_state(uuid,timestamp with time zone,numeric,numeric,text,text,uuid,boolean) to authenticated;

CREATE OR REPLACE FUNCTION public.accept_extension_commit_state(p_transportation_event_id uuid, p_current_billing_line_id uuid, p_new_expected_return_at timestamp with time zone, p_extension_amount numeric, p_extension_tax_amount numeric DEFAULT NULL::numeric, p_reason_code text DEFAULT NULL::text, p_optional_note text DEFAULT NULL::text, p_entered_by_user_id uuid DEFAULT NULL::uuid, p_dependency_id_to_escalate uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_old_expected_return_at timestamptz;
    v_expected_return_result jsonb;
    v_note_result jsonb;
    v_close_result jsonb;
    v_extension_line_result jsonb;
    v_escalation_result jsonb := NULL;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.transportation_events
        WHERE id = p_transportation_event_id
    ) THEN
        RAISE EXCEPTION
            'Transportation event % does not exist',
            p_transportation_event_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.billing_lines
        WHERE id = p_current_billing_line_id
          AND is_open = true
          AND line_type IS DISTINCT FROM 'tax'
    ) THEN
        RAISE EXCEPTION
            'Open current billing line % does not exist',
            p_current_billing_line_id;
    END IF;

    IF p_reason_code IS NULL OR btrim(p_reason_code) = '' THEN
        RAISE EXCEPTION
            'Reason code is required for accepted extension';
    END IF;

    IF p_extension_amount IS NULL OR p_extension_amount < 0 THEN
        RAISE EXCEPTION
            'Extension amount must be non-negative';
    END IF;

    IF p_extension_tax_amount IS NOT NULL
       AND p_extension_tax_amount < 0 THEN
        RAISE EXCEPTION
            'Extension tax amount must be non-negative';
    END IF;

    IF p_entered_by_user_id IS NOT NULL
       AND NOT EXISTS (
            SELECT 1
            FROM public.app_users
            WHERE id = p_entered_by_user_id
       ) THEN
        RAISE EXCEPTION
            'User % does not exist',
            p_entered_by_user_id;
    END IF;

    IF p_dependency_id_to_escalate IS NOT NULL
       AND NOT EXISTS (
            SELECT 1
            FROM public.reservation_vehicle_dependencies
            WHERE id = p_dependency_id_to_escalate
       ) THEN
        RAISE EXCEPTION
            'Dependency % does not exist',
            p_dependency_id_to_escalate;
    END IF;

    SELECT expected_return_at
    INTO v_old_expected_return_at
    FROM public.transportation_events
    WHERE id = p_transportation_event_id
    FOR UPDATE;

    v_expected_return_result :=
        public.set_expected_return_state(
            p_transportation_event_id,
            p_new_expected_return_at
        );

    v_note_result :=
        public.add_estimated_return_change_note_state(
            p_transportation_event_id,
            v_old_expected_return_at,
            p_new_expected_return_at,
            p_reason_code,
            p_optional_note,
            p_entered_by_user_id
        );

    v_close_result :=
        public.close_billing_line_at_paid_through_state(
            p_current_billing_line_id
        );

    v_extension_line_result :=
        public.create_extension_billing_line_state(
            p_current_billing_line_id,
            p_extension_amount,
            p_extension_tax_amount,
            p_new_expected_return_at
        );

    IF p_dependency_id_to_escalate IS NOT NULL THEN
        v_escalation_result :=
            public.escalate_dependency_to_critical_state(
                p_dependency_id_to_escalate,
                p_entered_by_user_id
            );
    END IF;

    RETURN jsonb_build_object(
        'status',
        CASE
            WHEN p_dependency_id_to_escalate IS NOT NULL
                THEN 'accepted_with_conflict_escalation'
            ELSE 'accepted'
        END,
        'transportation_event_id',
        p_transportation_event_id,
        'current_billing_line_id',
        p_current_billing_line_id,
        'expected_return_result',
        v_expected_return_result,
        'note_result',
        v_note_result,
        'close_result',
        v_close_result,
        'extension_line_result',
        v_extension_line_result,
        'dependency_escalation_result',
        v_escalation_result
    );
END;
$function$;
alter function public.accept_extension_commit_state(uuid,uuid,timestamp with time zone,numeric,numeric,text,text,uuid,uuid) owner to postgres;
revoke all on function public.accept_extension_commit_state(uuid,uuid,timestamp with time zone,numeric,numeric,text,text,uuid,uuid) from public, anon, authenticated, service_role;
grant execute on function public.accept_extension_commit_state(uuid,uuid,timestamp with time zone,numeric,numeric,text,text,uuid,uuid) to service_role;

CREATE OR REPLACE FUNCTION public.accept_reservation_extension_state(p_reservation_id uuid, p_new_expected_return_at timestamp with time zone, p_extension_amount numeric, p_extension_tax_amount numeric DEFAULT NULL::numeric, p_reason_code text DEFAULT NULL::text, p_optional_note text DEFAULT NULL::text, p_entered_by_user_id uuid DEFAULT NULL::uuid, p_escalate_current_dependency boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_reservation record;
    v_candidate record;
    v_dependency_id uuid := NULL;
    v_result jsonb;
BEGIN
    SELECT *
    INTO v_reservation
    FROM public.reservations
    WHERE id = p_reservation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Reservation % does not exist',
            p_reservation_id;
    END IF;

    IF p_new_expected_return_at IS NULL THEN
        RAISE EXCEPTION 'new_expected_return_at cannot be null';
    END IF;

    IF p_extension_amount IS NULL OR p_extension_amount < 0 THEN
        RAISE EXCEPTION 'extension_amount must be non-negative';
    END IF;

    IF p_extension_tax_amount IS NOT NULL
       AND p_extension_tax_amount < 0 THEN
        RAISE EXCEPTION 'extension_tax_amount must be non-negative';
    END IF;

    IF p_reason_code IS NULL OR btrim(p_reason_code) = '' THEN
        RAISE EXCEPTION 'reason_code cannot be blank';
    END IF;

    IF p_entered_by_user_id IS NOT NULL
       AND NOT EXISTS (
            SELECT 1
            FROM public.app_users
            WHERE id = p_entered_by_user_id
       ) THEN
        RAISE EXCEPTION
            'User % does not exist',
            p_entered_by_user_id;
    END IF;

    SELECT *
    INTO v_candidate
    FROM public.v_reservation_extension_candidate_state
    WHERE reservation_id = p_reservation_id
      AND parent_billing_line_id IS NOT NULL
    ORDER BY
        start_time DESC NULLS LAST,
        parent_billing_line_id DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'No extension-eligible billing line exists for reservation %',
            p_reservation_id;
    END IF;

    IF p_escalate_current_dependency THEN
        SELECT id
        INTO v_dependency_id
        FROM public.reservation_vehicle_dependencies
        WHERE reservation_id = p_reservation_id
          AND status IN ('pending_return', 'ready', 'conflict')
        ORDER BY
            updated_at DESC NULLS LAST,
            created_at DESC NULLS LAST
        LIMIT 1;
    END IF;

    v_result := public.accept_extension_commit_state(
        v_reservation.transportation_event_id,
        v_candidate.parent_billing_line_id,
        p_new_expected_return_at,
        p_extension_amount,
        p_extension_tax_amount,
        p_reason_code,
        p_optional_note,
        p_entered_by_user_id,
        v_dependency_id
    );

    RETURN jsonb_build_object(
        'status',
        'reservation_extension_accepted',
        'reservation_id',
        p_reservation_id,
        'transportation_event_id',
        v_reservation.transportation_event_id,
        'parent_billing_line_id',
        v_candidate.parent_billing_line_id,
        'dependency_id_escalated',
        v_dependency_id,
        'extension_commit_result',
        v_result
    );
END;
$function$;
alter function public.accept_reservation_extension_state(uuid,timestamp with time zone,numeric,numeric,text,text,uuid,boolean) owner to postgres;
revoke all on function public.accept_reservation_extension_state(uuid,timestamp with time zone,numeric,numeric,text,text,uuid,boolean) from public, anon, authenticated, service_role;
grant execute on function public.accept_reservation_extension_state(uuid,timestamp with time zone,numeric,numeric,text,text,uuid,boolean) to service_role;

CREATE OR REPLACE FUNCTION public.accept_transportation_event_extension_state(p_transportation_event_id uuid, p_new_expected_return_at timestamp with time zone, p_extension_amount numeric, p_extension_tax_amount numeric DEFAULT NULL::numeric, p_reason_code text DEFAULT NULL::text, p_optional_note text DEFAULT NULL::text, p_entered_by_user_id uuid DEFAULT NULL::uuid, p_escalate_current_dependency boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_te record;
    v_candidate record;
    v_dependency_id uuid := NULL;
    v_result jsonb;
BEGIN
    SELECT *
    INTO v_te
    FROM public.transportation_events
    WHERE id = p_transportation_event_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Transportation event % does not exist',
            p_transportation_event_id;
    END IF;

    IF p_new_expected_return_at IS NULL THEN
        RAISE EXCEPTION 'new_expected_return_at cannot be null';
    END IF;

    IF p_extension_amount IS NULL OR p_extension_amount < 0 THEN
        RAISE EXCEPTION 'extension_amount must be non-negative';
    END IF;

    IF p_extension_tax_amount IS NOT NULL
       AND p_extension_tax_amount < 0 THEN
        RAISE EXCEPTION 'extension_tax_amount must be non-negative';
    END IF;

    IF p_reason_code IS NULL OR btrim(p_reason_code) = '' THEN
        RAISE EXCEPTION 'reason_code cannot be blank';
    END IF;

    IF p_entered_by_user_id IS NOT NULL
       AND NOT EXISTS (
            SELECT 1
            FROM public.app_users
            WHERE id = p_entered_by_user_id
       ) THEN
        RAISE EXCEPTION
            'User % does not exist',
            p_entered_by_user_id;
    END IF;

    SELECT *
    INTO v_candidate
    FROM public.v_transportation_event_extension_candidate_state
    WHERE transportation_event_id = p_transportation_event_id
      AND parent_billing_line_id IS NOT NULL
    ORDER BY
        start_time DESC NULLS LAST,
        parent_billing_line_id DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'No extension-eligible billing line exists for transportation event %',
            p_transportation_event_id;
    END IF;

    IF p_escalate_current_dependency
       AND v_te.source_type = 'reservation'
       AND v_te.source_id IS NOT NULL THEN
        SELECT id
        INTO v_dependency_id
        FROM public.reservation_vehicle_dependencies
        WHERE reservation_id = v_te.source_id
          AND status IN ('pending_return', 'ready', 'conflict')
        ORDER BY
            updated_at DESC NULLS LAST,
            created_at DESC NULLS LAST
        LIMIT 1;
    END IF;

    v_result := public.accept_extension_commit_state(
        p_transportation_event_id,
        v_candidate.parent_billing_line_id,
        p_new_expected_return_at,
        p_extension_amount,
        p_extension_tax_amount,
        p_reason_code,
        p_optional_note,
        p_entered_by_user_id,
        v_dependency_id
    );

    RETURN jsonb_build_object(
        'status',
        'transportation_event_extension_accepted',
        'transportation_event_id',
        p_transportation_event_id,
        'parent_billing_line_id',
        v_candidate.parent_billing_line_id,
        'dependency_id_escalated',
        v_dependency_id,
        'extension_commit_result',
        v_result
    );
END;
$function$;
alter function public.accept_transportation_event_extension_state(uuid,timestamp with time zone,numeric,numeric,text,text,uuid,boolean) owner to postgres;
revoke all on function public.accept_transportation_event_extension_state(uuid,timestamp with time zone,numeric,numeric,text,text,uuid,boolean) from public, anon, authenticated, service_role;
grant execute on function public.accept_transportation_event_extension_state(uuid,timestamp with time zone,numeric,numeric,text,text,uuid,boolean) to service_role;

CREATE OR REPLACE FUNCTION public.activate_case_billing_state(p_reservation_id uuid, p_amount numeric, p_tax_amount numeric DEFAULT NULL::numeric, p_start_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_paid_through_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_line_type text DEFAULT 'initial_assignment'::text, p_source_rule text DEFAULT NULL::text, p_pay_type_override text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_reservation record;
    v_pay_type text;
    v_result jsonb;
BEGIN
    SELECT *
    INTO v_reservation
    FROM public.reservations
    WHERE id = p_reservation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation % does not exist', p_reservation_id;
    END IF;

    IF p_amount IS NULL OR p_amount < 0 THEN
        RAISE EXCEPTION 'amount must be non-negative';
    END IF;

    IF p_tax_amount IS NOT NULL AND p_tax_amount < 0 THEN
        RAISE EXCEPTION 'tax_amount must be non-negative';
    END IF;

    v_pay_type := coalesce(p_pay_type_override, v_reservation.pay_type);

    IF v_pay_type IS NULL OR btrim(v_pay_type) = '' THEN
        RAISE EXCEPTION 'pay_type cannot be blank';
    END IF;

    v_result := public.create_reservation_billing_line_state(
        p_reservation_id,
        v_pay_type,
        p_amount,
        p_tax_amount,
        p_start_time,
        NULL,
        p_line_type,
        p_paid_through_at,
        p_source_rule
    );

    RETURN jsonb_build_object(
        'status', 'case_billing_activated',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'billing_result', v_result
    );
END;
$function$;
alter function public.activate_case_billing_state(uuid,numeric,numeric,timestamp with time zone,timestamp with time zone,text,text,text) owner to postgres;
revoke all on function public.activate_case_billing_state(uuid,numeric,numeric,timestamp with time zone,timestamp with time zone,text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.activate_case_billing_state(uuid,numeric,numeric,timestamp with time zone,timestamp with time zone,text,text,text) to service_role;

CREATE OR REPLACE FUNCTION public.create_extension_billing_line_state(p_parent_billing_line_id uuid, p_extension_amount numeric, p_extension_tax_amount numeric, p_new_expected_return_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_parent record;
    v_result jsonb;
BEGIN
    SELECT *
    INTO v_parent
    FROM public.billing_lines
    WHERE id = p_parent_billing_line_id
      AND line_type IS DISTINCT FROM 'tax'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Parent billing line % does not exist or is a tax line',
            p_parent_billing_line_id;
    END IF;

    IF v_parent.paid_through_at IS NULL THEN
        RAISE EXCEPTION
            'Parent billing line % has no paid_through_at',
            p_parent_billing_line_id;
    END IF;

    IF p_extension_amount IS NULL THEN
        RAISE EXCEPTION 'Extension amount cannot be null';
    END IF;

    IF p_extension_amount < 0 THEN
        RAISE EXCEPTION
            'Extension amount % cannot be negative',
            p_extension_amount;
    END IF;

    IF p_extension_tax_amount IS NOT NULL
       AND p_extension_tax_amount < 0 THEN
        RAISE EXCEPTION
            'Extension tax amount % cannot be negative',
            p_extension_tax_amount;
    END IF;

    v_result := public.create_billing_parent_line_state(
        v_parent.transportation_event_id,
        v_parent.reservation_id,
        v_parent.vehicle_id,
        v_parent.pay_type,
        p_extension_amount,
        p_extension_tax_amount,
        v_parent.paid_through_at,
        p_new_expected_return_at,
        v_parent.source_rule,
        v_parent.vehicle_event_id,
        v_parent.contract_period_id,
        'rental_extension',
        v_parent.warranty_provider_id,
        v_parent.default_covered_days_snapshot,
        v_parent.covered_days_override,
        true,
        v_parent.paid_through_at,
        v_parent.id,
        v_parent.default_daily_rate_snapshot,
        v_parent.daily_rate_override
    );

    RETURN jsonb_build_object(
        'status', 'extension_billing_line_created',
        'parent_billing_line_id', p_parent_billing_line_id,
        'result', v_result
    );
END;
$function$;
alter function public.create_extension_billing_line_state(uuid,numeric,numeric,timestamp with time zone) owner to postgres;
revoke all on function public.create_extension_billing_line_state(uuid,numeric,numeric,timestamp with time zone) from public, anon, authenticated, service_role;
grant execute on function public.create_extension_billing_line_state(uuid,numeric,numeric,timestamp with time zone) to service_role;

CREATE OR REPLACE FUNCTION public.create_reservation_billing_line_state(p_reservation_id uuid, p_pay_type text, p_amount numeric, p_tax_amount numeric DEFAULT NULL::numeric, p_start_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_line_type text DEFAULT 'initial_assignment'::text, p_paid_through_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_source_rule text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_reservation record;
    v_current_continuity record;
    v_result jsonb;
    v_start_time timestamptz;
BEGIN
    SELECT *
    INTO v_reservation
    FROM public.reservations
    WHERE id = p_reservation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation % does not exist', p_reservation_id;
    END IF;

    IF p_pay_type IS NULL OR btrim(p_pay_type) = '' THEN
        RAISE EXCEPTION 'pay_type cannot be blank';
    END IF;

    IF p_amount IS NULL OR p_amount < 0 THEN
        RAISE EXCEPTION 'amount must be non-negative';
    END IF;

    IF p_tax_amount IS NOT NULL AND p_tax_amount < 0 THEN
        RAISE EXCEPTION 'tax_amount must be non-negative';
    END IF;

    v_start_time := coalesce(p_start_time, v_reservation.start_date);

    SELECT *
    INTO v_current_continuity
    FROM public.v_current_vehicle_continuity
    WHERE transportation_event_id = v_reservation.transportation_event_id
    LIMIT 1;

    v_result := public.create_billing_parent_line_state(
        v_reservation.transportation_event_id,
        p_reservation_id,
        coalesce(v_current_continuity.vehicle_id, v_reservation.vehicle_id),
        p_pay_type,
        p_amount,
        p_tax_amount,
        v_start_time,
        p_end_time,
        p_source_rule,
        v_current_continuity.vehicle_event_id,
        v_current_continuity.contract_period_id,
        p_line_type,
        NULL,
        NULL,
        NULL,
        true,
        p_paid_through_at,
        NULL,
        NULL,
        NULL
    );

    RETURN jsonb_build_object(
        'status', 'reservation_billing_line_created',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'billing_result', v_result
    );
END;
$function$;
alter function public.create_reservation_billing_line_state(uuid,text,numeric,numeric,timestamp with time zone,timestamp with time zone,text,timestamp with time zone,text) owner to postgres;
revoke all on function public.create_reservation_billing_line_state(uuid,text,numeric,numeric,timestamp with time zone,timestamp with time zone,text,timestamp with time zone,text) from public, anon, authenticated, service_role;
grant execute on function public.create_reservation_billing_line_state(uuid,text,numeric,numeric,timestamp with time zone,timestamp with time zone,text,timestamp with time zone,text) to service_role;

CREATE OR REPLACE FUNCTION public.create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_(p_tekion_customer_number text, p_customer_name text, p_start_date timestamp with time zone, p_expected_return_datetime timestamp with time zone, p_requested_model text, p_vehicle_vin text, p_vehicle_stock_number text, p_vehicle_model text, p_vehicle_fleet_type text, p_vehicle_mileage integer, p_vehicle_current_tag text, p_vehicle_fleet_conversion_type text, p_actual_out_at timestamp with time zone, p_billing_amount numeric, p_billing_tax_amount numeric DEFAULT NULL::numeric, p_billing_start_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_billing_paid_through_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_customer_phone text DEFAULT NULL::text, p_customer_email text DEFAULT NULL::text, p_customer_flags jsonb DEFAULT NULL::jsonb, p_customer_internal_notes text DEFAULT NULL::text, p_reservation_type text DEFAULT 'rental'::text, p_reservation_status text DEFAULT 'quote'::text, p_reservation_notes text DEFAULT NULL::text, p_service_advisor text DEFAULT NULL::text, p_ro_number text DEFAULT NULL::text, p_pay_type text DEFAULT 'customer'::text, p_vehicle_location text DEFAULT NULL::text, p_vehicle_notes text DEFAULT NULL::text, p_vehicle_status text DEFAULT 'available'::text, p_vehicle_recon_status text DEFAULT 'clean'::text, p_billing_line_type text DEFAULT 'initial_assignment'::text, p_billing_source_rule text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_execution_result jsonb;
    v_reservation_id uuid;
    v_unified_payload jsonb;
BEGIN
    v_execution_result :=
        public.create_start_and_bill_case_with_vehicle_by_vin_state(
            p_tekion_customer_number,
            p_customer_name,
            p_start_date,
            p_expected_return_datetime,
            p_requested_model,
            p_vehicle_vin,
            p_vehicle_stock_number,
            p_vehicle_model,
            p_vehicle_fleet_type,
            p_vehicle_mileage,
            p_vehicle_current_tag,
            p_vehicle_fleet_conversion_type,
            p_actual_out_at,
            p_billing_amount,
            p_billing_tax_amount,
            p_billing_start_time,
            p_billing_paid_through_at,
            p_customer_phone,
            p_customer_email,
            p_customer_flags,
            p_customer_internal_notes,
            p_reservation_type,
            p_reservation_status,
            p_reservation_notes,
            p_service_advisor,
            p_ro_number,
            p_pay_type,
            p_vehicle_location,
            p_vehicle_notes,
            p_vehicle_status,
            p_vehicle_recon_status,
            p_billing_line_type,
            p_billing_source_rule
        );

    v_reservation_id := (v_execution_result ->> 'reservation_id')::uuid;

    IF v_reservation_id IS NULL THEN
        RAISE EXCEPTION 'Failed to extract reservation_id from create_start_and_bill_case result';
    END IF;

    v_unified_payload :=
        public.get_unified_case_payload_state(v_reservation_id);

    RETURN jsonb_build_object(
        'status', 'full_case_created_started_billed_and_loaded',
        'reservation_id', v_reservation_id,
        'execution_result', v_execution_result,
        'unified_case_payload', v_unified_payload
    );
END;
$function$;
alter function public.create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text,timestamp with time zone,numeric,numeric,timestamp with time zone,timestamp with time zone,text,text,jsonb,text,text,text,text,text,text,text,text,text,text,text,text,text) owner to postgres;
revoke all on function public.create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text,timestamp with time zone,numeric,numeric,timestamp with time zone,timestamp with time zone,text,text,jsonb,text,text,text,text,text,text,text,text,text,text,text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text,timestamp with time zone,numeric,numeric,timestamp with time zone,timestamp with time zone,text,text,jsonb,text,text,text,text,text,text,text,text,text,text,text,text,text) to service_role;

CREATE OR REPLACE FUNCTION public.create_start_and_bill_case_with_vehicle_by_vin_state(p_tekion_customer_number text, p_customer_name text, p_start_date timestamp with time zone, p_expected_return_datetime timestamp with time zone, p_requested_model text, p_vehicle_vin text, p_vehicle_stock_number text, p_vehicle_model text, p_vehicle_fleet_type text, p_vehicle_mileage integer, p_vehicle_current_tag text, p_vehicle_fleet_conversion_type text, p_actual_out_at timestamp with time zone, p_billing_amount numeric, p_billing_tax_amount numeric DEFAULT NULL::numeric, p_billing_start_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_billing_paid_through_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_customer_phone text DEFAULT NULL::text, p_customer_email text DEFAULT NULL::text, p_customer_flags jsonb DEFAULT NULL::jsonb, p_customer_internal_notes text DEFAULT NULL::text, p_reservation_type text DEFAULT 'rental'::text, p_reservation_status text DEFAULT 'quote'::text, p_reservation_notes text DEFAULT NULL::text, p_service_advisor text DEFAULT NULL::text, p_ro_number text DEFAULT NULL::text, p_pay_type text DEFAULT 'customer'::text, p_vehicle_location text DEFAULT NULL::text, p_vehicle_notes text DEFAULT NULL::text, p_vehicle_status text DEFAULT 'available'::text, p_vehicle_recon_status text DEFAULT 'clean'::text, p_billing_line_type text DEFAULT 'initial_assignment'::text, p_billing_source_rule text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_case_step jsonb;
    v_reservation_id uuid;
    v_billing_result jsonb;
BEGIN
    IF p_billing_amount IS NULL OR p_billing_amount < 0 THEN
        RAISE EXCEPTION 'billing_amount must be non-negative';
    END IF;

    IF p_billing_tax_amount IS NOT NULL AND p_billing_tax_amount < 0 THEN
        RAISE EXCEPTION 'billing_tax_amount must be non-negative';
    END IF;

    v_case_step := public.create_and_start_case_with_vehicle_by_vin_state(
        p_tekion_customer_number,
        p_customer_name,
        p_start_date,
        p_expected_return_datetime,
        p_requested_model,
        p_vehicle_vin,
        p_vehicle_stock_number,
        p_vehicle_model,
        p_vehicle_fleet_type,
        p_vehicle_mileage,
        p_vehicle_current_tag,
        p_vehicle_fleet_conversion_type,
        p_actual_out_at,
        p_customer_phone,
        p_customer_email,
        p_customer_flags,
        p_customer_internal_notes,
        p_reservation_type,
        p_reservation_status,
        p_reservation_notes,
        p_service_advisor,
        p_ro_number,
        p_pay_type,
        p_vehicle_location,
        p_vehicle_notes,
        p_vehicle_status,
        p_vehicle_recon_status
    );

    v_reservation_id := (v_case_step ->> 'reservation_id')::uuid;

    IF v_reservation_id IS NULL THEN
        RAISE EXCEPTION 'Failed to extract reservation_id from create_and_start_case result';
    END IF;

    v_billing_result := public.activate_case_billing_state(
        v_reservation_id,
        p_billing_amount,
        p_billing_tax_amount,
        p_billing_start_time,
        p_billing_paid_through_at,
        p_billing_line_type,
        p_billing_source_rule,
        NULL
    );

    RETURN jsonb_build_object(
        'status', 'full_case_created_started_and_billed',
        'reservation_id', v_reservation_id,
        'case_step', v_case_step,
        'billing_step', v_billing_result
    );
END;
$function$;
alter function public.create_start_and_bill_case_with_vehicle_by_vin_state(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text,timestamp with time zone,numeric,numeric,timestamp with time zone,timestamp with time zone,text,text,jsonb,text,text,text,text,text,text,text,text,text,text,text,text,text) owner to postgres;
revoke all on function public.create_start_and_bill_case_with_vehicle_by_vin_state(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text,timestamp with time zone,numeric,numeric,timestamp with time zone,timestamp with time zone,text,text,jsonb,text,text,text,text,text,text,text,text,text,text,text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.create_start_and_bill_case_with_vehicle_by_vin_state(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text,timestamp with time zone,numeric,numeric,timestamp with time zone,timestamp with time zone,text,text,jsonb,text,text,text,text,text,text,text,text,text,text,text,text,text) to service_role;

CREATE OR REPLACE FUNCTION public.create_start_bill_case_and_get_payload_state(p_tekion_customer_number text, p_customer_name text, p_start_date timestamp with time zone, p_expected_return_datetime timestamp with time zone, p_requested_model text, p_vehicle_vin text, p_vehicle_stock_number text, p_vehicle_model text, p_vehicle_fleet_type text, p_vehicle_mileage integer, p_vehicle_current_tag text, p_vehicle_fleet_conversion_type text, p_actual_out_at timestamp with time zone, p_billing_amount numeric, p_billing_tax_amount numeric DEFAULT NULL::numeric, p_billing_start_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_billing_paid_through_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_customer_phone text DEFAULT NULL::text, p_customer_email text DEFAULT NULL::text, p_customer_flags jsonb DEFAULT NULL::jsonb, p_customer_internal_notes text DEFAULT NULL::text, p_reservation_type text DEFAULT 'rental'::text, p_reservation_status text DEFAULT 'quote'::text, p_reservation_notes text DEFAULT NULL::text, p_service_advisor text DEFAULT NULL::text, p_ro_number text DEFAULT NULL::text, p_pay_type text DEFAULT 'customer'::text, p_vehicle_location text DEFAULT NULL::text, p_vehicle_notes text DEFAULT NULL::text, p_vehicle_status text DEFAULT 'available'::text, p_vehicle_recon_status text DEFAULT 'clean'::text, p_billing_line_type text DEFAULT 'initial_assignment'::text, p_billing_source_rule text DEFAULT NULL::text, p_start_mileage integer DEFAULT NULL::integer, p_entered_by_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_actor_user_id uuid;
    v_execution_result jsonb;
    v_reservation_id uuid;
    v_vehicle_event_id uuid;
    v_contract_period_id uuid;
    v_unified_payload jsonb;
BEGIN
    SELECT au.id
    INTO v_actor_user_id
    FROM public.app_users AS au
    WHERE au.auth_user_id = auth.uid()
      AND au.is_active = true;

    IF v_actor_user_id IS NULL THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'An active application user is required';
    END IF;

    IF coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'AAL2 authentication is required';
    END IF;

    IF p_entered_by_user_id IS NOT NULL
       AND p_entered_by_user_id <> v_actor_user_id THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'entered_by_user_id must match the authenticated application user';
    END IF;

    IF p_start_mileage IS NOT NULL AND p_start_mileage < 0 THEN
        RAISE EXCEPTION 'start_mileage must be non-negative';
    END IF;

    v_execution_result :=
        public.create_start_and_bill_case_with_vehicle_by_vin_state(
            p_tekion_customer_number,
            p_customer_name,
            p_start_date,
            p_expected_return_datetime,
            p_requested_model,
            p_vehicle_vin,
            p_vehicle_stock_number,
            p_vehicle_model,
            p_vehicle_fleet_type,
            p_vehicle_mileage,
            p_vehicle_current_tag,
            p_vehicle_fleet_conversion_type,
            p_actual_out_at,
            p_billing_amount,
            p_billing_tax_amount,
            p_billing_start_time,
            p_billing_paid_through_at,
            p_customer_phone,
            p_customer_email,
            p_customer_flags,
            p_customer_internal_notes,
            p_reservation_type,
            p_reservation_status,
            p_reservation_notes,
            p_service_advisor,
            p_ro_number,
            p_pay_type,
            p_vehicle_location,
            p_vehicle_notes,
            p_vehicle_status,
            p_vehicle_recon_status,
            p_billing_line_type,
            p_billing_source_rule
        );

    BEGIN
        v_reservation_id := (v_execution_result ->> 'reservation_id')::uuid;

        v_vehicle_event_id := (
            v_execution_result
            -> 'case_step'
            -> 'start_result'
            -> 'continuity_result'
            ->> 'vehicle_event_id'
        )::uuid;

        v_contract_period_id := (
            v_execution_result
            -> 'case_step'
            -> 'start_result'
            -> 'continuity_result'
            ->> 'contract_period_id'
        )::uuid;
    EXCEPTION
        WHEN invalid_text_representation THEN
            RAISE EXCEPTION 'Workflow returned malformed created identifiers';
    END;

    IF v_reservation_id IS NULL
       OR v_vehicle_event_id IS NULL
       OR v_contract_period_id IS NULL THEN
        RAISE EXCEPTION
            'Workflow did not return reservation, vehicle-event, and contract-period identifiers';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.reservations r
        JOIN public.vehicle_events ve
          ON ve.transportation_event_id = r.transportation_event_id
        JOIN public.contract_periods cp
          ON cp.vehicle_event_id = ve.id
        WHERE r.id = v_reservation_id
          AND ve.id = v_vehicle_event_id
          AND cp.id = v_contract_period_id
    ) THEN
        RAISE EXCEPTION
            'Workflow returned identifiers that do not identify the created case continuity rows';
    END IF;

    IF p_start_mileage IS NOT NULL THEN
        UPDATE public.reservations
        SET start_mileage = p_start_mileage
        WHERE id = v_reservation_id;
    END IF;

    UPDATE public.vehicle_events
    SET created_by = v_actor_user_id,
        updated_by = v_actor_user_id
    WHERE id = v_vehicle_event_id;

    UPDATE public.contract_periods
    SET created_by = v_actor_user_id,
        updated_by = v_actor_user_id
    WHERE id = v_contract_period_id;

    v_unified_payload :=
        public.get_unified_case_payload_state(v_reservation_id);

    RETURN jsonb_build_object(
        'status',
        'full_case_created_started_billed_and_loaded',
        'reservation_id',
        v_reservation_id,
        'execution_result',
        v_execution_result,
        'unified_case_payload',
        v_unified_payload
    );
END;
$function$;
alter function public.create_start_bill_case_and_get_payload_state(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text,timestamp with time zone,numeric,numeric,timestamp with time zone,timestamp with time zone,text,text,jsonb,text,text,text,text,text,text,text,text,text,text,text,text,text,integer,uuid) owner to postgres;
revoke all on function public.create_start_bill_case_and_get_payload_state(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text,timestamp with time zone,numeric,numeric,timestamp with time zone,timestamp with time zone,text,text,jsonb,text,text,text,text,text,text,text,text,text,text,text,text,text,integer,uuid) from public, anon, authenticated, service_role;
grant execute on function public.create_start_bill_case_and_get_payload_state(text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,text,integer,text,text,timestamp with time zone,numeric,numeric,timestamp with time zone,timestamp with time zone,text,text,jsonb,text,text,text,text,text,text,text,text,text,text,text,text,text,integer,uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.create_transportation_event_billing_line_state(p_transportation_event_id uuid, p_pay_type text, p_amount numeric, p_tax_amount numeric DEFAULT NULL::numeric, p_start_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_line_type text DEFAULT 'initial_assignment'::text, p_paid_through_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_source_rule text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_te record;
    v_current_continuity record;
    v_reservation_id uuid := NULL;
    v_start_time timestamptz;
    v_result jsonb;
BEGIN
    SELECT *
    INTO v_te
    FROM public.transportation_events
    WHERE id = p_transportation_event_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transportation event % does not exist', p_transportation_event_id;
    END IF;

    IF p_pay_type IS NULL OR btrim(p_pay_type) = '' THEN
        RAISE EXCEPTION 'pay_type cannot be blank';
    END IF;

    IF p_amount IS NULL OR p_amount < 0 THEN
        RAISE EXCEPTION 'amount must be non-negative';
    END IF;

    IF p_tax_amount IS NOT NULL AND p_tax_amount < 0 THEN
        RAISE EXCEPTION 'tax_amount must be non-negative';
    END IF;

    IF v_te.source_type = 'reservation'
       AND v_te.source_id IS NOT NULL
       AND EXISTS (
            SELECT 1
            FROM public.reservations
            WHERE id = v_te.source_id
       ) THEN
        v_reservation_id := v_te.source_id;
    END IF;

    v_start_time := coalesce(p_start_time, now());

    SELECT *
    INTO v_current_continuity
    FROM public.v_current_vehicle_continuity
    WHERE transportation_event_id = p_transportation_event_id
    LIMIT 1;

    v_result := public.create_billing_parent_line_state(
        p_transportation_event_id,
        v_reservation_id,
        v_current_continuity.vehicle_id,
        p_pay_type,
        p_amount,
        p_tax_amount,
        v_start_time,
        p_end_time,
        p_source_rule,
        v_current_continuity.vehicle_event_id,
        v_current_continuity.contract_period_id,
        p_line_type,
        NULL,
        NULL,
        NULL,
        true,
        p_paid_through_at,
        NULL,
        NULL,
        NULL
    );

    RETURN jsonb_build_object(
        'status', 'transportation_event_billing_line_created',
        'transportation_event_id', p_transportation_event_id,
        'reservation_id', v_reservation_id,
        'billing_result', v_result
    );
END;
$function$;
alter function public.create_transportation_event_billing_line_state(uuid,text,numeric,numeric,timestamp with time zone,timestamp with time zone,text,timestamp with time zone,text) owner to postgres;
revoke all on function public.create_transportation_event_billing_line_state(uuid,text,numeric,numeric,timestamp with time zone,timestamp with time zone,text,timestamp with time zone,text) from public, anon, authenticated, service_role;
grant execute on function public.create_transportation_event_billing_line_state(uuid,text,numeric,numeric,timestamp with time zone,timestamp with time zone,text,timestamp with time zone,text) to service_role;
