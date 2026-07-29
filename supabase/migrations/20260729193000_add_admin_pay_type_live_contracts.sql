-- Reproduces the Admin pay-type contracts already applied to the live project.

CREATE OR REPLACE FUNCTION public.get_admin_pay_type_rules_state()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid;
  v_access jsonb;
  v_pay_types jsonb;
  v_colors jsonb;
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

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'pay_type_rule_id', rule.id,
        'pay_type', rule.pay_type,
        'is_enabled', rule.is_active and coalesce(rule.active, false),
        'is_active', rule.is_active,
        'active', coalesce(rule.active, false),
        'is_taxable', rule.is_taxable,
        'tax_applicable', coalesce(rule.tax_applicable, false),
        'default_daily_amount', rule.default_daily_amount,
        'sort_order', rule.sort_order,
        'priority', coalesce(rule.priority, 0),
        'stacking_allowed', coalesce(rule.stacking_allowed, true),
        'description', rule.description
      )
      order by rule.sort_order, rule.pay_type
    ),
    '[]'::jsonb
  )
    into v_pay_types
  from public.pay_type_rules rule;

  select coalesce(setting_value, '{}'::jsonb)
    into v_colors
  from public.admin_settings
  where setting_key = 'fleet_board.pay_type_colors';

  return jsonb_build_object(
    'status', 'admin_pay_type_rules_ready',
    'can_manage', true,
    'pay_types', v_pay_types,
    'colors', coalesce(v_colors, '{}'::jsonb)
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

  if p_is_taxable is null then
    raise exception 'Taxable selection is required'
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
    p_is_taxable,
    true,
    true,
    p_is_taxable,
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

CREATE OR REPLACE FUNCTION public.set_admin_pay_type_rule_enabled_state(p_pay_type_rule_id uuid, p_is_enabled boolean)
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

  if p_pay_type_rule_id is null then
    raise exception 'Pay type rule ID is required'
      using errcode = '22023';
  end if;

  if p_is_enabled is null then
    raise exception 'Enabled selection is required'
      using errcode = '22023';
  end if;

  update public.pay_type_rules
  set
    is_active = p_is_enabled,
    active = p_is_enabled
  where id = p_pay_type_rule_id
  returning *
    into v_rule;

  if not found then
    raise exception 'Pay type rule not found'
      using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'status',
    case
      when p_is_enabled then 'admin_pay_type_rule_enabled'
      else 'admin_pay_type_rule_disabled'
    end,
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

revoke all on function public.get_admin_pay_type_rules_state() from public, anon, authenticated;
revoke all on function public.create_admin_pay_type_rule_state(text, boolean, numeric, integer, text) from public, anon, authenticated;
revoke all on function public.set_admin_pay_type_rule_enabled_state(uuid, boolean) from public, anon, authenticated;

grant execute on function public.get_admin_pay_type_rules_state() to authenticated;
grant execute on function public.create_admin_pay_type_rule_state(text, boolean, numeric, integer, text) to authenticated;
grant execute on function public.set_admin_pay_type_rule_enabled_state(uuid, boolean) to authenticated;
