# Fleet Board Build Reference

## Purpose

This document is the persistent build reference and handoff checklist for the Stanley Fleet Board. It preserves the business context, exact database objects, decisions, completed work, and remaining work so another AI or developer can continue without redesigning the feature or losing operational intent.

## Product decision

The unfinished `Vehicle Calendar` is being replaced by a **Fleet Board** built around the existing backend.

The Fleet Board is the operational workspace for:

- model-level rental quotes and reservations;
- VIN-level rental and loaner assignments;
- vehicle availability;
- transportation-event state;
- billing/pay type;
- conflicts;
- later extensions, swaps, returns, and completion.

### Operational context

- The Fleet Board display window is **7:00 AM–7:00 PM**.
- Normal rental staffing is **8:00 AM–4:00 PM Monday–Friday**.
- Service handles activity from **7:00–8:00 AM** and approximately **4:00–6:00 PM**.
- Saturday rentals and loaners may occur by special arrangement.
- After-hours rental drop-offs may create actual return timestamps outside the display window.
- Scheduled rental return times remain inside the 7:00 AM–7:00 PM display window.
- These facts document operating context only. They do not add frontend validation, scheduling, or booking rules.

The board must visualize backend state. It must not create a separate calendar-only business model.

## Visual direction

Use the interaction pattern of the Stanley ServiceHub technician schedule, not its mechanic-specific controls:

- resources listed vertically on the left;
- a horizontal timeline;
- day and week views;
- previous/next navigation;
- Today button;
- date picker for jumping across days and months;
- dense, readable event blocks;
- fixed left resource column and fixed timeline header;
- current-time marker in day view.

Use the existing spreadsheet only as operational context, not as a literal design:

- reservations are represented separately from VIN assignments;
- rentals and loaners are grouped by fleet type, model, and vehicle;
- color remains a quick operational signal;
- day drill-down must be substantially better than the spreadsheet.

## Required behavior

### Quotes and reservations

- Reservations are normally **model-level**, not VIN-level.
- Creating from empty board time asks: **Quote** or **Reservation**.
- A quote or reservation records requested model/class and date range.
- It must not assign a VIN during normal booking.
- VIN assignment occurs later when the customer takes a vehicle.

### Immediate vehicle action

Clicking a vehicle in the left column offers:

- Rent now
- Loan now
- Vehicle details

Rent now / Loan now must hand off to the existing transportation-event and billing workflow so pay type and duration are established there.

### Filters

- All vehicles
- Rentals only
- Loaners only
- Available now
- Later: location, model, status, search, conflict visibility

### Reservation capacity

Admin controls the maximum rental reservation capacity by model/class.

The system must:

- show booked count versus configured limit for the visible period;
- prevent new reservations above the limit;
- preserve existing reservations if an administrator lowers a limit;
- create/show a Conflict Center conflict when the new limit is below current booked reservations;
- never silently cancel or reassign reservations.

## Exact database reference

The schema exports are context snapshots. Database changes must be created as migrations or explicit SQL, not by editing the schema export as if it were executable migration history.

### `public.vehicles`

#### Verified live database

The live `public.vehicles` table contains `model_year integer`. It does not contain `year`, `make`, or `is_active`.

#### Older repository snapshot

The older schema export predates the later vehicle-administration migration and records these relevant columns:

- `id uuid`
- `vin text`
- `stock_number text`
- `model text`
- `fleet_type text`
- `status text`
- `mileage integer`
- `recon_status text`
- `current_tag text`
- `fleet_conversion_type text`
- `location text`
- `notes text`
- `ctp_program_active boolean`
- `ctp_program_entered_at timestamptz`
- `ctp_entry_mileage integer`
- `ctp_monitoring_notes text`

The repository migration `20260713090000_add_ontrac_vehicle_admin_support.sql` adds `model_year integer`. Repository snapshots remain reference artifacts and are not evidence of current live-database state.

### `public.reservations`

Exact relevant columns:

