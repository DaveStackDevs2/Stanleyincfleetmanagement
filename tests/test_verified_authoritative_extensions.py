from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20260820120000_verified_authoritative_extensions.sql").read_text()
PR34_SQL = (ROOT / "supabase/migrations/20260819143500_verified_closed_billing_review.sql").read_text()
FINAL = (ROOT / 'supabase/migrations/20260821170000_correct_rental_payment_and_extension_workflow.sql').read_text()
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


def test_final_wrapper_reuses_preview_and_existing_chain():
    wrapper=FINAL[FINAL.index('CREATE OR REPLACE FUNCTION public.accept_case_extension_and_get_unified_payload_state'):]
    assert 'public.preview_rental_extension_state' in wrapper
    assert 'public.accept_reservation_extension_state' in wrapper
    assert 'get_unified_case_payload_state' in wrapper
    assert 'UPDATE public.billing_lines' not in wrapper
    assert 'set_expected_return_state' not in wrapper


def test_final_chain_removes_paid_through_dependency():
    commit=FINAL[FINAL.index('CREATE OR REPLACE FUNCTION public.accept_extension_commit_state'):FINAL.index('CREATE OR REPLACE FUNCTION public.accept_case_extension_and_get_unified_payload_state')]
    create=FINAL[FINAL.index('CREATE OR REPLACE FUNCTION public.create_extension_billing_line_state'):FINAL.index('CREATE OR REPLACE FUNCTION public.accept_extension_commit_state')]
    assert 'close_billing_line_state(p_current_billing_line_id,v_old_expected_return_at)' in commit
    assert 'close_billing_line_at_paid_through_state' not in commit
    assert 'v_parent.end_time,p_new_expected_return_at' in create
    assert 'v_parent.paid_through_at' not in create


def test_frontend_uses_existing_rpcs_without_billing_arithmetic():
    extension = UI[UI.index("function ExtensionAction"):UI.index("function CompletionAction")]
    assert "Update billed through" in UI
    assert "preview_rental_extension_state" in extension
    assert "accept_case_extension_and_get_unified_payload_state" in extension
    assert "p_extension_amount:0" in extension
    assert "p_extension_tax_amount:null" in extension
    assert "preview.effective_at!==proposed" not in extension
    for field in ("additional_charge", "additional_tax", "additional_total", "new_billing_line_id"):
        assert field in UI or field in SQL
    for arithmetic in ("preview.subtotal -", "preview.tax_amount +", "parseFloat", "toFixed"):
        assert arithmetic not in extension


def test_frontend_guards_duplicate_and_reloads_authoritative_state():
    extension = UI[UI.index("function ExtensionAction"):UI.index("function CompletionAction")]
    assert "if(!value||!preview)return" in extension
    assert "setBusy(true)" in extension
    assert "await onReload(item.transportation_event_id)" in extension
    assert "isObject(result.data)" in extension
    assert "mark_rental_billing_line_paid_in_full_state" in extension

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
    for label_text in ("Current rental", "Update billed through", "Preview billed through", "Confirm billed through", "Extend rental", "New return", "Billing history"):
        assert label_text in UI
    for removed in ("Authoritative Extension preview", "Billed-through boundary", "Stored current parent amount", "Stored current parent tax", "Projected subtotal", "Stored billing segment detail", "final Extension segment"):
        assert removed not in active and removed not in extension
    assert "additional_charge" in extension
    assert "additional_tax" in extension
    assert "additional_total" in extension
    assert "<table>" not in active
    assert "{p.extended_warranty&&" in active
    assert "Not configured" not in active


def test_successful_extension_resets_form_and_known_rejection_is_sanitized():
    extension = UI[UI.index("function ExtensionAction"):UI.index("function CompletionAction")]
    for reset in ("setPreview(null)", "setAt('')", "setReason('')", "setNote('')"):
        assert reset in extension
    assert "new Extension remains Not Paid" in extension
    assert "Extension succeeded but remains Not Paid" in extension
    assert "result.error?.message" not in extension
