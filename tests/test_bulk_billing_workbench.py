from pathlib import Path
from datetime import datetime, timedelta, timezone
SQL=Path('supabase/migrations/20260826120000_bulk_billing_workbench.sql').read_text().lower()
UI=Path('frontend/src/billing/BulkUpdating.tsx').read_text()
BILLING=Path('frontend/src/billing/BillingWorkspace.tsx').read_text()
def test_reservation_type_is_classification_authority():
 assert "reservation.reservation_type?.trim().tolowercase()==='rental'" in BILLING.lower()
 assert "fleet_type?.tolowercase().includes('rental')" not in BILLING.lower()
def test_engine_first_partial_success_and_future_target():
 for token in ('get_billing_preview_state','reconcile_extended_warranty_coverage_state','set_reservation_billed_through_state','ensure_tax_child_line_state','exception when others','foreach te in array'): assert token in SQL
 assert "p_allow_futureandp_target_at>clock_timestamp()" in SQL.replace(' ','')
 assert "checkpoint_case_internal_state(r.id,p_target_at,'bulkupdatingbatch'||p_batch_id,true)" in SQL.replace(" ", "")
def test_persisted_batch_undo_and_helper_contract():
 for table in ('billing_bulk_batches','billing_bulk_items','billing_bulk_helper_lines'):
  assert f'create table public.{table}' in SQL
  assert f'alter table public.{table} enable row level security' in SQL
 for rpc in ('apply_bulk_billing_batch_state','undo_latest_bulk_billing_batch_state','set_bulk_helper_line_checked_state','get_recent_bulk_billing_batches_state'): assert rpc in SQL
 assert "legitimate billing work changed after this bulk batch" in SQL
def test_security_boundaries():
 assert "auth.jwt()->>'aal'" in SQL and "billing.mark_billed_through" in SQL
 assert "security definer set search_path=''" in SQL
 assert 'revoke all on table' in SQL and 'from public,anon,authenticated' in SQL
def test_frontend_is_backend_money_only_and_workbench_states():
 for token in ('Bill Thru Sunday','America/New_York','Select at least one RO to update.','bulk-${row.state}','tekion-helper','Recall batches','Undo latest batch'): assert token in UI
 assert 'daily_rate*' not in UI and 'amount*' not in UI

def test_one_canonical_checkpoint_and_ew_boundary_order():
 assert "checkpoint_case_internal_state" in SQL
 assert "multiple open parent billing segments were found" in SQL
 assert "p_allow_future" in SQL and "p_target_at>clock_timestamp()" in SQL.replace(" ", "")
 assert "ew_effective_at:=boundary-interval '1 microsecond'" in SQL
 assert SQL.index("checkpoint_case_internal_state(r.id,ew_effective_at") < SQL.index("reconcile_extended_warranty_coverage_state(r.transportation_event_id,p_target_at)")
 assert "'checkpoint_days',(p->>'contract_days')::integer" in SQL
 assert "(checkpoint->>'checkpoint_days')::integer" in SQL
 assert "business_contract_days(line.start_time" not in SQL
 assert "new customer pay line required after extended warranty coverage cap" in SQL

def test_internal_checkpoint_days_do_not_leak_through_public_wrapper():
 internal=SQL.split("create or replace function public.checkpoint_case_internal_state",1)[1].split("create or replace function public.mark_case_billed_through_and_get_preview_state",1)[0]
 public_wrapper=SQL.split("create or replace function public.mark_case_billed_through_and_get_preview_state",1)[1].split("create or replace function public.bulk_checkpoint_one_state",1)[0]
 assert "'checkpoint_days',(p->>'contract_days')::integer" in internal
 assert "(result-'checkpoint_days')||jsonb_build_object('billing_preview',current_preview)" in ''.join(public_wrapper.split())
 checkpoint_validator=BILLING.split("const checkpointKeys=",1)[1].split("const localNow=",1)[0]
 assert "'checkpoint_days'" not in checkpoint_validator