- `id uuid`
- `vehicle_id uuid nullable`
- `start_date timestamptz`
- `expected_return_datetime timestamptz`
- `status text` default `quote`
- `reservation_type text` default `rental`
- `requested_model text`
- `service_advisor text`
- `ro_number text`
- `pay_type text`
- `actual_return_datetime timestamptz`
- `billed_through_datetime timestamptz`
- `transportation_event_id uuid`
- `customer_id uuid`

Business interpretation:

- `requested_model` is the model/class capacity key currently available in schema.
- `vehicle_id` must normally remain null for future reservations until physical assignment.
- status values must be verified from existing functions/data before hardcoding workflow rules.

### `public.quotes`

Exact relevant columns:

- `id uuid`
- `vehicle_class text`
- `start_date timestamptz`
- `expected_return_datetime timestamptz`
- `status text`
- `notes text`
- `is_active boolean`
- `converted_to_reservation_id uuid nullable`
- `customer_id uuid nullable`

Quotes are capacity visibility inputs only if existing backend rules say they hold capacity. Do not assume this until functions/rules are inspected.

### `public.rental_model_limits`

Exact columns:

- `id uuid`
- `created_at timestamptz`
- `vehicle_class text unique`
- `daily_limit integer`

This is the existing database object for editable rental reservation capacity.

The frontend should call it **Reservation Capacity** even though the table is named `rental_model_limits`.

### `public.reservation_conflicts`

Exact relevant columns:

- `id uuid`
- `reservation_id uuid`
- `vehicle_class text`
- `conflict_type text`
- `severity text`
- `message text`
- `is_resolved boolean`
- `resolved_at timestamptz`
- `created_by text`
- `reservation_vehicle_dependency_id uuid nullable`

This is the existing conflict persistence table. Capacity conflicts must use existing conflict creation/refresh logic if present; do not insert duplicate conflict logic in the frontend.

### `public.transportation_events`

Exact relevant columns:

- `id uuid`
- `source_type text`
- `source_id uuid nullable`
- `status text`
- `notes text`
- `customer_id uuid nullable`
- `updated_at timestamptz`
- `closed_at timestamptz nullable`
- `closed_by uuid nullable`
- `expected_return_at timestamptz nullable`

This remains the central operational entity. Sources may include quote, reservation, or walk-in.

### `public.active_vehicle_assignments`

Exact relevant columns:

- `transportation_event_id uuid unique`
- `vehicle_id uuid`
- `assigned_at timestamptz`
- `assignment_source text`
- `assigned_by text`
- `is_active boolean`

### `public.billing_lines`

Exact relevant calendar/billing columns:

- `transportation_event_id uuid`
- `reservation_id uuid nullable`
- `vehicle_id uuid nullable`
- `pay_type text`
- `start_time timestamptz nullable`
- `end_time timestamptz nullable`
- `vehicle_event_id uuid nullable`
- `contract_period_id uuid nullable`
- `pay_type_rule_id uuid nullable`
- `line_type text nullable`
- `is_open boolean`
- `paid_through_at timestamptz nullable`

### `public.pay_type_rules`

Exact columns relevant to this feature:

- `id uuid`
- `pay_type text unique`
- `tax_applicable boolean`
- `priority integer`
- `stacking_allowed boolean`
- `active boolean`
- `is_active boolean`
- `is_taxable boolean`
- `default_daily_amount numeric nullable`
- `sort_order integer`
- `description text nullable`
- `updated_at timestamptz`

Important: pay-type calendar color columns do **not** currently exist in the schema export. Color persistence must be designed as a backend addition and managed through Admin. Do not hardcode final production colors in the board.

### `public.v_transportation_event_unified_operational_state`

Use this existing unified operational view for assigned/open transportation-event display.

Exact relevant exposed fields verified from `views_export.sql`:

- `transportation_event_id`
- `source_type`
- `source_id`
- `transportation_event_status`
- `transportation_event_notes`
- `customer_id`
- `updated_at`
- `closed_at`
- `closed_by`
- `expected_return_at`
- `vehicle_event_id`
- `vehicle_id`
- `contract_period_id`
- `actual_out_at`
- `actual_in_at`
- `vehicle_event_is_open`
- `ended_reason`
- `contract_out_at`
- `contract_in_at`
- `renewal_sequence`
- `contract_period_is_open`
- `current_parent_billing_line_id`
- `current_billing_reservation_id`
- `current_billing_vehicle_id`
- `current_billing_pay_type`
- `current_billing_parent_amount`
- `current_billing_parent_tax_amount`
- `current_billing_start_time`
- `current_billing_end_time`
- `current_billing_line_type`
- `current_billing_paid_through_at`
- `current_billing_is_open`
- current dependency/conflict fields
- extension-candidate fields

