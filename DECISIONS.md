# Decisions

## 2026-07-30 — Normal operational case-write security boundary

**Decision:** Normal operational case writes require an active application user resolved from `auth.uid()` plus an `aal2` JWT. They do not require the separate `user_admin.manage` permission used by Admin/configuration workflows.

Top-level browser-callable wrappers are `SECURITY DEFINER`, owned by `postgres`, and use an empty `search_path`. They reject a supplied actor that differs from the authenticated application user and stamp the resolved application-user ID into internal workflows. Only `authenticated` and `service_role` receive execution on these wrappers; internal mutation helpers deny `PUBLIC`, `anon`, and `authenticated`, while retaining `service_role` execution.
