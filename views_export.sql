schemaname,viewname,definition
extensions,pg_stat_statements," SELECT userid,
    dbid,
    toplevel,
    queryid,
    query,
    plans,
    total_plan_time,
    min_plan_time,
    max_plan_time,
    mean_plan_time,
    stddev_plan_time,
    calls,
    total_exec_time,
    min_exec_time,
    max_exec_time,
    mean_exec_time,
    stddev_exec_time,
    rows,
    shared_blks_hit,
    shared_blks_read,
    shared_blks_dirtied,
    shared_blks_written,
    local_blks_hit,
    local_blks_read,
    local_blks_dirtied,
    local_blks_written,
    temp_blks_read,
    temp_blks_written,
    shared_blk_read_time,
    shared_blk_write_time,
    local_blk_read_time,
    local_blk_write_time,
    temp_blk_read_time,
    temp_blk_write_time,
    wal_records,
    wal_fpi,
    wal_bytes,
    jit_functions,
    jit_generation_time,
    jit_inlining_count,
    jit_inlining_time,
    jit_optimization_count,
    jit_optimization_time,
    jit_emission_count,
    jit_emission_time,
    jit_deform_count,
    jit_deform_time,
    stats_since,
    minmax_stats_since
   FROM pg_stat_statements(true) pg_stat_statements(userid, dbid, toplevel, queryid, query, plans, total_plan_time, min_plan_time, max_plan_time, mean_plan_time, stddev_plan_time, calls, total_exec_time, min_exec_time, max_exec_time, mean_exec_time, stddev_exec_time, rows, shared_blks_hit, shared_blks_read, shared_blks_dirtied, shared_blks_written, local_blks_hit, local_blks_read, local_blks_dirtied, local_blks_written, temp_blks_read, temp_blks_written, shared_blk_read_time, shared_blk_write_time, local_blk_read_time, local_blk_write_time, temp_blk_read_time, temp_blk_write_time, wal_records, wal_fpi, wal_bytes, jit_functions, jit_generation_time, jit_inlining_count, jit_inlining_time, jit_optimization_count, jit_optimization_time, jit_emission_count, jit_emission_time, jit_deform_count, jit_deform_time, stats_since, minmax_stats_since);"
extensions,pg_stat_statements_info," SELECT dealloc,
    stats_reset
   FROM pg_stat_statements_info() pg_stat_statements_info(dealloc, stats_reset);"
public,v_active_approved_networks," SELECT id,
    label,
    network_value,
    network_type,
    is_active,
    notes,
    created_at,
    updated_at,
    created_by_user_id,
    updated_by_user_id
   FROM approved_networks an
  WHERE (is_active = true);"
public,v_active_extended_warranty_provider_rules," SELECT wp.id AS provider_id,
    wp.name AS provider_name,
    wp.provider_type,
    wp.is_active AS provider_is_active,
    wp.default_daily_rate AS provider_default_daily_rate,
    ewr.id AS rule_id,
    ewr.covered_days,
    ewr.requires_approval,
    ewr.daily_rate AS rule_daily_rate,
    ewr.is_active AS rule_is_active,
    ewr.created_at,
    ewr.updated_at,
    COALESCE(ewr.daily_rate, wp.default_daily_rate) AS resolved_daily_rate
   FROM (warranty_providers wp
     JOIN extended_warranty_rules ewr ON ((ewr.provider_id = wp.id)))
  WHERE ((wp.is_active = true) AND (ewr.is_active = true));"
public,v_active_hard_lock_conflicts," SELECT d.id AS dependency_id,
    d.reservation_id,
    d.vehicle_id,
    d.source_transportation_event_id,
    d.dependency_type,
    d.status AS dependency_status,
    d.risk_level,
    d.expected_return_snapshot,
    c.id AS conflict_id,
    c.conflict_type,
    c.severity,
    c.message,
    c.is_resolved
   FROM (reservation_vehicle_dependencies d
     LEFT JOIN reservation_conflicts c ON (((c.reservation_vehicle_dependency_id = d.id) AND (c.is_resolved = false))))
  WHERE ((d.dependency_type = 'hard_lock'::text) AND (d.status = ANY (ARRAY['ready'::text, 'conflict'::text])));"
public,v_active_late_fee_rules," SELECT id AS late_fee_rule_id,
    is_active,
    sort_order,
    rule_kind,
    threshold_unit,
    threshold_value,
    fee_amount,
    description,
    created_at,
    updated_at,
    created_by,
    updated_by
   FROM late_fee_rules lfr
  WHERE (is_active = true);"
public,v_active_usable_reset_tokens," SELECT id AS reset_token_id,
    user_id,
    token_hash,
    reset_mode,
    issued_at,
    expires_at,
    used_at,
    is_active,
    issued_by_user_id,
    notes
   FROM app_user_reset_tokens t
  WHERE ((is_active = true) AND (used_at IS NULL) AND (expires_at >= now()));"
public,v_admin_settings_catalog," SELECT s.id AS admin_setting_id,
    s.setting_key,
    s.setting_value,
    s.description,
    asp.required_permission,
    (asp.required_permission IS NOT NULL) AS has_permission_requirement
   FROM (admin_settings s
     LEFT JOIN admin_setting_permissions asp ON ((asp.setting_key = s.setting_key)));"
public,v_app_users_with_roles," SELECT u.id AS user_id,
    u.auth_user_id,
    u.full_name,
    u.email,
    u.phone,
    u.is_active,
    u.last_login,
    u.notes,
    COALESCE(string_agg(DISTINCT r.role_name, ', '::text ORDER BY r.role_name) FILTER (WHERE (r.role_name IS NOT NULL)), ''::text) AS role_summary
   FROM ((app_users u
     LEFT JOIN user_roles ur ON ((ur.user_id = u.id)))
     LEFT JOIN roles r ON ((r.id = ur.role_id)))
  GROUP BY u.id, u.auth_user_id, u.full_name, u.email, u.phone, u.is_active, u.last_login, u.notes;"
public,v_auth_security_policy_state," SELECT COALESCE(( SELECT (admin_settings.setting_value)::boolean AS setting_value
           FROM admin_settings
          WHERE (admin_settings.setting_key = 'mfa_required_for_all_users'::text)
         LIMIT 1), true) AS mfa_required_for_all_users,
    COALESCE(( SELECT (admin_settings.setting_value)::boolean AS setting_value
           FROM admin_settings
          WHERE (admin_settings.setting_key = 'network_restriction_enabled'::text)
         LIMIT 1), false) AS network_restriction_enabled,
    COALESCE(( SELECT (admin_settings.setting_value)::boolean AS setting_value
           FROM admin_settings
          WHERE (admin_settings.setting_key = 'email_password_reset_link_enabled'::text)
         LIMIT 1), false) AS email_password_reset_link_enabled,
    COALESCE(( SELECT (admin_settings.setting_value)::integer AS setting_value
           FROM admin_settings
          WHERE (admin_settings.setting_key = 'reservation_vin_lock_lead_days'::text)
         LIMIT 1), 0) AS reservation_vin_lock_lead_days,
    COALESCE(( SELECT (admin_settings.setting_value)::boolean AS setting_value
           FROM admin_settings
          WHERE (admin_settings.setting_key = 'late_fees_enabled'::text)
         LIMIT 1), false) AS late_fees_enabled;"
public,v_case_activation_state," SELECT r.reservation_id,
    r.transportation_event_id,
    r.vehicle_id AS reservation_vehicle_id,
    r.start_date,
    r.expected_return_datetime,
    r.reservation_status,
    r.reservation_type,
    r.requested_model,
    r.pay_type AS reservation_pay_type,
    r.customer_id,
    c.vehicle_event_id AS current_vehicle_event_id,
    c.vehicle_id AS current_continuity_vehicle_id,
    c.contract_period_id AS current_contract_period_id,
    c.actual_out_at,
    c.contract_out_at,
    c.vehicle_event_is_open,
    c.contract_period_is_open,
    b.parent_billing_line_id,
    b.pay_type AS billing_pay_type,
    b.parent_amount,
    b.parent_tax_amount,
    b.start_time AS billing_start_time,
    b.end_time AS billing_end_time,
    b.paid_through_at,
    b.parent_is_open AS billing_is_open,
    (c.vehicle_event_id IS NOT NULL) AS has_active_continuity,
    (b.parent_billing_line_id IS NOT NULL) AS has_open_billing_line
   FROM ((v_reservation_transportation_link_state r
     LEFT JOIN v_current_vehicle_continuity c ON ((c.transportation_event_id = r.transportation_event_id)))
     LEFT JOIN LATERAL ( SELECT b_1.reservation_id,
            b_1.transportation_event_id,
            b_1.reservation_vehicle_id,
            b_1.start_date,
            b_1.expected_return_datetime,
            b_1.reservation_status,
            b_1.reservation_type,
            b_1.requested_model,
            b_1.reservation_pay_type,
            b_1.customer_id,
            b_1.parent_billing_line_id,
            b_1.billing_vehicle_id,
            b_1.vehicle_event_id,
            b_1.contract_period_id,
            b_1.pay_type,
            b_1.pay_type_rule_id,
            b_1.parent_amount,
            b_1.parent_tax_amount,
            b_1.start_time,
            b_1.end_time,
            b_1.parent_line_type,
            b_1.warranty_provider_id,
            b_1.default_covered_days_snapshot,
            b_1.covered_days_override,
            b_1.default_daily_rate_snapshot,
            b_1.daily_rate_override,
            b_1.paid_through_at,
            b_1.extended_from_billing_line_id,
            b_1.parent_is_open,
            b_1.tax_billing_line_id,
            b_1.tax_line_amount,
            b_1.tax_line_is_open
           FROM v_reservation_current_billing_state b_1
          WHERE ((b_1.reservation_id = r.reservation_id) AND (b_1.parent_billing_line_id IS NOT NULL))
          ORDER BY b_1.start_time DESC NULLS LAST, b_1.parent_billing_line_id DESC
         LIMIT 1) b ON (true));"
