# Decisions

## 2026-07-30 — Normal operational case-write security boundary

**Decision:** Normal operational case writes require an active application user resolved from `auth.uid()` plus an `aal2` JWT. They do not require the separate `user_admin.manage` permission used by Admin/configuration workflows.

Top-level browser-callable wrappers are `SECURITY DEFINER`, owned by `postgres`, and use an empty `search_path`. They reject a supplied actor that differs from the authenticated application user and stamp the resolved application-user ID into internal workflows. The top-level operational wrappers grant execution to `authenticated` only, in addition to their owner `postgres`; internal mutation helpers deny browser roles while retaining `service_role` execution.

## 2026-07-31 — Deferred late-fee administration

**Decision:** Applicable late-fee dollar amounts must eventually be editable in the Admin Rates, Fees & Billing Rules area, using the existing `public.late_fee_rules.fee_amount` source. The verified live placeholders are `grace_period` = null, `fixed_fee` = 0, and `full_day_trigger` = 0. Configuring a dollar amount must not automatically charge it. Late fees remain deferred and discretionary: staff-applied, waivable/reversible, and recorded with actor, reason, timestamp, and preserved audit history.

## 2026-07-31 — Stable start/assign/bill browser boundary

- **Decision:** Replace the truncated legacy payload-wrapper contract with the exact stable RPC `create_start_bill_case_and_get_payload_state`; retain the legacy workflow below a security-definer, empty-search-path boundary requiring an active `app_users` identity and AAL2.
- **Decision:** Treat `p_start_mileage` as optional checkout mileage and never repurpose inventory/create `p_vehicle_mileage`. Stamp the resolved actor only on the exact vehicle event and contract period created by this execution, then load the payload.
- **Decision:** Enforce at most one open `vehicle_events` row per vehicle, with an explicit migration precondition failure for existing conflicts, and remove browser mutation access to the internal helper chain and its operational tables. Preserve reads and service-role access.
- **Evidence:** the service action held a 68-character name while PostgreSQL stored `create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_`; live verification found no frontend or deployed `fleet-constraint-engine` caller and zero rows in the four continuity/billing tables.
- **Deferred:** authoritative amount and tax calculation is unresolved future work; this checkpoint does not redesign trusted legacy inputs.

## 2026-07-31 — Continuation and reassignment security boundary

- **Decision:** Preserve the existing same-vehicle continuation and active-case reassignment/swap engines behind their existing service-action contracts; secure and reconcile them rather than introduce replacement workflows.
- **Decision:** Both browser wrappers resolve the active application user from `auth.uid()`, require AAL2, use security-definer execution with an empty search path, and alone grant browser execution to `authenticated`. Reassignment rejects actor disagreement and propagates the resolved actor into dependency resolution.
- **Decision:** Repair the verified missing `restart_same_vehicle_after_gap` dependency only by delegating to the existing `start_vehicle_use_state` engine. Keep the repair and the full mutation chain service-role-only.
- **Decision:** Preserve old-row `created_by`, stamp exact closed and new continuity rows, and load the unified payload only after validation and stamping. Do not add billing segmentation or a `vehicle_swaps` insert.
- **Evidence:** No frontend or deployed Edge caller exists, and all seven relevant live operational tables were empty. Dave separately applied PR #11's earlier migration and passed all six checks; this Codex task applied no live SQL.
- **Pending:** Manual application and verification are required before broad Phase 1 or Phase 10 can close. Authoritative amount/tax calculation remains unresolved; pay-type administration Phase 2 follows Phase 1. Late fees remain disabled/deferred, and future editable Admin amounts must never auto-charge.

## 2026-08-19 — Closed Billing historical boundary

**Decision:** Closed-case filtering uses `transportation_events.closed_at`. `p_closed_from` is inclusive and `p_closed_before` is exclusive. Historical money always comes from stored billing-line and tax snapshots, never current rate or tax configuration. The browser only supplies query boundaries and renders returned exact strings; closed review is read-only Tekion reconciliation, not cashiering.
