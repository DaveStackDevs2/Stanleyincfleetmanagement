-- Reproduces the Admin pay-type contracts already applied to the live project.

CREATE OR REPLACE FUNCTION public.get_admin_pay_type_rules_state()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_user_admin_permission();

  return jsonb_build_object(
    'status',
    'admin_pay_type_rules_ready',
    'pay_types',
    (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', rule.id,
            'pay_type', rule.pay_type,
            'description', rule.description,
            'is_taxable', rule.is_taxable,
            'default_daily_amount', rule.default_daily_amount,
            'sort_order', rule.sort_order,
            'is_enabled', rule.is_active and rule.active
          )
          order by rule.sort_order, rule.pay_type, rule.id
        ),
        '[]'::jsonb
      )
      from public.pay_type_rules rule
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_admin_pay_type_rule_state(p_pay_type text, p_is_taxable boolean, p_default_daily_amount numeric, p_sort_order integer, p_description text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_rule public.pay_type_rules;
begin
  perform public.require_user_admin_permission();

  if p_pay_type is null
     or btrim(p_pay_type) = ''
     or p_is_taxable is null
     or p_default_daily_amount is null
     or p_default_daily_amount < 0
     or p_sort_order is null
  then
    raise exception 'Invalid pay type rule'
      using errcode = '22023';
  end if;

  insert into public.pay_type_rules (
    pay_type,
    tax_applicable,
    priority,
    stacking_allowed,
    active,
    is_active,
    is_taxable,
    default_daily_amount,
    sort_order,
    description
  )
  values (
    btrim(p_pay_type),
    p_is_taxable,
    p_sort_order,
    false,
    true,
    true,
    p_is_taxable,
    p_default_daily_amount,
    p_sort_order,
    nullif(btrim(p_description), '')
  )
  returning * into v_rule;

  return jsonb_build_object(
    'status', 'admin_pay_type_rule_created',
    'pay_type_rule_id', v_rule.id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_admin_pay_type_rule_enabled_state(p_pay_type_rule_id uuid, p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_user_admin_permission();

  if p_pay_type_rule_id is null or p_enabled is null then
    raise exception 'Invalid pay type rule state'
      using errcode = '22023';
  end if;

  update public.pay_type_rules
  set active = p_enabled,
      is_active = p_enabled,
      updated_at = now()
  where id = p_pay_type_rule_id;

  if not found then
    raise exception 'Pay type rule not found'
      using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'status', 'admin_pay_type_rule_enabled_state_saved',
    'pay_type_rule_id', p_pay_type_rule_id,
    'is_enabled', p_enabled
  );
end;
$function$;

revoke all on function public.get_admin_pay_type_rules_state() from public, anon, authenticated;
revoke all on function public.create_admin_pay_type_rule_state(text, boolean, numeric, integer, text) from public, anon, authenticated;
revoke all on function public.set_admin_pay_type_rule_enabled_state(uuid, boolean) from public, anon, authenticated;

grant execute on function public.get_admin_pay_type_rules_state() to authenticated;
grant execute on function public.create_admin_pay_type_rule_state(text, boolean, numeric, integer, text) to authenticated;
grant execute on function public.set_admin_pay_type_rule_enabled_state(uuid, boolean) to authenticated;