public,v_case_completion_candidate_state," SELECT r.reservation_id,
    r.transportation_event_id,
    r.vehicle_id AS reservation_vehicle_id,
    r.start_date,
    r.expected_return_datetime,
    r.reservation_status,
    r.reservation_type,
    r.reservation_notes,
    r.actual_return_datetime,
    r.billed_through_datetime,
    r.customer_id,
    r.transportation_event_status,
    r.expected_return_at,
    r.closed_at,
    r.closed_by,
    c.vehicle_event_id,
    c.contract_period_id,
    c.actual_out_at,
    c.actual_in_at,
    c.vehicle_event_is_open,
    c.contract_period_is_open,
    b.parent_billing_line_id,
    b.start_time AS billing_start_time,
    b.end_time AS billing_end_time,
    b.paid_through_at,
    b.parent_is_open AS billing_is_open,
    (c.vehicle_event_id IS NOT NULL) AS has_active_continuity,
    (b.parent_billing_line_id IS NOT NULL) AS has_open_billing_line
   FROM ((v_reservation_transportation_link_state r
     LEFT JOIN v_current_vehicle_continuity c ON ((c.transportation_event_id = r.transportation_event_id)))
     LEFT JOIN LATERAL ( SELECT b_1.reservation_id,
            b_1.transportation_event_id,
            b_1.reservation_vehicle_id,
            b_1.start_date,
            b_1.expected_return_datetime,
            b_1.reservation_status,
            b_1.reservation_type,
            b_1.requested_model,
            b_1.reservation_pay_type,
            b_1.customer_id,
            b_1.parent_billing_line_id,
            b_1.billing_vehicle_id,
            b_1.vehicle_event_id,
            b_1.contract_period_id,
            b_1.pay_type,
            b_1.pay_type_rule_id,
            b_1.parent_amount,
            b_1.parent_tax_amount,
            b_1.start_time,
            b_1.end_time,
            b_1.parent_line_type,
            b_1.warranty_provider_id,
            b_1.default_covered_days_snapshot,
            b_1.covered_days_override,
            b_1.default_daily_rate_snapshot,
            b_1.daily_rate_override,
            b_1.paid_through_at,
            b_1.extended_from_billing_line_id,
            b_1.parent_is_open,
            b_1.tax_billing_line_id,
            b_1.tax_line_amount,
            b_1.tax_line_is_open
           FROM v_reservation_current_billing_state b_1
          WHERE ((b_1.reservation_id = r.reservation_id) AND (b_1.parent_billing_line_id IS NOT NULL))
          ORDER BY b_1.start_time DESC NULLS LAST, b_1.parent_billing_line_id DESC
         LIMIT 1) b ON (true));"
public,v_case_continuation_candidate_state," SELECT r.reservation_id,
    r.transportation_event_id,
    r.vehicle_id AS reservation_vehicle_id,
    r.start_date,
    r.expected_return_datetime,
    r.reservation_status,
    r.reservation_type,
    r.requested_model,
    r.customer_id,
    r.actual_return_datetime,
    r.billed_through_datetime,
    c.vehicle_event_id AS current_vehicle_event_id,
    c.vehicle_id AS current_continuity_vehicle_id,
    c.contract_period_id AS current_contract_period_id,
    c.actual_out_at,
    c.actual_in_at,
    c.contract_out_at,
    c.contract_in_at,
    c.renewal_sequence,
    c.vehicle_event_is_open,
    c.contract_period_is_open,
    (r.vehicle_id IS NOT NULL) AS reservation_has_assigned_vehicle,
    (c.vehicle_event_id IS NOT NULL) AS has_active_continuity
   FROM (v_reservation_transportation_link_state r
     LEFT JOIN v_current_vehicle_continuity c ON ((c.transportation_event_id = r.transportation_event_id)));"
public,v_case_reassignment_candidate_state," SELECT r.reservation_id,
    r.transportation_event_id,
    r.vehicle_id AS reservation_vehicle_id,
    r.start_date,
    r.expected_return_datetime,
    r.reservation_status,
    r.reservation_type,
    r.requested_model,
    r.customer_id,
    c.vehicle_event_id AS current_vehicle_event_id,
    c.vehicle_id AS current_continuity_vehicle_id,
    c.contract_period_id AS current_contract_period_id,
    c.actual_out_at,
    c.contract_out_at,
    c.vehicle_event_is_open,
    c.contract_period_is_open,
    dep.current_dependency_id,
    dep.current_dependency_type,
    dep.current_dependency_status,
    dep.current_dependency_risk_level,
    dep.current_dependency_expected_return_snapshot,
    (c.vehicle_event_id IS NOT NULL) AS has_active_continuity,
    (r.vehicle_id IS NOT NULL) AS reservation_has_assigned_vehicle
   FROM ((v_reservation_operational_state r
     LEFT JOIN v_current_vehicle_continuity c ON ((c.transportation_event_id = r.transportation_event_id)))
     LEFT JOIN LATERAL ( SELECT d.id AS current_dependency_id,
            d.dependency_type AS current_dependency_type,
            d.status AS current_dependency_status,
            d.risk_level AS current_dependency_risk_level,
            d.expected_return_snapshot AS current_dependency_expected_return_snapshot
           FROM reservation_vehicle_dependencies d
          WHERE ((d.reservation_id = r.reservation_id) AND (d.status = ANY (ARRAY['pending_return'::text, 'ready'::text, 'conflict'::text])))
          ORDER BY d.updated_at DESC NULLS LAST, d.created_at DESC NULLS LAST, d.id DESC
         LIMIT 1) dep ON (true));"
public,v_contract_period_monitoring," SELECT cp.id AS contract_period_id,
    cp.vehicle_event_id,
    ve.transportation_event_id,
    ve.vehicle_id,
    cp.contract_out_at,
    cp.contract_in_at,
    cp.renewal_sequence,
    cp.is_open,
    business_contract_days(cp.contract_out_at, cp.contract_in_at) AS contract_day_count,
        CASE
            WHEN (business_contract_days(cp.contract_out_at, cp.contract_in_at) >= 30) THEN 'swap_required'::text
            WHEN (business_contract_days(cp.contract_out_at, cp.contract_in_at) >= 25) THEN 'renew_now'::text
            WHEN (business_contract_days(cp.contract_out_at, cp.contract_in_at) >= 20) THEN 'renew_soon'::text
            ELSE 'none'::text
        END AS reminder_state
   FROM (contract_periods cp
     JOIN vehicle_events ve ON ((ve.id = cp.vehicle_event_id)));"
public,v_ctp_monitoring_policy_state," SELECT COALESCE(( SELECT (admin_settings.setting_value)::integer AS setting_value
           FROM admin_settings
          WHERE (admin_settings.setting_key = 'preferred_max_ctp_days'::text)
         LIMIT 1), 60) AS preferred_max_ctp_days,
    COALESCE(( SELECT (admin_settings.setting_value)::integer AS setting_value
           FROM admin_settings
          WHERE (admin_settings.setting_key = 'preferred_max_ctp_qualified_miles'::text)
         LIMIT 1), 2000) AS preferred_max_ctp_qualified_miles;"
public,v_current_extendable_billing_lines," SELECT id AS parent_billing_line_id,
    transportation_event_id,
    reservation_id,
    vehicle_id,
    vehicle_event_id,
    contract_period_id,
    pay_type,
    pay_type_rule_id,
    amount,
    tax_amount,
    start_time,
    end_time,
    line_type,
    warranty_provider_id,
    default_covered_days_snapshot,
    covered_days_override,
    default_daily_rate_snapshot,
    daily_rate_override,
    paid_through_at,
    extended_from_billing_line_id,
    is_open
   FROM billing_lines p
  WHERE ((is_open = true) AND (paid_through_at IS NOT NULL) AND (line_type IS DISTINCT FROM 'tax'::text));"
public,v_current_open_billing_lines," SELECT p.id AS parent_billing_line_id,
    p.transportation_event_id,
    p.reservation_id,
    p.vehicle_id,
    p.vehicle_event_id,
    p.contract_period_id,
    p.pay_type,
    p.pay_type_rule_id,
    p.amount AS parent_amount,
    p.tax_amount AS parent_tax_amount,
    p.start_time,
    p.end_time,
    p.line_type AS parent_line_type,
    p.warranty_provider_id,
    p.default_covered_days_snapshot,
    p.covered_days_override,
    p.default_daily_rate_snapshot,
    p.daily_rate_override,
    p.paid_through_at,
    p.extended_from_billing_line_id,
    p.is_open AS parent_is_open,
    t.id AS tax_billing_line_id,
    t.amount AS tax_line_amount,
    t.is_open AS tax_line_is_open
   FROM (billing_lines p
     LEFT JOIN billing_lines t ON (((t.parent_billing_line_id = p.id) AND (t.line_type = 'tax'::text))))
  WHERE ((p.is_open = true) AND (p.line_type IS DISTINCT FROM 'tax'::text));"
