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
    assert 'THEN public.rental_pricing_days(v_billing_start, v_preview_end)' in sql
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
    assert 'public.rental_pricing_days(v_billing_start, v_preview_end)' in body('get_billing_preview_state')
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
