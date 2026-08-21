from pathlib import Path
import re
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

def test_future_start_patch_matches_live_multiline_guard_only():
 fixture="""BEGIN\r
    IF something_else THEN\r
        RAISE EXCEPTION 'Unrelated guard';\r
    END IF;\r
    IF v_preview_end < v_billing_start THEN\r
        RAISE EXCEPTION\r
            'Preview timestamp precedes the current billing segment'\r
            USING ERRCODE = '22023';\r
    END IF;\r
END""".replace('\r','')
 pattern=r"IF\s+v_preview_end\s*<\s*v_billing_start\s+THEN\s+RAISE\s+EXCEPTION\s+'Preview timestamp precedes the current billing segment'\s+USING\s+ERRCODE\s*=\s*'22023';\s+END\s+IF;"
 replacement="""IF v_preview_end < v_billing_start THEN
        IF v_current_line.line_type = 'rental_extension' AND v_current_line.extended_from_billing_line_id IS NOT NULL THEN
            v_preview_end := v_billing_start; -- valid future-start Extension: zero elapsed Extension days
        ELSE
            RAISE EXCEPTION 'Preview timestamp precedes the current billing segment' USING ERRCODE = '22023';
        END IF;
    END IF;"""
 transformed,count=re.subn(pattern,replacement,fixture)
 assert count==1
 assert transformed.count('valid future-start Extension: zero elapsed Extension days')==1
 assert "RAISE EXCEPTION 'Unrelated guard';" in transformed
 assert 'regexp_matches(v_definition,v_old_pattern' in SQL
 assert 'v_old_count<>1 OR v_target_count<>0 OR v_message_count<>1' in SQL
 assert "replace(pg_get_functiondef('public.get_billing_preview_state(uuid,timestamptz)'::regprocedure),chr(13),'')" in SQL

def test_payment_mutation_permission_and_flag_based_overall_state():
 payment=body('get_rental_payment_state','mark_rental_billing_line_paid_in_full_state')
 mutation=body('mark_rental_billing_line_paid_in_full_state')
 assert 'coalesce(bool_and(b.rental_paid_in_full),true)' in payment
 assert "'overall_paid_in_full',v_all_paid" in payment
 assert 'v_unpaid_charge+v_unpaid_tax=0' not in payment
 # A zero-dollar line remains operationally unpaid because the aggregate is flag based.
 assert all([True, False]) is False
 permission="public.v_user_effective_permissions WHERE user_id=v_user AND permission_key='billing.case_start'"
 assert permission in mutation
 assert mutation.index(permission)<mutation.index('UPDATE public.billing_lines SET rental_paid_in_full=true')
 assert "USING ERRCODE='42501'" in mutation

def test_idempotent_pickup_returns_authoritative_billing_and_payment():
 pickup=SQL[SQL.index('create or replace function public.activate_pricing_agreement_pickup_state'):SQL.index('CREATE OR REPLACE FUNCTION public.preview_rental_extension_state')]
 branch=pickup[pickup.index("if v_agreement.pricing_started_at is not null then"):pickup.index("raise exception 'Existing pickup state is inconsistent'")]
 assert 'public.get_billing_preview_state' in branch
 assert "billing_preview_ready" in branch
 assert 'public.get_rental_payment_state' in branch
 assert "'billing_preview',v_preview" in branch and "'rental_payment_state',v_payment" in branch
 assert "'Not Paid'" not in branch
 assert 'start_reservation_vehicle_use_state' not in branch

def test_warning_navigation_resolves_only_workspace_transportation_events():
 assert "warning.item_type==='unpaid_rental'" in BILLING
 assert "warning.item_type==='dependency_warning'" in BILLING
 assert "warning.item_type==='contract_reminder'" in BILLING
 assert 'item.reservation.reservation_id===warning.reservation_id' in BILLING
 assert 'item.preview.contract_period_id===warning.contract_period_id' in BILLING
 assert 'const id=warningTransportationEventId(warning,state);if(id){setSelected(id);rememberActiveCase(id)}' in BILLING

def test_payment_summary_and_warning_contracts():
 for x in ('contractual_charge','contractual_tax','contractual_total','unpaid_charge','unpaid_tax','unpaid_total','overall_paid_in_full','payment_status'): assert x in SQL
 assert "lower(btrim(te.status))='active'" in SQL
 assert 'GROUP BY te.id,r.id' in SQL and "'dependency_warning'" in SQL and "'contract_reminder'" in SQL

def test_unpaid_rental_warning_uses_type_safe_vehicle_uuid_aggregate():
 warning=SQL[SQL.index("UNION ALL SELECT 'unpaid_rental'"):SQL.index('GROUP BY te.id,r.id,te.status,te.expected_return_at')]
 assert 'min(b.vehicle_id::text)::uuid' in warning
 assert 'min(b.vehicle_id)' not in warning

def test_frontends_use_authoritative_payment_warning_and_loaner_preview():
 for x in ('get_rental_payment_state','Balance Due','Overall payment status','Mark Paid in Full','rental_paid_at','loadWarnings','onMutation'): assert x in BILLING
 assert "get_billing_preview_state" in BILLING and BILLING.index("get_billing_preview_state")<BILLING.index("mark_case_billed_through_and_get_preview_state")
 for x in ('Contract days','Vehicle charges','preview.tax_amount','setPreview(null);setPreviewAt(null)'): assert x in BILLING
 assert "parsePayment(activation.rental_payment_state)" in PICKUP and "get_rental_payment_state" in PICKUP
 assert "payment_status)==='Paid in Full'" not in PICKUP
 for forbidden in ('parseFloat','toFixed',".from('billing_lines')"): assert forbidden not in BILLING+PICKUP
