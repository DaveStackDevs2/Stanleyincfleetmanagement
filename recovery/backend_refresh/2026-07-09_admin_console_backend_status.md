# Admin Console Backend Status

Date: 2026-07-09

## Vehicle administration

### 1. Tables found
- `vehicles`
- `vehicle_stock_history`
- `vehicle_events`
- `contract_periods`
- `reservation_vehicle_dependencies`

### 2. Views found
- `v_vehicle_operational_state`
- `v_vehicle_operational_aggregate_state`
- `v_vehicle_ctp_monitoring_state`
- `v_reservation_vehicle_candidates`

### 3. Frontend-callable functions found
- `create_vehicle_state`
- `update_vehicle_core_state`
- `get_vehicle_by_vin_state`
- `get_or_create_vehicle_state_by_vin`
- `get_vehicle_operational_state`
- `get_vehicle_operational_payload_state`
- `get_vehicle_operational_aggregate_list_state`
- `get_vehicle_ctp_monitoring_state`
- `get_vehicle_ctp_monitoring_list_state`

### 4. Backend status
- PARTIAL

## User administration

### 1. Tables found
- `app_users`
- `roles`
- `user_roles`
- `permissions`
- `role_permissions`
- `app_user_security`
- `approved_networks`
- `app_user_reset_tokens`
- `user_auth_security_events`
- `admin_settings`
- `admin_setting_permissions`

### 2. Views found
- `v_app_users_with_roles`
- `v_roles_with_permissions`
- `v_user_account_admin_status`
- `v_user_admin_list_summary`
- `v_user_effective_permissions`
- `v_users_requiring_password_reset`
- `v_auth_security_policy_state`
- `v_security_admin_settings_state`
- `v_active_approved_networks`
- `v_user_auth_entry_state`
- `v_user_auth_security_event_history`

### 3. Frontend-callable functions found
- `create_app_user_state`
- `create_app_user_with_role_state`
- `add_user_role_state`
- `assign_user_role_by_name_state`
- `get_roles_with_permissions_state`
- `get_permissions_catalog_state`
- `begin_admin_password_reset_state`
- `clear_password_reset_pending_state`
- `complete_password_reset_db_state`
- `consume_reset_token_state`
- `create_approved_network_state`
- `get_approved_networks_state`
- `get_auth_security_policy_state`
- `get_security_admin_settings_state`
- `get_user_admin_detail_payload_state`
- `get_user_admin_list_payload_state`
- `get_user_auth_access_gate_state`
- `get_user_auth_access_gate_state_by_email`
- `get_user_security_detail_state`

### 4. Backend status
- READY

## Pay type administration

### 1. Tables found
- `pay_type_rules`
- `billing_lines`

### 2. Views found
- `v_current_pay_type_rules`
- `v_billing_rule_catalog` (documented as `get_billing_rule_catalog_state` consumer; no exported view name was provided in the repository docs)

### 3. Frontend-callable functions found
- `get_billing_rule_catalog_state`
- `create_billing_parent_line_state`
- `create_reservation_billing_line_state`
- `create_transportation_event_billing_line_state`
- `create_extension_billing_line_state`

### 4. Backend status
- PARTIAL

## Extended warranty administration

### 1. Tables found
- `warranty_providers`
- `extended_warranty_rules`
- `warranty_cases`
- `warranty_day_ledger`
- `warranty_alerts`

### 2. Views found
- `v_active_extended_warranty_provider_rules`
- `v_extended_warranty_rule_catalog`
- `v_warranty_provider_catalog`

### 3. Frontend-callable functions found
- `create_extended_warranty_rule_state`
- `update_extended_warranty_rule_state`
- `create_warranty_provider_state`
- `update_warranty_provider_state`
- `get_billing_rule_catalog_state`

### 4. Backend status
- READY

## GM warranty administration

### 1. Tables found
- `gm_warranty_rates`

### 2. Views found
- None found in the documented backend view inventory.

### 3. Frontend-callable functions found
- None found in the documented frontend-callable function inventory.

### 4. Backend status
- PARTIAL

## Rental late fee administration

### 1. Tables found
- `late_fee_rules`

### 2. Views found
- `v_active_late_fee_rules`
- `v_late_fee_rule_catalog`

### 3. Frontend-callable functions found
- `get_active_late_fee_rules_state`
- `create_late_fee_rule_state`
- `update_late_fee_rule_state`

### 4. Backend status
- READY

## Reservation VIN lock administration

### 1. Tables found
- `admin_settings`
- `reservations`
- `reservation_vehicle_dependencies`

### 2. Views found
- `v_auth_security_policy_state`
- `v_reservation_transportation_link_state`
- `v_reservations_needing_vin_assignment`

### 3. Frontend-callable functions found
- `get_reservation_vin_lock_lead_days_state`
- `get_reservation_vin_lock_window_state`
- `get_reservations_needing_vin_assignment_state`
- `get_auth_security_policy_state`

### 4. Backend status
- PARTIAL

## Email/message administration

### 1. Tables found
- `email_outbound_messages`
- `email_provider_webhook_events`
- `notification_rules`
- `notification_delivery_queue`
- `notifications`

### 2. Views found
- `v_email_outbound_message_state`
- `v_email_webhook_event_history`

### 3. Frontend-callable functions found
- `get_email_outbound_message_state`
- `get_user_email_outbound_history_state`

### 4. Backend status
- PARTIAL

## Dashboard/admin reporting

### 1. Tables found
- `billing_lines`
- `billing_event_totals`
- `lost_rentals`
- `reservations`
- `transportation_events`
- `vehicles`
- `customers`
- `reservation_vehicle_dependencies`
- `reservation_conflicts`

### 2. Views found
- `v_warning_center_critical_items`
- `v_warning_center_warning_items`
- `v_warning_center_review_items`
- `v_operational_domain_counts`
- `v_upcoming_rental_dependency_feed`
- `v_reservation_operational_state`
- `v_transportation_event_operational_state`
- `v_customer_operational_state`
- `v_customer_operational_aggregate_state`

### 3. Frontend-callable functions found
- `get_dashboard_payload_state`
- `get_master_operational_dashboard_state`
- `get_operational_domain_counts_state`
- `get_warning_center_counts_state`
- `get_warning_center_detail_state`
- `get_upcoming_rental_dependency_feed_state`
- `get_lost_rentals_summary_state`
- `get_utilization_snapshot_state`
- `get_customer_operational_state`
- `get_customer_operational_payload_state`
- `get_customer_operational_aggregate_list_state`

### 4. Backend status
- READY
