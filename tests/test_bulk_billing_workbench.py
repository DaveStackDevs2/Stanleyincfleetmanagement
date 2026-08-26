from pathlib import Path
SQL=Path('supabase/migrations/20260826120000_bulk_billing_workbench.sql').read_text().lower()
UI=Path('frontend/src/billing/BulkUpdating.tsx').read_text()
BILLING=Path('frontend/src/billing/BillingWorkspace.tsx').read_text()
def test_reservation_type_is_classification_authority():
 assert "reservation.reservation_type?.trim().tolowercase()==='rental'" in BILLING.lower()
 assert "fleet_type?.tolowercase().includes('rental')" not in BILLING.lower()
def test_engine_first_partial_success_and_future_target():
 for token in ('get_billing_preview_state','reconcile_extended_warranty_coverage_state','set_reservation_billed_through_state','ensure_tax_child_line_state','exception when others','foreach te in array'): assert token in SQL
 assert "p_target_at>clock_timestamp()" not in SQL.replace(' ','')
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
 for token in ('Bill Thru Sunday','America/New_York','Select at least one RO to update.','bulk-${row.state}','tekion-helper','Recall recent helper','Undo latest batch'): assert token in UI
 assert 'daily_rate*' not in UI and 'amount*' not in UI