def test_ew_three_day_inclusive_boundary_and_preview_are_exclusive():
 # The live day engine is inclusive, so both Apply and read-only preview must use
 # the final microsecond before the first post-coverage day for the EW segment.
 assert SQL.count("boundary-interval '1 microsecond'") >= 2
 assert "effective_at:=case when boundary is not null and p_target_at>=boundary" in SQL
 assert "bulk_ew_split_pending" in SQL and "extended warranty ends at the coverage cap" in SQL
 assert "'segment_kind','extended_warranty'" in SQL
 assert "'segment_kind','customer_pay_after_ew_cap'" in SQL
 start=datetime(2026,8,1,17,tzinfo=timezone.utc)
 boundary=start+timedelta(days=3)
 target=start+timedelta(days=4)
 inclusive_days=lambda out,through:int((through-out).total_seconds()//86400)+1
 assert inclusive_days(start,boundary-timedelta(microseconds=1)) == 3
 assert inclusive_days(boundary,target) == 2
 assert inclusive_days(start,boundary-timedelta(microseconds=1))+inclusive_days(boundary,target) == 5

def test_preview_failures_are_isolated_per_row_and_overdue_is_attention_only():
 assert "bulk_preview_one_state" in SQL
 assert "exception when sqlstate '21000'" in SQL
 assert "'bulk_preview_error',sqlerrm" in SQL
 assert "cross join lateral public.bulk_preview_one_state" in SQL
 assert "'expected_return_overdue'" in SQL
 assert "expected return overdue (does not cap billing)" in SQL
 assert "expected_return_datetime<p_target_at" not in SQL

def test_secure_persistence_and_normalized_input():
 assert "grant select on table public.billing_bulk" not in SQL
 assert "array_agg(distinct x order by x)" in SQL and "where x is not null" in SQL

def test_complete_fail_closed_undo_snapshot():
 for token in ("before_warranty", "after_warranty", "current_w-'current_day_count'", "notes=i.before_reservation->>'notes'", "bulk_billing_undo"):
  assert token in SQL
 assert "delete from public.billing_lines" in SQL

def test_post_write_helpers_and_browser_workflows():
 assert "result->'preview'->'segments'" not in SQL
 for token in ("documentPictureInPicture", "Open always-on-top", "bulk-failure-dialog", "missingFailures", "Recent batch", "chooseBatch"):
  assert token in UI
 assert "set_bulk_helper_line_checked_state" in UI

def test_apply_gesture_sunday_undo_refresh_and_visual_edges():
 compact=''.join(UI.split())
 assert compact.index("voidopenPip(true)") < compact.index("supabase.rpc('apply_bulk_billing_batch_state'")
 assert "if(!pip.current||pip.current.closed)" in compact and "catch{" in compact
 assert "afterSundayCutoff" in UI and "(afterSundayCutoff?7:0)" in UI
 assert "awaitpreview(target);awaitrecall();" in compact
 assert "expected_return_overdue" in UI and "overdue-badge" in UI
 css=Path('frontend/src/billing/BillingWorkspace.css').read_text()
 assert "tbody tr:nth-child(even)" in css and ".bulk-overdue" in css

def test_actor_owned_undo_and_helper_checkoff():
 compact=''.join(SQL.split())
 assert "whereactor_user_id=actorandstatusin('applied','partially_applied')" in compact
 assert "joinpublic.billing_bulk_batchesbonb.id=i.batch_id" in compact
 assert "i.id=h.batch_item_idandb.actor_user_id=actor" in compact

def test_warranty_undo_ignores_only_reconciliation_housekeeping():
 compact=''.join(SQL.split())
 material="current_w-'current_day_count'-'last_checked_at'-'updated_at'"
 snapshot="i.after_warranty-'current_day_count'-'last_checked_at'-'updated_at'"
 assert material in compact and snapshot in compact
 assert "current_risdistinctfromi.after_reservation" in compact
 assert "current_lisdistinctfromi.after_lines" in compact
 # Full snapshots remain available for evidence and exact restoration.
 assert "old_w:=jsonb_populate_record(null::public.warranty_cases,i.before_warranty)" in compact

def test_retry_batch_sync_and_empty_target_guards():
 compact=''.join(UI.split())
 assert "disabled={!row.selectable}" in compact
 assert "disabled={!row.selectable||!!failure}" not in compact
 assert "setBatches(old=>old.map(batch=>" in compact
 assert "setHelper(selected.helper_lines??[])" in compact
 assert "recall(typeofresult.data.batch_id==='string'?result.data.batch_id:undefined)" in compact
 required=compact.index("if(!target){setMessage('BulkBillingThroughisrequired.');return}")
 conversion=compact.index("p_target_at:dealershipWallTimeToIso(target)")
 assert required < conversion
 assert "if(!event.target.value)setSelected([])" in compact
