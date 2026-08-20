from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20260820120000_verified_authoritative_extensions.sql").read_text()
UI = (ROOT / "frontend/src/billing/BillingWorkspace.tsx").read_text()


def test_extension_boundary_is_scoped_to_three_expected_preview_branches():
    assert "pg_get_functiondef('public.get_billing_preview_state(uuid,timestamptz)'::regprocedure)" in SQL
    assert "chr(13)" in SQL
    assert "v_boundary_at" in SQL and "v_expression_start" in SQL and "v_expression_end" in SQL
    assert "Splice back-to-front" in SQL
    assert "v_definition := replace(v_definition" not in SQL
    assert "regexp_count(v_definition" in SQL
    assert "v_current_line.line_type = ''rental_extension''" in SQL
    assert "parent.line_type = ''rental_extension''" in SQL
    assert SQL.count("greatest(0, public.business_contract_days") >= 3
    assert "ELSE public.business_contract_days(v_billing_start, v_preview_end)" in SQL
    assert "stored_closed_billing_snapshot" not in SQL  # closed stored-money branch is not replaced


def test_wrapper_derives_money_from_exact_authoritative_preview_line():
    assert "public.get_billing_preview_state(v_candidate.transportation_event_id,p_new_expected_return_at)" in SQL
    assert "(v_preview->>'current_billing_line_id')::uuid IS DISTINCT FROM v_current_line.id" in SQL
    assert "(v_preview->>'subtotal')::numeric-v_current_line.amount" in SQL
    assert "public.accept_reservation_extension_state" in SQL
    assert "v_authoritative_extension_amount,NULL,p_reason_code" in SQL
    assert "submitted_amounts_ignored',true" in SQL
    assert "p_extension_amount" in SQL and "p_extension_tax_amount" in SQL
    assert "line.reservation_id=p_reservation_id" in SQL
    assert "line.transportation_event_id=v_candidate.transportation_event_id" in SQL
    assert "line.parent_billing_line_id IS NULL" in SQL
    assert "line.line_type IS DISTINCT FROM 'tax'" in SQL
    assert "line.is_open=true FOR UPDATE" in SQL
    assert "coalesce(v_candidate.current_expected_return_at, v_candidate.expected_return_datetime)" in SQL


def test_wrapper_preserves_verified_live_response_contract():
    fields = [
        "status", "reservation_id", "transportation_event_id",
        "previous_expected_return_at", "new_expected_return_at",
        "previous_billing_line_id", "billed_through_at",
        "authoritative_extension_amount", "submitted_amounts_ignored",
        "proposed_billing_preview", "action_result", "unified_case_payload",
    ]
    for field in fields:
        assert f"'{field}'" in SQL


def test_repeated_extension_requires_billed_through_progress():
    assert "v_current_line.line_type='rental_extension'" in SQL
    assert "v_current_line.paid_through_at<=v_current_line.start_time" in SQL


def test_frontend_uses_existing_rpcs_without_billing_arithmetic():
    extension = UI[UI.index("function ExtensionAction"):UI.index("function CompletionAction")]
    assert "Mark billed through" in extension
    assert "get_billing_preview_state" in extension
    assert "accept_case_extension_and_get_unified_payload_state" in extension
    assert "p_extension_amount:0" in extension
    assert "p_extension_tax_amount:null" in extension
    assert "v.submitted_amounts_ignored!==true" in UI
    assert "sameInstant(preview.effective_at,proposed)" in extension
    assert "preview.effective_at!==proposed" not in extension
    assert "Date.parse" in UI
    assert "sameInstant(v.new_expected_return_at,proposed)" in UI
    assert "v.previous_billing_line_id!==item.preview.current_billing_line_id" in UI
    assert "v.proposed_billing_preview.current_billing_line_id!==item.preview.current_billing_line_id" in UI
    for field in ("previous_expected_return_at", "new_expected_return_at", "previous_billing_line_id", "billed_through_at"):
        assert field in UI
    for arithmetic in ("preview.subtotal -", "preview.tax_amount +", "parseFloat", "toFixed"):
        assert arithmetic not in extension


def test_frontend_guards_duplicate_and_reloads_authoritative_state():
    extension = UI[UI.index("function ExtensionAction"):UI.index("function CompletionAction")]
    assert "busy||committed" in extension
    assert "setCommitted(true)" in extension
    assert "await onReload(item.transportation_event_id)" in extension
    assert "parseExtensionResponse(result.data,item,proposed)" in extension
