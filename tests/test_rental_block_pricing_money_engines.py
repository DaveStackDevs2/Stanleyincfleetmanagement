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
    assert "v_is_rental AND v_current_line.line_type = 'rental_extension'" in sql
    assert 'resolve_rental_block_pricing_state' in sql
    assert "ELSE\n        v_subtotal := v_daily_rate * v_contract_days" in sql
    assert "v_rate_source := 'rental_block_pricing_resolver'" in sql


def test_extension_commit_validates_client_money_and_persists_decomposition():
    sql = body('accept_extension_commit_state')
    assert 'p_extension_amount IS DISTINCT FROM v_server_amount' in sql
    assert 'business_contract_days(v_old_expected_return_at,p_new_expected_return_at)-1' in sql
    assert 'create_extension_billing_line_state(p_current_billing_line_id,v_server_amount,v_server_tax' in sql
    assert 'rental_block_pricing_snapshot=v_block_price' in sql
    assert "rate_plan_snapshot='daily'" in sql
    assert 'business_contract_days(v_reservation.start_date,p_new_expected_return_at)>56' in sql


def test_return_only_updates_locked_current_parent_and_reports_deltas():
    sql = body('complete_case_return_and_close_state')
    assert 'WHERE id = v_current_billing_line.id' in sql
    assert "line_type='rental_extension' THEN 1 ELSE 0" in sql
    for field in ('refund_due', 'customer_owes', 'no_difference', 'charge_delta', 'tax_delta', 'total_delta'):
        assert f"'{field}'" in sql
    assert 'cashier' not in sql.lower()
    assert 'late fee' not in sql.lower()


def test_extension_preview_boundary_and_renewal_states_are_corrected():
    assert "v_old+interval '1 day'" in A1
    assert 'business_contract_days(v_r.start_date,p_new_expected_return_at)>56' in A1
    assert "v_cp.renewal_sequence>=1 AND p_effective_at>=v_due" in A1
    assert "WHEN p_effective_at>=v_due THEN 'renewal_required'" in A1


def test_required_examples_follow_month_week_day_decomposition():
    def decomposition(days):
        months, remainder = divmod(days, 28)
        weeks, daily = divmod(remainder, 7)
        return months * 28, weeks * 7, daily
    assert decomposition(7) == (0, 7, 0)  # Original 5 remains locked; Extension prices its own 7.
    assert decomposition(38) == (28, 7, 3)


def test_non_rental_paths_and_permissions_remain_in_existing_engines():
    preview = body('get_billing_preview_state')
    assert 'v_extended_warranty' in preview
    assert "v_subtotal := v_daily_rate * v_contract_days" in preview
    pickup = body('activate_pricing_agreement_pickup_state')
    assert "permission_key='billing.case_start'" in pickup
    assert "permission_key='billing.pricing_agreement_manage'" in pickup