Time rendering precedence currently intended:

1. start: `actual_out_at`
2. fallback start: `current_billing_start_time`
3. scheduled reservations come directly from `public.reservations.start_date`

End precedence:

1. `actual_in_at`
2. `expected_return_at`
3. `current_billing_end_time`
4. scheduled reservations use `public.reservations.expected_return_datetime`

Do not use `transportation_events.updated_at` as the business start time.

## Frontend structure

Current files:

- `frontend/src/fleet-board/FleetBoard.tsx`
- `frontend/src/fleet-board/FleetBoard.css`

The application navigation and page state now use **Fleet Board**. The abandoned calendar component, event form, calendar-only styles, permission references, and branch-only foundation migration have been removed.

## Punchlist

Legend:

- `[x]` complete in branch
- `[~]` started / incomplete
- `[ ]` not started
- `[!]` blocked by backend decision or missing persistence

### Foundation

- [x] Stop using the missing calendar-state RPC.
- [x] Replace old calendar component foundation with backend-driven availability board.
- [x] Add day/week switching.
- [x] Add previous/next navigation, Today, and native date picker.
- [x] Add All/Rentals/Loaners filters.
- [ ] Add Available Now filter.
- [ ] Add click-vehicle workflow handoff after verifying the existing contracts.
- [ ] Add empty-time Quote/Reservation handoff after verifying the existing contracts.
- [x] Replace old calendar CSS with Fleet Board CSS.
- [x] Verify TypeScript build and correct all compile errors.
- [x] Rename component/files/routes from Vehicle Calendar to Fleet Board after route inspection.

### Database-accurate reads

- [x] Read vehicles, assignments, reservations, and capacity through the authenticated `get_fleet_board_state(timestamptz, timestamptz)` contract.
- [ ] Join/display customer names from `public.customers` through safe view/RPC or relation.
- [x] Resolve authenticated Fleet Board reads through a permission-boundary RPC without adding browser table policies.
- [x] Replace broad `select('*')` with explicit stable field lists.
- [x] Bound assignment and reservation loading to the RPC's requested visible period.

### Reservation capacity

- [x] Show model/class capacity rows.
- [x] Calculate visible-period reservation usage per day.
- [x] Calculate capacity per calendar day, not only total visible reservations.
- [ ] Display Available / Full / Over Capacity states.
- [ ] Prevent creating a reservation that exceeds capacity.
- [ ] Inspect existing backend functions/triggers for limit enforcement before writing new logic.
- [ ] Generate/refresh `reservation_conflicts` when a limit is reduced below booked usage.
- [ ] Prevent duplicate unresolved capacity conflicts.
- [ ] Resolve stale capacity conflicts when capacity or bookings return to valid levels.
- [ ] Add Admin editor for `rental_model_limits.daily_limit`.

### Hierarchy and board layout

- [~] Fleet type grouping.
- [~] Model grouping.
- [x] VIN/stock-number resource rows.
- [ ] Add independent collapse/expand for fleet and model groups.
- [ ] Add group counts.
- [ ] Add status text: Available / Out / Return time.
- [ ] Add search and model/location/status filters.
- [ ] Add conflict-only filter.
- [x] Render Day view as a horizontally scrollable 7:00 AM–7:00 PM operating timeline with twelve one-hour intervals, including the final 7:00 PM boundary, and a fixed VIN column. Keep the RPC range on the complete calendar day.
- [x] Position and clamp assignments by their actual timestamps, lane overlapping assignments deterministically, and expand VIN rows for those lanes.
- [x] Show the current-time marker only for today's Day view between 7:00 AM and 7:00 PM, updating it once per minute without reloading board data, while preserving dense sticky scheduler headers.
- [x] Improve day row density to match operational scheduler style.
- [ ] Improve week blocks for multi-day spans.
- [ ] Clicking week day header switches to that day.

