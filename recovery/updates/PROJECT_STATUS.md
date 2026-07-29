# Project Status

## Admin pay-type management — 2026-07-29

- **VERIFIED:** The Rates, Fees & Billing Rules Admin card now opens RPC-only pay-type management for listing, creating, disabling, and reactivating pay types.
- **VERIFIED:** Active Fleet Board pay-type colors use native color inputs, one neutral fallback pair, strict six-digit hex validation, and an explicit save that excludes disabled pay-type keys.
- **VERIFIED:** Every successful mutation reloads authoritative backend state, errors shown to users are sanitized, and no pay-type deletion workflow was introduced.
- **VERIFIED:** A unique index on `lower(btrim(pay_type))` atomically protects pay types from case- and whitespace-variant duplicates.
- **NOT VERIFIED:** Live authenticated payloads and browser interaction still require an approved Admin test account.

## Fleet Board contract follow-up — 2026-07-29

- Authenticated operational reads are resolved through `get_fleet_board_state(timestamptz, timestamptz)`.
- Assignment and reservation loading is bounded to the visible day/week period on the backend.
- Saved pay-type colors are read and validated; the Admin color-palette UI is implemented.

Last updated: 2026-07-29

## Current phase

The abandoned Vehicle Calendar has been removed and replaced by the Fleet Board foundation on top of Phase 2 authentication and effective permissions.

## Completed

- The authenticated application exposes a read-only Fleet Board with day/week navigation and rental/loaner filtering.
- Day and seven-day week views, date navigation, sticky resource/date headers, scrolling, rental/loaner filters, daily reservation-capacity counts, and assignment blocks are implemented.
- The Fleet Board reads existing vehicles, model-level reservations, reservation capacity, and unified transportation-event operational state with explicit field lists.
- Fleet Board date navigation uses local calendar dates, invalid date-picker values are ignored, cancelled reservations do not count toward displayed capacity, and resolved conflicts are not shown as active.
- No scheduling tables, views, RPCs, migrations, permissions, or frontend-only workflow rules were added. The branch-only calendar-foundation migration was removed.

## Verification

- `npm run build`: passed on 2026-07-29.
- `npm run lint`: passed on 2026-07-29.
- `git diff --check`: passed on 2026-07-29.
- Live RLS/grant behavior, authenticated Fleet Board payloads, and browser interaction remain unverified.

## Blocked backend requirements

- **BLOCKED:** authenticated read access is missing for required Fleet Board sources. This needs a reviewed backend grant/RLS change; it is not addressed in frontend code.
- **BLOCKED:** the unified operational assignment source does not provide a backend-supported visible-period boundary. Frontend pagination or filtering was intentionally not added because it could silently omit assignments.

## Next verification

After the backend blockers are resolved, browser-test real vehicle status vocabulary, daylight-saving and day-boundary behavior, capacity counts, conflict resolution display, and large-fleet scrolling before connecting existing workflow handoffs.

## Phase 3 final defect review

The Fleet Board foundation is intentionally read-only. Operational changes remain in the existing reservation, transportation-event, vehicle assignment, billing, and conflict workflows. Live browser behavior and access to every board read source remain unverified without an approved authenticated test environment.
