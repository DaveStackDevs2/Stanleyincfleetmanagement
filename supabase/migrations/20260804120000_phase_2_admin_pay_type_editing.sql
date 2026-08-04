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

  update public.pay_type_rules
  set
    is_taxable = p_is_taxable,
    tax_applicable = p_is_taxable,
    default_daily_amount = p_default_daily_amount,
    sort_order = p_sort_order,
    description = nullif(btrim(p_description), ''),
    updated_at = now()
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

ALTER FUNCTION public.update_admin_pay_type_rule_state(uuid, boolean, numeric, integer, text) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.update_admin_pay_type_rule_state(uuid, boolean, numeric, integer, text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.update_admin_pay_type_rule_state(uuid, boolean, numeric, integer, text) TO authenticated, service_role;
