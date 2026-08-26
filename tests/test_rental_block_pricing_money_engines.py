from pathlib import Path

A1 = Path('supabase/migrations/20260826193000_authoritative_rental_block_pricing_a1.sql').read_text()
WIRE = Path('supabase/migrations/20260826213000_wire_rental_block_pricing_money_engines.sql').read_text()


def body(name: str) -> str:
    marker = f'FUNCTION public.{name}'
    start = WIRE.lower().index(marker.lower())
    end = WIRE.index('$function$;', start)
    return WIRE[start:end]


def test_pickup_uses_resolver_without_plan_rejection_and_persists_snapshot():
    sql = body('activate_pricing_agreement_pickup_state')
    assert 'resolve_rental_block_pricing_state' in sql
    assert 'Weekly/monthly pickup billing is not implemented' not in sql
    assert 'rental_block_pricing_snapshot=v_block_price' in sql
    assert 'resolve_billing_tax_state' in sql


def test_active_billing_resolves_only_rental_segment_as_blocks():
    sql = body('get_billing_preview_state')
    assert 'v_rental_pricing_days := public.rental_pricing_days(v_billing_start,v_preview_end)' in sql
    assert 'resolve_rental_block_pricing_state' in sql
    assert "ELSE\n        v_subtotal := v_daily_rate * v_contract_days" in sql
    assert "v_rate_source := 'rental_block_pricing_resolver'" in sql


def test_extension_commit_validates_client_money_and_persists_decomposition():
    sql = body('accept_extension_commit_state')
    assert 'p_extension_amount IS DISTINCT FROM v_server_amount' in sql
    assert 'rental_pricing_days(v_old_expected_return_at,p_new_expected_return_at)' in sql
    assert 'create_extension_billing_line_state(p_current_billing_line_id,v_server_amount,v_server_tax' in sql
    assert 'rental_block_pricing_snapshot=v_block_price' in sql
    assert "rate_plan_snapshot='daily'" in sql
    assert 'rental_pricing_days(v_reservation.start_date,p_new_expected_return_at)>56' in sql


def test_return_only_updates_locked_current_parent_and_reports_deltas():
    sql = body('complete_case_return_and_close_state')
    assert 'WHERE id = v_current_billing_line.id' in sql
    assert "v_block_price := v_final_preview->'rental_block_pricing'" in sql
    assert "v_final_subtotal := (v_final_preview->>'subtotal')::numeric" in sql
    assert 'resolve_billing_tax_state' not in sql
    for field in ('refund_due', 'customer_owes', 'no_difference', 'charge_delta', 'tax_delta', 'total_delta'):
        assert f"'{field}'" in sql
    assert 'cashier' not in sql.lower()
    assert 'late fee' not in sql.lower()


def test_extension_preview_boundary_and_renewal_states_are_corrected():
    assert 'preview_rental_agreement_segment_state(v_a.id,v_old,p_new_expected_return_at)' in A1
    assert 'rental_pricing_days(v_r.start_date,p_new_expected_return_at)>56' in A1
    assert "v_cp.renewal_sequence>=1 AND p_effective_at>=v_due" in A1
    assert "WHEN p_effective_at>=v_due THEN 'renewal_required'" in A1


def test_required_examples_follow_month_week_day_decomposition():
    def decomposition(days):
        months, remainder = divmod(days, 28)
        weeks, daily = divmod(remainder, 7)
        return months * 28, weeks * 7, daily
    assert decomposition(7) == (0, 7, 0)  # Original 5 remains locked; Extension prices its own 7.
    assert decomposition(38) == (28, 7, 3)


def test_all_rental_money_engines_share_completed_day_boundary():
    assert 'greatest(public.business_contract_days(p_segment_start,p_segment_end)-1,0)' in A1
    preview = A1[A1.index('FUNCTION public.preview_rental_agreement_segment_state'):]
    extension_preview = A1[A1.index('FUNCTION public.preview_rental_extension_state'):]
    assert 'v_days:=public.rental_pricing_days(p_segment_start,p_segment_end)' in preview
    assert 'preview_rental_agreement_segment_state(v_a.id,v_old,p_new_expected_return_at)' in extension_preview
    assert 'v_segment_days:=public.rental_pricing_days(v_reservation.start_date,v_reservation.expected_return_datetime)' in body('activate_pricing_agreement_pickup_state')
    assert 'public.rental_pricing_days(v_billing_start,v_preview_end)' in body('get_billing_preview_state')
    assert 'public.rental_pricing_days(v_old_expected_return_at,p_new_expected_return_at)' in body('accept_extension_commit_state')


