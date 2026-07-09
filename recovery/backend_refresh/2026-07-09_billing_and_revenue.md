# Billing and Revenue Backend Reference

Date: 2026-07-09

This document records the backend objects that already exist for billing, revenue lines, warranty handling, and fee rules.

## Relevant tables
- `billing_lines`
  - Stores billing line records for transportation events, reservations, vehicles, and contract periods.
  - Fields include `transportation_event_id`, `reservation_id`, `vehicle_id`, `pay_type`, `amount`, `tax_amount`, `start_time`, `end_time`, `line_type`, `parent_billing_line_id`, `warranty_provider_id`, `default_covered_days_snapshot`, `covered_days_override`, `is_open`, `updated_at`, `paid_through_at`, `extended_from_billing_line_id`, `default_daily_rate_snapshot`, and `daily_rate_override`.
- `billing_event_totals`
  - Stores total billing values per transportation event.
  - Fields include `transportation_event_id`, `warranty_total`, `extended_warranty_total`, `customer_pay_total`, `tax_total`, and `grand_total`.
- `pay_type_rules`
  - Stores pay-type rules used by billing.
  - Fields include `pay_type`, `tax_applicable`, `priority`, `stacking_allowed`, `active`, `is_active`, `is_taxable`, `default_daily_amount`, `sort_order`, and `description`.
- `late_fee_rules`
  - Stores late-fee rules.
  - Fields include `is_active`, `sort_order`, `rule_kind`, `threshold_unit`, `threshold_value`, `fee_amount`, `description`, `created_at`, `updated_at`, `created_by`, and `updated_by`.
- `warranty_providers`
  - Stores warranty providers.
  - Fields include `name`, `provider_type`, `is_active`, `default_daily_rate`, `updated_at`, and `notes`.
- `extended_warranty_rules`
  - Stores provider-specific warranty rules.
  - Fields include `provider_id`, `covered_days`, `requires_approval`, `daily_rate`, `is_active`, `updated_at`, and `notes`.
- `gm_warranty_rates`
  - Stores GM warranty rate values.
  - Fields include `less_than_24hr_rate`, `over_24hr_rate`, `customer_pay_rate`, and `tax_rate`.
- `warranty_day_ledger`
  - Stores per-day warranty accounting ledger rows.
  - Fields include `warranty_case_id`, `transportation_event_id`, `day_index`, `date_used`, `billing_state`, `tax_applied`, and `amount_applied`.
- `warranty_cases`
  - Stores warranty case records linked to transportation events and reservations.
  - Fields include `transportation_event_id`, `reservation_id`, `provider_id`, `provider_name`, `approval_status`, `approved_at`, `approved_days`, `current_day_count`, `last_checked_at`, `requires_manual_review`, `escalation_level`, and `metadata`.
- `warranty_alerts`
  - Stores warranty-related alerts.
  - Fields include `transportation_event_id`, `ro_number`, `provider_name`, `status`, and `message`.
- `contract_periods`
  - Supports contract-period continuity for vehicle events and billing.
  - Fields include `vehicle_event_id`, `contract_out_at`, `contract_in_at`, `renewal_sequence`, `is_open`, `created_at`, `updated_at`, `created_by`, and `updated_by`.
- Related supporting tables: `transportation_events`, `reservations`, `vehicles`, `vehicle_events`, `customers`, `app_users`.

## Relevant views
- `v_current_open_billing_lines`
- `v_current_extendable_billing_lines`
- `v_current_pay_type_rules`
- `v_reservation_current_billing_state`
- `v_transportation_event_current_billing_state`
- `v_extension_commit_candidates`
- `v_active_late_fee_rules`
- `v_late_fee_rule_catalog`
- `v_active_extended_warranty_provider_rules`
- `v_extended_warranty_rule_catalog`
- `v_warranty_provider_catalog`
- `v_service_action_contract_state`

## Relevant frontend-callable functions
- `create_billing_parent_line_state`
- `create_reservation_billing_line_state`
- `create_transportation_event_billing_line_state`
- `create_extension_billing_line_state`
- `activate_case_billing_state`
- `close_billing_line_state`
- `close_billing_line_at_paid_through_state`
- `close_current_reservation_billing_line_state`
- `close_current_transportation_event_billing_line_state`
- `get_billing_dependency_banner_state`
- `get_billing_rule_catalog_state`
- `get_active_late_fee_rules_state`
- `create_late_fee_rule_state`
- `update_late_fee_rule_state`
- `create_extended_warranty_rule_state`
- `update_extended_warranty_rule_state`
- `create_warranty_provider_state`
- `update_warranty_provider_state`
- `create_start_and_bill_case_with_vehicle_by_vin_state`

## Important fields returned to the frontend
- Billing line state fields:
  - `parent_billing_line_id`
  - `reservation_id`
  - `transportation_event_id`
  - `pay_type`
  - `parent_amount`
  - `parent_tax_amount`
  - `start_time`
  - `end_time`
  - `paid_through_at`
  - `parent_is_open`
  - `line_type`
  - `tax_billing_line_id`
  - `tax_line_amount`
  - `tax_line_is_open`
- Billing context fields:
  - `warranty_provider_id`
  - `default_covered_days_snapshot`
  - `covered_days_override`
  - `default_daily_rate_snapshot`
  - `daily_rate_override`
  - `extended_from_billing_line_id`
- Totals and summary fields:
  - `warranty_total`
  - `extended_warranty_total`
  - `customer_pay_total`
  - `tax_total`
  - `grand_total`
- Rule catalog fields:
  - `pay_type`
  - `tax_applicable`
  - `priority`
  - `sort_order`
  - `description`
  - `fee_amount`
  - `threshold_unit`
  - `threshold_value`
  - `rule_kind`
- Warranty fields:
  - `provider_name`
  - `provider_type`
  - `requires_approval`
  - `daily_rate`
  - `approval_status`
  - `approved_days`
  - `current_day_count`
  - `requires_manual_review`
