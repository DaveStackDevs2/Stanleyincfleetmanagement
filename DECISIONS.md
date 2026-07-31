# Decisions

## 2026-07-30 — Normal operational case-write security boundary

**Decision:** Normal operational case writes require an active application user resolved from `auth.uid()` plus an `aal2` JWT. They do not require the separate `user_admin.manage` permission used by Admin/configuration workflows.

Top-level browser-callable wrappers are `SECURITY DEFINER`, owned by `postgres`, and use an empty `search_path`. They reject a supplied actor that differs from the authenticated application user and stamp the resolved application-user ID into internal workflows. The top-level operational wrappers grant execution to `authenticated` only, in addition to their owner `postgres`; internal mutation helpers deny browser roles while retaining `service_role` execution.

## 2026-07-31 — Deferred late-fee administration

**Decision:** Applicable late-fee dollar amounts must eventually be editable in the Admin Rates, Fees & Billing Rules area, using the existing `public.late_fee_rules.fee_amount` source. The verified live placeholders are `grace_period` = null, `fixed_fee` = 0, and `full_day_trigger` = 0. Configuring a dollar amount must not automatically charge it. Late fees remain deferred and discretionary: staff-applied, waivable/reversible, and recorded with actor, reason, timestamp, and preserved audit history.