public,v_current_pay_type_rules," SELECT id AS pay_type_rule_id,
    pay_type,
    is_active,
    is_taxable,
    default_daily_amount,
    sort_order,
    description
   FROM pay_type_rules p
  WHERE (is_active = true);"
public,v_current_vehicle_continuity," SELECT ve.id AS vehicle_event_id,
    ve.transportation_event_id,
    ve.vehicle_id,
    ve.actual_out_at,
    ve.actual_in_at,
    ve.is_open AS vehicle_event_is_open,
    ve.ended_reason,
    cp.id AS contract_period_id,
    cp.contract_out_at,
    cp.contract_in_at,
    cp.renewal_sequence,
    cp.is_open AS contract_period_is_open
   FROM (vehicle_events ve
     JOIN contract_periods cp ON ((cp.vehicle_event_id = ve.id)))
  WHERE ((ve.is_open = true) AND (cp.is_open = true));"
public,v_customer_operational_aggregate_state," SELECT c.id AS customer_id,
    c.created_at,
    c.tekion_customer_number,
    c.name,
    c.phone,
    c.email,
    c.flags,
    c.internal_notes,
    count(DISTINCT r.id) AS reservation_count,
    count(DISTINCT r.id) FILTER (WHERE (r.status IS DISTINCT FROM 'cancelled'::text)) AS non_cancelled_reservation_count,
    count(DISTINCT te.id) AS transportation_event_count,
    count(DISTINCT te.id) FILTER (WHERE (te.status = 'active'::text)) AS active_transportation_event_count,
    count(DISTINCT vc.vehicle_event_id) AS open_vehicle_continuity_count,
    max(te.expected_return_at) AS latest_expected_return_at
   FROM (((customers c
     LEFT JOIN reservations r ON ((r.customer_id = c.id)))
     LEFT JOIN transportation_events te ON ((te.customer_id = c.id)))
     LEFT JOIN v_current_vehicle_continuity vc ON ((vc.transportation_event_id = te.id)))
  GROUP BY c.id, c.created_at, c.tekion_customer_number, c.name, c.phone, c.email, c.flags, c.internal_notes;"
public,v_customer_operational_state," SELECT id AS customer_id,
    created_at,
    tekion_customer_number,
    name,
    phone,
    email,
    flags,
    internal_notes
   FROM customers c;"
public,v_email_outbound_message_state," SELECT m.id AS email_outbound_message_id,
    m.email_provider,
    m.message_type,
    m.template_key,
    m.related_user_id,
    u.email AS related_user_email,
    u.full_name AS related_user_full_name,
    m.related_customer_id,
    c.tekion_customer_number AS related_customer_tekion_customer_number,
    c.name AS related_customer_name,
    c.email AS related_customer_email,
    m.related_reservation_id,
    m.related_transportation_event_id,
    m.to_email,
    m.from_email,
    m.subject,
    m.provider_message_id,
    m.send_status,
    m.provider_response,
    m.queued_at,
    m.sent_at,
    m.failed_at,
    m.last_event_at,
    m.created_by_user_id,
    cb.email AS created_by_email,
    cb.full_name AS created_by_full_name
   FROM (((email_outbound_messages m
     LEFT JOIN app_users u ON ((u.id = m.related_user_id)))
     LEFT JOIN customers c ON ((c.id = m.related_customer_id)))
     LEFT JOIN app_users cb ON ((cb.id = m.created_by_user_id)));"
public,v_email_webhook_event_history," SELECT e.id AS email_webhook_event_id,
    e.email_outbound_message_id,
    m.message_type,
    m.template_key,
    m.to_email,
    m.from_email,
    m.subject,
    m.send_status AS current_message_send_status,
    m.related_user_id,
    u.email AS related_user_email,
    u.full_name AS related_user_full_name,
    m.related_customer_id,
    c.tekion_customer_number AS related_customer_tekion_customer_number,
    c.name AS related_customer_name,
    m.related_reservation_id,
    m.related_transportation_event_id,
    e.provider_name,
    e.provider_event_id,
    e.provider_message_id,
    e.event_type,
    e.event_payload,
    e.occurred_at,
    e.received_at,
    e.processed_status
   FROM (((email_provider_webhook_events e
     LEFT JOIN email_outbound_messages m ON ((m.id = e.email_outbound_message_id)))
     LEFT JOIN app_users u ON ((u.id = m.related_user_id)))
     LEFT JOIN customers c ON ((c.id = m.related_customer_id)));"
public,v_extended_warranty_rule_catalog," SELECT ewr.id AS rule_id,
    ewr.provider_id,
    wp.name AS provider_name,
    wp.provider_type,
    ewr.covered_days,
    ewr.requires_approval,
    ewr.daily_rate,
    ewr.is_active,
    ewr.notes,
    ewr.created_at,
    ewr.updated_at
   FROM (extended_warranty_rules ewr
     LEFT JOIN warranty_providers wp ON ((wp.id = ewr.provider_id)));"
public,v_extension_commit_candidates," SELECT b.parent_billing_line_id,
    b.transportation_event_id,
    b.reservation_id,
    b.vehicle_id,
    b.vehicle_event_id,
    b.contract_period_id,
    b.pay_type,
    b.pay_type_rule_id,
    b.amount,
    b.tax_amount,
    b.start_time,
    b.end_time,
    b.line_type,
    b.warranty_provider_id,
    b.default_covered_days_snapshot,
    b.covered_days_override,
    b.default_daily_rate_snapshot,
    b.daily_rate_override,
    b.paid_through_at,
    b.extended_from_billing_line_id,
    b.is_open,
    te.expected_return_at AS current_expected_return_at
   FROM (v_current_extendable_billing_lines b
     JOIN transportation_events te ON ((te.id = b.transportation_event_id)));"
public,v_late_fee_rule_catalog," SELECT id AS late_fee_rule_id,
    is_active,
    sort_order,
    rule_kind,
    threshold_unit,
    threshold_value,
    fee_amount,
    description,
    created_at,
    updated_at,
    created_by,
    updated_by
   FROM late_fee_rules lfr;"
public,v_live_active_case_state," SELECT r.reservation_id,
    r.transportation_event_id,
    r.vehicle_id,
    r.start_date,
    r.expected_return_datetime,
    r.reservation_status,
    r.reservation_type,
    r.requested_model,
    r.pay_type,
    r.customer_id,
    c.name AS customer_name,
    c.tekion_customer_number,
    v.vin,
    v.stock_number,
    v.model AS vehicle_model,
    v.status AS vehicle_status,
    r.transportation_event_status,
    r.expected_return_at,
    r.closed_at,
    r.closed_by
   FROM ((v_reservation_operational_state r
     LEFT JOIN customers c ON ((c.id = r.customer_id)))
     LEFT JOIN vehicles v ON ((v.id = r.vehicle_id)))
  WHERE ((r.reservation_status IS DISTINCT FROM 'cancelled'::text) AND (r.transportation_event_status = 'active'::text));"
public,v_operational_domain_counts," SELECT ( SELECT count(*) AS count
           FROM customers) AS customer_count,
    ( SELECT count(*) AS count
           FROM vehicles) AS vehicle_count,
    ( SELECT count(*) AS count
           FROM reservations) AS reservation_count,
    ( SELECT count(*) AS count
           FROM transportation_events) AS transportation_event_count,
    ( SELECT count(*) AS count
           FROM vehicle_events
          WHERE (vehicle_events.is_open = true)) AS open_vehicle_event_count,
    ( SELECT count(*) AS count
           FROM contract_periods
          WHERE (contract_periods.is_open = true)) AS open_contract_period_count,
    ( SELECT count(*) AS count
           FROM billing_lines
          WHERE ((billing_lines.is_open = true) AND (billing_lines.line_type IS DISTINCT FROM 'tax'::text))) AS open_billing_line_count,
    ( SELECT count(*) AS count
           FROM reservation_vehicle_dependencies
          WHERE (reservation_vehicle_dependencies.status = ANY (ARRAY['pending_return'::text, 'ready'::text, 'conflict'::text]))) AS unresolved_dependency_count,
    ( SELECT count(*) AS count
           FROM reservation_conflicts
          WHERE (reservation_conflicts.is_resolved = false)) AS unresolved_conflict_count,
    ( SELECT count(*) AS count
           FROM transportation_event_notes) AS transportation_event_note_count;"
