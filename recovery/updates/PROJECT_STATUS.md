# Project Status

Last updated: 2026-07-28

## Current phase

Phase 3 Vehicle Calendar Foundation is implemented in the repository on top of Phase 2 authentication and effective permissions.

## Completed

- The calendar provides Rental, Loaner, and combined modes; combined mode orders Loaners above Rentals and provides distinct collapsible sections.
- Day and seven-day week views, date navigation, a monthly picker, sticky stock/date headers, scrolling, row rendering containment, filters, persisted preferences, and optional dark mode are implemented.
- Vehicle focus exposes Reserve, Quote, and Schedule Maintenance placeholders. Event blocks expose required schedule metadata, hover summaries, details, and permission-gated confirmed drag reassignment/date moves.
- Calendar events, reusable event types, configurable colors, five calendar permissions, and protected visible-range/mutation RPCs are defined in the Phase 3 migration.
- Direct frontend table writes are not used for calendar events; RLS is enabled and direct authenticated table access is revoked.

## Verification

- `npm run build`: passed on 2026-07-28.
- Live migration application, live RLS behavior, authenticated calendar payloads, and browser interaction remain unverified.

## Known issues / next task

Apply the Phase 2 and Phase 3 migrations to an approved Supabase environment. Then validate authenticated access for representative permission combinations, real vehicle status vocabulary, time-zone behavior, drag conflict rejection, color changes, and large-fleet scrolling in a browser.

## Phase 3 final defect review

The repository implementation now uses 15-minute day-grid placement from 7:00 AM through 7:00 PM, records calendar mutations in `audit_log`, serializes overlap validation per vehicle, prevents edit permission from creating a missing event, exposes delete only with `calendar.delete`, and uses repeatable migration statements where practical. Static source review confirmed permission-key authorization and visible-range event loading. Live SQL execution, browser scrolling/dragging, visual dark-mode contrast, and authenticated behavior remain unverified without a connected test environment.
