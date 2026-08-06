-- Billing Phase 4 follow-up: the stored Admin-selected pay-type taxability is authoritative.
-- This migration intentionally does not seed or rewrite any pay_type_rules rows.

alter table public.pay_type_rules
  drop constraint if exists ck_pay_type_rules_only_warranty_tax_exempt;
alter table public.pay_type_rules
  drop constraint if exists ck_pay_type_rules_tax_fields_synchronized;
alter table public.pay_type_rules
  add constraint ck_pay_type_rules_tax_fields_synchronized
  check (tax_applicable = is_taxable);

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
  if v_rule.is_taxable is null or v_rule.tax_applicable is distinct from v_rule.is_taxable then
    raise exception 'Pay type tax configuration is invalid' using errcode='22023';
  end if;
  v_taxable := v_rule.is_taxable;
  if not v_taxable then v_rate:=0; v_source:='pay_type_exemption'; v_explanation:=v_rule.pay_type || ' is configured as exempt from loaner and rental tax.';
  else
    begin select (setting_value #>> '{}')::numeric into v_rate from public.admin_settings where setting_key='billing.loaner_rental_tax_rate';
    exception when others then raise exception 'Loaner and rental tax rate is invalid' using errcode='22023'; end;
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

create or replace function public.create_admin_pay_type_rule_state(p_pay_type text, p_is_taxable boolean, p_default_daily_amount numeric, p_sort_order integer, p_description text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_user_id uuid; v_access jsonb; v_rule public.pay_type_rules%rowtype;
begin
  select au.id into v_user_id from public.app_users au where au.auth_user_id=auth.uid() and au.is_active=true;
  if v_user_id is null then raise exception 'Pay type administration access denied' using errcode='42501'; end if;
  v_access:=public.get_user_admin_setting_access_state(v_user_id,'fleet_board.pay_type_colors');
  if coalesce((v_access->>'allowed')::boolean,false) is not true then raise exception 'Pay type administration access denied' using errcode='42501'; end if;
  if p_pay_type is null or btrim(p_pay_type)='' then raise exception 'Pay type name cannot be blank' using errcode='22023'; end if;
  if p_is_taxable is null then raise exception 'Taxable selection is required' using errcode='22023'; end if;
  if p_sort_order is null or p_sort_order<0 then raise exception 'Sort order must be zero or greater' using errcode='22023'; end if;
  if p_default_daily_amount is not null and p_default_daily_amount<0 then raise exception 'Default daily amount must be zero or greater' using errcode='22023'; end if;
  if exists(select 1 from public.pay_type_rules rule where lower(btrim(rule.pay_type))=lower(btrim(p_pay_type))) then raise exception 'Pay type already exists' using errcode='23505'; end if;
  insert into public.pay_type_rules(pay_type,tax_applicable,active,is_active,is_taxable,default_daily_amount,sort_order,description)
  values(btrim(p_pay_type),p_is_taxable,true,true,p_is_taxable,p_default_daily_amount,p_sort_order,nullif(btrim(p_description),'')) returning * into v_rule;
  return jsonb_build_object('status','admin_pay_type_rule_created','pay_type_rule',jsonb_build_object(
    'pay_type_rule_id',v_rule.id,'pay_type',v_rule.pay_type,'is_enabled',v_rule.is_active and coalesce(v_rule.active,false),
    'is_active',v_rule.is_active,'active',coalesce(v_rule.active,false),'is_taxable',v_rule.is_taxable,
    'tax_applicable',coalesce(v_rule.tax_applicable,false),'default_daily_amount',v_rule.default_daily_amount,
    'sort_order',v_rule.sort_order,'description',v_rule.description));
end $function$;

create or replace function public.update_admin_pay_type_rule_state(p_pay_type_rule_id uuid, p_is_taxable boolean, p_default_daily_amount numeric, p_sort_order integer, p_description text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_user_id uuid; v_access jsonb; v_rule public.pay_type_rules%rowtype;
begin
  select au.id into v_user_id from public.app_users au where au.auth_user_id=auth.uid() and au.is_active=true;
  if v_user_id is null then raise exception 'Pay type administration access denied' using errcode='42501'; end if;
  v_access:=public.get_user_admin_setting_access_state(v_user_id,'fleet_board.pay_type_colors');
  if coalesce((v_access->>'allowed')::boolean,false) is not true then raise exception 'Pay type administration access denied' using errcode='42501'; end if;
  if p_pay_type_rule_id is null then raise exception 'Pay type rule ID is required' using errcode='22023'; end if;
  if p_is_taxable is null then raise exception 'Taxable selection is required' using errcode='22023'; end if;
  if p_sort_order is null or p_sort_order<0 then raise exception 'Sort order must be zero or greater' using errcode='22023'; end if;
  if p_default_daily_amount is not null and p_default_daily_amount<0 then raise exception 'Default daily amount must be zero or greater' using errcode='22023'; end if;
  select * into v_rule from public.pay_type_rules where id=p_pay_type_rule_id for update;
  if not found then raise exception 'Pay type rule not found' using errcode='P0002'; end if;
  update public.pay_type_rules set is_taxable=p_is_taxable,tax_applicable=p_is_taxable,
    default_daily_amount=p_default_daily_amount,sort_order=p_sort_order,description=nullif(btrim(p_description),''),updated_at=clock_timestamp()
  where id=p_pay_type_rule_id returning * into v_rule;
  return jsonb_build_object('status','admin_pay_type_rule_updated','pay_type_rule',jsonb_build_object(
    'pay_type_rule_id',v_rule.id,'pay_type',v_rule.pay_type,'is_enabled',v_rule.is_active and coalesce(v_rule.active,false),
    'is_active',v_rule.is_active,'active',coalesce(v_rule.active,false),'is_taxable',v_rule.is_taxable,
    'tax_applicable',coalesce(v_rule.tax_applicable,false),'default_daily_amount',v_rule.default_daily_amount,
    'sort_order',v_rule.sort_order,'description',v_rule.description));
end $function$;

alter function public.create_admin_pay_type_rule_state(text,boolean,numeric,integer,text) owner to postgres;
alter function public.update_admin_pay_type_rule_state(uuid,boolean,numeric,integer,text) owner to postgres;
revoke all on function public.create_admin_pay_type_rule_state(text,boolean,numeric,integer,text) from public,anon,authenticated;
revoke all on function public.update_admin_pay_type_rule_state(uuid,boolean,numeric,integer,text) from public,anon,authenticated;
grant execute on function public.create_admin_pay_type_rule_state(text,boolean,numeric,integer,text) to authenticated,service_role;
grant execute on function public.update_admin_pay_type_rule_state(uuid,boolean,numeric,integer,text) to authenticated,service_role;
