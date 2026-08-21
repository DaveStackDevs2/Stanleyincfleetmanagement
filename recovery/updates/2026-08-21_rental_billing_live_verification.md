# 2026-08-21 — Rental Billing live verification

## GitHub and Supabase deployment

- PR #39 merged at `5aca4682368bc8d6945bd33f49d139a374ff0bc1`.
- Supabase migration `20260821185156 correct_rental_payment_and_extension_workflow` is applied to production.
- PR #40 merged at `d4485f2796c3229bc34f7fcabc36b54c6ad985f4`.
- Supabase migration `20260821185849 secure_warning_center_counts` is applied to production.

## Engine-first verification

The Rental correction reuses existing Supabase Billing, tax, continuity, Extension, and Warning Center engines. It does not introduce a parallel calculator or Extension workflow.

- `get_rental_payment_state` returns the authoritative per-parent-line payment state.
- `preview_rental_extension_state` derives its delta from the existing `get_billing_preview_state` engine.
- The existing Extension accept/commit/create chain remains authoritative.
- `v_warning_center_warning_items` remains the existing Warning Center source and now uses the PostgreSQL-compatible `min(b.vehicle_id::text)::uuid` aggregate.
- `get_warning_center_counts_state()` remains an internal helper used by the service-role dashboard path; its EXECUTE grant is now service-role-only.

## Live read-only proof

- The current active Rental has three parent billing lines totaling `$160 + $16 tax = $176`.
- All three parent lines are Not Paid, including a valid `$0/$0` Extension checkpoint; the authenticated AAL2 `get_rental_payment_state` response matches the stored rows and totals.
- Exactly one active Rental has unpaid parent lines and exactly one unpaid-Rental Warning row is returned. Warning membership, Balance Due, and vehicle ID match the authoritative billing rows.
- A one-day Rental Extension preview returns `$40 + $4 tax = $44`; charge, tax, and total match the deltas between two authoritative Billing previews.
- The future-start Extension guard returns `billing_preview_ready`, clamps the earlier preview end to the current Extension start, and returns zero elapsed `$0/$0`.

## Security follow-up

Post-deployment advisor review found that recreating `get_warning_center_counts_state()` as `SECURITY DEFINER` had restored broad PostgreSQL EXECUTE privileges. Engine tracing showed the counts helper is called by the existing service-role dashboard path while the Billing frontend uses `get_warning_center_detail_state()`.

The follow-up migration preserves the counts helper body, `postgres` owner, `SECURITY DEFINER`, and empty `search_path`, revokes browser/anonymous execution, and grants EXECUTE only to `service_role`. Live ACL verification passed and the specific anonymous SECURITY DEFINER advisor finding is cleared.

## Still open

- No production Rental billing line was marked Paid solely for testing. Verify the payment write path when a legitimate external Tekion Rental Sale should be recorded.
- A successfully persisted repeated Extension after the scheduled-start anchor correction remains a separate Phase 8 verification item; the read-only preview proof here does not close it.
- SO number per payment remains deferred.
- Mass/bulk Loaner billed-through remains a separate planned workflow; no verified live bulk engine is claimed.