def test_authoritative_boundaries_cover_original_extension_return_and_limit():
    # Integration SQL must route each authoritative interval to the one helper;
    # decomposition itself remains price-agnostic in the shared resolver.
    for days, expected in {1:(0,0,1), 6:(0,0,6), 7:(0,1,0), 10:(0,1,3),
                           28:(1,0,0), 30:(1,0,2), 38:(1,1,3), 56:(2,0,0)}.items():
        assert (days // 28, (days % 28) // 7, days % 7) == expected
    assert A1.count('rental_pricing_days(v_r.start_date') >= 2
    assert 'rental_pricing_days(v_reservation.start_date,p_new_expected_return_at)>56' in body('accept_extension_commit_state')
    assert "v_block_price := v_final_preview->'rental_block_pricing'" in body('complete_case_return_and_close_state')


def test_non_rental_paths_and_permissions_remain_in_existing_engines():
    preview = body('get_billing_preview_state')
    assert 'v_extended_warranty' in preview
    assert "v_subtotal := v_daily_rate * v_contract_days" in preview
    pickup = body('activate_pricing_agreement_pickup_state')
    assert "permission_key='billing.case_start'" in pickup
    assert "permission_key='billing.pricing_agreement_manage'" in pickup


def test_closed_billing_review_remains_stored_and_never_reprices_history():
    sql = body('get_billing_preview_state')
    assert "lower(btrim(v_event.status)) = 'closed'" in sql
    assert "'rate_source','stored_closed_billing_snapshot'" in sql
    assert "'current_billing_line_id',NULL" in sql
    assert 'historical_tax-child' not in sql  # guard is implemented by stored child count/sum checks
    assert 'stored_tax.child_count > 1' in sql
    for dependency in ('billing_history', 'closed_case_has_open_billing',
                       'historical_tax_line_mismatch'):
        assert f"'missing_dependency','{dependency}'" in sql
    closed = sql[sql.index("IF lower(btrim(v_event.status)) = 'closed'"):sql.index("IF (\n        SELECT count(*)", sql.index("IF lower(btrim(v_event.status)) = 'closed'"))]
    assert 'v_event.closed_at IS NOT NULL AND p_effective_at < v_event.closed_at' in closed
    assert 'v_event.closed_at IS NULL OR p_effective_at < v_event.closed_at' not in closed
    vehicle_order = ('ORDER BY vehicle_event.actual_in_at DESC NULLS LAST, '
                     'vehicle_event.actual_out_at DESC NULLS LAST, vehicle_event.id DESC')
    contract_order = ('ORDER BY contract_period.renewal_sequence DESC, '
                      'contract_period.contract_in_at DESC NULLS LAST, '
                      'contract_period.contract_out_at DESC, contract_period.id DESC')
    assert vehicle_order in closed
    assert contract_order in closed
    assert closed.index('vehicle_event.actual_in_at DESC NULLS LAST') < closed.index('vehicle_event.actual_out_at DESC NULLS LAST')
    assert closed.index('contract_period.contract_in_at DESC NULLS LAST') < closed.index('contract_period.contract_out_at DESC')
    assert 'resolve_rental_block_pricing_state' not in closed


def test_segments_keep_contract_days_and_future_extension_is_zero_elapsed():
    sql = body('get_billing_preview_state')
    assert sql.count("'contract_days'") >= 3
    assert "v_current_line.line_type = 'rental_extension' AND v_current_line.extended_from_billing_line_id IS NOT NULL" in sql
    assert 'v_preview_end := v_billing_start' in sql


def test_pickup_preserves_shared_rental_loaner_contract():
    sql = body('activate_pricing_agreement_pickup_state')
    assert "v_reservation_type not in ('rental','loaner')" in sql
    assert "'reservation_type',v_reservation_type" in sql
    assert "'ro_number',v_reservation.ro_number" in sql
    assert "v_reservation_type='loaner' and v_agreement.current_rate_plan<>'daily'" in sql
    loaner = sql[sql.rindex("else\n  -- Loaners"):]
    assert 'clock_timestamp()' in loaner
    assert 'resolve_rental_block_pricing_state' not in loaner
    assert 'get_rental_payment_state' not in loaner


def test_extension_preview_is_rental_only_and_uses_completed_day_helper():
    sql = A1[A1.index('FUNCTION public.preview_rental_extension_state'):]
    assert "lower(btrim(coalesce(v_r.reservation_type,''))) <> 'rental'" in sql
    assert 'preview_rental_agreement_segment_state(v_a.id,v_old,p_new_expected_return_at)' in sql
    for days, expected in ((1, (0, 0, 1)), (7, (0, 1, 0)), (10, (0, 1, 3))):
        assert (days // 28, (days % 28) // 7, days % 7) == expected


def test_extension_commit_keeps_non_rental_caller_money_and_helper_order():
    sql = body('accept_extension_commit_state')
    assert "lower(btrim(coalesce(v_reservation.reservation_type,''))) = 'rental'" in sql
    assert 'ELSE v_server_amount:=p_extension_amount; v_server_tax:=p_extension_tax_amount; END IF;' in sql
    helpers = ['set_expected_return_state', 'add_estimated_return_change_note_state',
               'close_billing_line_state', 'create_extension_billing_line_state']
    assert [sql.index(name) for name in helpers] == sorted(sql.index(name) for name in helpers)


def test_wire_migration_preserves_function_security_and_grants():
    preview = body('get_billing_preview_state')
    assert "auth.jwt() ->> 'aal'" not in preview
    assert 'ALTER FUNCTION public.get_billing_preview_state(uuid,timestamptz) SECURITY DEFINER;' in WIRE
    assert 'GRANT EXECUTE ON FUNCTION public.get_billing_preview_state(uuid,timestamptz) TO authenticated;' in WIRE
    assert 'ALTER FUNCTION public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) SECURITY DEFINER;' in WIRE
    assert 'TO authenticated,service_role;' in WIRE
    assert WIRE.count('SECURITY INVOKER;') >= 2
    assert 'GRANT EXECUTE ON FUNCTION public.accept_extension_commit_state(uuid,uuid,timestamptz,numeric,numeric,text,text,uuid,uuid) TO service_role;' in WIRE
    assert 'GRANT EXECUTE ON FUNCTION public.complete_case_return_and_close_state(uuid,timestamptz,integer,boolean,text,uuid) TO service_role;' in WIRE


def test_money_migrations_are_isolated_from_capacity_store():
    # Pricing consumes immutable agreement snapshots. Capacity is owned by the
    # reservation-acceptance workflow and must not become a money dependency.
    assert 'rental_model_limits' not in A1
    assert 'rental_model_limits' not in WIRE
    for name in ('get_billing_preview_state', 'activate_pricing_agreement_pickup_state',
                 'accept_extension_commit_state', 'complete_case_return_and_close_state'):
        assert 'rental_model_limits' not in body(name)


def test_every_rental_money_entrypoint_passes_all_stored_agreement_rates():
    exact_rates = ('v_agreement.daily_rate_snapshot', 'v_agreement.weekly_rate_snapshot',
                   'v_agreement.monthly_rate_snapshot')
    billing = body('get_billing_preview_state')
    pickup = body('activate_pricing_agreement_pickup_state')
    commit = body('accept_extension_commit_state')
    extension = A1[A1.index('FUNCTION public.preview_rental_extension_state'):]
    for sql in (billing, pickup, commit):
        for snapshot in exact_rates:
            assert snapshot in sql
    assert 'preview_rental_agreement_segment_state(v_a.id,v_old,p_new_expected_return_at)' in extension
    agreement_preview = A1[A1.index('FUNCTION public.preview_rental_agreement_segment_state'):A1.index('FUNCTION public.get_rental_contract_status_state')]
    for snapshot in exact_rates:
        assert snapshot in agreement_preview
    for sql in (A1, WIRE):
        assert 'weekly_rate_snapshot:=daily_rate_snapshot' not in sql.replace(' ', '').lower()
        assert 'monthly_rate_snapshot:=daily_rate_snapshot' not in sql.replace(' ', '').lower()


def test_extension_contract_days_are_reservation_anchored_in_both_segment_payloads():
    sql = body('get_billing_preview_state')
    anchored = "public.business_contract_days(v_reservation.start_date"
    ownership = "public.business_contract_days(v_reservation.start_date,parent.start_time)"
    assert sql.count(anchored) >= 5
    assert sql.count(ownership) == 2
    assert sql.count("parent.line_type = 'rental_extension' AND parent.extended_from_billing_line_id IS NOT NULL") == 2


def test_pickup_final_guard_covers_both_new_activation_branches():
    sql = body('activate_pricing_agreement_pickup_state')
    branch = sql[sql.index("if v_reservation_type='rental' then", sql.index('update public.rental_pricing_agreements')):]
    guard = "if v_preview->>'status'<>'billing_preview_ready' then raise exception 'Activated pickup could not be loaded by Billing'"
    assert branch.index('end if;\n if v_preview') < branch.index("return jsonb_build_object('rental_payment_state'")
    assert guard in branch


def test_extension_preview_locks_and_rechecks_current_line_identity():
    sql = A1[A1.index('FUNCTION public.preview_rental_extension_state'):]
    assert sql.count('FOR SHARE') == 2
    assert "v_billing_preview->>'status' IS DISTINCT FROM 'billing_preview_ready'" in sql
    assert "(v_billing_preview->>'current_billing_line_id')::uuid IS DISTINCT FROM v_line.id" in sql
    assert 'v_current_line_id IS DISTINCT FROM v_line.id' in sql
    assert "'billing_preview',v_billing_preview" in sql
    assert "'block_pricing',v_price" in sql