public,v_reservation_assignment_state," WITH vin_lock_setting AS (
         SELECT COALESCE(((admin_settings.setting_value #>> '{}'::text[]))::integer, 0) AS vin_lock_lead_days
           FROM admin_settings
          WHERE (admin_settings.setting_key = 'reservation_vin_lock_lead_days'::text)
        )
 SELECT r.id AS reservation_id,
    r.transportation_event_id,
    r.vehicle_id,
    r.start_date,
    r.expected_return_datetime,
    r.requested_model,
    r.reservation_type,
    r.status AS reservation_status,
    r.notes AS reservation_notes,
    s.vin_lock_lead_days,
    (r.start_date - make_interval(days => s.vin_lock_lead_days)) AS lock_window_starts_at,
    (now() >= (r.start_date - make_interval(days => s.vin_lock_lead_days))) AS is_in_lock_window,
    (r.vehicle_id IS NOT NULL) AS vehicle_is_assigned
   FROM (reservations r
     CROSS JOIN vin_lock_setting s);"
public,v_reservation_current_billing_state," SELECT r.reservation_id,
    r.transportation_event_id,
    r.vehicle_id AS reservation_vehicle_id,
    r.start_date,
    r.expected_return_datetime,
    r.reservation_status,
    r.reservation_type,
    r.requested_model,
    r.pay_type AS reservation_pay_type,
    r.customer_id,
    b.parent_billing_line_id,
    b.vehicle_id AS billing_vehicle_id,
    b.vehicle_event_id,
    b.contract_period_id,
    b.pay_type,
    b.pay_type_rule_id,
    b.parent_amount,
    b.parent_tax_amount,
    b.start_time,
    b.end_time,
    b.parent_line_type,
    b.warranty_provider_id,
    b.default_covered_days_snapshot,
    b.covered_days_override,
    b.default_daily_rate_snapshot,
    b.daily_rate_override,
    b.paid_through_at,
    b.extended_from_billing_line_id,
    b.parent_is_open,
    b.tax_billing_line_id,
    b.tax_line_amount,
    b.tax_line_is_open
   FROM (v_reservation_transportation_link_state r
     LEFT JOIN v_current_open_billing_lines b ON ((b.reservation_id = r.reservation_id)));"
public,v_reservation_extension_candidate_state," SELECT r.reservation_id,
    r.transportation_event_id,
    r.vehicle_id AS reservation_vehicle_id,
    r.start_date,
    r.expected_return_datetime,
    r.reservation_status,
    r.reservation_type,
    r.requested_model,
    r.pay_type AS reservation_pay_type,
    r.customer_id,
    e.parent_billing_line_id,
    e.vehicle_id AS billing_vehicle_id,
    e.vehicle_event_id,
    e.contract_period_id,
    e.pay_type,
    e.pay_type_rule_id,
    e.amount,
    e.tax_amount,
    e.start_time,
    e.end_time,
    e.line_type,
    e.warranty_provider_id,
    e.default_covered_days_snapshot,
    e.covered_days_override,
    e.default_daily_rate_snapshot,
    e.daily_rate_override,
    e.paid_through_at,
    e.extended_from_billing_line_id,
    e.is_open,
    e.current_expected_return_at
   FROM (v_reservation_transportation_link_state r
     LEFT JOIN v_extension_commit_candidates e ON ((e.reservation_id = r.reservation_id)));"
public,v_reservation_operational_state," SELECT r.reservation_id,
    r.transportation_event_id,
    r.vehicle_id,
    r.start_date,
    r.expected_return_datetime,
    r.reservation_status,
    r.reservation_type,
    r.reservation_notes,
    r.cancellation_reason,
    r.start_mileage,
    r.end_mileage,
    r.condition_flag,
    r.requested_model,
    r.service_advisor,
    r.ro_number,
    r.pay_type,
    r.actual_return_datetime,
    r.billed_through_datetime,
    r.customer_id,
    r.source_type,
    r.source_id,
    r.transportation_event_status,
    r.transportation_event_notes,
    r.expected_return_at,
    r.closed_at,
    r.closed_by,
    a.vin_lock_lead_days,
    a.lock_window_starts_at,
    a.is_in_lock_window,
    a.vehicle_is_assigned,
    dep.dependency_id AS current_dependency_id,
    dep.dependency_type AS current_dependency_type,
    dep.status AS current_dependency_status,
    dep.risk_level AS current_dependency_risk_level,
    dep.expected_return_snapshot AS current_dependency_expected_return_snapshot,
    dep.conflict_id AS current_conflict_id,
    dep.conflict_severity AS current_conflict_severity,
    dep.conflict_message AS current_conflict_message
   FROM ((v_reservation_transportation_link_state r
     LEFT JOIN v_reservation_assignment_state a ON ((a.reservation_id = r.reservation_id)))
     LEFT JOIN LATERAL ( SELECT d.id AS dependency_id,
            d.dependency_type,
            d.status,
            d.risk_level,
            d.expected_return_snapshot,
            c.id AS conflict_id,
            c.severity AS conflict_severity,
            c.message AS conflict_message
           FROM (reservation_vehicle_dependencies d
             LEFT JOIN reservation_conflicts c ON (((c.reservation_vehicle_dependency_id = d.id) AND (c.is_resolved = false))))
          WHERE ((d.reservation_id = r.reservation_id) AND (d.status = ANY (ARRAY['pending_return'::text, 'ready'::text, 'conflict'::text])))
          ORDER BY d.updated_at DESC NULLS LAST, d.created_at DESC NULLS LAST
         LIMIT 1) dep ON (true));"
public,v_reservation_transportation_link_state," SELECT r.id AS reservation_id,
    r.transportation_event_id,
    r.vehicle_id,
    r.start_date,
    r.expected_return_datetime,
    r.status AS reservation_status,
    r.reservation_type,
    r.notes AS reservation_notes,
    r.cancellation_reason,
    r.start_mileage,
    r.end_mileage,
    r.condition_flag,
    r.requested_model,
    r.service_advisor,
    r.ro_number,
    r.pay_type,
    r.actual_return_datetime,
    r.billed_through_datetime,
    r.customer_id,
    te.source_type,
    te.source_id,
    te.status AS transportation_event_status,
    te.notes AS transportation_event_notes,
    te.expected_return_at,
    te.closed_at,
    te.closed_by
   FROM (reservations r
     JOIN transportation_events te ON ((te.id = r.transportation_event_id)));"
public,v_reservation_vehicle_candidates," SELECT r.id AS reservation_id,
    r.transportation_event_id AS reservation_transportation_event_id,
    r.start_date AS reservation_start_at,
    r.expected_return_datetime AS reservation_end_at,
    r.requested_model,
    r.reservation_type,
    r.status AS reservation_status,
    r.notes AS reservation_notes,
    v.id AS vehicle_id,
    v.vin,
    v.stock_number,
    v.model AS vehicle_model,
    v.fleet_type,
    v.status AS vehicle_status,
    v.recon_status,
    v.location,
    c.transportation_event_id AS source_transportation_event_id,
    te.expected_return_at AS expected_return_snapshot,
        CASE
            WHEN (c.vehicle_event_id IS NOT NULL) THEN 'pending_return'::text
            WHEN (v.status = 'available'::text) THEN 'ready'::text
            ELSE 'unavailable'::text
        END AS candidate_state
   FROM (((reservations r
     JOIN vehicles v ON ((v.model = r.requested_model)))
     LEFT JOIN v_current_vehicle_continuity c ON ((c.vehicle_id = v.id)))
     LEFT JOIN transportation_events te ON ((te.id = c.transportation_event_id)))
  WHERE (r.status IS DISTINCT FROM 'cancelled'::text);"
public,v_reservations_needing_vin_assignment," SELECT reservation_id,
    transportation_event_id,
    start_date,
    expected_return_datetime,
    requested_model,
    reservation_type,
    reservation_status,
    reservation_notes,
    vehicle_id,
    vin_lock_lead_days,
    lock_window_starts_at,
    is_in_lock_window,
    vehicle_is_assigned
   FROM v_reservation_assignment_state ras
  WHERE ((is_in_lock_window = true) AND (vehicle_is_assigned = false) AND (reservation_status IS DISTINCT FROM 'cancelled'::text));"
public,v_roles_with_permissions," SELECT r.id AS role_id,
    r.role_name,
    COALESCE(string_agg(DISTINCT p.permission_key, ', '::text ORDER BY p.permission_key) FILTER (WHERE (p.permission_key IS NOT NULL)), ''::text) AS permission_summary,
    count(DISTINCT p.id) AS permission_count
   FROM ((roles r
     LEFT JOIN role_permissions rp ON ((rp.role_id = r.id)))
     LEFT JOIN permissions p ON ((p.id = rp.permission_id)))
  GROUP BY r.id, r.role_name;"
public,v_security_admin_settings_state," WITH settings AS (
         SELECT admin_settings.setting_key,
            admin_settings.setting_value
           FROM admin_settings
        )
 SELECT COALESCE(( SELECT ((settings.setting_value #>> '{}'::text[]))::boolean AS bool
           FROM settings
          WHERE (settings.setting_key = 'network_restriction_enabled'::text)), false) AS network_restriction_enabled,
    COALESCE(( SELECT ((settings.setting_value #>> '{}'::text[]))::boolean AS bool
           FROM settings
          WHERE (settings.setting_key = 'email_password_reset_link_enabled'::text)), false) AS email_password_reset_link_enabled,
    COALESCE(( SELECT ((settings.setting_value #>> '{}'::text[]))::boolean AS bool
           FROM settings
          WHERE (settings.setting_key = 'late_fees_enabled'::text)), false) AS late_fees_enabled,
    COALESCE(( SELECT ((settings.setting_value #>> '{}'::text[]))::integer AS int4
           FROM settings
          WHERE (settings.setting_key = 'reservation_vin_lock_lead_days'::text)), 0) AS reservation_vin_lock_lead_days;"
public,v_service_action_contract_state," SELECT id AS service_action_contract_id,
    action_key,
    action_group,
    entity_scope,
    db_function_name,
    action_type,
    description,
    requires_authenticated_user,
    requires_aal2,
    writes_data,
    frontend_safe,
    internal_only,
    required_permission,
    created_at,
    updated_at
   FROM service_action_contracts;"
public,v_transportation_event_current_billing_state," SELECT te.transportation_event_id,
    te.source_type,
    te.source_id,
    te.status AS transportation_event_status,
    te.notes AS transportation_event_notes,
    te.customer_id,
    te.updated_at,
    te.closed_at,
    te.closed_by,
    te.expected_return_at,
    b.parent_billing_line_id,
    b.reservation_id,
    b.vehicle_id AS billing_vehicle_id,
    b.vehicle_event_id,
    b.contract_period_id,
    b.pay_type,
    b.pay_type_rule_id,
    b.parent_amount,
    b.parent_tax_amount,
    b.start_time,
    b.end_time,
    b.parent_line_type,
    b.warranty_provider_id,
    b.default_covered_days_snapshot,
    b.covered_days_override,
    b.default_daily_rate_snapshot,
    b.daily_rate_override,
    b.paid_through_at,
    b.extended_from_billing_line_id,
    b.parent_is_open,
    b.tax_billing_line_id,
    b.tax_line_amount,
    b.tax_line_is_open
   FROM (v_transportation_event_state te
     LEFT JOIN v_current_open_billing_lines b ON ((b.transportation_event_id = te.transportation_event_id)));"
public,v_transportation_event_current_dependency_state," SELECT te.transportation_event_id,
    te.source_type,
    te.source_id,
    te.status AS transportation_event_status,
    te.customer_id,
    te.expected_return_at,
    te.closed_at,
    te.closed_by,
    dep.dependency_id,
    dep.reservation_id,
    dep.vehicle_id,
    dep.source_transportation_event_id,
    dep.dependency_type,
    dep.status AS dependency_status,
    dep.risk_level,
    dep.expected_return_snapshot,
    dep.notes AS dependency_notes,
    dep.created_at AS dependency_created_at,
    dep.updated_at AS dependency_updated_at,
    c.conflict_id,
    c.conflict_type,
    c.conflict_severity,
    c.conflict_message,
    c.is_resolved AS conflict_is_resolved
   FROM ((v_transportation_event_state te
     LEFT JOIN LATERAL ( SELECT d.id AS dependency_id,
            d.reservation_id,
            d.vehicle_id,
            d.source_transportation_event_id,
            d.dependency_type,
            d.status,
            d.risk_level,
            d.expected_return_snapshot,
            d.notes,
            d.created_at,
            d.updated_at
           FROM reservation_vehicle_dependencies d
          WHERE ((te.source_type = 'reservation'::text) AND (te.source_id IS NOT NULL) AND (d.reservation_id = te.source_id) AND (d.status = ANY (ARRAY['pending_return'::text, 'ready'::text, 'conflict'::text])))
          ORDER BY d.updated_at DESC NULLS LAST, d.created_at DESC NULLS LAST, d.id DESC
         LIMIT 1) dep ON (true))
     LEFT JOIN LATERAL ( SELECT rc.id AS conflict_id,
            rc.conflict_type,
            rc.severity AS conflict_severity,
            rc.message AS conflict_message,
            rc.is_resolved
           FROM reservation_conflicts rc
          WHERE ((rc.reservation_vehicle_dependency_id = dep.dependency_id) AND (rc.is_resolved = false))
          ORDER BY rc.id DESC
         LIMIT 1) c ON (true));"
public,v_transportation_event_extension_candidate_state," SELECT te.transportation_event_id,
    te.source_type,
    te.source_id,
    te.status AS transportation_event_status,
    te.notes AS transportation_event_notes,
    te.customer_id,
    te.updated_at,
    te.closed_at,
    te.closed_by,
    te.expected_return_at,
    e.parent_billing_line_id,
    e.reservation_id,
    e.vehicle_id AS billing_vehicle_id,
    e.vehicle_event_id,
    e.contract_period_id,
    e.pay_type,
    e.pay_type_rule_id,
    e.amount,
    e.tax_amount,
    e.start_time,
    e.end_time,
    e.line_type,
    e.warranty_provider_id,
    e.default_covered_days_snapshot,
    e.covered_days_override,
    e.default_daily_rate_snapshot,
    e.daily_rate_override,
    e.paid_through_at,
    e.extended_from_billing_line_id,
    e.is_open,
    e.current_expected_return_at
   FROM (v_transportation_event_state te
     LEFT JOIN v_extension_commit_candidates e ON ((e.transportation_event_id = te.transportation_event_id)));"
public,v_transportation_event_note_history," SELECT n.id AS note_id,
    n.transportation_event_id,
    n.note_type,
    n.note_text,
    n.entered_at,
    n.entered_by_user_id,
    u.full_name AS entered_by_name
   FROM (transportation_event_notes n
     LEFT JOIN app_users u ON ((u.id = n.entered_by_user_id)));"
public,v_transportation_event_operational_state," SELECT te.id AS transportation_event_id,
    te.source_type,
    te.source_id,
    te.status AS transportation_event_status,
    te.customer_id,
    te.expected_return_at,
    te.closed_at,
    c.vehicle_event_id,
    c.vehicle_id,
    c.contract_period_id,
    c.actual_out_at,
    c.actual_in_at,
    c.vehicle_event_is_open,
    c.ended_reason,
    c.contract_out_at,
    c.contract_in_at,
    c.renewal_sequence,
    c.contract_period_is_open
   FROM (transportation_events te
     LEFT JOIN v_current_vehicle_continuity c ON ((c.transportation_event_id = te.id)));"
public,v_transportation_event_state," SELECT id AS transportation_event_id,
    source_type,
    source_id,
    status,
    notes,
    customer_id,
    updated_at,
    closed_at,
    closed_by,
    expected_return_at
   FROM transportation_events te;"
public,v_transportation_event_unified_operational_state," SELECT te.transportation_event_id,
    te.source_type,
    te.source_id,
    te.status AS transportation_event_status,
    te.notes AS transportation_event_notes,
    te.customer_id,
    te.updated_at,
    te.closed_at,
    te.closed_by,
    te.expected_return_at,
    op.vehicle_event_id,
    op.vehicle_id,
    op.contract_period_id,
    op.actual_out_at,
    op.actual_in_at,
    op.vehicle_event_is_open,
    op.ended_reason,
    op.contract_out_at,
    op.contract_in_at,
    op.renewal_sequence,
    op.contract_period_is_open,
    bill.parent_billing_line_id AS current_parent_billing_line_id,
    bill.reservation_id AS current_billing_reservation_id,
    bill.billing_vehicle_id AS current_billing_vehicle_id,
    bill.pay_type AS current_billing_pay_type,
    bill.parent_amount AS current_billing_parent_amount,
    bill.parent_tax_amount AS current_billing_parent_tax_amount,
    bill.start_time AS current_billing_start_time,
    bill.end_time AS current_billing_end_time,
    bill.parent_line_type AS current_billing_line_type,
    bill.paid_through_at AS current_billing_paid_through_at,
    bill.parent_is_open AS current_billing_is_open,
    dep.dependency_id AS current_dependency_id,
    dep.reservation_id AS current_dependency_reservation_id,
    dep.vehicle_id AS current_dependency_vehicle_id,
    dep.source_transportation_event_id AS current_dependency_source_transportation_event_id,
    dep.dependency_type AS current_dependency_type,
    dep.dependency_status AS current_dependency_status,
    dep.risk_level AS current_dependency_risk_level,
    dep.expected_return_snapshot AS current_dependency_expected_return_snapshot,
    dep.conflict_id AS current_conflict_id,
    dep.conflict_type AS current_conflict_type,
    dep.conflict_severity AS current_conflict_severity,
    dep.conflict_message AS current_conflict_message,
    dep.conflict_is_resolved AS current_conflict_is_resolved,
    ext.parent_billing_line_id AS extension_candidate_parent_billing_line_id,
    ext.reservation_id AS extension_candidate_reservation_id,
    ext.billing_vehicle_id AS extension_candidate_billing_vehicle_id,
    ext.pay_type AS extension_candidate_pay_type,
    ext.amount AS extension_candidate_amount,
    ext.tax_amount AS extension_candidate_tax_amount,
    ext.start_time AS extension_candidate_start_time,
    ext.paid_through_at AS extension_candidate_paid_through_at,
    ext.is_open AS extension_candidate_is_open,
    ext.current_expected_return_at AS extension_candidate_current_expected_return_at
   FROM ((((v_transportation_event_state te
     LEFT JOIN v_transportation_event_operational_state op ON ((op.transportation_event_id = te.transportation_event_id)))
     LEFT JOIN LATERAL ( SELECT b.transportation_event_id,
            b.source_type,
            b.source_id,
            b.transportation_event_status,
            b.transportation_event_notes,
            b.customer_id,
            b.updated_at,
            b.closed_at,
            b.closed_by,
            b.expected_return_at,
            b.parent_billing_line_id,
            b.reservation_id,
            b.billing_vehicle_id,
            b.vehicle_event_id,
            b.contract_period_id,
            b.pay_type,
            b.pay_type_rule_id,
            b.parent_amount,
            b.parent_tax_amount,
            b.start_time,
            b.end_time,
            b.parent_line_type,
            b.warranty_provider_id,
            b.default_covered_days_snapshot,
            b.covered_days_override,
            b.default_daily_rate_snapshot,
            b.daily_rate_override,
            b.paid_through_at,
            b.extended_from_billing_line_id,
            b.parent_is_open,
            b.tax_billing_line_id,
            b.tax_line_amount,
            b.tax_line_is_open
           FROM v_transportation_event_current_billing_state b
          WHERE ((b.transportation_event_id = te.transportation_event_id) AND (b.parent_billing_line_id IS NOT NULL))
          ORDER BY b.start_time DESC NULLS LAST, b.parent_billing_line_id DESC
         LIMIT 1) bill ON (true))
     LEFT JOIN v_transportation_event_current_dependency_state dep ON ((dep.transportation_event_id = te.transportation_event_id)))
     LEFT JOIN LATERAL ( SELECT e.transportation_event_id,
            e.source_type,
            e.source_id,
            e.transportation_event_status,
            e.transportation_event_notes,
            e.customer_id,
            e.updated_at,
            e.closed_at,
            e.closed_by,
            e.expected_return_at,
            e.parent_billing_line_id,
            e.reservation_id,
            e.billing_vehicle_id,
            e.vehicle_event_id,
            e.contract_period_id,
            e.pay_type,
            e.pay_type_rule_id,
            e.amount,
            e.tax_amount,
            e.start_time,
            e.end_time,
            e.line_type,
            e.warranty_provider_id,
            e.default_covered_days_snapshot,
            e.covered_days_override,
            e.default_daily_rate_snapshot,
            e.daily_rate_override,
            e.paid_through_at,
            e.extended_from_billing_line_id,
            e.is_open,
            e.current_expected_return_at
           FROM v_transportation_event_extension_candidate_state e
          WHERE ((e.transportation_event_id = te.transportation_event_id) AND (e.parent_billing_line_id IS NOT NULL))
          ORDER BY e.start_time DESC NULLS LAST, e.parent_billing_line_id DESC
         LIMIT 1) ext ON (true));"
public,v_unresolved_reservation_conflicts," SELECT id AS conflict_id,
    reservation_id,
    reservation_vehicle_dependency_id,
    conflict_type,
    severity,
    message,
    is_resolved
   FROM reservation_conflicts c
  WHERE (is_resolved = false);"
public,v_unresolved_reservation_dependencies," SELECT id AS dependency_id,
    reservation_id,
    vehicle_id,
    source_transportation_event_id,
    dependency_type,
    status,
    risk_level,
    expected_return_snapshot,
    notes,
    created_at,
    updated_at,
    created_by_user_id,
    updated_by_user_id
   FROM reservation_vehicle_dependencies d
  WHERE (status = ANY (ARRAY['pending_return'::text, 'ready'::text, 'conflict'::text]));"
public,v_upcoming_rental_dependency_feed," SELECT d.id AS dependency_id,
    d.reservation_id,
    r.start_date AS reservation_start_at,
    r.expected_return_datetime AS reservation_end_at,
    r.requested_model,
    r.reservation_type,
    r.status AS reservation_status,
    r.notes AS reservation_notes,
    to_jsonb(r.*) AS reservation_payload,
    d.vehicle_id,
    d.source_transportation_event_id,
    d.dependency_type,
    d.status AS dependency_status,
    d.risk_level,
    d.expected_return_snapshot,
    c.id AS conflict_id,
    c.conflict_type,
    c.severity AS conflict_severity,
    c.message AS conflict_message,
    c.is_resolved
   FROM ((reservation_vehicle_dependencies d
     JOIN reservations r ON ((r.id = d.reservation_id)))
     LEFT JOIN reservation_conflicts c ON (((c.reservation_vehicle_dependency_id = d.id) AND (c.is_resolved = false))))
  WHERE (d.status = ANY (ARRAY['pending_return'::text, 'ready'::text, 'conflict'::text]));"
public,v_user_account_admin_status," SELECT u.id AS user_id,
    u.email,
    u.is_active,
    s.failed_login_count,
    s.last_failed_login_at,
    s.locked_until,
    s.lockout_count,
    s.post_lockout_final_attempt_allowed,
    s.is_disabled,
    s.disabled_at,
    s.disabled_reason,
    s.password_reset_pending,
    s.temporary_password_issued_at,
    s.temporary_password_expires_at,
    s.temporary_password_issued_by,
    s.outside_network_access_allowed,
    s.last_successful_login_at,
        CASE
            WHEN s.is_disabled THEN 'disabled'::text
            WHEN ((s.locked_until IS NOT NULL) AND (s.locked_until > now())) THEN 'locked'::text
            WHEN s.password_reset_pending THEN 'password_reset_pending'::text
            WHEN u.is_active THEN 'active'::text
            ELSE 'inactive'::text
        END AS security_status
   FROM (app_users u
     JOIN app_user_security s ON ((s.user_id = u.id)));"
public,v_user_admin_list_summary," SELECT u.id AS user_id,
    u.email,
    u.is_active,
    s.failed_login_count,
    s.last_failed_login_at,
    s.locked_until,
    s.lockout_count,
    s.post_lockout_final_attempt_allowed,
    s.is_disabled,
    s.disabled_at,
    s.disabled_reason,
    s.password_reset_pending,
    s.temporary_password_issued_at,
    s.temporary_password_expires_at,
    s.outside_network_access_allowed,
    s.last_successful_login_at,
        CASE
            WHEN s.is_disabled THEN 'disabled'::text
            WHEN ((s.locked_until IS NOT NULL) AND (s.locked_until > now())) THEN 'locked'::text
            WHEN s.password_reset_pending THEN 'password_reset_pending'::text
            WHEN u.is_active THEN 'active'::text
            ELSE 'inactive'::text
        END AS security_status,
    COALESCE(string_agg(DISTINCT r.role_name, ', '::text ORDER BY r.role_name) FILTER (WHERE (r.role_name IS NOT NULL)), ''::text) AS role_summary
   FROM (((app_users u
     JOIN app_user_security s ON ((s.user_id = u.id)))
     LEFT JOIN user_roles ur ON ((ur.user_id = u.id)))
     LEFT JOIN roles r ON ((r.id = ur.role_id)))
  GROUP BY u.id, u.email, u.is_active, s.failed_login_count, s.last_failed_login_at, s.locked_until, s.lockout_count, s.post_lockout_final_attempt_allowed, s.is_disabled, s.disabled_at, s.disabled_reason, s.password_reset_pending, s.temporary_password_issued_at, s.temporary_password_expires_at, s.outside_network_access_allowed, s.last_successful_login_at;"
public,v_user_auth_entry_orchestration_state," WITH latest_auth_event AS (
         SELECT e.user_id,
            e.auth_security_event_id,
            e.event_type,
            e.factor_type,
            e.event_status,
            e.details,
            e.recorded_by_user_id,
            e.recorded_by_email,
            e.recorded_by_full_name,
            e.recorded_at,
            row_number() OVER (PARTITION BY e.user_id ORDER BY e.recorded_at DESC, e.auth_security_event_id DESC) AS rn
           FROM v_user_auth_security_event_history e
        ), mfa_enrollment_flags AS (
         SELECT e.user_id,
            bool_or((e.event_type = ANY (ARRAY['mfa_enrolled'::text, 'backup_factor_registered'::text]))) AS has_mfa_enrolled_event,
            max(e.recorded_at) FILTER (WHERE (e.event_type = ANY (ARRAY['mfa_enrolled'::text, 'backup_factor_registered'::text]))) AS last_mfa_enrolled_at
           FROM v_user_auth_security_event_history e
          GROUP BY e.user_id
        )
 SELECT u.id AS user_id,
    u.auth_user_id,
    u.email,
    u.full_name,
    u.phone,
    u.is_active,
    u.last_login,
    u.notes,
    s.failed_login_count,
    s.last_failed_login_at,
    s.locked_until,
    s.lockout_count,
    s.post_lockout_final_attempt_allowed,
    s.is_disabled,
    s.disabled_at,
    s.disabled_reason,
    s.password_reset_pending,
    s.temporary_password_issued_at,
    s.temporary_password_expires_at,
    s.outside_network_access_allowed,
    s.last_successful_login_at,
    policy.mfa_required_for_all_users,
    policy.network_restriction_enabled,
    policy.email_password_reset_link_enabled,
    COALESCE(m.has_mfa_enrolled_event, false) AS has_mfa_enrolled_event,
    m.last_mfa_enrolled_at,
    lae.auth_security_event_id AS latest_auth_security_event_id,
    lae.event_type AS latest_auth_event_type,
    lae.factor_type AS latest_auth_factor_type,
    lae.event_status AS latest_auth_event_status,
    lae.details AS latest_auth_event_details,
    lae.recorded_by_user_id AS latest_auth_recorded_by_user_id,
    lae.recorded_by_email AS latest_auth_recorded_by_email,
    lae.recorded_by_full_name AS latest_auth_recorded_by_full_name,
    lae.recorded_at AS latest_auth_recorded_at,
        CASE
            WHEN (u.is_active = false) THEN 'inactive_user'::text
            WHEN (s.is_disabled = true) THEN 'disabled_user'::text
            WHEN ((s.locked_until IS NOT NULL) AND (s.locked_until > now())) THEN 'locked_user'::text
            WHEN (s.password_reset_pending = true) THEN 'password_reset_required'::text
            WHEN ((policy.mfa_required_for_all_users = true) AND (COALESCE(m.has_mfa_enrolled_event, false) = false)) THEN 'mfa_enrollment_required'::text
            ELSE 'auth_entry_ready_for_session_check'::text
        END AS base_auth_gate_status
   FROM ((((app_users u
     JOIN app_user_security s ON ((s.user_id = u.id)))
     CROSS JOIN v_auth_security_policy_state policy)
     LEFT JOIN mfa_enrollment_flags m ON ((m.user_id = u.id)))
     LEFT JOIN latest_auth_event lae ON (((lae.user_id = u.id) AND (lae.rn = 1))));"
public,v_user_auth_entry_state," SELECT u.id AS user_id,
    u.auth_user_id,
    u.email,
    u.full_name,
    u.phone,
    u.is_active,
    s.failed_login_count,
    s.last_failed_login_at,
    s.locked_until,
    s.lockout_count,
    s.post_lockout_final_attempt_allowed,
    s.is_disabled,
    s.disabled_at,
    s.disabled_reason,
    s.password_reset_pending,
    s.temporary_password_issued_at,
    s.temporary_password_expires_at,
    s.temporary_password_issued_by,
    s.outside_network_access_allowed,
    s.last_successful_login_at,
        CASE
            WHEN s.is_disabled THEN 'disabled'::text
            WHEN ((s.locked_until IS NOT NULL) AND (now() < s.locked_until)) THEN 'locked'::text
            WHEN s.password_reset_pending THEN 'password_reset_pending'::text
            WHEN (u.is_active = false) THEN 'inactive'::text
            ELSE 'active'::text
        END AS auth_status,
    ((s.temporary_password_expires_at IS NOT NULL) AND (now() > s.temporary_password_expires_at)) AS temporary_password_is_expired
   FROM (app_users u
     JOIN app_user_security s ON ((s.user_id = u.id)));"
public,v_user_auth_security_event_history," SELECT e.id AS auth_security_event_id,
    e.user_id,
    u.email,
    u.full_name,
    e.event_type,
    e.factor_type,
    e.event_status,
    e.details,
    e.recorded_by_user_id,
    rb.email AS recorded_by_email,
    rb.full_name AS recorded_by_full_name,
    e.recorded_at
   FROM ((user_auth_security_events e
     JOIN app_users u ON ((u.id = e.user_id)))
     LEFT JOIN app_users rb ON ((rb.id = e.recorded_by_user_id)));"
public,v_user_effective_permissions," SELECT DISTINCT u.id AS user_id,
    p.permission_key
   FROM (((app_users u
     JOIN user_roles ur ON ((ur.user_id = u.id)))
     JOIN role_permissions rp ON ((rp.role_id = ur.role_id)))
     JOIN permissions p ON ((p.id = rp.permission_id)));"
public,v_user_reset_artifact_state," WITH ranked_tokens AS (
         SELECT t.reset_token_id,
            t.user_id,
            t.token_hash,
            t.reset_mode,
            t.issued_at,
            t.expires_at,
            t.issued_by_user_id,
            t.notes,
            row_number() OVER (PARTITION BY t.user_id ORDER BY t.expires_at DESC NULLS LAST, t.issued_at DESC NULLS LAST, t.reset_token_id DESC) AS rn,
            count(*) OVER (PARTITION BY t.user_id) AS active_usable_token_count
           FROM v_active_usable_reset_tokens t
        )
 SELECT u.id AS user_id,
    u.auth_user_id,
    u.email,
    u.full_name,
    u.phone,
    u.is_active,
    s.password_reset_pending,
    s.temporary_password_issued_at,
    s.temporary_password_expires_at,
    s.temporary_password_issued_by,
    s.is_disabled,
    s.locked_until,
    s.post_lockout_final_attempt_allowed,
    rt.reset_token_id,
    rt.token_hash,
    rt.reset_mode,
    rt.issued_at AS token_issued_at,
    rt.expires_at AS token_expires_at,
    rt.issued_by_user_id AS token_issued_by_user_id,
    rt.notes AS token_notes,
    COALESCE(rt.active_usable_token_count, (0)::bigint) AS active_usable_token_count
   FROM ((app_users u
     JOIN app_user_security s ON ((s.user_id = u.id)))
     LEFT JOIN ranked_tokens rt ON (((rt.user_id = u.id) AND (rt.rn = 1))));"
public,v_users_requiring_password_reset," SELECT u.id AS user_id,
    u.auth_user_id,
    u.email,
    u.full_name,
    u.phone,
    u.is_active,
    s.password_reset_pending,
    s.temporary_password_issued_at,
    s.temporary_password_expires_at,
    s.temporary_password_issued_by,
    s.is_disabled,
    s.locked_until,
    s.post_lockout_final_attempt_allowed,
    s.outside_network_access_allowed
   FROM (app_users u
     JOIN app_user_security s ON ((s.user_id = u.id)))
  WHERE (s.password_reset_pending = true);"
public,v_vehicle_ctp_monitoring_state," SELECT v.id AS vehicle_id,
    v.created_at,
    v.vin,
    v.stock_number,
    v.model,
    v.fleet_type,
    v.status AS vehicle_status,
    v.mileage AS current_mileage,
    v.recon_status,
    v.current_tag,
    v.fleet_conversion_type,
    v.location,
    v.notes,
    v.ctp_program_active,
    v.ctp_program_entered_at,
    v.ctp_entry_mileage,
    v.ctp_monitoring_notes,
    policy.preferred_max_ctp_days,
    policy.preferred_max_ctp_qualified_miles,
        CASE
            WHEN ((v.ctp_program_active = true) AND (v.ctp_program_entered_at IS NOT NULL)) THEN GREATEST(((CURRENT_DATE - (v.ctp_program_entered_at)::date) + 1), 1)
            ELSE NULL::integer
        END AS current_ctp_day_number,
        CASE
            WHEN ((v.ctp_program_active = true) AND (v.ctp_entry_mileage IS NOT NULL)) THEN GREATEST((v.mileage - v.ctp_entry_mileage), 0)
            ELSE NULL::integer
        END AS current_ctp_qualified_miles,
        CASE
            WHEN ((v.ctp_program_active = true) AND (v.ctp_program_entered_at IS NOT NULL) AND (GREATEST(((CURRENT_DATE - (v.ctp_program_entered_at)::date) + 1), 1) >= policy.preferred_max_ctp_days)) THEN true
            ELSE false
        END AS is_at_or_over_preferred_ctp_days,
        CASE
            WHEN ((v.ctp_program_active = true) AND (v.ctp_entry_mileage IS NOT NULL) AND (GREATEST((v.mileage - v.ctp_entry_mileage), 0) >= policy.preferred_max_ctp_qualified_miles)) THEN true
            ELSE false
        END AS is_at_or_over_preferred_ctp_qualified_miles,
        CASE
            WHEN (v.ctp_program_active = false) THEN 'not_in_ctp_program'::text
            WHEN (v.ctp_program_entered_at IS NULL) THEN 'missing_ctp_entry_date'::text
            WHEN (v.ctp_entry_mileage IS NULL) THEN 'missing_ctp_entry_mileage'::text
            WHEN ((v.ctp_program_active = true) AND (v.ctp_program_entered_at IS NOT NULL) AND (GREATEST(((CURRENT_DATE - (v.ctp_program_entered_at)::date) + 1), 1) >= policy.preferred_max_ctp_days) AND ((v.ctp_program_active = true) AND (v.ctp_entry_mileage IS NOT NULL) AND (GREATEST((v.mileage - v.ctp_entry_mileage), 0) >= policy.preferred_max_ctp_qualified_miles))) THEN 'at_or_over_both_preferred_thresholds'::text
            WHEN ((v.ctp_program_active = true) AND (v.ctp_program_entered_at IS NOT NULL) AND (GREATEST(((CURRENT_DATE - (v.ctp_program_entered_at)::date) + 1), 1) >= policy.preferred_max_ctp_days)) THEN 'at_or_over_preferred_days'::text
            WHEN ((v.ctp_program_active = true) AND (v.ctp_entry_mileage IS NOT NULL) AND (GREATEST((v.mileage - v.ctp_entry_mileage), 0) >= policy.preferred_max_ctp_qualified_miles)) THEN 'at_or_over_preferred_miles'::text
            ELSE 'within_preferred_ctp_thresholds'::text
        END AS ctp_monitoring_status
   FROM (vehicles v
     CROSS JOIN v_ctp_monitoring_policy_state policy);"
public,v_vehicle_operational_aggregate_state," SELECT v.vehicle_id,
    v.created_at,
    v.vin,
    v.stock_number,
    v.model,
    v.fleet_type,
    v.status AS vehicle_status,
    v.mileage,
    v.recon_status,
    v.current_tag,
    v.fleet_conversion_type,
    v.location,
    v.notes,
    v.active_transportation_event_id,
    v.vehicle_event_id,
    v.contract_period_id,
    v.actual_out_at,
    v.contract_out_at,
    v.renewal_sequence,
    v.vehicle_event_is_open,
    v.contract_period_is_open,
    te.expected_return_at AS latest_expected_return_at,
    COALESCE(ar.assigned_reservation_count, (0)::bigint) AS assigned_reservation_count,
    COALESCE(cr.candidate_reservation_count, (0)::bigint) AS candidate_reservation_count,
    COALESCE(dep.unresolved_dependency_count, (0)::bigint) AS unresolved_dependency_count,
    COALESCE(dep.unresolved_conflict_count, (0)::bigint) AS unresolved_conflict_count
   FROM ((((v_vehicle_operational_state v
     LEFT JOIN transportation_events te ON ((te.id = v.active_transportation_event_id)))
     LEFT JOIN LATERAL ( SELECT count(*) AS assigned_reservation_count
           FROM reservations r
          WHERE ((r.vehicle_id = v.vehicle_id) AND (r.status IS DISTINCT FROM 'cancelled'::text))) ar ON (true))
     LEFT JOIN LATERAL ( SELECT count(*) AS candidate_reservation_count
           FROM reservations r
          WHERE ((r.requested_model = v.model) AND (r.status IS DISTINCT FROM 'cancelled'::text))) cr ON (true))
     LEFT JOIN LATERAL ( SELECT count(DISTINCT d.id) AS unresolved_dependency_count,
            count(DISTINCT c.id) AS unresolved_conflict_count
           FROM (reservation_vehicle_dependencies d
             LEFT JOIN reservation_conflicts c ON (((c.reservation_vehicle_dependency_id = d.id) AND (c.is_resolved = false))))
          WHERE ((d.vehicle_id = v.vehicle_id) AND (d.status = ANY (ARRAY['pending_return'::text, 'ready'::text, 'conflict'::text])))) dep ON (true));"
public,v_vehicle_operational_state," SELECT v.id AS vehicle_id,
    v.created_at,
    v.vin,
    v.stock_number,
    v.model,
    v.fleet_type,
    v.status,
    v.mileage,
    v.recon_status,
    v.current_tag,
    v.fleet_conversion_type,
    v.location,
    v.notes,
    c.transportation_event_id AS active_transportation_event_id,
    c.vehicle_event_id,
    c.contract_period_id,
    c.actual_out_at,
    c.contract_out_at,
    c.renewal_sequence,
    c.vehicle_event_is_open,
    c.contract_period_is_open
   FROM (vehicles v
     LEFT JOIN v_current_vehicle_continuity c ON ((c.vehicle_id = v.id)));"
public,v_vehicle_qr_action_entry_state," SELECT v.id AS vehicle_id,
    v.created_at,
    v.vin,
    v.stock_number,
    v.model,
    v.fleet_type,
    v.status AS vehicle_status,
    v.mileage,
    v.recon_status,
    v.current_tag,
    v.fleet_conversion_type,
    v.location,
    v.notes,
    q.id AS vehicle_qr_code_id,
    q.qr_token,
    q.landing_mode,
    q.is_active AS qr_is_active,
    q.issued_at AS qr_issued_at,
    q.retired_at AS qr_retired_at,
    q.issued_by_user_id AS qr_issued_by_user_id,
        CASE
            WHEN (v.status = 'available'::text) THEN true
            ELSE false
        END AS vehicle_is_available_now,
    jsonb_build_array('quote', 'reserve', 'rent', 'ctp_lot_inventory_mark_present', 'swap_customer_to_this_vehicle') AS available_scan_actions
   FROM (vehicles v
     LEFT JOIN LATERAL ( SELECT q_1.id,
            q_1.vehicle_id,
            q_1.qr_token,
            q_1.landing_mode,
            q_1.is_active,
            q_1.issued_at,
            q_1.retired_at,
            q_1.issued_by_user_id,
            q_1.notes
           FROM vehicle_qr_codes q_1
          WHERE ((q_1.vehicle_id = v.id) AND (q_1.is_active = true))
          ORDER BY q_1.issued_at DESC, q_1.id DESC
         LIMIT 1) q ON (true));"
public,v_vehicle_scan_event_history," SELECT e.id AS vehicle_scan_event_id,
    e.vehicle_id,
    v.vin,
    v.stock_number,
    v.model,
    e.vehicle_qr_code_id,
    q.qr_token,
    e.scan_session_id,
    s.session_type,
    e.scanned_by_user_id,
    u.email AS scanned_by_email,
    u.full_name AS scanned_by_full_name,
    e.action_type,
    e.result_status,
    e.scanned_at,
    e.related_reservation_id,
    e.related_transportation_event_id,
    e.metadata
   FROM ((((vehicle_scan_events e
     JOIN vehicles v ON ((v.id = e.vehicle_id)))
     LEFT JOIN vehicle_qr_codes q ON ((q.id = e.vehicle_qr_code_id)))
     LEFT JOIN vehicle_scan_sessions s ON ((s.id = e.scan_session_id)))
     JOIN app_users u ON ((u.id = e.scanned_by_user_id)));"
public,v_vehicle_scan_session_history," SELECT s.id AS vehicle_scan_session_id,
    s.session_type,
    s.started_by_user_id,
    u.email AS started_by_email,
    u.full_name AS started_by_full_name,
    s.started_at,
    s.ended_at,
    s.session_status,
    s.notes,
    count(e.id) AS scan_event_count
   FROM ((vehicle_scan_sessions s
     JOIN app_users u ON ((u.id = s.started_by_user_id)))
     LEFT JOIN vehicle_scan_events e ON ((e.scan_session_id = s.id)))
  GROUP BY s.id, s.session_type, s.started_by_user_id, u.email, u.full_name, s.started_at, s.ended_at, s.session_status, s.notes;"
public,v_warning_center_critical_items," SELECT 'dependency_conflict'::text AS item_type,
    d.id AS source_id,
    d.reservation_id,
    d.vehicle_id,
    d.risk_level,
    d.status AS source_status,
    d.expected_return_snapshot,
    NULL::uuid AS contract_period_id,
    NULL::text AS reminder_state,
    COALESCE(c.message, 'Critical dependency/conflict'::text) AS message
   FROM (reservation_vehicle_dependencies d
     LEFT JOIN reservation_conflicts c ON (((c.reservation_vehicle_dependency_id = d.id) AND (c.is_resolved = false))))
  WHERE ((d.status = 'conflict'::text) OR (d.risk_level = 'critical'::text))
UNION ALL
 SELECT 'reservation_conflict'::text AS item_type,
    NULL::uuid AS source_id,
    c.reservation_id,
    NULL::uuid AS vehicle_id,
    'critical'::text AS risk_level,
    'conflict'::text AS source_status,
    NULL::timestamp with time zone AS expected_return_snapshot,
    NULL::uuid AS contract_period_id,
    NULL::text AS reminder_state,
    COALESCE(c.message, 'Critical unresolved reservation conflict'::text) AS message
   FROM reservation_conflicts c
  WHERE ((c.is_resolved = false) AND (c.severity = 'critical'::text));"
public,v_warning_center_review_items," SELECT 'dependency_review'::text AS item_type,
    d.id AS source_id,
    d.reservation_id,
    d.vehicle_id,
    d.risk_level,
    d.status AS source_status,
    d.expected_return_snapshot,
    NULL::uuid AS contract_period_id,
    NULL::text AS reminder_state,
    'Dependency should be reviewed'::text AS message
   FROM reservation_vehicle_dependencies d
  WHERE ((d.status = ANY (ARRAY['pending_return'::text, 'ready'::text, 'conflict'::text])) AND (d.risk_level = 'depends_on_return'::text))
UNION ALL
 SELECT 'contract_review'::text AS item_type,
    NULL::uuid AS source_id,
    NULL::uuid AS reservation_id,
    NULL::uuid AS vehicle_id,
    NULL::text AS risk_level,
    NULL::text AS source_status,
    NULL::timestamp with time zone AS expected_return_snapshot,
    m.contract_period_id,
    m.reminder_state,
    'Contract/reminder should be reviewed'::text AS message
   FROM v_contract_period_monitoring m
  WHERE (m.reminder_state = 'renew_soon'::text);"
public,v_warning_center_warning_items," SELECT 'dependency_warning'::text AS item_type,
    d.id AS source_id,
    d.reservation_id,
    d.vehicle_id,
    d.risk_level,
    d.status AS source_status,
    d.expected_return_snapshot,
    NULL::uuid AS contract_period_id,
    NULL::text AS reminder_state,
    'Dependency requires near-term attention'::text AS message
   FROM reservation_vehicle_dependencies d
  WHERE ((d.status = ANY (ARRAY['pending_return'::text, 'ready'::text, 'conflict'::text])) AND (d.risk_level = ANY (ARRAY['at_risk'::text, 'must_return'::text])))
UNION ALL
 SELECT 'contract_reminder'::text AS item_type,
    NULL::uuid AS source_id,
    NULL::uuid AS reservation_id,
    NULL::uuid AS vehicle_id,
    NULL::text AS risk_level,
    NULL::text AS source_status,
    NULL::timestamp with time zone AS expected_return_snapshot,
    m.contract_period_id,
    m.reminder_state,
    'Contract/reminder action needed soon'::text AS message
   FROM v_contract_period_monitoring m
  WHERE (m.reminder_state = ANY (ARRAY['renew_now'::text, 'swap_required'::text]));"
public,v_warranty_provider_catalog," SELECT id AS provider_id,
    name,
    provider_type,
    is_active,
    default_daily_rate,
    notes,
    created_at,
    updated_at
   FROM warranty_providers wp;"
vault,decrypted_secrets," SELECT id,
    name,
    description,
    secret,
    convert_from(vault._crypto_aead_det_decrypt(message => decode(secret, 'base64'::text), additional => convert_to((id)::text, 'utf8'::name), key_id => (0)::bigint, context => '\x7067736f6469756d'::bytea, nonce => nonce), 'utf8'::name) AS decrypted_secret,
    key_id,
    nonce,
    created_at,
    updated_at
   FROM vault.secrets s;"
