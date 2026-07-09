# Frontend Function Map

Date: 2026-07-09

This document maps the backend functions that are already exposed for frontend use, grouped by the operational area they serve.

## Dashboard and operations
- `get_dashboard_payload_state`
  - Returns dashboard access flags and dashboard payload sections for warning center, upcoming rentals, lost rentals, utilization, warranty, conflicts, and AI-related sections.
  - Important returned fields include `status`, `dashboard_access`, `payload.warning_center_counts`, `payload.warning_center_detail`, `payload.upcoming_rental_dependencies`, `payload.lost_rentals_summary`, and `payload.utilization_snapshot`.
- `get_master_operational_dashboard_state`
  - Returns a master operational payload for counts, customer rows, vehicle rows, reservation rows, transportation event rows, and case candidate groups.
  - Important returned fields include `status`, `counts`, `customers.items`, `vehicles.items`, `reservations.items`, `transportation_events.items`, and `case_candidates.activation|continuation|reassignment|completion`.
- `get_operational_domain_counts_state`
- `get_live_active_case_list_state`
- `get_case_candidate_dashboard_state`
- `get_warning_center_counts_state`
- `get_warning_center_detail_state`
- `get_upcoming_rental_dependency_feed_state`
- `get_lost_rentals_summary_state`
- `get_utilization_snapshot_state`

## Billing and warranty
- `create_billing_parent_line_state`
- `create_reservation_billing_line_state`
- `create_transportation_event_billing_line_state`
- `create_extension_billing_line_state`
- `activate_case_billing_state`
- `close_billing_line_state`
- `close_billing_line_at_paid_through_state`
- `get_billing_rule_catalog_state`
- `get_active_late_fee_rules_state`
- `create_late_fee_rule_state`
- `update_late_fee_rule_state`
- `create_extended_warranty_rule_state`
- `update_extended_warranty_rule_state`
- `create_warranty_provider_state`
- `update_warranty_provider_state`
- `get_billing_dependency_banner_state`
- Important returned fields include billing line identifiers, `pay_type`, `amount`, `tax_amount`, `line_type`, `start_time`, `end_time`, `paid_through_at`, `is_open`, and warranty-related rate/coverage values.

## Vehicle and fleet
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
- Important returned fields include `vehicle_id`, `vin`, `stock_number`, `model`, `fleet_type`, `vehicle_status`, `mileage`, `recon_status`, `current_tag`, `location`, `active_transportation_event_id`, `vehicle_event_id`, `contract_period_id`, `latest_expected_return_at`, `assigned_reservation_count`, and `candidate_reservation_count`.

## Reservations and cases
- `create_reservation_with_transportation_event_state`
- `create_reservation_for_tekion_customer_state`
- `create_case_bootstrap_state`
- `create_case_bootstrap_with_vehicle_by_vin_state`
- `create_and_start_case_with_vehicle_by_vin_state`
- `create_start_and_bill_case_with_vehicle_by_vin_state`
- `create_transportation_event_state`
- `assign_reservation_vehicle_state`
- `assign_reservation_vehicle_with_hard_lock_state`
- `clear_reservation_vehicle_assignment_state`
- `clear_reservation_vehicle_assignment_with_dependency_state`
- `create_or_update_reservation_conflict_state`
- `accept_case_extension_and_get_unified_payload_state`
- `continue_case_same_vehicle_and_get_unified_payload_state`
- `complete_case_and_get_unified_payload_state`
- `cancel_case_and_get_unified_payload_state`
- `close_transportation_event_state`
- `add_transportation_event_general_note_state`
- `add_estimated_return_change_note_state`
- `add_billing_context_note_state`
- `get_unified_case_payload_state`
- `get_transportation_event_operational_payload_state`
- `get_reservation_operational_payload_state`
- `get_reservation_lifecycle_state`
- `get_transportation_event_state`
- Important returned fields include `reservation_id`, `transportation_event_id`, `reservation_status`, `reservation_type`, `expected_return_datetime`, `transportation_event_status`, `vehicle_event_id`, `contract_period_id`, `current_dependency_id`, `current_conflict_id`, `note_type`, `note_text`, and `entered_at`.

## Customers and users
- `create_customer_state`
- `get_or_create_customer_state_by_tekion`
- `get_customer_operational_state`
- `get_customer_operational_payload_state`
- `get_customer_operational_aggregate_list_state`
- `create_app_user_state`
- `create_app_user_with_role_state`
- `add_user_role_state`
- `assign_user_role_by_name_state`
- `get_roles_with_permissions_state`
- `get_permissions_catalog_state`
- `get_user_admin_detail_payload_state`
- `get_user_admin_list_payload_state`
- `get_user_auth_access_gate_state`
- `get_user_auth_access_gate_state_by_email`
- `begin_admin_password_reset_state`
- `complete_password_reset_db_state`
- `consume_reset_token_state`
- Important returned fields include `customer_id`, `tekion_customer_number`, `name`, `email`, `phone`, `user_id`, `full_name`, `role_summary`, `permission_key`, and reset-token/security state fields.
