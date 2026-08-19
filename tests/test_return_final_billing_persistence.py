from pathlib import Path


ROOT = Path(__file__).parents[1]
SQL = (ROOT / "supabase/migrations/20260819160500_verified_return_final_billing_persistence.sql").read_text()


def position(fragment: str) -> int:
    found = SQL.find(fragment)
    assert found >= 0, fragment
    return found


def test_authoritative_preview_is_persisted_before_return_and_close():
    preview = position("public.get_billing_preview_state(")
    returned = position("public.return_reservation_vehicle_use_state(")
    close_billing = position("public.close_current_reservation_billing_line_state(")
    close_event = position("public.close_transportation_event_state(")
    assert preview < returned < close_billing < close_event
    assert "v_final_preview->>'status' <> 'billing_preview_ready'" in SQL
    assert "(v_final_preview->>'current_billing_line_id')::uuid IS DISTINCT FROM v_current_billing_line.id" in SQL
    assert "v_final_subtotal := (v_final_preview->>'subtotal')::numeric" in SQL
    assert "v_final_tax := (v_final_preview->>'tax_amount')::numeric" in SQL
    assert "SET amount = v_final_subtotal" in SQL
    assert "tax_amount = v_final_tax" in SQL


def test_existing_parent_and_tax_child_are_strictly_reconciled():
    assert "line.id = v_candidate.parent_billing_line_id" in SQL
    assert "line.parent_billing_line_id IS NOT NULL" in SQL
    assert "line.is_open IS DISTINCT FROM true" in SQL
    assert "public.ensure_tax_child_line_state(v_current_billing_line.id)" in SQL
    assert "v_tax_child_count <> 1" in SQL
    assert "v_tax_child_amount IS DISTINCT FROM v_final_tax" in SQL
    assert "v_final_tax = 0 AND v_tax_child_count <> 0" in SQL
    assert "v_billing_close_result->>'parent_billing_line_id'" in SQL


def test_no_second_calculator_or_manual_checkpoint_permission():
    for forbidden in (
        "resolve_rental_daily_rate_state",
        "resolve_case_tax_state",
        "business_contract_days",
        "billing.mark_billed_through",
        "mark_case_billed_through",
    ):
        assert forbidden not in SQL


def test_optional_open_billing_branch_and_response_contract_are_preserved():
    assert "IF p_close_billing AND coalesce(v_candidate.has_open_billing_line, false) THEN" in SQL
    assert "public.set_reservation_actual_return_state(" in SQL
    for key in (
        "'status', 'case_returned_and_closed'",
        "'reservation_id', p_reservation_id",
        "'transportation_event_id', v_reservation.transportation_event_id",
        "'actual_in_at', p_actual_in_at",
        "'return_result', v_return_result",
        "'billing_close_result', v_billing_close_result",
        "'transportation_event_close_result', v_transportation_close_result",
    ):
        assert key in SQL


def test_verified_function_metadata_is_preserved():
    signature = "complete_case_return_and_close_state(uuid,timestamptz,integer,boolean,text,uuid)"
    assert "SECURITY INVOKER" in SQL
    assert f"ALTER FUNCTION public.{signature} OWNER TO postgres" in SQL
    assert f"ALTER FUNCTION public.{signature} RESET ALL" in SQL
    assert f"REVOKE ALL ON FUNCTION public.{signature} FROM PUBLIC, anon, authenticated" in SQL
    assert f"GRANT EXECUTE ON FUNCTION public.{signature} TO service_role" in SQL
    assert "SET search_path" not in SQL
