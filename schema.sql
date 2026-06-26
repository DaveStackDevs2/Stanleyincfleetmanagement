-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.vehicles (
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  vin text NOT NULL UNIQUE,
  stock_number text NOT NULL,
  model text NOT NULL,
  fleet_type text NOT NULL,
  status text NOT NULL DEFAULT 'available'::text,
  mileage integer NOT NULL,
  recon_status text NOT NULL DEFAULT 'clean'::text,
  current_tag text NOT NULL,
  fleet_conversion_type text NOT NULL,
  location text,
  notes text,
  ctp_program_active boolean NOT NULL DEFAULT false,
  ctp_program_entered_at timestamp with time zone,
  ctp_entry_mileage integer,
  ctp_monitoring_notes text,
  CONSTRAINT vehicles_pkey PRIMARY KEY (id)
);
CREATE TABLE public.tags (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  tag_name text NOT NULL UNIQUE,
  tag_type text NOT NULL,
  expires_at timestamp with time zone,
  status text NOT NULL DEFAULT 'active'::text,
  CONSTRAINT tags_pkey PRIMARY KEY (id)
);
CREATE TABLE public.reservations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  vehicle_id uuid,
  start_date timestamp with time zone NOT NULL,
  expected_return_datetime timestamp with time zone NOT NULL,
  status text NOT NULL DEFAULT 'quote'::text,
  reservation_type text NOT NULL DEFAULT 'rental'::text,
  notes text,
  cancellation_reason text,
  start_mileage integer,
  end_mileage integer,
  condition_flag boolean NOT NULL DEFAULT false,
  requested_model text NOT NULL,
  service_advisor text,
  ro_number text,
  pay_type text NOT NULL DEFAULT 'customer'::text,
  actual_return_datetime timestamp with time zone,
  billed_through_datetime timestamp with time zone,
  transportation_event_id uuid NOT NULL,
  customer_id uuid,
  CONSTRAINT reservations_pkey PRIMARY KEY (id),
  CONSTRAINT reservations_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id),
  CONSTRAINT reservations_customer_fk FOREIGN KEY (customer_id) REFERENCES public.customers(id),
  CONSTRAINT fk_reservations_transportation_event FOREIGN KEY (transportation_event_id) REFERENCES public.transportation_events(id)
);
CREATE TABLE public.audit_log (
  id uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  action_type text NOT NULL,
  field_name text,
  old_value text,
  new_value text,
  metadata jsonb,
  actor_user_id text NOT NULL,
  CONSTRAINT audit_log_pkey PRIMARY KEY (id)
);
CREATE TABLE public.vehicle_tags (
  id uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  vehicle_id uuid NOT NULL,
  tag_id uuid,
  applied_at timestamp with time zone NOT NULL DEFAULT now(),
  removed_at timestamp with time zone,
  is_active boolean NOT NULL DEFAULT true,
  applied_by_user_id uuid,
  removed_by_user_id uuid,
  notes text,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT vehicle_tags_pkey PRIMARY KEY (id),
  CONSTRAINT vehicle_tags_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id),
  CONSTRAINT vehicle_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES public.tags(id),
  CONSTRAINT vehicle_tags_applied_by_user_id_fkey FOREIGN KEY (applied_by_user_id) REFERENCES public.app_users(id),
  CONSTRAINT vehicle_tags_removed_by_user_id_fkey FOREIGN KEY (removed_by_user_id) REFERENCES public.app_users(id)
);
CREATE TABLE public.rental_model_limits (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  vehicle_class text NOT NULL UNIQUE,
  daily_limit integer NOT NULL,
  CONSTRAINT rental_model_limits_pkey PRIMARY KEY (id)
);
CREATE TABLE public.reservation_conflicts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  reservation_id uuid NOT NULL,
  vehicle_class text NOT NULL,
  conflict_type text NOT NULL,
  severity text NOT NULL,
  message text NOT NULL,
  is_resolved boolean NOT NULL DEFAULT false,
  resolved_at timestamp with time zone,
  created_by text NOT NULL,
  reservation_vehicle_dependency_id uuid,
  CONSTRAINT reservation_conflicts_pkey PRIMARY KEY (id),
  CONSTRAINT reservation_conflicts_reservation_id_fkey FOREIGN KEY (reservation_id) REFERENCES public.reservations(id)
);
CREATE TABLE public.quotes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  vehicle_class text NOT NULL,
  start_date timestamp with time zone NOT NULL,
  expected_return_datetime timestamp with time zone NOT NULL,
  status text NOT NULL,
  notes text,
  is_active boolean NOT NULL DEFAULT true,
  converted_to_reservation_id uuid,
  customer_id uuid,
  CONSTRAINT quotes_pkey PRIMARY KEY (id),
  CONSTRAINT quotes_converted_to_reservation_id_fkey FOREIGN KEY (converted_to_reservation_id) REFERENCES public.reservations(id),
  CONSTRAINT quotes_customer_fk FOREIGN KEY (customer_id) REFERENCES public.customers(id)
);
CREATE TABLE public.fleet_policies (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  vehicle_class text NOT NULL,
  model_lock_window_days integer NOT NULL,
  overbook_threshold integer,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT fleet_policies_pkey PRIMARY KEY (id)
);
CREATE TABLE public.engine_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  run_id text NOT NULL UNIQUE,
  trigger_type text NOT NULL,
  reservation_id text,
  status text DEFAULT 'completed'::text,
  conflicts_count integer DEFAULT 0,
  audit_events_count integer DEFAULT 0,
  metadata jsonb,
  CONSTRAINT engine_runs_pkey PRIMARY KEY (id)
);
CREATE TABLE public.transportation_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  source_type text NOT NULL,
  source_id uuid,
  status text NOT NULL DEFAULT 'active'::text,
  notes text,
  customer_id uuid,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  closed_at timestamp with time zone,
  closed_by uuid,
  expected_return_at timestamp with time zone,
  CONSTRAINT transportation_events_pkey PRIMARY KEY (id),
  CONSTRAINT transportation_events_customer_fk FOREIGN KEY (customer_id) REFERENCES public.customers(id),
  CONSTRAINT transportation_events_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.app_users(id)
);
CREATE TABLE public.vehicle_swaps (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  transportation_event_id uuid NOT NULL,
  old_vehicle_id uuid,
  new_vehicle_id uuid,
  swapped_at timestamp with time zone DEFAULT now(),
  reason text,
  actor_user_id text,
  CONSTRAINT vehicle_swaps_pkey PRIMARY KEY (id),
  CONSTRAINT vehicle_swaps_transportation_event_id_fkey FOREIGN KEY (transportation_event_id) REFERENCES public.transportation_events(id),
  CONSTRAINT vehicle_swaps_old_vehicle_id_fkey FOREIGN KEY (old_vehicle_id) REFERENCES public.vehicles(id),
  CONSTRAINT vehicle_swaps_new_vehicle_id_fkey FOREIGN KEY (new_vehicle_id) REFERENCES public.vehicles(id)
);
CREATE TABLE public.billing_lines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  transportation_event_id uuid NOT NULL,
  reservation_id uuid,
  vehicle_id uuid,
  pay_type text NOT NULL,
  amount numeric DEFAULT 0 CHECK (amount IS NULL OR amount >= 0::numeric),
  tax_amount numeric DEFAULT 0 CHECK (tax_amount IS NULL OR tax_amount >= 0::numeric),
  start_time timestamp with time zone,
  end_time timestamp with time zone,
  source_rule text,
  vehicle_event_id uuid,
  contract_period_id uuid,
  pay_type_rule_id uuid,
  line_type text CHECK (line_type IS NULL OR (line_type = ANY (ARRAY['initial_assignment'::text, 'same_vehicle_renewal'::text, 'pay_type_split'::text, 'new_vehicle_segment'::text, 'new_event_after_gap'::text, 'rental_extension'::text, 'tax'::text, 'late_fee'::text, 'loaner_overdue'::text]))),
  parent_billing_line_id uuid,
  warranty_provider_id uuid,
  default_covered_days_snapshot integer CHECK (default_covered_days_snapshot IS NULL OR default_covered_days_snapshot >= 0),
  covered_days_override integer CHECK (covered_days_override IS NULL OR covered_days_override >= 0),
  is_open boolean NOT NULL DEFAULT true,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  paid_through_at timestamp with time zone,
  extended_from_billing_line_id uuid,
  default_daily_rate_snapshot numeric,
  daily_rate_override numeric,
  CONSTRAINT billing_lines_pkey PRIMARY KEY (id),
  CONSTRAINT billing_lines_transportation_event_id_fkey FOREIGN KEY (transportation_event_id) REFERENCES public.transportation_events(id),
  CONSTRAINT billing_lines_reservation_id_fkey FOREIGN KEY (reservation_id) REFERENCES public.reservations(id),
  CONSTRAINT billing_lines_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id),
  CONSTRAINT billing_lines_vehicle_event_id_fkey FOREIGN KEY (vehicle_event_id) REFERENCES public.vehicle_events(id),
  CONSTRAINT billing_lines_contract_period_id_fkey FOREIGN KEY (contract_period_id) REFERENCES public.contract_periods(id),
  CONSTRAINT billing_lines_pay_type_rule_id_fkey FOREIGN KEY (pay_type_rule_id) REFERENCES public.pay_type_rules(id),
  CONSTRAINT billing_lines_parent_billing_line_id_fkey FOREIGN KEY (parent_billing_line_id) REFERENCES public.billing_lines(id),
  CONSTRAINT billing_lines_warranty_provider_id_fkey FOREIGN KEY (warranty_provider_id) REFERENCES public.warranty_providers(id)
);
CREATE TABLE public.billing_event_totals (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  transportation_event_id uuid UNIQUE,
  warranty_total numeric DEFAULT 0,
  extended_warranty_total numeric DEFAULT 0,
  customer_pay_total numeric DEFAULT 0,
  tax_total numeric DEFAULT 0,
  grand_total numeric DEFAULT 0,
  CONSTRAINT billing_event_totals_pkey PRIMARY KEY (id),
  CONSTRAINT billing_event_totals_transportation_event_id_fkey FOREIGN KEY (transportation_event_id) REFERENCES public.transportation_events(id)
);
CREATE TABLE public.warranty_providers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  name text NOT NULL UNIQUE,
  provider_type text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  default_daily_rate numeric,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  notes text,
  CONSTRAINT warranty_providers_pkey PRIMARY KEY (id)
);
CREATE TABLE public.extended_warranty_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  provider_id uuid,
  covered_days integer DEFAULT 0,
  requires_approval boolean DEFAULT false,
  daily_rate numeric,
  is_active boolean NOT NULL DEFAULT true,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  notes text,
  CONSTRAINT extended_warranty_rules_pkey PRIMARY KEY (id),
  CONSTRAINT extended_warranty_rules_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES public.warranty_providers(id)
);
CREATE TABLE public.gm_warranty_rates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  less_than_24hr_rate numeric DEFAULT 0,
  over_24hr_rate numeric DEFAULT 0,
  customer_pay_rate numeric DEFAULT 0,
  tax_rate numeric DEFAULT 0,
  CONSTRAINT gm_warranty_rates_pkey PRIMARY KEY (id)
);
CREATE TABLE public.warranty_alerts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  transportation_event_id uuid,
  ro_number text,
  provider_name text,
  status text DEFAULT 'open'::text,
  message text,
  CONSTRAINT warranty_alerts_pkey PRIMARY KEY (id),
  CONSTRAINT warranty_alerts_transportation_event_id_fkey FOREIGN KEY (transportation_event_id) REFERENCES public.transportation_events(id)
);
CREATE TABLE public.customers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  tekion_customer_number text NOT NULL UNIQUE,
  name text NOT NULL,
  phone text,
  email text,
  flags jsonb,
  internal_notes text,
  CONSTRAINT customers_pkey PRIMARY KEY (id)
);
CREATE TABLE public.notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  type text NOT NULL,
  message text NOT NULL,
  related_event_id uuid,
  is_read boolean DEFAULT false,
  CONSTRAINT notifications_pkey PRIMARY KEY (id),
  CONSTRAINT notifications_related_event_id_fkey FOREIGN KEY (related_event_id) REFERENCES public.transportation_events(id)
);
CREATE TABLE public.transportation_event_state_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  transportation_event_id uuid NOT NULL,
  previous_status text,
  new_status text NOT NULL,
  changed_at timestamp with time zone DEFAULT now(),
  changed_by text,
  metadata jsonb,
  CONSTRAINT transportation_event_state_history_pkey PRIMARY KEY (id)
);
CREATE TABLE public.active_vehicle_assignments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  transportation_event_id uuid NOT NULL UNIQUE,
  vehicle_id uuid NOT NULL,
  assigned_at timestamp with time zone DEFAULT now(),
  assignment_source text NOT NULL,
  assigned_by text,
  is_active boolean DEFAULT true,
  CONSTRAINT active_vehicle_assignments_pkey PRIMARY KEY (id)
);
CREATE TABLE public.warranty_cases (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  transportation_event_id uuid NOT NULL,
  reservation_id uuid,
  provider_id uuid,
  provider_name text,
  approval_status text DEFAULT 'pending'::text,
  approved_at timestamp with time zone,
  approved_days integer,
  current_day_count integer DEFAULT 0,
  last_checked_at timestamp with time zone,
  requires_manual_review boolean DEFAULT false,
  escalation_level integer DEFAULT 0,
  metadata jsonb,
  CONSTRAINT warranty_cases_pkey PRIMARY KEY (id)
);
CREATE TABLE public.warranty_day_ledger (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  warranty_case_id uuid NOT NULL,
  transportation_event_id uuid NOT NULL,
  day_index integer NOT NULL,
  date_used date NOT NULL,
  billing_state text NOT NULL,
  tax_applied numeric DEFAULT 0,
  amount_applied numeric DEFAULT 0,
  CONSTRAINT warranty_day_ledger_pkey PRIMARY KEY (id)
);
CREATE TABLE public.pay_type_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  pay_type text NOT NULL UNIQUE,
  tax_applicable boolean DEFAULT false,
  priority integer DEFAULT 0,
  stacking_allowed boolean DEFAULT true,
  active boolean DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  is_taxable boolean NOT NULL DEFAULT false,
  default_daily_amount numeric CHECK (default_daily_amount IS NULL OR default_daily_amount >= 0::numeric),
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  description text,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT pay_type_rules_pkey PRIMARY KEY (id)
);
CREATE TABLE public.admin_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  setting_key text NOT NULL UNIQUE,
  setting_value jsonb NOT NULL,
  description text,
  CONSTRAINT admin_settings_pkey PRIMARY KEY (id)
);
CREATE TABLE public.notification_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  rule_name text NOT NULL UNIQUE,
  trigger_event text NOT NULL,
  severity text DEFAULT 'info'::text,
  notify_admin boolean DEFAULT true,
  notify_service boolean DEFAULT false,
  cooldown_minutes integer DEFAULT 1440,
  is_active boolean DEFAULT true,
  CONSTRAINT notification_rules_pkey PRIMARY KEY (id)
);
CREATE TABLE public.notification_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  notification_type text NOT NULL,
  message text NOT NULL,
  related_event_id uuid,
  sent_to jsonb,
  status text DEFAULT 'sent'::text,
  CONSTRAINT notification_log_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_users (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  auth_user_id uuid NOT NULL UNIQUE,
  full_name text,
  email text NOT NULL,
  phone text,
  is_active boolean NOT NULL DEFAULT true,
  last_login timestamp with time zone,
  notes text,
  CONSTRAINT app_users_pkey PRIMARY KEY (id)
);
CREATE TABLE public.roles (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  role_name text NOT NULL UNIQUE,
  description text,
  is_system_role boolean DEFAULT false,
  CONSTRAINT roles_pkey PRIMARY KEY (id)
);
CREATE TABLE public.user_roles (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  user_id uuid,
  role_id uuid,
  CONSTRAINT user_roles_pkey PRIMARY KEY (id),
  CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_users(id),
  CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id)
);
CREATE TABLE public.permissions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  permission_key text NOT NULL UNIQUE,
  description text,
  CONSTRAINT permissions_pkey PRIMARY KEY (id)
);
CREATE TABLE public.role_permissions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  role_id uuid,
  permission_id uuid,
  CONSTRAINT role_permissions_pkey PRIMARY KEY (id),
  CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id),
  CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(id)
);
CREATE TABLE public.approval_actions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  transportation_event_id uuid,
  reservation_id uuid,
  action_type text NOT NULL,
  requested_by uuid,
  approved_by uuid,
  status text DEFAULT 'pending'::text,
  reason text,
  metadata jsonb,
  CONSTRAINT approval_actions_pkey PRIMARY KEY (id),
  CONSTRAINT approval_actions_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.app_users(id),
  CONSTRAINT approval_actions_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.app_users(id)
);
CREATE TABLE public.customer_preferences (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  customer_id uuid,
  allow_sms boolean DEFAULT false,
  allow_email boolean DEFAULT false,
  allow_phone boolean DEFAULT false,
  vip_flag boolean DEFAULT false,
  frequent_renter boolean DEFAULT false,
  CONSTRAINT customer_preferences_pkey PRIMARY KEY (id),
  CONSTRAINT customer_preferences_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id)
);
CREATE TABLE public.notification_recipients (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  user_id uuid,
  channel text NOT NULL,
  is_enabled boolean DEFAULT true,
  CONSTRAINT notification_recipients_pkey PRIMARY KEY (id),
  CONSTRAINT notification_recipients_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_users(id)
);
CREATE TABLE public.notification_delivery_queue (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  notification_type text NOT NULL,
  message text NOT NULL,
  related_event_id uuid,
  target_user_id uuid,
  channel text NOT NULL,
  status text DEFAULT 'pending'::text,
  sent_at timestamp with time zone,
  CONSTRAINT notification_delivery_queue_pkey PRIMARY KEY (id),
  CONSTRAINT notification_delivery_queue_target_user_id_fkey FOREIGN KEY (target_user_id) REFERENCES public.app_users(id)
);
CREATE TABLE public.admin_setting_permissions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone DEFAULT now(),
  setting_key text NOT NULL,
  required_permission text NOT NULL,
  CONSTRAINT admin_setting_permissions_pkey PRIMARY KEY (id)
);
CREATE TABLE public.vehicle_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  transportation_event_id uuid NOT NULL,
  vehicle_id uuid NOT NULL,
  actual_out_at timestamp with time zone NOT NULL,
  actual_in_at timestamp with time zone,
  is_open boolean NOT NULL DEFAULT true,
  ended_reason text CHECK (ended_reason = ANY (ARRAY['returned'::text, 'swapped'::text, 'case_closed'::text, 'other'::text])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid,
  updated_by uuid,
  CONSTRAINT vehicle_events_pkey PRIMARY KEY (id),
  CONSTRAINT vehicle_events_transportation_event_id_fkey FOREIGN KEY (transportation_event_id) REFERENCES public.transportation_events(id),
  CONSTRAINT vehicle_events_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id),
  CONSTRAINT vehicle_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.app_users(id),
  CONSTRAINT vehicle_events_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.app_users(id)
);
CREATE TABLE public.contract_periods (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  vehicle_event_id uuid NOT NULL,
  contract_out_at timestamp with time zone NOT NULL,
  contract_in_at timestamp with time zone,
  renewal_sequence integer NOT NULL DEFAULT 0 CHECK (renewal_sequence >= 0),
  is_open boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid,
  updated_by uuid,
  CONSTRAINT contract_periods_pkey PRIMARY KEY (id),
  CONSTRAINT contract_periods_vehicle_event_id_fkey FOREIGN KEY (vehicle_event_id) REFERENCES public.vehicle_events(id),
  CONSTRAINT contract_periods_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.app_users(id),
  CONSTRAINT contract_periods_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.app_users(id)
);
CREATE TABLE public.transportation_event_notes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  transportation_event_id uuid NOT NULL,
  note_type text NOT NULL CHECK (note_type = ANY (ARRAY['general_case_note'::text, 'estimated_return_change'::text, 'billing_note'::text])),
  reason_code text,
  note_text text,
  old_estimated_return timestamp with time zone,
  new_estimated_return timestamp with time zone,
  entered_by_user_id uuid,
  entered_at timestamp with time zone NOT NULL DEFAULT now(),
  source_context text CHECK (source_context IS NULL OR (source_context = ANY (ARRAY['case'::text, 'billing'::text, 'reservation'::text]))),
  CONSTRAINT transportation_event_notes_pkey PRIMARY KEY (id),
  CONSTRAINT transportation_event_notes_transportation_event_id_fkey FOREIGN KEY (transportation_event_id) REFERENCES public.transportation_events(id),
  CONSTRAINT transportation_event_notes_entered_by_user_id_fkey FOREIGN KEY (entered_by_user_id) REFERENCES public.app_users(id)
);
CREATE TABLE public.late_fee_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order >= 0),
  rule_kind text NOT NULL CHECK (rule_kind = ANY (ARRAY['grace_period'::text, 'fixed_fee'::text, 'full_day_trigger'::text])),
  threshold_unit text NOT NULL CHECK (threshold_unit = ANY (ARRAY['minutes'::text, 'hours'::text, 'days'::text])),
  threshold_value integer NOT NULL CHECK (threshold_value >= 0),
  fee_amount numeric CHECK (fee_amount IS NULL OR fee_amount >= 0::numeric),
  description text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid,
  updated_by uuid,
  CONSTRAINT late_fee_rules_pkey PRIMARY KEY (id),
  CONSTRAINT late_fee_rules_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.app_users(id),
  CONSTRAINT late_fee_rules_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.app_users(id)
);
CREATE TABLE public.reservation_vehicle_dependencies (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL,
  vehicle_id uuid NOT NULL,
  source_transportation_event_id uuid,
  dependency_type text NOT NULL CHECK (dependency_type = ANY (ARRAY['soft_lock'::text, 'hard_lock'::text])),
  status text NOT NULL DEFAULT 'pending_return'::text CHECK (status = ANY (ARRAY['pending_return'::text, 'ready'::text, 'conflict'::text, 'resolved'::text, 'cancelled'::text])),
  risk_level text NOT NULL DEFAULT 'normal'::text CHECK (risk_level = ANY (ARRAY['normal'::text, 'depends_on_return'::text, 'at_risk'::text, 'must_return'::text, 'critical'::text])),
  expected_return_snapshot timestamp with time zone,
  resolution_type text CHECK (resolution_type = ANY (ARRAY['reassigned'::text, 'vehicle_returned_available'::text, 'removed'::text, 'cancelled'::text, 'other'::text])),
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by_user_id uuid,
  updated_by_user_id uuid,
  resolved_at timestamp with time zone,
  resolved_by_user_id uuid,
  CONSTRAINT reservation_vehicle_dependencies_pkey PRIMARY KEY (id),
  CONSTRAINT reservation_vehicle_dependencies_reservation_id_fkey FOREIGN KEY (reservation_id) REFERENCES public.reservations(id),
  CONSTRAINT reservation_vehicle_dependencies_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id),
  CONSTRAINT reservation_vehicle_dependenc_source_transportation_event__fkey FOREIGN KEY (source_transportation_event_id) REFERENCES public.transportation_events(id),
  CONSTRAINT reservation_vehicle_dependencies_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.app_users(id),
  CONSTRAINT reservation_vehicle_dependencies_updated_by_user_id_fkey FOREIGN KEY (updated_by_user_id) REFERENCES public.app_users(id),
  CONSTRAINT reservation_vehicle_dependencies_resolved_by_user_id_fkey FOREIGN KEY (resolved_by_user_id) REFERENCES public.app_users(id)
);
CREATE TABLE public.vehicle_stock_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL,
  stock_number text NOT NULL,
  applied_at timestamp with time zone NOT NULL DEFAULT now(),
  removed_at timestamp with time zone,
  is_active boolean NOT NULL DEFAULT true,
  changed_by_user_id uuid,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT vehicle_stock_history_pkey PRIMARY KEY (id),
  CONSTRAINT vehicle_stock_history_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id),
  CONSTRAINT vehicle_stock_history_changed_by_user_id_fkey FOREIGN KEY (changed_by_user_id) REFERENCES public.app_users(id)
);
CREATE TABLE public.lost_rentals (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  requested_at timestamp with time zone NOT NULL DEFAULT now(),
  vehicle_class text,
  model_requested text,
  requested_start_at timestamp with time zone,
  requested_end_at timestamp with time zone,
  requested_duration_days integer CHECK (requested_duration_days IS NULL OR requested_duration_days >= 0),
  quoted_daily_rate numeric CHECK (quoted_daily_rate IS NULL OR quoted_daily_rate >= 0::numeric),
  customer_id uuid,
  transportation_event_id uuid,
  reservation_id uuid,
  reason text,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by_user_id uuid,
  updated_by_user_id uuid,
  CONSTRAINT lost_rentals_pkey PRIMARY KEY (id),
  CONSTRAINT lost_rentals_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id),
  CONSTRAINT lost_rentals_transportation_event_id_fkey FOREIGN KEY (transportation_event_id) REFERENCES public.transportation_events(id),
  CONSTRAINT lost_rentals_reservation_id_fkey FOREIGN KEY (reservation_id) REFERENCES public.reservations(id),
  CONSTRAINT lost_rentals_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.app_users(id),
  CONSTRAINT lost_rentals_updated_by_user_id_fkey FOREIGN KEY (updated_by_user_id) REFERENCES public.app_users(id)
);
CREATE TABLE public.app_user_security (
  user_id uuid NOT NULL,
  failed_login_count integer NOT NULL DEFAULT 0 CHECK (failed_login_count >= 0),
  last_failed_login_at timestamp with time zone,
  locked_until timestamp with time zone,
  post_lockout_final_attempt_allowed boolean NOT NULL DEFAULT false,
  is_disabled boolean NOT NULL DEFAULT false,
  disabled_at timestamp with time zone,
  disabled_reason text,
  password_reset_pending boolean NOT NULL DEFAULT false,
  temporary_password_issued_at timestamp with time zone,
  temporary_password_expires_at timestamp with time zone,
  temporary_password_issued_by uuid,
  outside_network_access_allowed boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  lockout_count integer NOT NULL DEFAULT 0 CHECK (lockout_count >= 0),
  last_successful_login_at timestamp with time zone,
  CONSTRAINT app_user_security_pkey PRIMARY KEY (user_id),
  CONSTRAINT app_user_security_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_users(id),
  CONSTRAINT app_user_security_temporary_password_issued_by_fkey FOREIGN KEY (temporary_password_issued_by) REFERENCES public.app_users(id)
);
CREATE TABLE public.approved_networks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  label text NOT NULL,
  network_value text NOT NULL,
  network_type text NOT NULL CHECK (network_type = ANY (ARRAY['single_ip'::text, 'cidr'::text])),
  is_active boolean NOT NULL DEFAULT true,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by_user_id uuid,
  updated_by_user_id uuid,
  CONSTRAINT approved_networks_pkey PRIMARY KEY (id),
  CONSTRAINT approved_networks_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.app_users(id),
  CONSTRAINT approved_networks_updated_by_user_id_fkey FOREIGN KEY (updated_by_user_id) REFERENCES public.app_users(id)
);
CREATE TABLE public.app_user_reset_tokens (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  token_hash text NOT NULL,
  reset_mode text NOT NULL CHECK (reset_mode = ANY (ARRAY['email_link'::text, 'admin_reset'::text])),
  issued_at timestamp with time zone NOT NULL DEFAULT now(),
  expires_at timestamp with time zone NOT NULL,
  used_at timestamp with time zone,
  is_active boolean NOT NULL DEFAULT true,
  issued_by_user_id uuid,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_user_reset_tokens_pkey PRIMARY KEY (id),
  CONSTRAINT app_user_reset_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_users(id),
  CONSTRAINT app_user_reset_tokens_issued_by_user_id_fkey FOREIGN KEY (issued_by_user_id) REFERENCES public.app_users(id)
);
CREATE TABLE public.user_auth_security_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  event_type text NOT NULL,
  factor_type text,
  event_status text,
  details jsonb,
  recorded_by_user_id uuid,
  recorded_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT user_auth_security_events_pkey PRIMARY KEY (id),
  CONSTRAINT user_auth_security_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.app_users(id),
  CONSTRAINT user_auth_security_events_recorded_by_user_id_fkey FOREIGN KEY (recorded_by_user_id) REFERENCES public.app_users(id)
);
CREATE TABLE public.email_outbound_messages (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  email_provider text NOT NULL DEFAULT 'resend'::text,
  message_type text NOT NULL,
  template_key text,
  related_user_id uuid,
  related_customer_id uuid,
  related_reservation_id uuid,
  related_transportation_event_id uuid,
  to_email text NOT NULL,
  from_email text NOT NULL,
  subject text,
  provider_message_id text,
  send_status text NOT NULL DEFAULT 'queued'::text,
  provider_response jsonb,
  queued_at timestamp with time zone NOT NULL DEFAULT now(),
  sent_at timestamp with time zone,
  failed_at timestamp with time zone,
  last_event_at timestamp with time zone,
  created_by_user_id uuid,
  CONSTRAINT email_outbound_messages_pkey PRIMARY KEY (id),
  CONSTRAINT email_outbound_messages_related_user_id_fkey FOREIGN KEY (related_user_id) REFERENCES public.app_users(id),
  CONSTRAINT email_outbound_messages_related_customer_id_fkey FOREIGN KEY (related_customer_id) REFERENCES public.customers(id),
  CONSTRAINT email_outbound_messages_related_reservation_id_fkey FOREIGN KEY (related_reservation_id) REFERENCES public.reservations(id),
  CONSTRAINT email_outbound_messages_related_transportation_event_id_fkey FOREIGN KEY (related_transportation_event_id) REFERENCES public.transportation_events(id),
  CONSTRAINT email_outbound_messages_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.app_users(id)
);
CREATE TABLE public.email_provider_webhook_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  email_outbound_message_id uuid,
  provider_name text NOT NULL DEFAULT 'resend'::text,
  provider_event_id text,
  provider_message_id text,
  event_type text NOT NULL,
  event_payload jsonb,
  occurred_at timestamp with time zone NOT NULL DEFAULT now(),
  received_at timestamp with time zone NOT NULL DEFAULT now(),
  processed_status text NOT NULL DEFAULT 'received'::text,
  CONSTRAINT email_provider_webhook_events_pkey PRIMARY KEY (id),
  CONSTRAINT email_provider_webhook_events_email_outbound_message_id_fkey FOREIGN KEY (email_outbound_message_id) REFERENCES public.email_outbound_messages(id)
);
CREATE TABLE public.service_action_contracts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  action_key text NOT NULL UNIQUE,
  action_group text NOT NULL,
  entity_scope text NOT NULL,
  db_function_name text NOT NULL,
  action_type text NOT NULL,
  description text,
  requires_authenticated_user boolean NOT NULL DEFAULT true,
  requires_aal2 boolean NOT NULL DEFAULT false,
  writes_data boolean NOT NULL DEFAULT false,
  frontend_safe boolean NOT NULL DEFAULT true,
  internal_only boolean NOT NULL DEFAULT false,
  required_permission text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT service_action_contracts_pkey PRIMARY KEY (id)
);
CREATE TABLE public.vehicle_qr_codes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL,
  qr_token text NOT NULL UNIQUE,
  landing_mode text NOT NULL DEFAULT 'vehicle_action_hub'::text,
  is_active boolean NOT NULL DEFAULT true,
  issued_at timestamp with time zone NOT NULL DEFAULT now(),
  retired_at timestamp with time zone,
  issued_by_user_id uuid,
  notes text,
  CONSTRAINT vehicle_qr_codes_pkey PRIMARY KEY (id),
  CONSTRAINT vehicle_qr_codes_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id),
  CONSTRAINT vehicle_qr_codes_issued_by_user_id_fkey FOREIGN KEY (issued_by_user_id) REFERENCES public.app_users(id)
);
CREATE TABLE public.vehicle_scan_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  session_type text NOT NULL,
  started_by_user_id uuid NOT NULL,
  started_at timestamp with time zone NOT NULL DEFAULT now(),
  ended_at timestamp with time zone,
  session_status text NOT NULL DEFAULT 'active'::text,
  notes text,
  CONSTRAINT vehicle_scan_sessions_pkey PRIMARY KEY (id),
  CONSTRAINT vehicle_scan_sessions_started_by_user_id_fkey FOREIGN KEY (started_by_user_id) REFERENCES public.app_users(id)
);
CREATE TABLE public.vehicle_scan_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL,
  vehicle_qr_code_id uuid,
  scan_session_id uuid,
  scanned_by_user_id uuid NOT NULL,
  action_type text NOT NULL,
  result_status text NOT NULL DEFAULT 'recorded'::text,
  scanned_at timestamp with time zone NOT NULL DEFAULT now(),
  related_reservation_id uuid,
  related_transportation_event_id uuid,
  metadata jsonb,
  CONSTRAINT vehicle_scan_events_pkey PRIMARY KEY (id),
  CONSTRAINT vehicle_scan_events_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id),
  CONSTRAINT vehicle_scan_events_vehicle_qr_code_id_fkey FOREIGN KEY (vehicle_qr_code_id) REFERENCES public.vehicle_qr_codes(id),
  CONSTRAINT vehicle_scan_events_scan_session_id_fkey FOREIGN KEY (scan_session_id) REFERENCES public.vehicle_scan_sessions(id),
  CONSTRAINT vehicle_scan_events_scanned_by_user_id_fkey FOREIGN KEY (scanned_by_user_id) REFERENCES public.app_users(id),
  CONSTRAINT vehicle_scan_events_related_reservation_id_fkey FOREIGN KEY (related_reservation_id) REFERENCES public.reservations(id),
  CONSTRAINT vehicle_scan_events_related_transportation_event_id_fkey FOREIGN KEY (related_transportation_event_id) REFERENCES public.transportation_events(id)
);
