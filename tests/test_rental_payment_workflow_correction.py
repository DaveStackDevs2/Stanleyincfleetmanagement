from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SQL=(ROOT/'supabase/migrations/20260821170000_correct_rental_payment_and_extension_workflow.sql').read_text()
BILLING=(ROOT/'frontend/src/billing/BillingWorkspace.tsx').read_text()
PICKUP=(ROOT/'frontend/src/reservations/PickupWorkspace.tsx').read_text()

def body(name,next_name=None):
 s=SQL.index(f'CREATE OR REPLACE FUNCTION public.{name}')
 e=SQL.index(f'CREATE OR REPLACE FUNCTION public.{next_name}',s) if next_name else len(SQL)
 return SQL[s:e]

def test_schema_security_and_no_deferred_scope():
 for x in ('rental_paid_in_full','rental_paid_at','rental_paid_by_user_id','ck_billing_lines_rental_payment_consistency','REFERENCES public.app_users(id)','ON DELETE RESTRICT'): assert x in SQL
 assert 'so_number' not in SQL.lower() and 'invoice_number' not in SQL.lower() and 'bulk_loaner' not in SQL.lower()
 read=body('get_rental_payment_state','mark_rental_billing_line_paid_in_full_state')
 for x in ("auth_user_id=auth.uid()","is_active=true","SECURITY DEFINER","SET search_path TO ''","An active application user is required"): assert x in read
 assert 'REVOKE ALL ON FUNCTION public.get_rental_payment_state(uuid)' in SQL and 'GRANT EXECUTE ON FUNCTION public.get_rental_payment_state(uuid)' in SQL

def test_existing_extension_chain_is_preserved_without_wrapper_mutations():
 wrapper=body('accept_case_extension_and_get_unified_payload_state')
 assert 'public.accept_reservation_extension_state' in wrapper
 for forbidden in ('UPDATE public.billing_lines','INSERT INTO public.billing_lines','set_expected_return_state','add_estimated_return_change_note_state','create_billing_parent_line_state'): assert forbidden not in wrapper
 predecessor=(ROOT/'supabase/migrations/20260806120000_authoritative_loaner_rental_tax.sql').read_text()
 reservation=predecessor[predecessor.index('CREATE OR REPLACE FUNCTION public.accept_reservation_extension_state'):predecessor.index('CREATE OR REPLACE FUNCTION public.accept_transportation_event_extension_state')]
 assert 'public.accept_extension_commit_state' in reservation
 commit=body('accept_extension_commit_state','accept_case_extension_and_get_unified_payload_state')
 assert 'public.create_extension_billing_line_state' in commit
 assert 'public.close_billing_line_state(p_current_billing_line_id,v_old_expected_return_at)' in commit
 assert 'close_billing_line_at_paid_through_state' not in commit

def test_extension_boundary_tax_and_payment_defaults():
 create=body('create_extension_billing_line_state','accept_extension_commit_state')
 assert 'v_parent.end_time,p_new_expected_return_at' in create
 assert 'v_parent.paid_through_at' not in create
 assert "'rental_extension'" in create and 'true,NULL,v_parent.id' in create
 assert 'public.create_billing_parent_line_state' in create
 pickup=SQL[SQL.index('create or replace function public.activate_pricing_agreement_pickup_state'):SQL.index('CREATE OR REPLACE FUNCTION public.preview_rental_extension_state')]
 assert 'public.ensure_tax_child_line_state(v_line_id)' in pickup
 assert "update public.billing_lines set amount=(v_preview->>'tax_amount')" not in pickup
 assert "'rental_payment_state',v_payment" in pickup

def test_preview_is_authoritative_validated_and_future_start_narrow():
 preview=body('preview_rental_extension_state')
 for x in ('public.get_billing_preview_state',"status' IS DISTINCT FROM 'billing_preview_ready'",'current_parent_billing_line_id','additional_charge','additional_tax','additional_total'): assert x in preview
 assert "v_current_line.line_type = ''rental_extension''" in SQL and 'extended_from_billing_line_id IS NOT NULL' in SQL
 assert 'v_preview_end := v_billing_start' in SQL
 assert "RAISE EXCEPTION ''Preview timestamp precedes the current billing segment''" in SQL
 anchor=(ROOT/'supabase/migrations/20260820190000_anchor_extension_contract_days.sql').read_text()
 assert 'business_contract_days(v_reservation.start_date' in anchor

def test_payment_summary_and_warning_contracts():
 for x in ('contractual_charge','contractual_tax','contractual_total','unpaid_charge','unpaid_tax','unpaid_total','overall_paid_in_full','payment_status'): assert x in SQL
 assert "lower(btrim(te.status))='active'" in SQL
 assert 'GROUP BY te.id,r.id' in SQL and "'dependency_warning'" in SQL and "'contract_reminder'" in SQL

def test_frontends_use_authoritative_payment_warning_and_loaner_preview():
 for x in ('get_rental_payment_state','Balance Due','Overall payment status','Mark Paid in Full','rental_paid_at','loadWarnings','onMutation'): assert x in BILLING
 assert "get_billing_preview_state" in BILLING and BILLING.index("get_billing_preview_state")<BILLING.index("mark_case_billed_through_and_get_preview_state")
 for x in ('Contract days','Vehicle charges','preview.tax_amount','setPreview(null);setPreviewAt(null)'): assert x in BILLING
 assert "parsePayment(activation.rental_payment_state)" in PICKUP and "get_rental_payment_state" in PICKUP
 assert "payment_status)==='Paid in Full'" not in PICKUP
 for forbidden in ('parseFloat','toFixed',".from('billing_lines')"): assert forbidden not in BILLING+PICKUP
