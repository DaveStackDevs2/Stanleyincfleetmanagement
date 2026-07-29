# Project Status

Last updated: 2026-07-29

## Current phase

The abandoned Vehicle Calendar has been removed and replaced by the Fleet Board foundation on top of Phase 2 authentication and effective permissions.

## Completed

- The authenticated application exposes a read-only Fleet Board with day/week navigation and rental/loaner filtering.
- Day and seven-day week views, date navigation, sticky resource/date headers, scrolling, rental/loaner filters, daily reservation-capacity counts, and assignment blocks are implemented.
- The Fleet Board reads existing vehicles, model-level reservations, reservation capacity, and unified transportation-event operational state with explicit field lists.
- No scheduling tables, views, RPCs, migrations, permissions, or frontend-only workflow rules were added. The branch-only calendar-foundation migration was removed.

## Verification

- `npm run build`: passed on 2026-07-29.
- `npm run lint`: passed on 2026-07-29.
- `git diff --check`: passed on 2026-07-29.
- Live RLS/grant behavior, authenticated Fleet Board payloads, and browser interaction remain unverified.

## Known issues / next task

Verify least-privileged authenticated read access for all four existing Fleet Board sources. Then browser-test real vehicle status vocabulary, time-zone behavior, day boundaries, capacity counts, and large-fleet scrolling before connecting existing workflow handoffs.

## Phase 3 final defect review

The Fleet Board foundation is intentionally read-only. Operational changes remain in the existing reservation, transportation-event, vehicle assignment, billing, and conflict workflows. Live browser behavior and access to every board read source remain unverified without an approved authenticated test environment.
