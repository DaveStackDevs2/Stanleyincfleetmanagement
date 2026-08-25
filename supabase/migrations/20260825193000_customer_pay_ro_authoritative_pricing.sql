-- Customer Pay RO authoritative standard pricing and permission-secured whole-segment overrides.
-- Data-free except for the dedicated permission and its initial trusted-role mappings.

alter table public.rental_pricing_agreements alter column rental_rate_rule_id drop not null;

insert into public.permissions(permission_key,description)
values('billing.customer_pay_rate_override','Change or clear the whole-segment Customer Pay RO daily-rate override')
on conflict(permission_key) do update set description=excluded.description;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where p.permission_key='billing.customer_pay_rate_override' and r.role_name in ('Admin','Service Manager','Dev')
on conflict do nothing;
create or replace function public.create_quote_with_pricing_agreement_without_capacity_state(
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
 if lower(btrim(p_reservation_type))='loaner' and lower(btrim(v_pay.pay_type))='customer pay' then
  if p_initial_rate_plan<>'daily' then raise exception 'Customer Pay Loaner pricing is daily-only' using errcode='22023'; end if;
  if v_pay.default_daily_amount is null or v_pay.default_daily_amount<0 or v_pay.default_daily_amount in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Customer Pay Standard RO daily rate is not configured' using errcode='P0001'; end if;
  v_rate_rule:=null;
  v_rate:=jsonb_build_object('daily_rate',v_pay.default_daily_amount,'weekly_rate',null,'monthly_rate',null,'pricing_source','customer_pay_standard_ro_daily_rate');
 else
  v_rate:=public.resolve_rental_rate_card_state(btrim(p_vehicle_class),v_at);
  if v_rate->>'status'<>'rental_rate_card_resolved' or nullif(v_rate->>'rental_rate_rule_id','') is null then raise exception 'Rental rate card not configured' using errcode='P0001'; end if;
  begin v_rate_rule:=(v_rate->>'rental_rate_rule_id')::uuid;
  exception when invalid_text_representation then raise exception 'Rental rate card resolution failed' using errcode='P0001'; end;
  if p_initial_rate_plan='weekly' and (v_rate->>'weekly_rate') is null then raise exception 'Weekly rate is not configured' using errcode='22023'; end if;
  if p_initial_rate_plan='monthly' and (v_rate->>'monthly_rate') is null then raise exception 'Monthly rate is not configured' using errcode='22023'; end if;
 end if;
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

create or replace function public.create_reservation_with_pricing_agreement_without_capacity_state(
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
 if lower(btrim(p_reservation_type))='loaner' and lower(btrim(v_pay.pay_type))='customer pay' then
  if p_initial_rate_plan<>'daily' then raise exception 'Customer Pay Loaner pricing is daily-only' using errcode='22023'; end if;
  if v_pay.default_daily_amount is null or v_pay.default_daily_amount<0 or v_pay.default_daily_amount in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Customer Pay Standard RO daily rate is not configured' using errcode='P0001'; end if;
  v_rate_rule:=null;
  v_rate:=jsonb_build_object('daily_rate',v_pay.default_daily_amount,'weekly_rate',null,'monthly_rate',null,'pricing_source','customer_pay_standard_ro_daily_rate');
 else
  v_rate:=public.resolve_rental_rate_card_state(btrim(p_vehicle_class),v_at);
  if v_rate->>'status'<>'rental_rate_card_resolved' or nullif(v_rate->>'rental_rate_rule_id','') is null then raise exception 'Rental rate card not configured' using errcode='P0001'; end if;
  begin v_rate_rule:=(v_rate->>'rental_rate_rule_id')::uuid;
  exception when invalid_text_representation then raise exception 'Rental rate card resolution failed' using errcode='P0001'; end;
  if p_initial_rate_plan='weekly' and (v_rate->>'weekly_rate') is null then raise exception 'Weekly rate is not configured' using errcode='22023'; end if;
  if p_initial_rate_plan='monthly' and (v_rate->>'monthly_rate') is null then raise exception 'Monthly rate is not configured' using errcode='22023'; end if;
 end if;
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
 if lower(btrim(p_reservation_type))='loaner' and lower(btrim(v_pay.pay_type))='customer pay' then
  if p_initial_rate_plan<>'daily' then raise exception 'Customer Pay Loaner pricing is daily-only' using errcode='22023'; end if;
  if v_pay.default_daily_amount is null or v_pay.default_daily_amount<0 or v_pay.default_daily_amount in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Customer Pay Standard RO daily rate is not configured' using errcode='P0001'; end if;
  v_rate_rule:=null;
  v_rate:=jsonb_build_object('daily_rate',v_pay.default_daily_amount,'weekly_rate',null,'monthly_rate',null,'pricing_source','customer_pay_standard_ro_daily_rate');
 else
  v_rate:=public.resolve_rental_rate_card_state(btrim(p_vehicle_class),v_at);
  if v_rate->>'status'<>'rental_rate_card_resolved' or nullif(v_rate->>'rental_rate_rule_id','') is null then raise exception 'Rental rate card not configured' using errcode='P0001'; end if;
  begin v_rate_rule:=(v_rate->>'rental_rate_rule_id')::uuid;
  exception when invalid_text_representation then raise exception 'Rental rate card resolution failed' using errcode='P0001'; end;
  if p_initial_rate_plan='weekly' and (v_rate->>'weekly_rate') is null then raise exception 'Weekly rate is not configured' using errcode='22023'; end if;
  if p_initial_rate_plan='monthly' and (v_rate->>'monthly_rate') is null then raise exception 'Monthly rate is not configured' using errcode='22023'; end if;
 end if;
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

-- Expose the configured standard alongside each intake pay type without introducing a second settings source.
create or replace function public.get_pricing_agreement_intake_state()
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_at timestamptz:=clock_timestamp();
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
  if v_user is null then raise exception 'An active application user is required' using errcode='42501'; end if;
  if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication is required' using errcode='42501'; end if;
  if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.pricing_agreement_manage') then raise exception 'Pricing-agreement permission is required' using errcode='42501'; end if;
 return jsonb_build_object(
  'status','pricing_agreement_intake_ready','observed_at',v_at,
  'customers',coalesce((select jsonb_agg(jsonb_build_object('customer_id',c.id,'tekion_customer_number',c.tekion_customer_number,'name',c.name,'phone',c.phone,'email',c.email,'created_at',c.created_at) order by lower(btrim(c.name)),c.tekion_customer_number,c.id) from public.customers c),'[]'::jsonb),
  'pay_types',coalesce((select jsonb_agg(jsonb_build_object('pay_type_rule_id',pay_type.id,'pay_type',pay_type.pay_type,'description',pay_type.description,'is_taxable',pay_type.is_taxable,'default_daily_amount',pay_type.default_daily_amount,'sort_order',pay_type.sort_order) order by pay_type.sort_order,lower(btrim(pay_type.pay_type)),pay_type.id) from public.pay_type_rules pay_type where pay_type.is_active=true and coalesce(pay_type.active,false)=true),'[]'::jsonb),
  'rate_cards',coalesce((select jsonb_agg(jsonb_build_object('rental_rate_rule_id',r.id,'vehicle_class',r.vehicle_class,'daily_rate',r.daily_rate::text,'weekly_rate',r.weekly_rate::text,'monthly_rate',r.monthly_rate::text,'sort_order',r.sort_order,'effective_from',r.effective_from,'effective_to',r.effective_to) order by r.sort_order,lower(btrim(r.vehicle_class)),r.id) from public.rental_rate_rules r where r.is_active=true and r.effective_from<=v_at and (r.effective_to is null or r.effective_to>v_at)),'[]'::jsonb),
  'quotes',coalesce((select jsonb_agg(jsonb_build_object(
    'quote_id',q.id,'created_at',q.created_at,'status',q.status,'reservation_type',q.reservation_type,
    'start_date',q.start_date,'expected_return_datetime',q.expected_return_datetime,'notes',q.notes,
    'customer',jsonb_build_object('customer_id',c.id,'tekion_customer_number',c.tekion_customer_number,'name',c.name,'phone',c.phone,'email',c.email),
    'transportation_event_id',a.transportation_event_id,'pricing_agreement_id',a.id,'origin_type',a.origin_type,'vehicle_class',a.vehicle_class,
    'rental_rate_rule_id',a.rental_rate_rule_id,'pay_type_rule_id',a.pay_type_rule_id,'pay_type',p.pay_type,
    'initial_rate_plan',a.initial_rate_plan,'current_rate_plan',a.current_rate_plan,'daily_rate',a.daily_rate_snapshot::text,
    'weekly_rate',a.weekly_rate_snapshot::text,'monthly_rate',a.monthly_rate_snapshot::text,'pricing_started_at',a.pricing_started_at) order by q.start_date,q.created_at,q.id)
   from public.quotes q
   join public.rental_pricing_agreements a on a.quote_id=q.id and a.origin_type='quote' and a.reservation_id is null and a.is_active=true
   join public.transportation_events te on te.id=a.transportation_event_id and te.source_type='quote' and te.source_id=q.id and te.status='active'
   join public.customers c on c.id=q.customer_id
   join public.pay_type_rules p on p.id=a.pay_type_rule_id
   where q.is_active=true and q.status='active' and q.converted_to_reservation_id is null),'[]'::jsonb)
 );
end;$function$;

alter function public.get_pricing_agreement_intake_state() owner to postgres;
revoke all on function public.get_pricing_agreement_intake_state() from public,anon;
grant execute on function public.get_pricing_agreement_intake_state() to authenticated,service_role;

-- The existing EW cap engine remains authoritative; only snapshot Customer Pay's configured standard on its new split.
CREATE OR REPLACE FUNCTION public.reconcile_extended_warranty_coverage_state(p_transportation_event_id uuid, p_effective_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  v_case public.warranty_cases%ROWTYPE;
  v_event public.transportation_events%ROWTYPE;
  v_current_line public.billing_lines%ROWTYPE;
  v_existing_split public.billing_lines%ROWTYPE;
  v_post_coverage_pay_type public.pay_type_rules%ROWTYPE;
  v_effective_at timestamptz;
  v_coverage_boundary timestamptz;
  v_effective_covered_days integer;
  v_current_contract_day integer;
  v_close_result jsonb;
  v_split_result jsonb;
  v_split_line_id uuid;
  v_changed_at timestamptz;
BEGIN
  IF p_transportation_event_id IS NULL OR p_effective_at IS NULL THEN
    RAISE EXCEPTION 'Transportation event and effective timestamp are required'
      USING ERRCODE = '22023';
  END IF;

  SELECT warranty_case.*
    INTO v_case
  FROM public.warranty_cases warranty_case
  WHERE warranty_case.transportation_event_id =
    p_transportation_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'status', 'no_extended_warranty_case',
      'transportation_event_id', p_transportation_event_id
    );
  END IF;

  SELECT event.*
    INTO v_event
  FROM public.transportation_events event
  WHERE event.id = p_transportation_event_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transportation event was not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_case.coverage_started_at IS NULL THEN
    RAISE EXCEPTION 'Extended Warranty coverage start is missing'
      USING ERRCODE = '22023';
  END IF;

  v_effective_at :=
    least(
      p_effective_at,
      coalesce(v_event.closed_at, p_effective_at)
    );

  IF v_effective_at < v_case.coverage_started_at THEN
    RAISE EXCEPTION 'Effective timestamp precedes Extended Warranty coverage'
      USING ERRCODE = '22023';
  END IF;

  v_effective_covered_days :=
    coalesce(
      v_case.approved_days,
      v_case.default_covered_days_snapshot
    );

  v_current_contract_day :=
    public.business_contract_days(
      v_case.coverage_started_at,
      v_effective_at
    );

  v_changed_at := clock_timestamp();

  UPDATE public.warranty_cases
  SET current_day_count = v_current_contract_day,
      last_checked_at = v_changed_at,
      updated_at = v_changed_at
  WHERE id = v_case.id
  RETURNING *
    INTO v_case;

  IF v_effective_covered_days IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'extended_warranty_coverage_uncapped',
      'case_id', v_case.id,
      'transportation_event_id', p_transportation_event_id,
      'coverage_started_at', v_case.coverage_started_at,
      'current_contract_day', v_current_contract_day,
      'effective_covered_days', NULL,
      'split_required', false
    );
  END IF;

  v_coverage_boundary :=
    v_case.coverage_started_at
    + make_interval(days => v_effective_covered_days);

  SELECT line.*
    INTO v_existing_split
  FROM public.billing_lines line
  WHERE line.transportation_event_id =
      p_transportation_event_id
    AND line.parent_billing_line_id IS NULL
    AND line.line_type = 'pay_type_split'
    AND line.source_rule =
      'extended_warranty_coverage_cap'
  ORDER BY line.created_at, line.id
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    IF v_existing_split.start_time =
       v_coverage_boundary THEN
      UPDATE public.warranty_cases
      SET coverage_exhausted_at = v_coverage_boundary,
          updated_at = v_changed_at
      WHERE id = v_case.id
      RETURNING *
        INTO v_case;

      RETURN jsonb_build_object(
        'status', 'extended_warranty_coverage_already_split',
        'case_id', v_case.id,
        'transportation_event_id',
          p_transportation_event_id,
        'coverage_boundary', v_coverage_boundary,
        'current_contract_day',
          v_current_contract_day,
        'effective_covered_days',
          v_effective_covered_days,
        'split_billing_line_id',
          v_existing_split.id
      );
    END IF;

    UPDATE public.warranty_cases
    SET requires_manual_review = true,
        escalation_level =
          greatest(coalesce(escalation_level, 0), 1),
        updated_at = v_changed_at
    WHERE id = v_case.id
    RETURNING *
      INTO v_case;

    RETURN jsonb_build_object(
      'status',
        'extended_warranty_split_boundary_changed_manual_review',
      'case_id', v_case.id,
      'transportation_event_id',
        p_transportation_event_id,
      'existing_coverage_boundary',
        v_existing_split.start_time,
      'requested_coverage_boundary',
        v_coverage_boundary,
      'current_contract_day',
        v_current_contract_day,
      'effective_covered_days',
        v_effective_covered_days,
      'split_billing_line_id',
        v_existing_split.id,
      'requires_manual_review', true
    );
  END IF;

  IF v_effective_at < v_coverage_boundary THEN
    RETURN jsonb_build_object(
      'status', 'extended_warranty_coverage_active',
      'case_id', v_case.id,
      'transportation_event_id',
        p_transportation_event_id,
      'coverage_started_at',
        v_case.coverage_started_at,
      'coverage_boundary',
        v_coverage_boundary,
      'current_contract_day',
        v_current_contract_day,
      'effective_covered_days',
        v_effective_covered_days,
      'split_required', false
    );
  END IF;

  SELECT rule.*
    INTO v_post_coverage_pay_type
  FROM public.pay_type_rules rule
  WHERE rule.id =
    v_case.post_coverage_pay_type_rule_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post-coverage pay type was not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF lower(btrim(v_post_coverage_pay_type.pay_type)) =
     'extended warranty' THEN
    RAISE EXCEPTION 'Post-coverage pay type must differ from Extended Warranty'
      USING ERRCODE = '22023';
  END IF;

  SELECT line.*
    INTO v_current_line
  FROM public.billing_lines line
  WHERE line.transportation_event_id =
      p_transportation_event_id
    AND line.parent_billing_line_id IS NULL
    AND line.is_open = true
    AND lower(btrim(line.pay_type)) =
      'extended warranty'
    AND line.start_time <= v_coverage_boundary
    AND (
      line.end_time IS NULL
      OR line.end_time >= v_coverage_boundary
    )
  ORDER BY line.start_time DESC,
           line.created_at DESC,
           line.id DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    UPDATE public.warranty_cases
    SET requires_manual_review = true,
        escalation_level =
          greatest(coalesce(escalation_level, 0), 1),
        updated_at = v_changed_at
    WHERE id = v_case.id
    RETURNING *
      INTO v_case;

    RETURN jsonb_build_object(
      'status',
        'extended_warranty_split_line_missing_manual_review',
      'case_id', v_case.id,
      'transportation_event_id',
        p_transportation_event_id,
      'coverage_boundary',
        v_coverage_boundary,
      'current_contract_day',
        v_current_contract_day,
      'effective_covered_days',
        v_effective_covered_days,
      'requires_manual_review', true
    );
  END IF;

  v_close_result :=
    public.close_billing_line_state(
      v_current_line.id,
      v_coverage_boundary
    );

  v_split_result :=
    public.create_billing_parent_line_state(
      p_transportation_event_id =>
        p_transportation_event_id,
      p_reservation_id =>
        v_case.reservation_id,
      p_vehicle_id =>
        v_current_line.vehicle_id,
      p_pay_type =>
        v_post_coverage_pay_type.pay_type,
      p_amount =>
        0,
      p_tax_amount =>
        0,
      p_start_time =>
        v_coverage_boundary,
      p_end_time =>
        NULL,
      p_source_rule =>
        'extended_warranty_coverage_cap',
      p_vehicle_event_id =>
        v_current_line.vehicle_event_id,
      p_contract_period_id =>
        v_current_line.contract_period_id,
      p_line_type =>
        'pay_type_split',
      p_warranty_provider_id =>
        NULL,
      p_default_covered_days_snapshot =>
        NULL,
      p_covered_days_override =>
        NULL,
      p_is_open =>
        true,
      p_paid_through_at =>
        NULL,
      p_extended_from_billing_line_id =>
        v_current_line.id,
      p_default_daily_rate_snapshot =>
        CASE
          WHEN lower(btrim(v_post_coverage_pay_type.pay_type)) = 'customer pay'
            THEN v_post_coverage_pay_type.default_daily_amount
          ELSE NULL
        END, -- customer_pay_standard_snapshot
      p_daily_rate_override =>
        NULL
    );

  BEGIN
    v_split_line_id :=
      (v_split_result ->>
        'parent_billing_line_id')::uuid;
  EXCEPTION
    WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'Billing split returned an invalid identifier';
  END;

  IF v_split_line_id IS NULL THEN
    RAISE EXCEPTION 'Billing split did not return a billing-line identifier';
  END IF;

  UPDATE public.warranty_cases
  SET coverage_exhausted_at =
        v_coverage_boundary,
      requires_manual_review = false,
      updated_at = v_changed_at
  WHERE id = v_case.id
  RETURNING *
    INTO v_case;

  INSERT INTO public.audit_log (
    entity_type,
    entity_id,
    action_type,
    field_name,
    old_value,
    new_value,
    metadata,
    actor_user_id
  )
  VALUES (
    'extended_warranty_case',
    v_case.id::text,
    'coverage_pay_type_split',
    'coverage_exhausted_at',
    NULL,
    v_coverage_boundary::text,
    jsonb_build_object(
      'transportation_event_id',
        p_transportation_event_id,
      'provider_id', v_case.provider_id,
      'effective_covered_days',
        v_effective_covered_days,
      'closed_extended_warranty_billing_line_id',
        v_current_line.id,
      'post_coverage_billing_line_id',
        v_split_line_id,
      'post_coverage_pay_type_rule_id',
        v_post_coverage_pay_type.id,
      'post_coverage_pay_type',
        v_post_coverage_pay_type.pay_type,
      'close_result', v_close_result
    ),
    coalesce(
      auth.uid()::text,
      'system:extended_warranty_coverage'
    )
  );

  RETURN jsonb_build_object(
    'status', 'extended_warranty_coverage_split',
    'case_id', v_case.id,
    'transportation_event_id',
      p_transportation_event_id,
    'coverage_started_at',
      v_case.coverage_started_at,
    'coverage_boundary',
      v_case.coverage_exhausted_at,
    'current_contract_day',
      v_current_contract_day,
    'effective_covered_days',
      v_effective_covered_days,
    'closed_extended_warranty_billing_line_id',
      v_current_line.id,
    'post_coverage_billing_line_id',
      v_split_line_id,
    'post_coverage_pay_type_rule_id',
      v_post_coverage_pay_type.id,
    'post_coverage_pay_type',
      v_post_coverage_pay_type.pay_type
  );
END;
$function$;

alter function public.reconcile_extended_warranty_coverage_state(uuid,timestamptz) owner to postgres;
revoke all on function public.reconcile_extended_warranty_coverage_state(uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.reconcile_extended_warranty_coverage_state(uuid,timestamptz) to service_role;

create or replace function public.get_customer_pay_rate_override_capability_state()
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_user uuid; v_allowed boolean;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null then raise exception 'An active application user is required' using errcode='42501'; end if;
 if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication is required' using errcode='42501'; end if;
 select exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.customer_pay_rate_override') into v_allowed;
 return jsonb_build_object('status','customer_pay_rate_override_capability_ready','can_override_customer_pay_rate',v_allowed);
end;$function$;

create or replace function public.set_customer_pay_billing_line_rate_override_state(p_billing_line_id uuid,p_daily_rate_override numeric,p_reason text default null)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
 v_user uuid; v_line public.billing_lines%rowtype; v_reservation public.reservations%rowtype; v_event public.transportation_events%rowtype;
 v_old_override numeric; v_old_amount numeric; v_old_tax numeric; v_effective numeric; v_boundary timestamptz; v_days integer; v_new_amount numeric; v_new_tax numeric; v_tax_child jsonb; v_preview jsonb;
begin
 select id into v_user from public.app_users where auth_user_id=auth.uid() and is_active=true;
 if v_user is null then raise exception 'An active application user is required' using errcode='42501'; end if;
 if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'AAL2 authentication is required' using errcode='42501'; end if;
 if not exists(select 1 from public.v_user_effective_permissions where user_id=v_user and permission_key='billing.customer_pay_rate_override') then raise exception 'Customer Pay rate-override permission is required' using errcode='42501'; end if;
 if p_billing_line_id is null then raise exception 'Parent billing line is required' using errcode='22023'; end if;
 if p_daily_rate_override is not null and (p_daily_rate_override<0 or p_daily_rate_override in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Daily-rate override must be finite and nonnegative' using errcode='22023'; end if;
 if p_daily_rate_override is not null and p_daily_rate_override<>trunc(p_daily_rate_override,2) then raise exception 'Daily-rate override must have at most two decimal places' using errcode='22023'; end if;
 select * into v_line from public.billing_lines where id=p_billing_line_id for update;
 if not found then raise exception 'Billing line was not found' using errcode='P0002'; end if;
 if v_line.parent_billing_line_id is not null then raise exception 'A parent billing line is required' using errcode='22023'; end if;
 if lower(btrim(coalesce(v_line.pay_type,'')))<>'customer pay' then raise exception 'Only Customer Pay segments support this override' using errcode='22023'; end if;
 select * into v_reservation from public.reservations where id=v_line.reservation_id for share;
 if not found or lower(btrim(coalesce(v_reservation.reservation_type,'')))<>'loaner' then raise exception 'Only Customer Pay Loaner/RO segments support this override' using errcode='22023'; end if;
 select * into v_event from public.transportation_events where id=v_line.transportation_event_id for share;
 if not found then raise exception 'Transportation Event was not found' using errcode='P0002'; end if;
 if v_line.default_daily_rate_snapshot is null or v_line.default_daily_rate_snapshot<0 or v_line.default_daily_rate_snapshot in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Customer Pay segment standard snapshot is invalid' using errcode='P0001'; end if;
 v_old_override:=v_line.daily_rate_override; v_old_amount:=v_line.amount; v_old_tax:=v_line.tax_amount;
 v_effective:=coalesce(p_daily_rate_override,v_line.default_daily_rate_snapshot);
 v_boundary:=case when v_line.is_open then v_line.paid_through_at else coalesce(v_line.end_time,v_reservation.actual_return_datetime,v_event.closed_at,v_line.paid_through_at) end;
 if v_boundary is not null then
  if v_line.start_time is null or v_boundary<v_line.start_time then raise exception 'Billing segment boundary is invalid' using errcode='P0001'; end if;
  v_days:=public.business_contract_days(v_line.start_time,v_boundary);
  v_new_amount:=v_effective*v_days;
  v_new_tax:=case when coalesce(v_line.is_taxable_snapshot,false) then v_new_amount*coalesce(v_line.tax_rate_snapshot,0) else 0 end;
 else
  v_days:=null; v_new_amount:=v_line.amount; v_new_tax:=v_line.tax_amount;
 end if;
 update public.billing_lines set daily_rate_override=p_daily_rate_override,amount=v_new_amount,tax_amount=v_new_tax,updated_at=clock_timestamp() where id=v_line.id;
 v_tax_child:=public.ensure_tax_child_line_state(v_line.id);
 insert into public.audit_log(entity_type,entity_id,action_type,field_name,old_value,new_value,actor_user_id,metadata)
 values('billing_line',v_line.id::text,case when p_daily_rate_override is null then 'customer_pay_rate_override_cleared' else 'customer_pay_rate_override_changed' end,'daily_rate_override',v_old_override::text,p_daily_rate_override::text,v_user::text,
  jsonb_build_object('billing_line_id',v_line.id,'reservation_id',v_line.reservation_id,'ro_number',v_reservation.ro_number,'transportation_event_id',v_line.transportation_event_id,'old_override',v_old_override,'new_override',p_daily_rate_override,'standard_daily_rate_snapshot',v_line.default_daily_rate_snapshot,'old_amount',v_old_amount,'old_tax_amount',v_old_tax,'corrected_amount',case when v_boundary is null then null else v_new_amount end,'corrected_tax_amount',case when v_boundary is null then null else v_new_tax end,'billed_through_at',v_line.paid_through_at,'reason',nullif(btrim(p_reason),''),'actor_user_id',v_user,'whole_segment_start_time',v_line.start_time,'recalculation_boundary',v_boundary,'contract_days',v_days));
 v_preview:=public.get_billing_preview_state(v_line.transportation_event_id,clock_timestamp());
 return jsonb_build_object('status','customer_pay_rate_override_updated','billing_line_id',v_line.id,'transportation_event_id',v_line.transportation_event_id,'reservation_id',v_line.reservation_id,'daily_rate_override',p_daily_rate_override,'standard_daily_rate_snapshot',v_line.default_daily_rate_snapshot,'effective_daily_rate',v_effective,'stored_amount',v_new_amount,'stored_tax_amount',v_new_tax,'paid_through_at',v_line.paid_through_at,'recalculation_boundary',v_boundary,'contract_days',v_days,'tax_child',v_tax_child,'billing_preview',v_preview);
end;$function$;

alter function public.get_customer_pay_rate_override_capability_state() owner to postgres;
alter function public.set_customer_pay_billing_line_rate_override_state(uuid,numeric,text) owner to postgres;
revoke all on function public.get_customer_pay_rate_override_capability_state() from public,anon;
revoke all on function public.set_customer_pay_billing_line_rate_override_state(uuid,numeric,text) from public,anon;
grant execute on function public.get_customer_pay_rate_override_capability_state() to authenticated,service_role;
grant execute on function public.set_customer_pay_billing_line_rate_override_state(uuid,numeric,text) to authenticated,service_role;
