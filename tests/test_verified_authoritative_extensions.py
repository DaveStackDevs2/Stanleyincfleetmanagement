from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20260820120000_verified_authoritative_extensions.sql").read_text()
PR34_SQL = (ROOT / "supabase/migrations/20260819143500_verified_closed_billing_review.sql").read_text()
UI = (ROOT / "frontend/src/billing/BillingWorkspace.tsx").read_text()


def test_extension_boundary_is_scoped_to_three_expected_preview_branches():
    assert "pg_get_functiondef('public.get_billing_preview_state(uuid,timestamptz)'::regprocedure)" in SQL
    assert "chr(13)" in SQL
    assert "v_boundary_at" in SQL
    assert "v_closed_expression_start" in SQL and "v_closed_expression_end" in SQL
    assert "v_active_expression_start" in SQL and "v_active_expression_end" in SQL
    assert "Splice back-to-front" in SQL
    assert "v_definition := replace(v_definition" not in SQL
    assert "regexp_count(v_definition" in SQL
    assert "v_current_line.line_type = ''rental_extension''" in SQL
    assert "parent.line_type = ''rental_extension''" in SQL
    assert SQL.count("greatest(0, public.business_contract_days") >= 3
    assert "ELSE public.business_contract_days(v_billing_start, v_preview_end)" in SQL
    assert "stored_closed_billing_snapshot" not in SQL  # closed stored-money branch is not replaced


def test_closed_splice_anchor_matches_pr34_baseline_structure():
    closed_anchor = "IF lower(btrim(v_event.status)) = 'closed' THEN"
    nonexistent_anchor = "IF v_event.status IN ('closed','completed','cancelled') THEN"

    # Exercise the structural assumption against the migration that introduced the
    # closed branch: its segment contract-days expression must fall inside that branch.
    closed_start = PR34_SQL.index(closed_anchor)
    closed_end = PR34_SQL.index("$closed$;", closed_start)
    contract_days = PR34_SQL.index("'contract_days'", closed_start, closed_end)
    is_open = PR34_SQL.index("'is_open'", contract_days, closed_end)
    assert closed_start < contract_days < is_open < closed_end

    # The Extension migration must search for that exact baseline anchor and must
    # never regress to the status-list branch that exists in neither PR #34 nor live.
    sql_literal_anchor = "IF lower(btrim(v_event.status)) = ''closed'' THEN"
    sql_literal_nonexistent = "IF v_event.status IN (''closed'',''completed'',''cancelled'') THEN"
    assert sql_literal_anchor in SQL
    assert sql_literal_nonexistent not in SQL
    assert nonexistent_anchor not in PR34_SQL


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
    assert "Mark Tekion updated" in UI
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

FOLLOWUP_SQL = (ROOT / "supabase/migrations/20260820173000_correct_estimated_return_note_columns.sql").read_text()


def test_note_helper_uses_live_transportation_event_note_columns_without_widening_access():
    insert_columns = FOLLOWUP_SQL[FOLLOWUP_SQL.index("INSERT INTO public.transportation_event_notes"):FOLLOWUP_SQL.index("VALUES", FOLLOWUP_SQL.index("INSERT INTO public.transportation_event_notes"))]
    assert "old_estimated_return" in insert_columns
    assert "new_estimated_return" in insert_columns
    assert "old_expected_return_at" not in insert_columns
    assert "new_expected_return_at" not in insert_columns
    assert "old_expected_return_at" in FOLLOWUP_SQL  # signature and JSON contract stay stable
    assert "new_expected_return_at" in FOLLOWUP_SQL
    assert "SECURITY INVOKER" in FOLLOWUP_SQL
    assert "GRANT " not in FOLLOWUP_SQL and "REVOKE " not in FOLLOWUP_SQL


def test_active_case_session_navigation_contract():
    assert "sessionStorage.getItem(ACTIVE_CASE_STORAGE_KEY)" in UI
    assert "useState<string|null>(rememberedActiveCase)" in UI
    assert "const candidate=keepSelected??current" in UI
    assert "parsed?.items.some" in UI
    assert "rememberActiveCase(item.transportation_event_id)" in UI
    assert "Back to active cases" in UI and "forgetActiveCase()" in UI
    assert "setMode('closed');setSelected(null);forgetActiveCase()" in UI
    assert "if(reloaded){forgetActiveCase();setCompletionItem(null)" in UI


def test_active_case_uses_staff_facing_labels_and_compact_history():
    active = UI[UI.index("function CaseDetail"):UI.index("const closedClassification")]
    extension = UI[UI.index("function ExtensionAction"):UI.index("function CompletionAction")]
    for label_text in ("Current rental", "Tekion billing", "Updated through:", "Mark Tekion updated", "Extend rental", "New return", "Billing history"):
        assert label_text in UI
    for removed in ("Authoritative Extension preview", "Billed-through boundary", "Stored current parent amount", "Stored current parent tax", "Projected subtotal", "Stored billing segment detail", "final Extension segment"):
        assert removed not in active and removed not in extension
    assert "preview.accumulated_subtotal" in extension
    assert "preview.accumulated_tax" in extension
    assert "preview.accumulated_total" in extension
    assert "<table>" not in active
    assert "{p.extended_warranty&&" in active
    assert "Not configured" not in active


def test_successful_extension_resets_form_and_known_rejection_is_sanitized():
    extension = UI[UI.index("function ExtensionAction"):UI.index("function CompletionAction")]
    for reset in ("setPreview(null)", "setAt('')", "setReason('')", "setNote('')", "setCommitted(false)"):
        assert reset in extension
    assert "Rental extended to ${showDate(proposed)}." in extension
    assert "Update Tekion billing through a later time before extending this rental again." in extension
    assert "result.error?.message" not in extension
