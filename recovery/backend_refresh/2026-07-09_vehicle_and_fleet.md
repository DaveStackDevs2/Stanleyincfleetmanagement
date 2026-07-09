# Vehicle and Fleet Backend Reference

Date: 2026-07-09

This document records the backend objects that already exist for vehicle inventory, fleet state, continuity records, and vehicle scan/QR workflows.

## Relevant tables
- `vehicles`
  - Fields include `vin`, `stock_number`, `model`, `fleet_type`, `status`, `mileage`, `recon_status`, `current_tag`, `fleet_conversion_type`, `location`, `notes`, `ctp_program_active`, `ctp_program_entered_at`, `ctp_entry_mileage`, and `ctp_monitoring_notes`.
- `tags`
- `vehicle_tags`
- `vehicle_events`
  - Fields include `transportation_event_id`, `vehicle_id`, `actual_out_at`, `actual_in_at`, `is_open`, `ended_reason`, `created_by`, and `updated_by`.
- `contract_periods`
  - Fields include `vehicle_event_id`, `contract_out_at`, `contract_in_at`, `renewal_sequence`, `is_open`, `created_by`, and `updated_by`.
- `vehicle_swaps`
- `vehicle_stock_history`
- `rental_model_limits`
- `fleet_policies`
- `vehicle_qr_codes`
  - Fields include `vehicle_id`, `qr_token`, `landing_mode`, `is_active`, `issued_at`, `retired_at`, `issued_by_user_id`, and `notes`.
- `vehicle_scan_sessions`
  - Fields include `session_type`, `started_by_user_id`, `started_at`, `ended_at`, `session_status`, and `notes`.
- `vehicle_scan_events`
  - Fields include `vehicle_id`, `vehicle_qr_code_id`, `scan_session_id`, `scanned_by_user_id`, `action_type`, `result_status`, `scanned_at`, `related_reservation_id`, `related_transportation_event_id`, and `metadata`.
- `reservation_vehicle_dependencies`
  - Fields include `reservation_id`, `vehicle_id`, `source_transportation_event_id`, `dependency_type`, `status`, `risk_level`, `expected_return_snapshot`, `resolution_type`, `notes`, `created_by_user_id`, `updated_by_user_id`, `resolved_at`, and `resolved_by_user_id`.
- Related supporting tables: `reservations`, `transportation_events`, `active_vehicle_assignments`, `customers`, `app_users`.

## Relevant views
- `v_vehicle_operational_state`
- `v_vehicle_operational_aggregate_state`
- `v_vehicle_ctp_monitoring_state`
- `v_vehicle_qr_action_entry_state`
- `v_vehicle_scan_event_history`
- `v_vehicle_scan_session_history`
- `v_current_vehicle_continuity`
- `v_reservation_vehicle_candidates`

## Relevant frontend-callable functions
- `create_vehicle_state`
- `update_vehicle_core_state`
- `get_vehicle_by_vin_state`
- `get_or_create_vehicle_state_by_vin`
- `get_vehicle_operational_state`
- `get_vehicle_operational_payload_state`
- `get_vehicle_operational_aggregate_list_state`
- `get_vehicle_ctp_monitoring_state`
- `get_vehicle_ctp_monitoring_list_state`
- `get_vehicle_qr_action_entry_state`
- `get_vehicle_scan_session_state`
- `close_vehicle_scan_session_state`
- `assign_reservation_vehicle_state`
- `assign_reservation_vehicle_with_hard_lock_state`
- `clear_reservation_vehicle_assignment_state`
- `clear_reservation_vehicle_assignment_with_dependency_state`
- `create_hard_lock_state`

## Important fields returned to the frontend
- Core vehicle fields:
  - `vehicle_id`
  - `vin`
  - `stock_number`
  - `model`
  - `fleet_type`
  - `vehicle_status`
  - `mileage`
  - `recon_status`
  - `current_tag`
  - `fleet_conversion_type`
  - `location`
  - `notes`
- Continuity and case linkage fields:
  - `active_transportation_event_id`
  - `vehicle_event_id`
  - `contract_period_id`
  - `actual_out_at`
  - `contract_out_at`
  - `renewal_sequence`
  - `vehicle_event_is_open`
  - `contract_period_is_open`
  - `latest_expected_return_at`
- Fleet utilization and assignment fields:
  - `assigned_reservation_count`
  - `candidate_reservation_count`
  - `unresolved_dependency_count`
  - `unresolved_conflict_count`
- CTP and QR/scan fields:
  - `ctp_program_active`
  - `ctp_program_entered_at`
  - `ctp_entry_mileage`
  - `ctp_monitoring_notes`
  - `qr_token`
  - `landing_mode`
  - `scan_session_id`
  - `action_type`
  - `result_status`
  - `scanned_at`