### Pay-type colors

- [x] Persist Admin-configured pay-type background/text colors in `fleet_board.pay_type_colors`.
- [x] Keep the palette in the existing Admin setting system rather than extending operational pay-type rows.
- [x] Add the verified live functions, grants, setting, and `user_admin.manage` mapping as one idempotent migration.
- [x] Add Admin UI for active/inactive pay types and explicit Fleet Board palette saving.
- [x] Read configured colors on Fleet Board and validate each six-digit hex value.
- [x] Use one neutral fallback when a saved pair is absent or invalid; do not encode pay-type-specific colors.

### Workflow handoffs

- [ ] Quote workflow entry point.
- [ ] Reservation workflow entry point.
- [ ] Rent Now workflow entry point.
- [ ] Loan Now workflow entry point.
- [ ] Connect Quote to existing quote workflow/function.
- [ ] Connect Reservation to existing reservation workflow/function.
- [ ] Connect Rent Now / Loan Now to transportation-event activation and billing workflow.
- [ ] Clicking existing event opens its transportation-event workspace.
- [ ] Add return, extension, continuation, swap, and completion actions only through existing backend workflows.

### Quality and safety

- [ ] Inspect all relevant existing RPCs before adding writes.
- [ ] Never create calendar-only event persistence.
- [ ] Never assign VINs to ordinary future reservations by default.
- [ ] Do not treat `updated_at` as schedule start.
- [ ] Do not hardcode production pay-type colors.
- [ ] Add loading, empty, access-denied, and partial-data states.
- [ ] Add tests for overlap, day boundaries, week boundaries, timezone handling, and capacity reduction.
- [ ] Test with no transportation events and no reservations.
- [ ] Test with reservations over capacity.
- [ ] Test with active rental/loaner events and returns spanning date ranges.

### Verified review corrections

- [x] Use local calendar-date arithmetic for navigation across daylight-saving transitions.
- [x] Ignore empty or invalid native date-picker values before updating board state.
- [x] Exclude reservations with the verified `cancelled` status from capacity usage.
- [x] Read `current_conflict_is_resolved` and show a conflict only when it is explicitly unresolved.

## Work log

### 2026-07-30

- Replaced the Day view's single undifferentiated date cell with a fixed 7:00 AM–7:00 PM horizontal operating timeline while leaving the complete-calendar-day RPC request and Week view behavior intact.
- Added boundary-clamped timestamp positioning, deterministic overlap lanes, adaptive assignment detail, and a today-only current-time marker.
- Continued to load the read-only board exclusively through the verified live `get_fleet_board_state(timestamptz, timestamptz)` contract; no backend objects or workflows changed.

### 2026-07-29

- Confirmed old frontend calendar depended on missing RPCs and a backend contract that was never implemented.
- Decided to replace it with Fleet Board using existing backend operational objects.
- Replaced `frontend/src/calendar/VehicleCalendar.tsx` foundation in commit `af43f30a8dcd8bb85f176515925809905b508884`.
- Added this reference and punchlist.
- Removed the abandoned Vehicle Calendar implementation and its unmerged calendar-foundation migration.
- Added the authenticated, read-only Fleet Board foundation using existing vehicles, reservations, rental capacity, and unified transportation-event state.
- Renamed the application navigation, page state, imports, and component to Fleet Board without inventing a feature permission.
- Replaced direct browser reads with the live `get_fleet_board_state` RPC, including backend-visible-period filtering and complete payload validation.
- Integrated the live pay-type color read contract with a neutral validated fallback. The Admin palette editor remains the next task.
- Connected the existing Rates, Fees & Billing Rules card to RPC-only pay-type management. Admins can add, disable, and reactivate pay types without deleting billing history, and can explicitly save validated colors for active pay types.

## Continuation rule

Before making changes, update this document when:

- a database field/table/view/function is verified;
- a product decision changes;
- a punchlist item is completed or blocked;
- a migration or frontend integration is added.

Do not redesign the feature from scratch unless the user explicitly changes direction.
