


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."accept_case_extension_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric DEFAULT 0, "p_reason_code" "text" DEFAULT NULL::"text", "p_optional_note" "text" DEFAULT NULL::"text", "p_entered_by_user_id" "uuid" DEFAULT NULL::"uuid", "p_escalate_current_dependency" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_action_result jsonb;
    v_unified_payload jsonb;
begin
    v_action_result := public.accept_reservation_extension_state(
        p_reservation_id,
        p_new_expected_return_at,
        p_extension_amount,
        p_extension_tax_amount,
        p_reason_code,
        p_optional_note,
        p_entered_by_user_id,
        p_escalate_current_dependency
    );

    v_unified_payload := public.get_unified_case_payload_state(
        p_reservation_id
    );

    return jsonb_build_object(
        'status', 'case_extension_accepted_and_loaded',
        'reservation_id', p_reservation_id,
        'action_result', v_action_result,
        'unified_case_payload', v_unified_payload
    );
end;
$$;


ALTER FUNCTION "public"."accept_case_extension_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_escalate_current_dependency" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_extension_commit_state"("p_transportation_event_id" "uuid", "p_current_billing_line_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric DEFAULT 0, "p_reason_code" "text" DEFAULT NULL::"text", "p_optional_note" "text" DEFAULT NULL::"text", "p_entered_by_user_id" "uuid" DEFAULT NULL::"uuid", "p_dependency_id_to_escalate" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_old_expected_return_at timestamptz;
    v_expected_return_result jsonb;
    v_note_result jsonb;
    v_close_result jsonb;
    v_extension_line_result jsonb;
    v_escalation_result jsonb := null;
begin
    if not exists (
        select 1
        from public.transportation_events
        where id = p_transportation_event_id
    ) then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    if not exists (
        select 1
        from public.billing_lines
        where id = p_current_billing_line_id
          and is_open = true
          and (line_type is distinct from 'tax')
    ) then
        raise exception 'Open current billing line % does not exist', p_current_billing_line_id;
    end if;

    if p_reason_code is null or btrim(p_reason_code) = '' then
        raise exception 'Reason code is required for accepted extension';
    end if;

    if p_extension_amount is null or p_extension_amount < 0 then
        raise exception 'Extension amount must be non-negative';
    end if;

    if coalesce(p_extension_tax_amount, 0) < 0 then
        raise exception 'Extension tax amount must be non-negative';
    end if;

    if p_entered_by_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_entered_by_user_id
       ) then
        raise exception 'User % does not exist', p_entered_by_user_id;
    end if;

    if p_dependency_id_to_escalate is not null
       and not exists (
            select 1
            from public.reservation_vehicle_dependencies
            where id = p_dependency_id_to_escalate
       ) then
        raise exception 'Dependency % does not exist', p_dependency_id_to_escalate;
    end if;

    select expected_return_at
    into v_old_expected_return_at
    from public.transportation_events
    where id = p_transportation_event_id
    for update;

    -- 1) Update expected return state
    v_expected_return_result := public.set_expected_return_state(
        p_transportation_event_id,
        p_new_expected_return_at
    );

    -- 2) Add expected return change note
    v_note_result := public.add_estimated_return_change_note_state(
        p_transportation_event_id,
        v_old_expected_return_at,
        p_new_expected_return_at,
        p_reason_code,
        p_optional_note,
        p_entered_by_user_id
    );

    -- 3) Close the current billing line at paid_through_at
    v_close_result := public.close_billing_line_at_paid_through_state(
        p_current_billing_line_id
    );

    -- 4) Create the accepted extension line
    v_extension_line_result := public.create_extension_billing_line_state(
        p_current_billing_line_id,
        p_extension_amount,
        coalesce(p_extension_tax_amount, 0),
        p_new_expected_return_at
    );

    -- 5) Optionally escalate dependency to critical
    if p_dependency_id_to_escalate is not null then
        v_escalation_result := public.escalate_dependency_to_critical_state(
            p_dependency_id_to_escalate,
            p_entered_by_user_id
        );
    end if;

    return jsonb_build_object(
        'status',
            case
                when p_dependency_id_to_escalate is not null then 'accepted_with_conflict_escalation'
                else 'accepted'
            end,
        'transportation_event_id', p_transportation_event_id,
        'current_billing_line_id', p_current_billing_line_id,
        'expected_return_result', v_expected_return_result,
        'note_result', v_note_result,
        'close_result', v_close_result,
        'extension_line_result', v_extension_line_result,
        'dependency_escalation_result', v_escalation_result
    );
end;
$$;


ALTER FUNCTION "public"."accept_extension_commit_state"("p_transportation_event_id" "uuid", "p_current_billing_line_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_dependency_id_to_escalate" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_reservation_extension_state"("p_reservation_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric DEFAULT 0, "p_reason_code" "text" DEFAULT NULL::"text", "p_optional_note" "text" DEFAULT NULL::"text", "p_entered_by_user_id" "uuid" DEFAULT NULL::"uuid", "p_escalate_current_dependency" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_reservation record;
    v_candidate record;
    v_dependency_id uuid := null;
    v_result jsonb;
begin
    select *
    into v_reservation
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_new_expected_return_at is null then
        raise exception 'new_expected_return_at cannot be null';
    end if;

    if p_extension_amount is null or p_extension_amount < 0 then
        raise exception 'extension_amount must be non-negative';
    end if;

    if coalesce(p_extension_tax_amount, 0) < 0 then
        raise exception 'extension_tax_amount must be non-negative';
    end if;

    if p_reason_code is null or btrim(p_reason_code) = '' then
        raise exception 'reason_code cannot be blank';
    end if;

    if p_entered_by_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_entered_by_user_id
       ) then
        raise exception 'User % does not exist', p_entered_by_user_id;
    end if;

    select *
    into v_candidate
    from public.v_reservation_extension_candidate_state
    where reservation_id = p_reservation_id
      and parent_billing_line_id is not null
    order by start_time desc nulls last, parent_billing_line_id desc
    limit 1;

    if not found then
        raise exception 'No extension-eligible billing line exists for reservation %', p_reservation_id;
    end if;

    if p_escalate_current_dependency then
        select id
        into v_dependency_id
        from public.reservation_vehicle_dependencies
        where reservation_id = p_reservation_id
          and status in ('pending_return', 'ready', 'conflict')
        order by updated_at desc nulls last, created_at desc nulls last
        limit 1;
    end if;

    v_result := public.accept_extension_commit_state(
        v_reservation.transportation_event_id,
        v_candidate.parent_billing_line_id,
        p_new_expected_return_at,
        p_extension_amount,
        coalesce(p_extension_tax_amount, 0),
        p_reason_code,
        p_optional_note,
        p_entered_by_user_id,
        v_dependency_id
    );

    return jsonb_build_object(
        'status', 'reservation_extension_accepted',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'parent_billing_line_id', v_candidate.parent_billing_line_id,
        'dependency_id_escalated', v_dependency_id,
        'extension_commit_result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."accept_reservation_extension_state"("p_reservation_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_escalate_current_dependency" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_transportation_event_extension_state"("p_transportation_event_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric DEFAULT 0, "p_reason_code" "text" DEFAULT NULL::"text", "p_optional_note" "text" DEFAULT NULL::"text", "p_entered_by_user_id" "uuid" DEFAULT NULL::"uuid", "p_escalate_current_dependency" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_te record;
    v_candidate record;
    v_dependency_id uuid := null;
    v_result jsonb;
begin
    select *
    into v_te
    from public.transportation_events
    where id = p_transportation_event_id
    for update;

    if not found then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    if p_new_expected_return_at is null then
        raise exception 'new_expected_return_at cannot be null';
    end if;

    if p_extension_amount is null or p_extension_amount < 0 then
        raise exception 'extension_amount must be non-negative';
    end if;

    if coalesce(p_extension_tax_amount, 0) < 0 then
        raise exception 'extension_tax_amount must be non-negative';
    end if;

    if p_reason_code is null or btrim(p_reason_code) = '' then
        raise exception 'reason_code cannot be blank';
    end if;

    if p_entered_by_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_entered_by_user_id
       ) then
        raise exception 'User % does not exist', p_entered_by_user_id;
    end if;

    select *
    into v_candidate
    from public.v_transportation_event_extension_candidate_state
    where transportation_event_id = p_transportation_event_id
      and parent_billing_line_id is not null
    order by start_time desc nulls last, parent_billing_line_id desc
    limit 1;

    if not found then
        raise exception 'No extension-eligible billing line exists for transportation event %', p_transportation_event_id;
    end if;

    if p_escalate_current_dependency
       and v_te.source_type = 'reservation'
       and v_te.source_id is not null then
        select id
        into v_dependency_id
        from public.reservation_vehicle_dependencies
        where reservation_id = v_te.source_id
          and status in ('pending_return', 'ready', 'conflict')
        order by updated_at desc nulls last, created_at desc nulls last
        limit 1;
    end if;

    v_result := public.accept_extension_commit_state(
        p_transportation_event_id,
        v_candidate.parent_billing_line_id,
        p_new_expected_return_at,
        p_extension_amount,
        coalesce(p_extension_tax_amount, 0),
        p_reason_code,
        p_optional_note,
        p_entered_by_user_id,
        v_dependency_id
    );

    return jsonb_build_object(
        'status', 'transportation_event_extension_accepted',
        'transportation_event_id', p_transportation_event_id,
        'parent_billing_line_id', v_candidate.parent_billing_line_id,
        'dependency_id_escalated', v_dependency_id,
        'extension_commit_result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."accept_transportation_event_extension_state"("p_transportation_event_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_escalate_current_dependency" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."activate_case_billing_state"("p_reservation_id" "uuid", "p_amount" numeric, "p_tax_amount" numeric DEFAULT 0, "p_start_time" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_paid_through_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_line_type" "text" DEFAULT 'initial_assignment'::"text", "p_source_rule" "text" DEFAULT NULL::"text", "p_pay_type_override" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_reservation record;
    v_pay_type text;
    v_result jsonb;
begin
    select *
    into v_reservation
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_amount is null or p_amount < 0 then
        raise exception 'amount must be non-negative';
    end if;

    if coalesce(p_tax_amount, 0) < 0 then
        raise exception 'tax_amount must be non-negative';
    end if;

    v_pay_type := coalesce(p_pay_type_override, v_reservation.pay_type);

    if v_pay_type is null or btrim(v_pay_type) = '' then
        raise exception 'pay_type cannot be blank';
    end if;

    v_result := public.create_reservation_billing_line_state(
        p_reservation_id,
        v_pay_type,
        p_amount,
        coalesce(p_tax_amount, 0),
        p_start_time,
        null,
        p_line_type,
        p_paid_through_at,
        p_source_rule
    );

    return jsonb_build_object(
        'status', 'case_billing_activated',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'billing_result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."activate_case_billing_state"("p_reservation_id" "uuid", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_paid_through_at" timestamp with time zone, "p_line_type" "text", "p_source_rule" "text", "p_pay_type_override" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_billing_context_note_state"("p_transportation_event_id" "uuid", "p_note_text" "text", "p_entered_by_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_note_id uuid;
begin
    if not exists (
        select 1
        from public.transportation_events
        where id = p_transportation_event_id
    ) then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    if p_entered_by_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_entered_by_user_id
       ) then
        raise exception 'User % does not exist', p_entered_by_user_id;
    end if;

    if p_note_text is null or btrim(p_note_text) = '' then
        raise exception 'Billing-context note text cannot be blank';
    end if;

    insert into public.transportation_event_notes (
        transportation_event_id,
        note_type,
        note_text,
        entered_by_user_id,
        entered_at
    )
    values (
        p_transportation_event_id,
        'billing_note',
        p_note_text,
        p_entered_by_user_id,
        now()
    )
    returning id into v_note_id;

    return jsonb_build_object(
        'status', 'billing_note_created',
        'note_id', v_note_id,
        'transportation_event_id', p_transportation_event_id
    );
end;
$$;


ALTER FUNCTION "public"."add_billing_context_note_state"("p_transportation_event_id" "uuid", "p_note_text" "text", "p_entered_by_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_estimated_return_change_note_state"("p_transportation_event_id" "uuid", "p_old_expected_return_at" timestamp with time zone, "p_new_expected_return_at" timestamp with time zone, "p_reason_code" "text", "p_optional_note" "text" DEFAULT NULL::"text", "p_entered_by_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_note_id uuid;
    v_note_text text;
begin
    if not exists (
        select 1
        from public.transportation_events
        where id = p_transportation_event_id
    ) then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    if p_entered_by_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_entered_by_user_id
       ) then
        raise exception 'User % does not exist', p_entered_by_user_id;
    end if;

    if p_reason_code is null or btrim(p_reason_code) = '' then
        raise exception 'Reason code is required for estimated return changes';
    end if;

    v_note_text := coalesce(p_optional_note, '');

    insert into public.transportation_event_notes (
        transportation_event_id,
        note_type,
        old_expected_return_at,
        new_expected_return_at,
        reason_code,
        note_text,
        entered_by_user_id,
        entered_at
    )
    values (
        p_transportation_event_id,
        'estimated_return_change',
        p_old_expected_return_at,
        p_new_expected_return_at,
        p_reason_code,
        v_note_text,
        p_entered_by_user_id,
        now()
    )
    returning id into v_note_id;

    return jsonb_build_object(
        'status', 'estimated_return_change_note_created',
        'note_id', v_note_id,
        'transportation_event_id', p_transportation_event_id,
        'old_expected_return_at', p_old_expected_return_at,
        'new_expected_return_at', p_new_expected_return_at,
        'reason_code', p_reason_code
    );
end;
$$;


ALTER FUNCTION "public"."add_estimated_return_change_note_state"("p_transportation_event_id" "uuid", "p_old_expected_return_at" timestamp with time zone, "p_new_expected_return_at" timestamp with time zone, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_transportation_event_general_note_state"("p_transportation_event_id" "uuid", "p_note_text" "text", "p_entered_by_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_note_id uuid;
begin
    if not exists (
        select 1
        from public.transportation_events
        where id = p_transportation_event_id
    ) then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    if p_entered_by_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_entered_by_user_id
       ) then
        raise exception 'User % does not exist', p_entered_by_user_id;
    end if;

    if p_note_text is null or btrim(p_note_text) = '' then
        raise exception 'General note text cannot be blank';
    end if;

    insert into public.transportation_event_notes (
        transportation_event_id,
        note_type,
        note_text,
        entered_by_user_id,
        entered_at
    )
    values (
        p_transportation_event_id,
        'general_case_note',
        p_note_text,
        p_entered_by_user_id,
        now()
    )
    returning id into v_note_id;

    return jsonb_build_object(
        'status', 'general_case_note_created',
        'note_id', v_note_id,
        'transportation_event_id', p_transportation_event_id
    );
end;
$$;


ALTER FUNCTION "public"."add_transportation_event_general_note_state"("p_transportation_event_id" "uuid", "p_note_text" "text", "p_entered_by_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_user_role_state"("p_user_id" "uuid", "p_role_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    if not exists (
        select 1
        from public.roles
        where id = p_role_id
    ) then
        raise exception 'Role % does not exist', p_role_id;
    end if;

    insert into public.user_roles (user_id, role_id)
    values (p_user_id, p_role_id)
    on conflict do nothing;

    return jsonb_build_object(
        'status', 'role_added_or_already_present',
        'user_id', p_user_id,
        'role_id', p_role_id
    );
end;
$$;


ALTER FUNCTION "public"."add_user_role_state"("p_user_id" "uuid", "p_role_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_reservation_vehicle_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_reference_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_res record;
    v_vin_lock_lead_days integer := 0;
    v_lock_window_starts_at timestamptz;
begin
    select *
    into v_res
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if not exists (
        select 1
        from public.vehicles
        where id = p_vehicle_id
    ) then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    select coalesce((setting_value #>> '{}')::integer, 0)
    into v_vin_lock_lead_days
    from public.admin_settings
    where setting_key = 'reservation_vin_lock_lead_days';

    v_lock_window_starts_at := v_res.start_date - make_interval(days => v_vin_lock_lead_days);

    if p_reference_at < v_lock_window_starts_at then
        raise exception
            'Reservation % is not yet inside the VIN-lock window. Lock window starts at %',
            p_reservation_id,
            v_lock_window_starts_at;
    end if;

    update public.reservations
    set vehicle_id = p_vehicle_id
    where id = p_reservation_id;

    return jsonb_build_object(
        'status', 'reservation_vehicle_assigned',
        'reservation_id', p_reservation_id,
        'vehicle_id', p_vehicle_id,
        'lock_window_starts_at', v_lock_window_starts_at,
        'assigned_at_reference', p_reference_at
    );
end;
$$;


ALTER FUNCTION "public"."assign_reservation_vehicle_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_reference_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_reservation_vehicle_with_hard_lock_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_vehicle_available_now" boolean, "p_reference_at" timestamp with time zone DEFAULT "now"(), "p_actor_user_id" "uuid" DEFAULT NULL::"uuid", "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_res record;
    v_vin_lock_lead_days integer := 0;
    v_lock_window_starts_at timestamptz;
    v_source_transportation_event_id uuid;
    v_expected_return_snapshot timestamptz;
    v_dependency_result jsonb;
begin
    select *
    into v_res
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if not exists (
        select 1
        from public.vehicles
        where id = p_vehicle_id
    ) then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    if p_actor_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_actor_user_id
       ) then
        raise exception 'Actor user % does not exist', p_actor_user_id;
    end if;

    select coalesce((setting_value #>> '{}')::integer, 0)
    into v_vin_lock_lead_days
    from public.admin_settings
    where setting_key = 'reservation_vin_lock_lead_days';

    v_lock_window_starts_at := v_res.start_date - make_interval(days => v_vin_lock_lead_days);

    if p_reference_at < v_lock_window_starts_at then
        raise exception
            'Reservation % is not yet inside the VIN-lock window. Lock window starts at %',
            p_reservation_id,
            v_lock_window_starts_at;
    end if;

    -- Assign the specific vehicle on the reservation
    update public.reservations
    set vehicle_id = p_vehicle_id
    where id = p_reservation_id;

    -- If the vehicle is currently out, try to capture source continuity context
    if not p_vehicle_available_now then
        select
            c.transportation_event_id
        into v_source_transportation_event_id
        from public.v_current_vehicle_continuity c
        where c.vehicle_id = p_vehicle_id
        limit 1;

        if v_source_transportation_event_id is not null then
            select expected_return_at
            into v_expected_return_snapshot
            from public.transportation_events
            where id = v_source_transportation_event_id;
        end if;
    end if;

    -- Create/update hard-lock dependency state
    v_dependency_result := public.create_hard_lock_state(
        p_reservation_id,
        p_vehicle_id,
        p_vehicle_available_now,
        v_source_transportation_event_id,
        v_expected_return_snapshot,
        p_notes,
        p_actor_user_id
    );

    return jsonb_build_object(
        'status', 'reservation_vehicle_assigned_with_hard_lock',
        'reservation_id', p_reservation_id,
        'vehicle_id', p_vehicle_id,
        'lock_window_starts_at', v_lock_window_starts_at,
        'assigned_at_reference', p_reference_at,
        'dependency_result', v_dependency_result
    );
end;
$$;


ALTER FUNCTION "public"."assign_reservation_vehicle_with_hard_lock_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_vehicle_available_now" boolean, "p_reference_at" timestamp with time zone, "p_actor_user_id" "uuid", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_user_role_by_name_state"("p_user_id" "uuid", "p_role_name" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_role_id uuid;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    if p_role_name is null or btrim(p_role_name) = '' then
        raise exception 'role_name cannot be blank';
    end if;

    select id
    into v_role_id
    from public.roles
    where role_name = p_role_name;

    if not found then
        raise exception 'Role % does not exist', p_role_name;
    end if;

    insert into public.user_roles (user_id, role_id)
    values (p_user_id, v_role_id)
    on conflict do nothing;

    return jsonb_build_object(
        'status', 'role_added_or_already_present',
        'user_id', p_user_id,
        'role_id', v_role_id,
        'role_name', p_role_name
    );
end;
$$;


ALTER FUNCTION "public"."assign_user_role_by_name_state"("p_user_id" "uuid", "p_role_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."begin_admin_password_reset_state"("p_target_user_id" "uuid", "p_admin_user_id" "uuid", "p_issued_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_target_user_id
    ) then
        raise exception 'Target user % does not exist in public.app_users', p_target_user_id;
    end if;

    if not exists (
        select 1
        from public.app_users
        where id = p_admin_user_id
    ) then
        raise exception 'Admin user % does not exist in public.app_users', p_admin_user_id;
    end if;

    perform public.ensure_user_security_state(p_target_user_id);

    update public.app_user_security
    set
        failed_login_count = 0,
        last_failed_login_at = null,
        locked_until = null,
        post_lockout_final_attempt_allowed = false,
        is_disabled = false,
        disabled_at = null,
        disabled_reason = null,
        password_reset_pending = true,
        temporary_password_issued_at = p_issued_at,
        temporary_password_expires_at = p_issued_at + interval '72 hours',
        temporary_password_issued_by = p_admin_user_id,
        updated_at = now()
    where user_id = p_target_user_id;

    return jsonb_build_object(
        'status', 'reset_pending_started',
        'password_reset_pending', true,
        'temporary_password_issued_at', p_issued_at,
        'temporary_password_expires_at', p_issued_at + interval '72 hours'
    );
end;
$$;


ALTER FUNCTION "public"."begin_admin_password_reset_state"("p_target_user_id" "uuid", "p_admin_user_id" "uuid", "p_issued_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."business_contract_days"("p_out" timestamp with time zone, "p_in" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS integer
    LANGUAGE "sql" STABLE
    AS $$
    select
        case
            when p_out is null then null
            else greatest(
                1,
                floor(extract(epoch from (coalesce(p_in, now()) - p_out)) / 86400.0)::int + 1
            )
        end
$$;


ALTER FUNCTION "public"."business_contract_days"("p_out" timestamp with time zone, "p_in" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_case_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_cancellation_reason" "text", "p_closed_by" "uuid" DEFAULT NULL::"uuid", "p_closed_at" timestamp with time zone DEFAULT "now"(), "p_note" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_action_result jsonb;
    v_unified_payload jsonb;
begin
    v_action_result := public.cancel_reservation_with_transportation_event_state(
        p_reservation_id,
        p_cancellation_reason,
        p_closed_by,
        p_closed_at,
        p_note
    );

    v_unified_payload := public.get_unified_case_payload_state(
        p_reservation_id
    );

    return jsonb_build_object(
        'status', 'case_cancelled_and_loaded',
        'reservation_id', p_reservation_id,
        'action_result', v_action_result,
        'unified_case_payload', v_unified_payload
    );
end;
$$;


ALTER FUNCTION "public"."cancel_case_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_cancellation_reason" "text", "p_closed_by" "uuid", "p_closed_at" timestamp with time zone, "p_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_reservation_with_transportation_event_state"("p_reservation_id" "uuid", "p_cancellation_reason" "text", "p_closed_by" "uuid" DEFAULT NULL::"uuid", "p_closed_at" timestamp with time zone DEFAULT "now"(), "p_note" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_reservation record;
    v_current_reservation_notes text;
    v_current_transportation_notes text;
begin
    select *
    into v_reservation
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_cancellation_reason is null or btrim(p_cancellation_reason) = '' then
        raise exception 'cancellation_reason cannot be blank';
    end if;

    if p_closed_by is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_closed_by
       ) then
        raise exception 'User % does not exist', p_closed_by;
    end if;

    select notes
    into v_current_reservation_notes
    from public.reservations
    where id = p_reservation_id;

    select notes
    into v_current_transportation_notes
    from public.transportation_events
    where id = v_reservation.transportation_event_id
    for update;

    update public.reservations
    set
        status = 'cancelled',
        cancellation_reason = p_cancellation_reason,
        vehicle_id = null,
        notes = case
            when p_note is null or btrim(p_note) = '' then v_current_reservation_notes
            when v_current_reservation_notes is null or btrim(v_current_reservation_notes) = '' then p_note
            else v_current_reservation_notes || E'\n' || p_note
        end
    where id = p_reservation_id;

    update public.transportation_events
    set
        status = 'closed',
        closed_at = p_closed_at,
        closed_by = p_closed_by,
        notes = case
            when p_note is null or btrim(p_note) = '' then v_current_transportation_notes
            when v_current_transportation_notes is null or btrim(v_current_transportation_notes) = '' then p_note
            else v_current_transportation_notes || E'\n' || p_note
        end,
        updated_at = now()
    where id = v_reservation.transportation_event_id;

    return jsonb_build_object(
        'status', 'reservation_cancelled_with_transportation_event_closed',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'cancellation_reason', p_cancellation_reason,
        'closed_at', p_closed_at,
        'closed_by', p_closed_by
    );
end;
$$;


ALTER FUNCTION "public"."cancel_reservation_with_transportation_event_state"("p_reservation_id" "uuid", "p_cancellation_reason" "text", "p_closed_by" "uuid", "p_closed_at" timestamp with time zone, "p_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clear_password_reset_pending_state"("p_user_id" "uuid", "p_completed_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    perform public.ensure_user_security_state(p_user_id);

    update public.app_user_security
    set
        password_reset_pending = false,
        temporary_password_issued_at = null,
        temporary_password_expires_at = null,
        temporary_password_issued_by = null,
        failed_login_count = 0,
        last_failed_login_at = null,
        locked_until = null,
        post_lockout_final_attempt_allowed = false,
        updated_at = p_completed_at
    where user_id = p_user_id;

    return jsonb_build_object(
        'status', 'password_reset_pending_cleared',
        'user_id', p_user_id,
        'completed_at', p_completed_at
    );
end;
$$;


ALTER FUNCTION "public"."clear_password_reset_pending_state"("p_user_id" "uuid", "p_completed_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clear_reservation_vehicle_assignment_state"("p_reservation_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_res record;
begin
    select *
    into v_res
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    update public.reservations
    set vehicle_id = null
    where id = p_reservation_id;

    return jsonb_build_object(
        'status', 'reservation_vehicle_cleared',
        'reservation_id', p_reservation_id
    );
end;
$$;


ALTER FUNCTION "public"."clear_reservation_vehicle_assignment_state"("p_reservation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clear_reservation_vehicle_assignment_with_dependency_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_res record;
    v_dependency record;
    v_resolution_result jsonb := null;
begin
    select *
    into v_res
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_actor_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_actor_user_id
       ) then
        raise exception 'Actor user % does not exist', p_actor_user_id;
    end if;

    update public.reservations
    set vehicle_id = null
    where id = p_reservation_id;

    select *
    into v_dependency
    from public.reservation_vehicle_dependencies
    where reservation_id = p_reservation_id
      and status in ('pending_return', 'ready', 'conflict')
    order by updated_at desc nulls last, created_at desc nulls last
    limit 1
    for update;

    if found then
        v_resolution_result := public.resolve_reservation_dependency_state(
            v_dependency.id,
            'removed',
            p_actor_user_id
        );
    end if;

    return jsonb_build_object(
        'status', 'reservation_vehicle_cleared_with_dependency_resolution',
        'reservation_id', p_reservation_id,
        'dependency_resolution_result', v_resolution_result
    );
end;
$$;


ALTER FUNCTION "public"."clear_reservation_vehicle_assignment_with_dependency_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."close_billing_line_at_paid_through_state"("p_billing_line_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_parent record;
begin
    select *
    into v_parent
    from public.billing_lines
    where id = p_billing_line_id
      and (line_type is distinct from 'tax')
      and is_open = true
    for update;

    if not found then
        raise exception 'Open parent billing line % does not exist', p_billing_line_id;
    end if;

    if v_parent.paid_through_at is null then
        raise exception 'Billing line % has no paid_through_at', p_billing_line_id;
    end if;

    return public.close_billing_line_state(
        p_billing_line_id,
        v_parent.paid_through_at
    );
end;
$$;


ALTER FUNCTION "public"."close_billing_line_at_paid_through_state"("p_billing_line_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."close_billing_line_state"("p_billing_line_id" "uuid", "p_effective_end_time" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_parent record;
    v_tax_line record;
begin
    select *
    into v_parent
    from public.billing_lines
    where id = p_billing_line_id
      and (line_type is distinct from 'tax')
      and is_open = true
    for update;

    if not found then
        raise exception 'Open parent billing line % does not exist', p_billing_line_id;
    end if;

    if p_effective_end_time < v_parent.start_time then
        raise exception 'effective_end_time % is before start_time %',
            p_effective_end_time,
            v_parent.start_time;
    end if;

    update public.billing_lines
    set
        end_time = p_effective_end_time,
        is_open = false,
        updated_at = now()
    where id = p_billing_line_id;

    select *
    into v_tax_line
    from public.billing_lines
    where parent_billing_line_id = p_billing_line_id
      and line_type = 'tax'
      and is_open = true
    for update;

    if found then
        update public.billing_lines
        set
            end_time = p_effective_end_time,
            is_open = false,
            updated_at = now()
        where id = v_tax_line.id;
    end if;

    return jsonb_build_object(
        'status', 'billing_line_closed',
        'parent_billing_line_id', p_billing_line_id,
        'tax_billing_line_id', coalesce(v_tax_line.id, null)
    );
end;
$$;


ALTER FUNCTION "public"."close_billing_line_state"("p_billing_line_id" "uuid", "p_effective_end_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."close_current_reservation_billing_line_state"("p_reservation_id" "uuid", "p_effective_end_time" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_line record;
    v_result jsonb;
begin
    if not exists (
        select 1
        from public.reservations
        where id = p_reservation_id
    ) then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_effective_end_time is null then
        raise exception 'effective_end_time cannot be null';
    end if;

    select *
    into v_line
    from public.billing_lines
    where reservation_id = p_reservation_id
      and is_open = true
      and (line_type is distinct from 'tax')
    order by start_time desc nulls last, created_at desc nulls last, id desc
    limit 1
    for update;

    if not found then
        raise exception 'No open billing line exists for reservation %', p_reservation_id;
    end if;

    v_result := public.close_billing_line_state(
        v_line.id,
        p_effective_end_time
    );

    return jsonb_build_object(
        'status', 'reservation_current_billing_line_closed',
        'reservation_id', p_reservation_id,
        'parent_billing_line_id', v_line.id,
        'close_result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."close_current_reservation_billing_line_state"("p_reservation_id" "uuid", "p_effective_end_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."close_current_transportation_event_billing_line_state"("p_transportation_event_id" "uuid", "p_effective_end_time" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_line record;
    v_result jsonb;
begin
    if not exists (
        select 1
        from public.transportation_events
        where id = p_transportation_event_id
    ) then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    if p_effective_end_time is null then
        raise exception 'effective_end_time cannot be null';
    end if;

    select *
    into v_line
    from public.billing_lines
    where transportation_event_id = p_transportation_event_id
      and is_open = true
      and (line_type is distinct from 'tax')
    order by start_time desc nulls last, created_at desc nulls last, id desc
    limit 1
    for update;

    if not found then
        raise exception 'No open billing line exists for transportation event %', p_transportation_event_id;
    end if;

    v_result := public.close_billing_line_state(
        v_line.id,
        p_effective_end_time
    );

    return jsonb_build_object(
        'status', 'transportation_event_current_billing_line_closed',
        'transportation_event_id', p_transportation_event_id,
        'parent_billing_line_id', v_line.id,
        'close_result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."close_current_transportation_event_billing_line_state"("p_transportation_event_id" "uuid", "p_effective_end_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."close_transportation_event_state"("p_transportation_event_id" "uuid", "p_closed_by" "uuid" DEFAULT NULL::"uuid", "p_closed_at" timestamp with time zone DEFAULT "now"(), "p_close_note" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_current_notes text;
begin
    if not exists (
        select 1
        from public.transportation_events
        where id = p_transportation_event_id
    ) then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    if p_closed_by is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_closed_by
       ) then
        raise exception 'User % does not exist', p_closed_by;
    end if;

    select notes
    into v_current_notes
    from public.transportation_events
    where id = p_transportation_event_id
    for update;

    update public.transportation_events
    set
        status = 'closed',
        closed_at = p_closed_at,
        closed_by = p_closed_by,
        notes = case
            when p_close_note is null or btrim(p_close_note) = '' then v_current_notes
            when v_current_notes is null or btrim(v_current_notes) = '' then p_close_note
            else v_current_notes || E'\n' || p_close_note
        end,
        updated_at = now()
    where id = p_transportation_event_id;

    return jsonb_build_object(
        'status', 'transportation_event_closed',
        'transportation_event_id', p_transportation_event_id,
        'closed_at', p_closed_at,
        'closed_by', p_closed_by
    );
end;
$$;


ALTER FUNCTION "public"."close_transportation_event_state"("p_transportation_event_id" "uuid", "p_closed_by" "uuid", "p_closed_at" timestamp with time zone, "p_close_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."close_vehicle_scan_session_state"("p_vehicle_scan_session_id" "uuid", "p_notes" "text" DEFAULT NULL::"text", "p_closed_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.vehicle_scan_sessions
        where id = p_vehicle_scan_session_id
    ) then
        raise exception 'Vehicle scan session % does not exist', p_vehicle_scan_session_id;
    end if;

    update public.vehicle_scan_sessions
    set
        ended_at = p_closed_at,
        session_status = 'closed',
        notes = coalesce(p_notes, notes)
    where id = p_vehicle_scan_session_id;

    return jsonb_build_object(
        'status', 'vehicle_scan_session_closed',
        'vehicle_scan_session_id', p_vehicle_scan_session_id,
        'closed_at', p_closed_at
    );
end;
$$;


ALTER FUNCTION "public"."close_vehicle_scan_session_state"("p_vehicle_scan_session_id" "uuid", "p_notes" "text", "p_closed_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_case_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer DEFAULT NULL::integer, "p_close_billing" boolean DEFAULT true, "p_close_note" "text" DEFAULT NULL::"text", "p_closed_by" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_completion_result jsonb;
    v_unified_payload jsonb;
begin
    v_completion_result := public.complete_case_return_and_close_state(
        p_reservation_id,
        p_actual_in_at,
        p_end_mileage,
        p_close_billing,
        p_close_note,
        p_closed_by
    );

    v_unified_payload := public.get_unified_case_payload_state(
        p_reservation_id
    );

    return jsonb_build_object(
        'status', 'case_completed_and_loaded',
        'reservation_id', p_reservation_id,
        'completion_result', v_completion_result,
        'unified_case_payload', v_unified_payload
    );
end;
$$;


ALTER FUNCTION "public"."complete_case_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer, "p_close_billing" boolean, "p_close_note" "text", "p_closed_by" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_case_return_and_close_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer DEFAULT NULL::integer, "p_close_billing" boolean DEFAULT true, "p_close_note" "text" DEFAULT NULL::"text", "p_closed_by" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_reservation record;
    v_candidate record;
    v_return_result jsonb := null;
    v_billing_close_result jsonb := null;
    v_transportation_close_result jsonb;
begin
    select *
    into v_reservation
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_actual_in_at is null then
        raise exception 'actual_in_at cannot be null';
    end if;

    if p_actual_in_at < v_reservation.start_date then
        raise exception 'actual_in_at % is before reservation start_date %',
            p_actual_in_at,
            v_reservation.start_date;
    end if;

    if p_end_mileage is not null and p_end_mileage < 0 then
        raise exception 'end_mileage must be non-negative';
    end if;

    if p_closed_by is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_closed_by
       ) then
        raise exception 'User % does not exist', p_closed_by;
    end if;

    select *
    into v_candidate
    from public.v_case_completion_candidate_state
    where reservation_id = p_reservation_id
    limit 1;

    if not found then
        raise exception 'Case completion candidate state not found for reservation %', p_reservation_id;
    end if;

    -- Return continuity and set reservation actual return if active continuity exists
    if coalesce(v_candidate.has_active_continuity, false) then
        v_return_result := public.return_reservation_vehicle_use_state(
            p_reservation_id,
            p_actual_in_at,
            p_end_mileage,
            p_close_note
        );
    else
        -- Still allow actual return state to be set even if continuity is already absent
        v_return_result := public.set_reservation_actual_return_state(
            p_reservation_id,
            p_actual_in_at,
            p_end_mileage,
            p_close_note
        );
    end if;

    -- Optionally close current reservation billing line
    if p_close_billing and coalesce(v_candidate.has_open_billing_line, false) then
        v_billing_close_result := public.close_current_reservation_billing_line_state(
            p_reservation_id,
            p_actual_in_at
        );
    end if;

    -- Close linked transportation event
    v_transportation_close_result := public.close_transportation_event_state(
        v_reservation.transportation_event_id,
        p_closed_by,
        p_actual_in_at,
        p_close_note
    );

    return jsonb_build_object(
        'status', 'case_returned_and_closed',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'actual_in_at', p_actual_in_at,
        'return_result', v_return_result,
        'billing_close_result', v_billing_close_result,
        'transportation_event_close_result', v_transportation_close_result
    );
end;
$$;


ALTER FUNCTION "public"."complete_case_return_and_close_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer, "p_close_billing" boolean, "p_close_note" "text", "p_closed_by" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_password_reset_db_state"("p_user_id" "uuid", "p_token_hash" "text" DEFAULT NULL::"text", "p_completed_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_consumed_user_id uuid := null;
    v_clear_result jsonb;
    v_invalidate_result jsonb;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    -- If a token hash was provided, consume that token first
    if p_token_hash is not null and btrim(p_token_hash) <> '' then
        v_consumed_user_id := public.consume_reset_token_state(
            p_token_hash,
            p_completed_at
        );

        -- If token existed/consumed for a different user, block
        if v_consumed_user_id is not null and v_consumed_user_id <> p_user_id then
            raise exception
                'Token hash belongs to user %, not user %',
                v_consumed_user_id,
                p_user_id;
        end if;
    end if;

    v_clear_result := public.clear_password_reset_pending_state(
        p_user_id,
        p_completed_at
    );

    v_invalidate_result := public.invalidate_reset_tokens_for_user_state(
        p_user_id,
        p_completed_at
    );

    return jsonb_build_object(
        'status', 'password_reset_db_state_completed',
        'user_id', p_user_id,
        'token_consumed_for_user_id', v_consumed_user_id,
        'clear_result', v_clear_result,
        'invalidate_result', v_invalidate_result
    );
end;
$$;


ALTER FUNCTION "public"."complete_password_reset_db_state"("p_user_id" "uuid", "p_token_hash" "text", "p_completed_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."consume_reset_token_state"("p_token_hash" "text", "p_used_at" timestamp with time zone DEFAULT "now"()) RETURNS "uuid"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_user_id uuid;
begin
    update public.app_user_reset_tokens
    set
        used_at = p_used_at,
        is_active = false,
        updated_at = now()
    where token_hash = p_token_hash
      and is_active = true
      and used_at is null
      and expires_at >= p_used_at
    returning user_id into v_user_id;

    return v_user_id;
end;
$$;


ALTER FUNCTION "public"."consume_reset_token_state"("p_token_hash" "text", "p_used_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."continue_case_same_vehicle_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_time" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_action_result jsonb;
    v_unified_payload jsonb;
begin
    v_action_result := public.continue_case_same_vehicle_state(
        p_reservation_id,
        p_new_time
    );

    v_unified_payload := public.get_unified_case_payload_state(
        p_reservation_id
    );

    return jsonb_build_object(
        'status', 'case_continued_and_loaded',
        'reservation_id', p_reservation_id,
        'action_result', v_action_result,
        'unified_case_payload', v_unified_payload
    );
end;
$$;


ALTER FUNCTION "public"."continue_case_same_vehicle_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."continue_case_same_vehicle_state"("p_reservation_id" "uuid", "p_new_time" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_candidate record;
    v_result jsonb;
begin
    select *
    into v_candidate
    from public.v_case_continuation_candidate_state
    where reservation_id = p_reservation_id
    limit 1;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_new_time is null then
        raise exception 'new_time cannot be null';
    end if;

    if coalesce(v_candidate.reservation_has_assigned_vehicle, false) = false then
        raise exception 'Reservation % does not have an assigned vehicle to continue on', p_reservation_id;
    end if;

    if coalesce(v_candidate.has_active_continuity, false) then
        v_result := public.renew_reservation_same_vehicle_state(
            p_reservation_id,
            p_new_time
        );

        return jsonb_build_object(
            'status', 'case_continued_via_same_vehicle_renewal',
            'reservation_id', p_reservation_id,
            'transportation_event_id', v_candidate.transportation_event_id,
            'vehicle_id', v_candidate.reservation_vehicle_id,
            'new_time', p_new_time,
            'continuation_result', v_result
        );
    end if;

    v_result := public.restart_reservation_same_vehicle_after_gap_state(
        p_reservation_id,
        p_new_time
    );

    return jsonb_build_object(
        'status', 'case_continued_via_same_vehicle_restart_after_gap',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_candidate.transportation_event_id,
        'vehicle_id', v_candidate.reservation_vehicle_id,
        'new_time', p_new_time,
        'continuation_result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."continue_case_same_vehicle_state"("p_reservation_id" "uuid", "p_new_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_and_start_case_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_customer_phone" "text" DEFAULT NULL::"text", "p_customer_email" "text" DEFAULT NULL::"text", "p_customer_flags" "jsonb" DEFAULT NULL::"jsonb", "p_customer_internal_notes" "text" DEFAULT NULL::"text", "p_reservation_type" "text" DEFAULT 'rental'::"text", "p_reservation_status" "text" DEFAULT 'quote'::"text", "p_reservation_notes" "text" DEFAULT NULL::"text", "p_service_advisor" "text" DEFAULT NULL::"text", "p_ro_number" "text" DEFAULT NULL::"text", "p_pay_type" "text" DEFAULT 'customer'::"text", "p_vehicle_location" "text" DEFAULT NULL::"text", "p_vehicle_notes" "text" DEFAULT NULL::"text", "p_vehicle_status" "text" DEFAULT 'available'::"text", "p_vehicle_recon_status" "text" DEFAULT 'clean'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_case_step jsonb;
    v_vehicle_id uuid;
    v_reservation_id uuid;
    v_transportation_event_id uuid;
    v_start_result jsonb;
begin
    if p_actual_out_at is null then
        raise exception 'actual_out_at cannot be null';
    end if;

    v_case_step := public.create_case_bootstrap_with_vehicle_by_vin_state(
        p_tekion_customer_number,
        p_customer_name,
        p_start_date,
        p_expected_return_datetime,
        p_requested_model,
        p_vehicle_vin,
        p_vehicle_stock_number,
        p_vehicle_model,
        p_vehicle_fleet_type,
        p_vehicle_mileage,
        p_vehicle_current_tag,
        p_vehicle_fleet_conversion_type,
        p_customer_phone,
        p_customer_email,
        p_customer_flags,
        p_customer_internal_notes,
        p_reservation_type,
        p_reservation_status,
        p_reservation_notes,
        p_service_advisor,
        p_ro_number,
        p_pay_type,
        p_vehicle_location,
        p_vehicle_notes,
        p_vehicle_status,
        p_vehicle_recon_status
    );

    v_vehicle_id := (v_case_step ->> 'vehicle_id')::uuid;

    v_reservation_id := (
        v_case_step
        -> 'case_step'
        -> 'reservation_step'
        -> 'create_result'
        ->> 'reservation_id'
    )::uuid;

    v_transportation_event_id := (
        v_case_step
        -> 'case_step'
        -> 'reservation_step'
        -> 'create_result'
        ->> 'transportation_event_id'
    )::uuid;

    if v_reservation_id is null then
        raise exception 'Failed to extract reservation_id from case bootstrap result';
    end if;

    if v_transportation_event_id is null then
        raise exception 'Failed to extract transportation_event_id from case bootstrap result';
    end if;

    if v_vehicle_id is null then
        raise exception 'Failed to extract vehicle_id from case bootstrap result';
    end if;

    v_start_result := public.start_reservation_vehicle_use_state(
        v_reservation_id,
        v_vehicle_id,
        p_actual_out_at
    );

    return jsonb_build_object(
        'status', 'full_case_created_and_started',
        'vehicle_id', v_vehicle_id,
        'reservation_id', v_reservation_id,
        'transportation_event_id', v_transportation_event_id,
        'case_step', v_case_step,
        'start_result', v_start_result
    );
end;
$$;


ALTER FUNCTION "public"."create_and_start_case_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_app_user_state"("p_auth_user_id" "uuid", "p_email" "text", "p_full_name" "text" DEFAULT NULL::"text", "p_phone" "text" DEFAULT NULL::"text", "p_is_active" boolean DEFAULT true, "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_user_id uuid;
begin
    if p_auth_user_id is null then
        raise exception 'auth_user_id cannot be null';
    end if;

    if p_email is null or btrim(p_email) = '' then
        raise exception 'email cannot be blank';
    end if;

    if exists (
        select 1
        from public.app_users
        where auth_user_id = p_auth_user_id
    ) then
        raise exception 'auth_user_id % already exists in public.app_users', p_auth_user_id;
    end if;

    if exists (
        select 1
        from public.app_users
        where lower(email) = lower(p_email)
    ) then
        raise exception 'email % already exists in public.app_users', p_email;
    end if;

    insert into public.app_users (
        auth_user_id,
        full_name,
        email,
        phone,
        is_active,
        notes
    )
    values (
        p_auth_user_id,
        p_full_name,
        p_email,
        p_phone,
        p_is_active,
        p_notes
    )
    returning id into v_user_id;

    return jsonb_build_object(
        'status', 'app_user_created',
        'user_id', v_user_id,
        'auth_user_id', p_auth_user_id,
        'email', p_email
    );
end;
$$;


ALTER FUNCTION "public"."create_app_user_state"("p_auth_user_id" "uuid", "p_email" "text", "p_full_name" "text", "p_phone" "text", "p_is_active" boolean, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_app_user_with_role_state"("p_auth_user_id" "uuid", "p_email" "text", "p_role_name" "text", "p_full_name" "text" DEFAULT NULL::"text", "p_phone" "text" DEFAULT NULL::"text", "p_is_active" boolean DEFAULT true, "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_create_result jsonb;
    v_role_result jsonb;
    v_user_id uuid;
begin
    v_create_result := public.create_app_user_state(
        p_auth_user_id,
        p_email,
        p_full_name,
        p_phone,
        p_is_active,
        p_notes
    );

    v_user_id := (v_create_result ->> 'user_id')::uuid;

    v_role_result := public.assign_user_role_by_name_state(
        v_user_id,
        p_role_name
    );

    return jsonb_build_object(
        'status', 'app_user_created_with_role',
        'create_result', v_create_result,
        'role_result', v_role_result
    );
end;
$$;


ALTER FUNCTION "public"."create_app_user_with_role_state"("p_auth_user_id" "uuid", "p_email" "text", "p_role_name" "text", "p_full_name" "text", "p_phone" "text", "p_is_active" boolean, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_approved_network_state"("p_label" "text", "p_network_value" "text", "p_network_type" "text", "p_notes" "text" DEFAULT NULL::"text", "p_created_by_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_id uuid;
begin
    if p_label is null or btrim(p_label) = '' then
        raise exception 'Approved network label cannot be blank';
    end if;

    if p_network_value is null or btrim(p_network_value) = '' then
        raise exception 'Approved network value cannot be blank';
    end if;

    if p_network_type is null or btrim(p_network_type) = '' then
        raise exception 'Approved network type cannot be blank';
    end if;

    if p_created_by_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_created_by_user_id
       ) then
        raise exception 'User % does not exist', p_created_by_user_id;
    end if;

    insert into public.approved_networks (
        label,
        network_value,
        network_type,
        is_active,
        notes,
        created_at,
        updated_at,
        created_by_user_id,
        updated_by_user_id
    )
    values (
        p_label,
        p_network_value,
        p_network_type,
        true,
        p_notes,
        now(),
        now(),
        p_created_by_user_id,
        p_created_by_user_id
    )
    returning id into v_id;

    return jsonb_build_object(
        'status', 'approved_network_created',
        'approved_network_id', v_id
    );
end;
$$;


ALTER FUNCTION "public"."create_approved_network_state"("p_label" "text", "p_network_value" "text", "p_network_type" "text", "p_notes" "text", "p_created_by_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_billing_parent_line_state"("p_transportation_event_id" "uuid", "p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_source_rule" "text" DEFAULT NULL::"text", "p_vehicle_event_id" "uuid" DEFAULT NULL::"uuid", "p_contract_period_id" "uuid" DEFAULT NULL::"uuid", "p_line_type" "text" DEFAULT 'initial_assignment'::"text", "p_warranty_provider_id" "uuid" DEFAULT NULL::"uuid", "p_default_covered_days_snapshot" integer DEFAULT NULL::integer, "p_covered_days_override" integer DEFAULT NULL::integer, "p_is_open" boolean DEFAULT true, "p_paid_through_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_extended_from_billing_line_id" "uuid" DEFAULT NULL::"uuid", "p_default_daily_rate_snapshot" numeric DEFAULT NULL::numeric, "p_daily_rate_override" numeric DEFAULT NULL::numeric) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_pay_type_rule record;
    v_parent_line_id uuid;
    v_tax_result jsonb;
begin
    if not exists (
        select 1
        from public.transportation_events
        where id = p_transportation_event_id
    ) then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    if p_vehicle_id is not null
       and not exists (
            select 1
            from public.vehicles
            where id = p_vehicle_id
       ) then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    if p_vehicle_event_id is not null
       and not exists (
            select 1
            from public.vehicle_events
            where id = p_vehicle_event_id
       ) then
        raise exception 'Vehicle event % does not exist', p_vehicle_event_id;
    end if;

    if p_contract_period_id is not null
       and not exists (
            select 1
            from public.contract_periods
            where id = p_contract_period_id
       ) then
        raise exception 'Contract period % does not exist', p_contract_period_id;
    end if;

    if p_end_time is not null and p_end_time < p_start_time then
        raise exception 'end_time % is before start_time %', p_end_time, p_start_time;
    end if;

    if p_paid_through_at is not null and p_paid_through_at < p_start_time then
        raise exception 'paid_through_at % is before start_time %', p_paid_through_at, p_start_time;
    end if;

    select
        id,
        pay_type,
        is_active,
        is_taxable
    into v_pay_type_rule
    from public.pay_type_rules
    where pay_type = p_pay_type
    limit 1;

    if not found then
        raise exception 'Pay type % does not exist in public.pay_type_rules', p_pay_type;
    end if;

    insert into public.billing_lines (
        transportation_event_id,
        reservation_id,
        vehicle_id,
        pay_type,
        amount,
        tax_amount,
        start_time,
        end_time,
        source_rule,
        vehicle_event_id,
        contract_period_id,
        pay_type_rule_id,
        line_type,
        parent_billing_line_id,
        warranty_provider_id,
        default_covered_days_snapshot,
        covered_days_override,
        is_open,
        updated_at,
        paid_through_at,
        extended_from_billing_line_id,
        default_daily_rate_snapshot,
        daily_rate_override
    )
    values (
        p_transportation_event_id,
        p_reservation_id,
        p_vehicle_id,
        p_pay_type,
        coalesce(p_amount, 0),
        coalesce(p_tax_amount, 0),
        p_start_time,
        p_end_time,
        p_source_rule,
        p_vehicle_event_id,
        p_contract_period_id,
        v_pay_type_rule.id,
        p_line_type,
        null,
        p_warranty_provider_id,
        p_default_covered_days_snapshot,
        p_covered_days_override,
        p_is_open,
        now(),
        p_paid_through_at,
        p_extended_from_billing_line_id,
        p_default_daily_rate_snapshot,
        p_daily_rate_override
    )
    returning id into v_parent_line_id;

    v_tax_result := public.ensure_tax_child_line_state(v_parent_line_id);

    return jsonb_build_object(
        'status', 'parent_billing_line_created',
        'parent_billing_line_id', v_parent_line_id,
        'pay_type_rule_id', v_pay_type_rule.id,
        'tax_result', v_tax_result
    );
end;
$$;


ALTER FUNCTION "public"."create_billing_parent_line_state"("p_transportation_event_id" "uuid", "p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_source_rule" "text", "p_vehicle_event_id" "uuid", "p_contract_period_id" "uuid", "p_line_type" "text", "p_warranty_provider_id" "uuid", "p_default_covered_days_snapshot" integer, "p_covered_days_override" integer, "p_is_open" boolean, "p_paid_through_at" timestamp with time zone, "p_extended_from_billing_line_id" "uuid", "p_default_daily_rate_snapshot" numeric, "p_daily_rate_override" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_case_bootstrap_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_customer_phone" "text" DEFAULT NULL::"text", "p_customer_email" "text" DEFAULT NULL::"text", "p_customer_flags" "jsonb" DEFAULT NULL::"jsonb", "p_customer_internal_notes" "text" DEFAULT NULL::"text", "p_reservation_type" "text" DEFAULT 'rental'::"text", "p_status" "text" DEFAULT 'quote'::"text", "p_notes" "text" DEFAULT NULL::"text", "p_service_advisor" "text" DEFAULT NULL::"text", "p_ro_number" "text" DEFAULT NULL::"text", "p_pay_type" "text" DEFAULT 'customer'::"text", "p_vehicle_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_customer_step jsonb;
    v_create_step jsonb;
begin
    if p_tekion_customer_number is null or btrim(p_tekion_customer_number) = '' then
        raise exception 'tekion_customer_number cannot be blank';
    end if;

    if p_customer_name is null or btrim(p_customer_name) = '' then
        raise exception 'customer_name cannot be blank';
    end if;

    if p_start_date is null then
        raise exception 'start_date cannot be null';
    end if;

    if p_expected_return_datetime is null then
        raise exception 'expected_return_datetime cannot be null';
    end if;

    if p_requested_model is null or btrim(p_requested_model) = '' then
        raise exception 'requested_model cannot be blank';
    end if;

    v_customer_step := public.get_or_create_customer_state_by_tekion(
        p_tekion_customer_number,
        p_customer_name,
        p_customer_phone,
        p_customer_email,
        p_customer_flags,
        p_customer_internal_notes
    );

    v_create_step := public.create_reservation_for_tekion_customer_state(
        p_tekion_customer_number,
        p_start_date,
        p_expected_return_datetime,
        p_requested_model,
        p_reservation_type,
        p_status,
        p_notes,
        p_service_advisor,
        p_ro_number,
        p_pay_type,
        p_vehicle_id
    );

    return jsonb_build_object(
        'status', 'case_bootstrap_created',
        'customer_step', v_customer_step,
        'reservation_step', v_create_step
    );
end;
$$;


ALTER FUNCTION "public"."create_case_bootstrap_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_status" "text", "p_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_case_bootstrap_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_customer_phone" "text" DEFAULT NULL::"text", "p_customer_email" "text" DEFAULT NULL::"text", "p_customer_flags" "jsonb" DEFAULT NULL::"jsonb", "p_customer_internal_notes" "text" DEFAULT NULL::"text", "p_reservation_type" "text" DEFAULT 'rental'::"text", "p_reservation_status" "text" DEFAULT 'quote'::"text", "p_reservation_notes" "text" DEFAULT NULL::"text", "p_service_advisor" "text" DEFAULT NULL::"text", "p_ro_number" "text" DEFAULT NULL::"text", "p_pay_type" "text" DEFAULT 'customer'::"text", "p_vehicle_location" "text" DEFAULT NULL::"text", "p_vehicle_notes" "text" DEFAULT NULL::"text", "p_vehicle_status" "text" DEFAULT 'available'::"text", "p_vehicle_recon_status" "text" DEFAULT 'clean'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_customer_step jsonb;
    v_vehicle_step jsonb;
    v_vehicle_id uuid;
    v_case_step jsonb;
begin
    if p_tekion_customer_number is null or btrim(p_tekion_customer_number) = '' then
        raise exception 'tekion_customer_number cannot be blank';
    end if;

    if p_customer_name is null or btrim(p_customer_name) = '' then
        raise exception 'customer_name cannot be blank';
    end if;

    if p_start_date is null then
        raise exception 'start_date cannot be null';
    end if;

    if p_expected_return_datetime is null then
        raise exception 'expected_return_datetime cannot be null';
    end if;

    if p_requested_model is null or btrim(p_requested_model) = '' then
        raise exception 'requested_model cannot be blank';
    end if;

    if p_vehicle_vin is null or btrim(p_vehicle_vin) = '' then
        raise exception 'vehicle_vin cannot be blank';
    end if;

    if p_vehicle_stock_number is null or btrim(p_vehicle_stock_number) = '' then
        raise exception 'vehicle_stock_number cannot be blank';
    end if;

    if p_vehicle_model is null or btrim(p_vehicle_model) = '' then
        raise exception 'vehicle_model cannot be blank';
    end if;

    if p_vehicle_fleet_type is null or btrim(p_vehicle_fleet_type) = '' then
        raise exception 'vehicle_fleet_type cannot be blank';
    end if;

    if p_vehicle_current_tag is null or btrim(p_vehicle_current_tag) = '' then
        raise exception 'vehicle_current_tag cannot be blank';
    end if;

    if p_vehicle_fleet_conversion_type is null or btrim(p_vehicle_fleet_conversion_type) = '' then
        raise exception 'vehicle_fleet_conversion_type cannot be blank';
    end if;

    if p_vehicle_mileage is null or p_vehicle_mileage < 0 then
        raise exception 'vehicle_mileage must be non-negative';
    end if;

    v_customer_step := public.get_or_create_customer_state_by_tekion(
        p_tekion_customer_number,
        p_customer_name,
        p_customer_phone,
        p_customer_email,
        p_customer_flags,
        p_customer_internal_notes
    );

    v_vehicle_step := public.get_or_create_vehicle_state_by_vin(
        p_vehicle_vin,
        p_vehicle_stock_number,
        p_vehicle_model,
        p_vehicle_fleet_type,
        p_vehicle_mileage,
        p_vehicle_current_tag,
        p_vehicle_fleet_conversion_type,
        p_vehicle_location,
        p_vehicle_notes,
        p_vehicle_status,
        p_vehicle_recon_status
    );

    if (v_vehicle_step ->> 'status') = 'vehicle_already_exists' then
        v_vehicle_id := (v_vehicle_step -> 'vehicle_state' ->> 'vehicle_id')::uuid;
    else
        v_vehicle_id := (v_vehicle_step -> 'vehicle_result' ->> 'vehicle_id')::uuid;
    end if;

    v_case_step := public.create_case_bootstrap_state(
        p_tekion_customer_number,
        p_customer_name,
        p_start_date,
        p_expected_return_datetime,
        p_requested_model,
        p_customer_phone,
        p_customer_email,
        p_customer_flags,
        p_customer_internal_notes,
        p_reservation_type,
        p_reservation_status,
        p_reservation_notes,
        p_service_advisor,
        p_ro_number,
        p_pay_type,
        v_vehicle_id
    );

    return jsonb_build_object(
        'status', 'case_bootstrap_with_vehicle_created',
        'customer_step', v_customer_step,
        'vehicle_step', v_vehicle_step,
        'vehicle_id', v_vehicle_id,
        'case_step', v_case_step
    );
end;
$$;


ALTER FUNCTION "public"."create_case_bootstrap_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_customer_state"("p_tekion_customer_number" "text", "p_name" "text", "p_phone" "text" DEFAULT NULL::"text", "p_email" "text" DEFAULT NULL::"text", "p_flags" "jsonb" DEFAULT NULL::"jsonb", "p_internal_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_id uuid;
begin
    if p_tekion_customer_number is null or btrim(p_tekion_customer_number) = '' then
        raise exception 'tekion_customer_number cannot be blank';
    end if;

    if p_name is null or btrim(p_name) = '' then
        raise exception 'name cannot be blank';
    end if;

    if exists (
        select 1
        from public.customers
        where tekion_customer_number = p_tekion_customer_number
    ) then
        raise exception 'tekion_customer_number % already exists', p_tekion_customer_number;
    end if;

    insert into public.customers (
        tekion_customer_number,
        name,
        phone,
        email,
        flags,
        internal_notes
    )
    values (
        p_tekion_customer_number,
        p_name,
        p_phone,
        p_email,
        p_flags,
        p_internal_notes
    )
    returning id into v_id;

    return jsonb_build_object(
        'status', 'customer_created',
        'customer_id', v_id,
        'tekion_customer_number', p_tekion_customer_number,
        'name', p_name
    );
end;
$$;


ALTER FUNCTION "public"."create_customer_state"("p_tekion_customer_number" "text", "p_name" "text", "p_phone" "text", "p_email" "text", "p_flags" "jsonb", "p_internal_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_extended_warranty_rule_state"("p_provider_id" "uuid", "p_covered_days" integer DEFAULT 0, "p_requires_approval" boolean DEFAULT false, "p_daily_rate" numeric DEFAULT NULL::numeric, "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_id uuid;
begin
    if not exists (
        select 1
        from public.warranty_providers
        where id = p_provider_id
    ) then
        raise exception 'Warranty provider % does not exist', p_provider_id;
    end if;

    if p_covered_days is not null and p_covered_days < 0 then
        raise exception 'covered_days cannot be negative';
    end if;

    if p_daily_rate is not null and p_daily_rate < 0 then
        raise exception 'daily_rate cannot be negative';
    end if;

    insert into public.extended_warranty_rules (
        provider_id,
        covered_days,
        requires_approval,
        daily_rate,
        is_active,
        updated_at,
        notes
    )
    values (
        p_provider_id,
        coalesce(p_covered_days, 0),
        coalesce(p_requires_approval, false),
        p_daily_rate,
        true,
        now(),
        p_notes
    )
    returning id into v_id;

    return jsonb_build_object(
        'status', 'extended_warranty_rule_created',
        'rule_id', v_id
    );
end;
$$;


ALTER FUNCTION "public"."create_extended_warranty_rule_state"("p_provider_id" "uuid", "p_covered_days" integer, "p_requires_approval" boolean, "p_daily_rate" numeric, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_extension_billing_line_state"("p_parent_billing_line_id" "uuid", "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_new_expected_return_at" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_parent record;
    v_result jsonb;
begin
    select *
    into v_parent
    from public.billing_lines
    where id = p_parent_billing_line_id
      and (line_type is distinct from 'tax')
    for update;

    if not found then
        raise exception 'Parent billing line % does not exist or is a tax line', p_parent_billing_line_id;
    end if;

    if v_parent.paid_through_at is null then
        raise exception 'Parent billing line % has no paid_through_at', p_parent_billing_line_id;
    end if;

    if p_extension_amount is null then
        raise exception 'Extension amount cannot be null';
    end if;

    if coalesce(p_extension_amount, 0) < 0 then
        raise exception 'Extension amount % cannot be negative', p_extension_amount;
    end if;

    if coalesce(p_extension_tax_amount, 0) < 0 then
        raise exception 'Extension tax amount % cannot be negative', p_extension_tax_amount;
    end if;

    v_result := public.create_billing_parent_line_state(
        v_parent.transportation_event_id,
        v_parent.reservation_id,
        v_parent.vehicle_id,
        v_parent.pay_type,
        p_extension_amount,
        coalesce(p_extension_tax_amount, 0),
        v_parent.paid_through_at,
        p_new_expected_return_at,
        v_parent.source_rule,
        v_parent.vehicle_event_id,
        v_parent.contract_period_id,
        'rental_extension',
        v_parent.warranty_provider_id,
        v_parent.default_covered_days_snapshot,
        v_parent.covered_days_override,
        true,
        v_parent.paid_through_at,
        v_parent.id,
        v_parent.default_daily_rate_snapshot,
        v_parent.daily_rate_override
    );

    return jsonb_build_object(
        'status', 'extension_billing_line_created',
        'parent_billing_line_id', p_parent_billing_line_id,
        'result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."create_extension_billing_line_state"("p_parent_billing_line_id" "uuid", "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_new_expected_return_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_hard_lock_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_vehicle_available_now" boolean, "p_source_transportation_event_id" "uuid" DEFAULT NULL::"uuid", "p_expected_return_snapshot" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_notes" "text" DEFAULT NULL::"text", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_status text;
    v_risk_level text;
begin
    if p_vehicle_available_now then
        v_status := 'ready';
        v_risk_level := 'normal';
    else
        v_status := 'conflict';
        v_risk_level := 'critical';
    end if;

    return public.upsert_reservation_dependency_state(
        p_reservation_id,
        p_vehicle_id,
        p_source_transportation_event_id,
        'hard_lock',
        v_status,
        v_risk_level,
        p_expected_return_snapshot,
        p_notes,
        p_actor_user_id
    );
end;
$$;


ALTER FUNCTION "public"."create_hard_lock_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_vehicle_available_now" boolean, "p_source_transportation_event_id" "uuid", "p_expected_return_snapshot" timestamp with time zone, "p_notes" "text", "p_actor_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_late_fee_rule_state"("p_rule_kind" "text", "p_threshold_unit" "text", "p_threshold_value" integer, "p_fee_amount" numeric DEFAULT NULL::numeric, "p_sort_order" integer DEFAULT 0, "p_description" "text" DEFAULT NULL::"text", "p_created_by" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_id uuid;
begin
    if p_rule_kind is null or btrim(p_rule_kind) = '' then
        raise exception 'rule_kind cannot be blank';
    end if;

    if p_threshold_unit is null or btrim(p_threshold_unit) = '' then
        raise exception 'threshold_unit cannot be blank';
    end if;

    if p_threshold_value is null or p_threshold_value < 0 then
        raise exception 'threshold_value must be non-negative';
    end if;

    if p_fee_amount is not null and p_fee_amount < 0 then
        raise exception 'fee_amount cannot be negative';
    end if;

    if p_sort_order is null or p_sort_order < 0 then
        raise exception 'sort_order must be non-negative';
    end if;

    if p_created_by is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_created_by
       ) then
        raise exception 'User % does not exist', p_created_by;
    end if;

    insert into public.late_fee_rules (
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
    )
    values (
        true,
        p_sort_order,
        p_rule_kind,
        p_threshold_unit,
        p_threshold_value,
        p_fee_amount,
        p_description,
        now(),
        now(),
        p_created_by,
        p_created_by
    )
    returning id into v_id;

    return jsonb_build_object(
        'status', 'late_fee_rule_created',
        'late_fee_rule_id', v_id
    );
end;
$$;


ALTER FUNCTION "public"."create_late_fee_rule_state"("p_rule_kind" "text", "p_threshold_unit" "text", "p_threshold_value" integer, "p_fee_amount" numeric, "p_sort_order" integer, "p_description" "text", "p_created_by" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_or_update_reservation_conflict_state"("p_reservation_id" "uuid", "p_dependency_id" "uuid", "p_conflict_type" "text", "p_severity" "text", "p_message" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_existing_conflict record;
    v_new_conflict_id uuid;
begin
    if p_severity not in ('critical', 'warning', 'review') then
        raise exception 'Invalid severity: %', p_severity;
    end if;

    if not exists (
        select 1
        from public.reservations
        where id = p_reservation_id
    ) then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if not exists (
        select 1
        from public.reservation_vehicle_dependencies
        where id = p_dependency_id
    ) then
        raise exception 'Dependency % does not exist', p_dependency_id;
    end if;

    select *
    into v_existing_conflict
    from public.reservation_conflicts
    where reservation_vehicle_dependency_id = p_dependency_id
      and is_resolved = false
    order by id desc
    limit 1
    for update;

    if found then
        update public.reservation_conflicts
        set
            reservation_id = p_reservation_id,
            conflict_type = p_conflict_type,
            severity = p_severity,
            message = p_message,
            is_resolved = false
        where id = v_existing_conflict.id;

        return jsonb_build_object(
            'status', 'conflict_updated',
            'conflict_id', v_existing_conflict.id,
            'reservation_id', p_reservation_id,
            'dependency_id', p_dependency_id,
            'severity', p_severity
        );
    end if;

    insert into public.reservation_conflicts (
        reservation_id,
        reservation_vehicle_dependency_id,
        conflict_type,
        severity,
        message,
        is_resolved
    )
    values (
        p_reservation_id,
        p_dependency_id,
        p_conflict_type,
        p_severity,
        p_message,
        false
    )
    returning id into v_new_conflict_id;

    return jsonb_build_object(
        'status', 'conflict_created',
        'conflict_id', v_new_conflict_id,
        'reservation_id', p_reservation_id,
        'dependency_id', p_dependency_id,
        'severity', p_severity
    );
end;
$$;


ALTER FUNCTION "public"."create_or_update_reservation_conflict_state"("p_reservation_id" "uuid", "p_dependency_id" "uuid", "p_conflict_type" "text", "p_severity" "text", "p_message" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_reservation_billing_line_state"("p_reservation_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric DEFAULT 0, "p_start_time" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_end_time" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_line_type" "text" DEFAULT 'initial_assignment'::"text", "p_paid_through_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_source_rule" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_reservation record;
    v_current_continuity record;
    v_result jsonb;
    v_start_time timestamptz;
begin
    select *
    into v_reservation
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_pay_type is null or btrim(p_pay_type) = '' then
        raise exception 'pay_type cannot be blank';
    end if;

    if p_amount is null or p_amount < 0 then
        raise exception 'amount must be non-negative';
    end if;

    if coalesce(p_tax_amount, 0) < 0 then
        raise exception 'tax_amount must be non-negative';
    end if;

    v_start_time := coalesce(p_start_time, v_reservation.start_date);

    select *
    into v_current_continuity
    from public.v_current_vehicle_continuity
    where transportation_event_id = v_reservation.transportation_event_id
    limit 1;

    v_result := public.create_billing_parent_line_state(
        v_reservation.transportation_event_id,
        p_reservation_id,
        coalesce(v_current_continuity.vehicle_id, v_reservation.vehicle_id),
        p_pay_type,
        p_amount,
        coalesce(p_tax_amount, 0),
        v_start_time,
        p_end_time,
        p_source_rule,
        v_current_continuity.vehicle_event_id,
        v_current_continuity.contract_period_id,
        p_line_type,
        null,
        null,
        null,
        true,
        p_paid_through_at,
        null,
        null,
        null
    );

    return jsonb_build_object(
        'status', 'reservation_billing_line_created',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'billing_result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."create_reservation_billing_line_state"("p_reservation_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_line_type" "text", "p_paid_through_at" timestamp with time zone, "p_source_rule" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_reservation_for_tekion_customer_state"("p_tekion_customer_number" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_reservation_type" "text" DEFAULT 'rental'::"text", "p_status" "text" DEFAULT 'quote'::"text", "p_notes" "text" DEFAULT NULL::"text", "p_service_advisor" "text" DEFAULT NULL::"text", "p_ro_number" "text" DEFAULT NULL::"text", "p_pay_type" "text" DEFAULT 'customer'::"text", "p_vehicle_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_customer_id uuid;
    v_create_result jsonb;
begin
    if p_tekion_customer_number is null or btrim(p_tekion_customer_number) = '' then
        raise exception 'tekion_customer_number cannot be blank';
    end if;

    select id
    into v_customer_id
    from public.customers
    where tekion_customer_number = p_tekion_customer_number
    limit 1;

    if not found then
        raise exception 'Customer with tekion_customer_number % does not exist', p_tekion_customer_number;
    end if;

    v_create_result := public.create_reservation_with_transportation_event_state(
        p_start_date,
        p_expected_return_datetime,
        p_requested_model,
        p_reservation_type,
        p_status,
        p_notes,
        v_customer_id,
        p_service_advisor,
        p_ro_number,
        p_pay_type,
        p_vehicle_id
    );

    return jsonb_build_object(
        'status', 'reservation_created_for_tekion_customer',
        'tekion_customer_number', p_tekion_customer_number,
        'customer_id', v_customer_id,
        'create_result', v_create_result
    );
end;
$$;


ALTER FUNCTION "public"."create_reservation_for_tekion_customer_state"("p_tekion_customer_number" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_reservation_type" "text", "p_status" "text", "p_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_reservation_with_transportation_event_state"("p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_reservation_type" "text" DEFAULT 'rental'::"text", "p_status" "text" DEFAULT 'quote'::"text", "p_notes" "text" DEFAULT NULL::"text", "p_customer_id" "uuid" DEFAULT NULL::"uuid", "p_service_advisor" "text" DEFAULT NULL::"text", "p_ro_number" "text" DEFAULT NULL::"text", "p_pay_type" "text" DEFAULT 'customer'::"text", "p_vehicle_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_transportation_event_id uuid;
    v_reservation_id uuid;
begin
    if p_start_date is null then
        raise exception 'start_date cannot be null';
    end if;

    if p_expected_return_datetime is null then
        raise exception 'expected_return_datetime cannot be null';
    end if;

    if p_expected_return_datetime < p_start_date then
        raise exception 'expected_return_datetime % is before start_date %',
            p_expected_return_datetime,
            p_start_date;
    end if;

    if p_requested_model is null or btrim(p_requested_model) = '' then
        raise exception 'requested_model cannot be blank';
    end if;

    if p_reservation_type is null or btrim(p_reservation_type) = '' then
        raise exception 'reservation_type cannot be blank';
    end if;

    if p_status is null or btrim(p_status) = '' then
        raise exception 'status cannot be blank';
    end if;

    if p_customer_id is not null
       and not exists (
            select 1
            from public.customers
            where id = p_customer_id
       ) then
        raise exception 'Customer % does not exist', p_customer_id;
    end if;

    if p_vehicle_id is not null
       and not exists (
            select 1
            from public.vehicles
            where id = p_vehicle_id
       ) then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    -- Create linked transportation event first
    insert into public.transportation_events (
        source_type,
        source_id,
        status,
        notes,
        customer_id,
        updated_at,
        closed_at,
        closed_by,
        expected_return_at
    )
    values (
        'reservation',
        null,
        'active',
        p_notes,
        p_customer_id,
        now(),
        null,
        null,
        p_expected_return_datetime
    )
    returning id into v_transportation_event_id;

    -- Create reservation linked to that transportation event
    insert into public.reservations (
        vehicle_id,
        start_date,
        expected_return_datetime,
        status,
        reservation_type,
        notes,
        service_advisor,
        ro_number,
        pay_type,
        transportation_event_id,
        customer_id,
        requested_model
    )
    values (
        p_vehicle_id,
        p_start_date,
        p_expected_return_datetime,
        p_status,
        p_reservation_type,
        p_notes,
        p_service_advisor,
        p_ro_number,
        p_pay_type,
        v_transportation_event_id,
        p_customer_id,
        p_requested_model
    )
    returning id into v_reservation_id;

    -- Backfill source_id on transportation_event to point to reservation
    update public.transportation_events
    set
        source_id = v_reservation_id,
        updated_at = now()
    where id = v_transportation_event_id;

    return jsonb_build_object(
        'status', 'reservation_with_transportation_event_created',
        'reservation_id', v_reservation_id,
        'transportation_event_id', v_transportation_event_id
    );
end;
$$;


ALTER FUNCTION "public"."create_reservation_with_transportation_event_state"("p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_reservation_type" "text", "p_status" "text", "p_notes" "text", "p_customer_id" "uuid", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_reset_token_state"("p_user_id" "uuid", "p_token_hash" "text", "p_reset_mode" "text", "p_issued_by_user_id" "uuid" DEFAULT NULL::"uuid", "p_issued_at" timestamp with time zone DEFAULT "now"(), "p_notes" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_token_id uuid;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist in public.app_users', p_user_id;
    end if;

    if p_issued_by_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_issued_by_user_id
       ) then
        raise exception 'Issued-by user % does not exist in public.app_users', p_issued_by_user_id;
    end if;

    if p_reset_mode not in ('email_link', 'admin_reset') then
        raise exception 'Invalid reset_mode: %', p_reset_mode;
    end if;

    update public.app_user_reset_tokens
    set
        is_active = false,
        updated_at = now()
    where user_id = p_user_id
      and is_active = true
      and used_at is null;

    insert into public.app_user_reset_tokens (
        user_id,
        token_hash,
        reset_mode,
        issued_at,
        expires_at,
        is_active,
        issued_by_user_id,
        notes,
        created_at,
        updated_at
    )
    values (
        p_user_id,
        p_token_hash,
        p_reset_mode,
        p_issued_at,
        p_issued_at + interval '72 hours',
        true,
        p_issued_by_user_id,
        p_notes,
        now(),
        now()
    )
    returning id into v_token_id;

    return v_token_id;
end;
$$;


ALTER FUNCTION "public"."create_reset_token_state"("p_user_id" "uuid", "p_token_hash" "text", "p_reset_mode" "text", "p_issued_by_user_id" "uuid", "p_issued_at" timestamp with time zone, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_billing_amount" numeric, "p_billing_tax_amount" numeric DEFAULT 0, "p_billing_start_time" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_billing_paid_through_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_customer_phone" "text" DEFAULT NULL::"text", "p_customer_email" "text" DEFAULT NULL::"text", "p_customer_flags" "jsonb" DEFAULT NULL::"jsonb", "p_customer_internal_notes" "text" DEFAULT NULL::"text", "p_reservation_type" "text" DEFAULT 'rental'::"text", "p_reservation_status" "text" DEFAULT 'quote'::"text", "p_reservation_notes" "text" DEFAULT NULL::"text", "p_service_advisor" "text" DEFAULT NULL::"text", "p_ro_number" "text" DEFAULT NULL::"text", "p_pay_type" "text" DEFAULT 'customer'::"text", "p_vehicle_location" "text" DEFAULT NULL::"text", "p_vehicle_notes" "text" DEFAULT NULL::"text", "p_vehicle_status" "text" DEFAULT 'available'::"text", "p_vehicle_recon_status" "text" DEFAULT 'clean'::"text", "p_billing_line_type" "text" DEFAULT 'initial_assignment'::"text", "p_billing_source_rule" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_execution_result jsonb;
    v_reservation_id uuid;
    v_unified_payload jsonb;
begin
    v_execution_result := public.create_start_and_bill_case_with_vehicle_by_vin_state(
        p_tekion_customer_number,
        p_customer_name,
        p_start_date,
        p_expected_return_datetime,
        p_requested_model,
        p_vehicle_vin,
        p_vehicle_stock_number,
        p_vehicle_model,
        p_vehicle_fleet_type,
        p_vehicle_mileage,
        p_vehicle_current_tag,
        p_vehicle_fleet_conversion_type,
        p_actual_out_at,
        p_billing_amount,
        coalesce(p_billing_tax_amount, 0),
        p_billing_start_time,
        p_billing_paid_through_at,
        p_customer_phone,
        p_customer_email,
        p_customer_flags,
        p_customer_internal_notes,
        p_reservation_type,
        p_reservation_status,
        p_reservation_notes,
        p_service_advisor,
        p_ro_number,
        p_pay_type,
        p_vehicle_location,
        p_vehicle_notes,
        p_vehicle_status,
        p_vehicle_recon_status,
        p_billing_line_type,
        p_billing_source_rule
    );

    v_reservation_id := (v_execution_result ->> 'reservation_id')::uuid;

    if v_reservation_id is null then
        raise exception 'Failed to extract reservation_id from create_start_and_bill_case result';
    end if;

    v_unified_payload := public.get_unified_case_payload_state(
        v_reservation_id
    );

    return jsonb_build_object(
        'status', 'full_case_created_started_billed_and_loaded',
        'reservation_id', v_reservation_id,
        'execution_result', v_execution_result,
        'unified_case_payload', v_unified_payload
    );
end;
$$;


ALTER FUNCTION "public"."create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_billing_amount" numeric, "p_billing_tax_amount" numeric, "p_billing_start_time" timestamp with time zone, "p_billing_paid_through_at" timestamp with time zone, "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text", "p_billing_line_type" "text", "p_billing_source_rule" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_start_and_bill_case_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_billing_amount" numeric, "p_billing_tax_amount" numeric DEFAULT 0, "p_billing_start_time" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_billing_paid_through_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_customer_phone" "text" DEFAULT NULL::"text", "p_customer_email" "text" DEFAULT NULL::"text", "p_customer_flags" "jsonb" DEFAULT NULL::"jsonb", "p_customer_internal_notes" "text" DEFAULT NULL::"text", "p_reservation_type" "text" DEFAULT 'rental'::"text", "p_reservation_status" "text" DEFAULT 'quote'::"text", "p_reservation_notes" "text" DEFAULT NULL::"text", "p_service_advisor" "text" DEFAULT NULL::"text", "p_ro_number" "text" DEFAULT NULL::"text", "p_pay_type" "text" DEFAULT 'customer'::"text", "p_vehicle_location" "text" DEFAULT NULL::"text", "p_vehicle_notes" "text" DEFAULT NULL::"text", "p_vehicle_status" "text" DEFAULT 'available'::"text", "p_vehicle_recon_status" "text" DEFAULT 'clean'::"text", "p_billing_line_type" "text" DEFAULT 'initial_assignment'::"text", "p_billing_source_rule" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_case_step jsonb;
    v_reservation_id uuid;
    v_billing_result jsonb;
begin
    if p_billing_amount is null or p_billing_amount < 0 then
        raise exception 'billing_amount must be non-negative';
    end if;

    if coalesce(p_billing_tax_amount, 0) < 0 then
        raise exception 'billing_tax_amount must be non-negative';
    end if;

    v_case_step := public.create_and_start_case_with_vehicle_by_vin_state(
        p_tekion_customer_number,
        p_customer_name,
        p_start_date,
        p_expected_return_datetime,
        p_requested_model,
        p_vehicle_vin,
        p_vehicle_stock_number,
        p_vehicle_model,
        p_vehicle_fleet_type,
        p_vehicle_mileage,
        p_vehicle_current_tag,
        p_vehicle_fleet_conversion_type,
        p_actual_out_at,
        p_customer_phone,
        p_customer_email,
        p_customer_flags,
        p_customer_internal_notes,
        p_reservation_type,
        p_reservation_status,
        p_reservation_notes,
        p_service_advisor,
        p_ro_number,
        p_pay_type,
        p_vehicle_location,
        p_vehicle_notes,
        p_vehicle_status,
        p_vehicle_recon_status
    );

    v_reservation_id := (v_case_step ->> 'reservation_id')::uuid;

    if v_reservation_id is null then
        raise exception 'Failed to extract reservation_id from create_and_start_case result';
    end if;

    v_billing_result := public.activate_case_billing_state(
        v_reservation_id,
        p_billing_amount,
        coalesce(p_billing_tax_amount, 0),
        p_billing_start_time,
        p_billing_paid_through_at,
        p_billing_line_type,
        p_billing_source_rule,
        null
    );

    return jsonb_build_object(
        'status', 'full_case_created_started_and_billed',
        'reservation_id', v_reservation_id,
        'case_step', v_case_step,
        'billing_step', v_billing_result
    );
end;
$$;


ALTER FUNCTION "public"."create_start_and_bill_case_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_billing_amount" numeric, "p_billing_tax_amount" numeric, "p_billing_start_time" timestamp with time zone, "p_billing_paid_through_at" timestamp with time zone, "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text", "p_billing_line_type" "text", "p_billing_source_rule" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_transportation_event_billing_line_state"("p_transportation_event_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric DEFAULT 0, "p_start_time" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_end_time" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_line_type" "text" DEFAULT 'initial_assignment'::"text", "p_paid_through_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_source_rule" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_te record;
    v_current_continuity record;
    v_reservation_id uuid := null;
    v_start_time timestamptz;
    v_result jsonb;
begin
    select *
    into v_te
    from public.transportation_events
    where id = p_transportation_event_id
    for update;

    if not found then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    if p_pay_type is null or btrim(p_pay_type) = '' then
        raise exception 'pay_type cannot be blank';
    end if;

    if p_amount is null or p_amount < 0 then
        raise exception 'amount must be non-negative';
    end if;

    if coalesce(p_tax_amount, 0) < 0 then
        raise exception 'tax_amount must be non-negative';
    end if;

    if v_te.source_type = 'reservation'
       and v_te.source_id is not null
       and exists (
            select 1
            from public.reservations
            where id = v_te.source_id
       ) then
        v_reservation_id := v_te.source_id;
    end if;

    v_start_time := coalesce(p_start_time, now());

    select *
    into v_current_continuity
    from public.v_current_vehicle_continuity
    where transportation_event_id = p_transportation_event_id
    limit 1;

    v_result := public.create_billing_parent_line_state(
        p_transportation_event_id,
        v_reservation_id,
        v_current_continuity.vehicle_id,
        p_pay_type,
        p_amount,
        coalesce(p_tax_amount, 0),
        v_start_time,
        p_end_time,
        p_source_rule,
        v_current_continuity.vehicle_event_id,
        v_current_continuity.contract_period_id,
        p_line_type,
        null,
        null,
        null,
        true,
        p_paid_through_at,
        null,
        null,
        null
    );

    return jsonb_build_object(
        'status', 'transportation_event_billing_line_created',
        'transportation_event_id', p_transportation_event_id,
        'reservation_id', v_reservation_id,
        'billing_result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."create_transportation_event_billing_line_state"("p_transportation_event_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_line_type" "text", "p_paid_through_at" timestamp with time zone, "p_source_rule" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_transportation_event_state"("p_source_type" "text", "p_source_id" "uuid" DEFAULT NULL::"uuid", "p_customer_id" "uuid" DEFAULT NULL::"uuid", "p_expected_return_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_notes" "text" DEFAULT NULL::"text", "p_status" "text" DEFAULT 'active'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_id uuid;
begin
    if p_source_type is null or btrim(p_source_type) = '' then
        raise exception 'source_type cannot be blank';
    end if;

    if p_status is null or btrim(p_status) = '' then
        raise exception 'status cannot be blank';
    end if;

    if p_customer_id is not null
       and not exists (
            select 1
            from public.customers
            where id = p_customer_id
       ) then
        raise exception 'Customer % does not exist', p_customer_id;
    end if;

    insert into public.transportation_events (
        source_type,
        source_id,
        status,
        notes,
        customer_id,
        updated_at,
        closed_at,
        closed_by,
        expected_return_at
    )
    values (
        p_source_type,
        p_source_id,
        p_status,
        p_notes,
        p_customer_id,
        now(),
        null,
        null,
        p_expected_return_at
    )
    returning id into v_id;

    return jsonb_build_object(
        'status', 'transportation_event_created',
        'transportation_event_id', v_id,
        'source_type', p_source_type,
        'source_id', p_source_id,
        'customer_id', p_customer_id,
        'expected_return_at', p_expected_return_at
    );
end;
$$;


ALTER FUNCTION "public"."create_transportation_event_state"("p_source_type" "text", "p_source_id" "uuid", "p_customer_id" "uuid", "p_expected_return_at" timestamp with time zone, "p_notes" "text", "p_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_vehicle_state"("p_vin" "text", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text", "p_status" "text" DEFAULT 'available'::"text", "p_recon_status" "text" DEFAULT 'clean'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_id uuid;
begin
    if p_vin is null or btrim(p_vin) = '' then
        raise exception 'vin cannot be blank';
    end if;

    if p_stock_number is null or btrim(p_stock_number) = '' then
        raise exception 'stock_number cannot be blank';
    end if;

    if p_model is null or btrim(p_model) = '' then
        raise exception 'model cannot be blank';
    end if;

    if p_fleet_type is null or btrim(p_fleet_type) = '' then
        raise exception 'fleet_type cannot be blank';
    end if;

    if p_current_tag is null or btrim(p_current_tag) = '' then
        raise exception 'current_tag cannot be blank';
    end if;

    if p_fleet_conversion_type is null or btrim(p_fleet_conversion_type) = '' then
        raise exception 'fleet_conversion_type cannot be blank';
    end if;

    if p_status is null or btrim(p_status) = '' then
        raise exception 'status cannot be blank';
    end if;

    if p_recon_status is null or btrim(p_recon_status) = '' then
        raise exception 'recon_status cannot be blank';
    end if;

    if p_mileage is null or p_mileage < 0 then
        raise exception 'mileage must be non-negative';
    end if;

    if exists (
        select 1
        from public.vehicles
        where vin = p_vin
    ) then
        raise exception 'vin % already exists', p_vin;
    end if;

    insert into public.vehicles (
        vin,
        stock_number,
        model,
        fleet_type,
        status,
        mileage,
        recon_status,
        current_tag,
        fleet_conversion_type,
        location,
        notes
    )
    values (
        p_vin,
        p_stock_number,
        p_model,
        p_fleet_type,
        p_status,
        p_mileage,
        p_recon_status,
        p_current_tag,
        p_fleet_conversion_type,
        p_location,
        p_notes
    )
    returning id into v_id;

    return jsonb_build_object(
        'status', 'vehicle_created',
        'vehicle_id', v_id,
        'vin', p_vin,
        'stock_number', p_stock_number
    );
end;
$$;


ALTER FUNCTION "public"."create_vehicle_state"("p_vin" "text", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text", "p_notes" "text", "p_status" "text", "p_recon_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_warranty_provider_state"("p_name" "text", "p_provider_type" "text", "p_default_daily_rate" numeric DEFAULT NULL::numeric, "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_id uuid;
begin
    if p_name is null or btrim(p_name) = '' then
        raise exception 'Provider name cannot be blank';
    end if;

    if p_provider_type is null or btrim(p_provider_type) = '' then
        raise exception 'Provider type cannot be blank';
    end if;

    if p_default_daily_rate is not null and p_default_daily_rate < 0 then
        raise exception 'Default daily rate cannot be negative';
    end if;

    insert into public.warranty_providers (
        name,
        provider_type,
        is_active,
        default_daily_rate,
        updated_at,
        notes
    )
    values (
        p_name,
        p_provider_type,
        true,
        p_default_daily_rate,
        now(),
        p_notes
    )
    returning id into v_id;

    return jsonb_build_object(
        'status', 'warranty_provider_created',
        'provider_id', v_id
    );
end;
$$;


ALTER FUNCTION "public"."create_warranty_provider_state"("p_name" "text", "p_provider_type" "text", "p_default_daily_rate" numeric, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_app_user_security_row"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    insert into public.app_user_security (user_id)
    values (new.id)
    on conflict (user_id) do nothing;

    return new;
end;
$$;


ALTER FUNCTION "public"."ensure_app_user_security_row"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_tax_child_line_state"("p_parent_billing_line_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_parent record;
    v_existing_tax_line record;
    v_tax_line_id uuid;
begin
    select *
    into v_parent
    from public.billing_lines
    where id = p_parent_billing_line_id
      and (line_type is distinct from 'tax')
    for update;

    if not found then
        raise exception 'Parent billing line % does not exist or is itself a tax line', p_parent_billing_line_id;
    end if;

    select *
    into v_existing_tax_line
    from public.billing_lines
    where parent_billing_line_id = p_parent_billing_line_id
      and line_type = 'tax'
    for update;

    -- No tax should remain
    if coalesce(v_parent.tax_amount, 0) <= 0 then
        if found then
            delete from public.billing_lines
            where id = v_existing_tax_line.id;

            return jsonb_build_object(
                'status', 'tax_child_removed',
                'parent_billing_line_id', p_parent_billing_line_id
            );
        end if;

        return jsonb_build_object(
            'status', 'no_tax_child_needed',
            'parent_billing_line_id', p_parent_billing_line_id
        );
    end if;

    -- Update existing child
    if found then
        update public.billing_lines
        set
            transportation_event_id = v_parent.transportation_event_id,
            reservation_id = v_parent.reservation_id,
            vehicle_id = v_parent.vehicle_id,
            vehicle_event_id = v_parent.vehicle_event_id,
            contract_period_id = v_parent.contract_period_id,
            pay_type = v_parent.pay_type,
            pay_type_rule_id = v_parent.pay_type_rule_id,
            amount = v_parent.tax_amount,
            tax_amount = 0,
            start_time = v_parent.start_time,
            end_time = v_parent.end_time,
            source_rule = v_parent.source_rule,
            is_open = v_parent.is_open,
            updated_at = now()
        where id = v_existing_tax_line.id;

        return jsonb_build_object(
            'status', 'tax_child_updated',
            'parent_billing_line_id', p_parent_billing_line_id,
            'tax_billing_line_id', v_existing_tax_line.id
        );
    end if;

    -- Create new child
    insert into public.billing_lines (
        transportation_event_id,
        reservation_id,
        vehicle_id,
        pay_type,
        amount,
        tax_amount,
        start_time,
        end_time,
        source_rule,
        vehicle_event_id,
        contract_period_id,
        pay_type_rule_id,
        line_type,
        parent_billing_line_id,
        warranty_provider_id,
        default_covered_days_snapshot,
        covered_days_override,
        is_open,
        updated_at,
        paid_through_at,
        extended_from_billing_line_id,
        default_daily_rate_snapshot,
        daily_rate_override
    )
    values (
        v_parent.transportation_event_id,
        v_parent.reservation_id,
        v_parent.vehicle_id,
        v_parent.pay_type,
        v_parent.tax_amount,
        0,
        v_parent.start_time,
        v_parent.end_time,
        v_parent.source_rule,
        v_parent.vehicle_event_id,
        v_parent.contract_period_id,
        v_parent.pay_type_rule_id,
        'tax',
        v_parent.id,
        v_parent.warranty_provider_id,
        v_parent.default_covered_days_snapshot,
        v_parent.covered_days_override,
        v_parent.is_open,
        now(),
        v_parent.paid_through_at,
        v_parent.extended_from_billing_line_id,
        v_parent.default_daily_rate_snapshot,
        v_parent.daily_rate_override
    )
    returning id into v_tax_line_id;

    return jsonb_build_object(
        'status', 'tax_child_created',
        'parent_billing_line_id', p_parent_billing_line_id,
        'tax_billing_line_id', v_tax_line_id
    );
end;
$$;


ALTER FUNCTION "public"."ensure_tax_child_line_state"("p_parent_billing_line_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_user_security_state"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist in public.app_users', p_user_id;
    end if;

    insert into public.app_user_security (user_id)
    values (p_user_id)
    on conflict (user_id) do nothing;
end;
$$;


ALTER FUNCTION "public"."ensure_user_security_state"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."escalate_dependency_to_critical_state"("p_dependency_id" "uuid", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_dep record;
begin
    select *
    into v_dep
    from public.reservation_vehicle_dependencies
    where id = p_dependency_id
    for update;

    if not found then
        raise exception 'Dependency % does not exist', p_dependency_id;
    end if;

    if p_actor_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_actor_user_id
       ) then
        raise exception 'Actor user % does not exist', p_actor_user_id;
    end if;

    update public.reservation_vehicle_dependencies
    set
        status = 'conflict',
        risk_level = 'critical',
        updated_by_user_id = p_actor_user_id,
        updated_at = now()
    where id = p_dependency_id;

    return jsonb_build_object(
        'status', 'dependency_escalated_to_critical',
        'dependency_id', p_dependency_id
    );
end;
$$;


ALTER FUNCTION "public"."escalate_dependency_to_critical_state"("p_dependency_id" "uuid", "p_actor_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."escalate_reservation_dependency_to_critical_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_dependency record;
    v_result jsonb;
begin
    if not exists (
        select 1
        from public.reservations
        where id = p_reservation_id
    ) then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_actor_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_actor_user_id
       ) then
        raise exception 'Actor user % does not exist', p_actor_user_id;
    end if;

    select *
    into v_dependency
    from public.reservation_vehicle_dependencies
    where reservation_id = p_reservation_id
      and status in ('pending_return', 'ready', 'conflict')
    order by updated_at desc nulls last, created_at desc nulls last
    limit 1
    for update;

    if not found then
        return jsonb_build_object(
            'status', 'no_active_dependency_for_reservation',
            'reservation_id', p_reservation_id
        );
    end if;

    v_result := public.escalate_dependency_to_critical_state(
        v_dependency.id,
        p_actor_user_id
    );

    return jsonb_build_object(
        'status', 'reservation_dependency_escalated_to_critical',
        'reservation_id', p_reservation_id,
        'dependency_id', v_dependency.id,
        'escalation_result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."escalate_reservation_dependency_to_critical_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."escalate_transportation_event_dependency_to_critical_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_te record;
    v_result jsonb;
begin
    select *
    into v_te
    from public.transportation_events
    where id = p_transportation_event_id
    limit 1;

    if not found then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    if v_te.source_type is distinct from 'reservation' or v_te.source_id is null then
        return jsonb_build_object(
            'status', 'transportation_event_not_reservation_sourced',
            'transportation_event_id', p_transportation_event_id
        );
    end if;

    v_result := public.escalate_reservation_dependency_to_critical_state(
        v_te.source_id,
        p_actor_user_id
    );

    return jsonb_build_object(
        'status', 'transportation_event_dependency_escalated_to_critical',
        'transportation_event_id', p_transportation_event_id,
        'reservation_id', v_te.source_id,
        'escalation_result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."escalate_transportation_event_dependency_to_critical_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_active_late_fee_rules_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'late_fee_rule_id', late_fee_rule_id,
                'sort_order', sort_order,
                'rule_kind', rule_kind,
                'threshold_unit', threshold_unit,
                'threshold_value', threshold_value,
                'fee_amount', fee_amount,
                'description', description
            )
            order by sort_order asc, late_fee_rule_id
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_active_late_fee_rules;

    return jsonb_build_object(
        'status', 'active_late_fee_rules_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_active_late_fee_rules_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_admin_setting_permission_requirement_state"("p_setting_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    if p_setting_key is null or btrim(p_setting_key) = '' then
        raise exception 'setting_key cannot be blank';
    end if;

    select *
    into v_row
    from public.v_admin_settings_catalog
    where setting_key = p_setting_key
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'admin_setting_not_found',
            'setting_key', p_setting_key
        );
    end if;

    return jsonb_build_object(
        'status', 'admin_setting_permission_requirement_ready',
        'setting_key', v_row.setting_key,
        'required_permission', v_row.required_permission,
        'has_permission_requirement', v_row.has_permission_requirement
    );
end;
$$;


ALTER FUNCTION "public"."get_admin_setting_permission_requirement_state"("p_setting_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_admin_settings_catalog_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'admin_setting_id', admin_setting_id,
                'setting_key', setting_key,
                'setting_value', setting_value,
                'description', description,
                'required_permission', required_permission,
                'has_permission_requirement', has_permission_requirement
            )
            order by setting_key asc
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_admin_settings_catalog;

    return jsonb_build_object(
        'status', 'admin_settings_catalog_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_admin_settings_catalog_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_approved_network_match_state"("p_request_ip" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_ip inet;
    v_match record;
begin
    if p_request_ip is null or btrim(p_request_ip) = '' then
        raise exception 'Request IP cannot be blank';
    end if;

    begin
        v_ip := p_request_ip::inet;
    exception
        when others then
            raise exception 'Invalid request IP value: %', p_request_ip;
    end;

    select
        an.id,
        an.label,
        an.network_value,
        an.network_type
    into v_match
    from public.v_active_approved_networks an
    where (
            an.network_type = 'single_ip'
            and v_ip = an.network_value::inet
          )
       or (
            an.network_type = 'cidr'
            and (
                v_ip << an.network_value::cidr
                or v_ip = an.network_value::inet
            )
          )
    order by an.label asc, an.id
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'no_approved_network_match',
            'request_ip', p_request_ip,
            'matched', false
        );
    end if;

    return jsonb_build_object(
        'status', 'approved_network_match_found',
        'request_ip', p_request_ip,
        'matched', true,
        'approved_network_id', v_match.id,
        'label', v_match.label,
        'network_value', v_match.network_value,
        'network_type', v_match.network_type
    );
end;
$$;


ALTER FUNCTION "public"."get_approved_network_match_state"("p_request_ip" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_approved_networks_state"("p_active_only" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'id', an.id,
                'label', an.label,
                'network_value', an.network_value,
                'network_type', an.network_type,
                'is_active', an.is_active,
                'notes', an.notes,
                'created_at', an.created_at,
                'updated_at', an.updated_at,
                'created_by_user_id', an.created_by_user_id,
                'updated_by_user_id', an.updated_by_user_id
            )
            order by an.label asc, an.id
        ),
        '[]'::jsonb
    )
    into v_items
    from public.approved_networks an
    where (p_active_only = false or an.is_active = true);

    return jsonb_build_object(
        'status', 'approved_networks_ready',
        'active_only', p_active_only,
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_approved_networks_state"("p_active_only" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_auth_security_policy_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_auth_security_policy_state
    limit 1;

    return jsonb_build_object(
        'status', 'auth_security_policy_ready',
        'mfa_required_for_all_users', v_row.mfa_required_for_all_users,
        'network_restriction_enabled', v_row.network_restriction_enabled,
        'email_password_reset_link_enabled', v_row.email_password_reset_link_enabled,
        'reservation_vin_lock_lead_days', v_row.reservation_vin_lock_lead_days,
        'late_fees_enabled', v_row.late_fees_enabled
    );
end;
$$;


ALTER FUNCTION "public"."get_auth_security_policy_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_billing_dependency_banner_state"("p_transportation_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_current record;
    v_dep record;
begin
    if not exists (
        select 1
        from public.transportation_events
        where id = p_transportation_event_id
    ) then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    select *
    into v_current
    from public.v_current_vehicle_continuity
    where transportation_event_id = p_transportation_event_id
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'banner_none',
            'transportation_event_id', p_transportation_event_id
        );
    end if;

    select *
    into v_dep
    from public.v_upcoming_rental_dependency_feed
    where vehicle_id = v_current.vehicle_id
    order by
        case
            when risk_level = 'critical' then 1
            when risk_level = 'must_return' then 2
            when risk_level = 'at_risk' then 3
            when risk_level = 'depends_on_return' then 4
            else 5
        end,
        reservation_start_at asc nulls last
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'banner_none',
            'transportation_event_id', p_transportation_event_id
        );
    end if;

    return jsonb_build_object(
        'status',
            case
                when v_dep.risk_level = 'critical' then 'banner_critical'
                when v_dep.risk_level = 'must_return' then 'banner_must_return'
                when v_dep.risk_level = 'at_risk' then 'banner_at_risk'
                when v_dep.risk_level = 'depends_on_return' then 'banner_depends_on_return'
                else 'banner_none'
            end,
        'transportation_event_id', p_transportation_event_id,
        'vehicle_id', v_current.vehicle_id,
        'dependency_id', v_dep.dependency_id,
        'reservation_id', v_dep.reservation_id,
        'reservation_start_at', v_dep.reservation_start_at,
        'reservation_end_at', v_dep.reservation_end_at,
        'requested_model', v_dep.requested_model,
        'reservation_type', v_dep.reservation_type,
        'reservation_status', v_dep.reservation_status,
        'reservation_notes', v_dep.reservation_notes,
        'reservation_payload', v_dep.reservation_payload,
        'dependency_type', v_dep.dependency_type,
        'risk_level', v_dep.risk_level,
        'expected_return_snapshot', v_dep.expected_return_snapshot,
        'conflict_id', v_dep.conflict_id,
        'conflict_severity', v_dep.conflict_severity,
        'conflict_message', v_dep.conflict_message
    );
end;
$$;


ALTER FUNCTION "public"."get_billing_dependency_banner_state"("p_transportation_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_billing_rule_catalog_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_pay_types jsonb;
    v_over_due jsonb;
    v_late_fees jsonb;
    v_ew_rules jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'pay_type_rule_id', pay_type_rule_id,
                'pay_type', pay_type,
                'is_active', is_active,
                'is_taxable', is_taxable,
                'default_daily_amount', default_daily_amount,
                'sort_order', sort_order,
                'description', description
            )
            order by sort_order asc, pay_type
        ),
        '[]'::jsonb
    )
    into v_pay_types
    from public.v_current_pay_type_rules;

    begin
        v_over_due := public.resolve_over_due_pay_type_default_state();
    exception
        when others then
            v_over_due := jsonb_build_object(
                'status', 'over_due_not_available'
            );
    end;

    v_late_fees := public.get_active_late_fee_rules_state();

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'provider_id', provider_id,
                'provider_name', provider_name,
                'provider_type', provider_type,
                'provider_default_daily_rate', provider_default_daily_rate,
                'rule_id', rule_id,
                'covered_days', covered_days,
                'requires_approval', requires_approval,
                'rule_daily_rate', rule_daily_rate,
                'resolved_daily_rate', resolved_daily_rate
            )
            order by provider_name asc, rule_id
        ),
        '[]'::jsonb
    )
    into v_ew_rules
    from public.v_active_extended_warranty_provider_rules;

    return jsonb_build_object(
        'status', 'billing_rule_catalog_ready',
        'pay_type_rules', v_pay_types,
        'over_due', v_over_due,
        'late_fee_rules', v_late_fees,
        'extended_warranty_provider_rules', v_ew_rules
    );
end;
$$;


ALTER FUNCTION "public"."get_billing_rule_catalog_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_calendar_dependency_badges_state"("p_range_start" timestamp with time zone, "p_range_end" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_rows jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'dependency_id', f.dependency_id,
                'reservation_id', f.reservation_id,
                'reservation_start_at', f.reservation_start_at,
                'reservation_end_at', f.reservation_end_at,
                'requested_model', f.requested_model,
                'reservation_type', f.reservation_type,
                'reservation_status', f.reservation_status,
                'reservation_notes', f.reservation_notes,
                'reservation_payload', f.reservation_payload,
                'vehicle_id', f.vehicle_id,
                'dependency_type', f.dependency_type,
                'dependency_status', f.dependency_status,
                'risk_level', f.risk_level,
                'badge_state',
                    case
                        when f.risk_level = 'critical' or f.dependency_status = 'conflict' then 'critical'
                        when f.dependency_type = 'hard_lock' and f.dependency_status = 'ready' then 'hard_lock'
                        when f.risk_level = 'must_return' then 'must_return'
                        when f.risk_level = 'depends_on_return' then 'depends_on_return'
                        when f.dependency_type = 'soft_lock' and f.dependency_status = 'ready' then 'soft_lock'
                        else 'ready'
                    end
            )
            order by f.reservation_start_at asc nulls last
        ),
        '[]'::jsonb
    )
    into v_rows
    from public.v_upcoming_rental_dependency_feed f
    where (
            f.reservation_start_at is null
            or f.reservation_start_at <= p_range_end
          )
      and (
            f.reservation_end_at is null
            or f.reservation_end_at >= p_range_start
          );

    return jsonb_build_object(
        'status', 'calendar_dependency_badges_ready',
        'range_start', p_range_start,
        'range_end', p_range_end,
        'items', v_rows
    );
end;
$$;


ALTER FUNCTION "public"."get_calendar_dependency_badges_state"("p_range_start" timestamp with time zone, "p_range_end" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_case_activation_list_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            to_jsonb(x)
            order by x.start_date asc nulls last, x.reservation_id
        ),
        '[]'::jsonb
    )
    into v_items
    from (
        select
            reservation_id,
            transportation_event_id,
            reservation_vehicle_id,
            start_date,
            expected_return_datetime,
            reservation_status,
            reservation_type,
            requested_model,
            reservation_pay_type,
            customer_id,
            current_vehicle_event_id,
            current_continuity_vehicle_id,
            current_contract_period_id,
            actual_out_at,
            contract_out_at,
            vehicle_event_is_open,
            contract_period_is_open,
            parent_billing_line_id,
            billing_pay_type,
            parent_amount,
            parent_tax_amount,
            billing_start_time,
            billing_end_time,
            paid_through_at,
            billing_is_open,
            has_active_continuity,
            has_open_billing_line
        from public.v_case_activation_state
    ) x;

    return jsonb_build_object(
        'status', 'case_activation_list_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_case_activation_list_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_case_candidate_dashboard_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_activation jsonb;
    v_continuation jsonb;
    v_reassignment jsonb;
    v_completion jsonb;
begin
    v_activation := public.get_case_activation_list_state();
    v_continuation := public.get_case_continuation_list_state();
    v_reassignment := public.get_case_reassignment_list_state();
    v_completion := public.get_case_completion_list_state();

    return jsonb_build_object(
        'status', 'case_candidate_dashboard_ready',
        'activation', v_activation,
        'continuation', v_continuation,
        'reassignment', v_reassignment,
        'completion', v_completion
    );
end;
$$;


ALTER FUNCTION "public"."get_case_candidate_dashboard_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_case_completion_candidate_state"("p_reservation_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_case_completion_candidate_state
    where reservation_id = p_reservation_id
    limit 1;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    return jsonb_build_object(
        'status', 'case_completion_candidate_state_ready',
        'reservation_id', v_row.reservation_id,
        'transportation_event_id', v_row.transportation_event_id,
        'reservation_vehicle_id', v_row.reservation_vehicle_id,
        'start_date', v_row.start_date,
        'expected_return_datetime', v_row.expected_return_datetime,
        'reservation_status', v_row.reservation_status,
        'reservation_type', v_row.reservation_type,
        'reservation_notes', v_row.reservation_notes,
        'actual_return_datetime', v_row.actual_return_datetime,
        'billed_through_datetime', v_row.billed_through_datetime,
        'customer_id', v_row.customer_id,
        'transportation_event_status', v_row.transportation_event_status,
        'expected_return_at', v_row.expected_return_at,
        'closed_at', v_row.closed_at,
        'closed_by', v_row.closed_by,
        'vehicle_event_id', v_row.vehicle_event_id,
        'contract_period_id', v_row.contract_period_id,
        'actual_out_at', v_row.actual_out_at,
        'actual_in_at', v_row.actual_in_at,
        'vehicle_event_is_open', v_row.vehicle_event_is_open,
        'contract_period_is_open', v_row.contract_period_is_open,
        'parent_billing_line_id', v_row.parent_billing_line_id,
        'billing_start_time', v_row.billing_start_time,
        'billing_end_time', v_row.billing_end_time,
        'paid_through_at', v_row.paid_through_at,
        'billing_is_open', v_row.billing_is_open,
        'has_active_continuity', v_row.has_active_continuity,
        'has_open_billing_line', v_row.has_open_billing_line
    );
end;
$$;


ALTER FUNCTION "public"."get_case_completion_candidate_state"("p_reservation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_case_completion_list_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            to_jsonb(x)
            order by x.start_date asc nulls last, x.reservation_id
        ),
        '[]'::jsonb
    )
    into v_items
    from (
        select
            reservation_id,
            transportation_event_id,
            reservation_vehicle_id,
            start_date,
            expected_return_datetime,
            reservation_status,
            reservation_type,
            reservation_notes,
            actual_return_datetime,
            billed_through_datetime,
            customer_id,
            transportation_event_status,
            expected_return_at,
            closed_at,
            closed_by,
            vehicle_event_id,
            contract_period_id,
            actual_out_at,
            actual_in_at,
            vehicle_event_is_open,
            contract_period_is_open,
            parent_billing_line_id,
            billing_start_time,
            billing_end_time,
            paid_through_at,
            billing_is_open,
            has_active_continuity,
            has_open_billing_line
        from public.v_case_completion_candidate_state
    ) x;

    return jsonb_build_object(
        'status', 'case_completion_list_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_case_completion_list_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_case_continuation_candidate_state"("p_reservation_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_case_continuation_candidate_state
    where reservation_id = p_reservation_id
    limit 1;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    return jsonb_build_object(
        'status', 'case_continuation_candidate_state_ready',
        'reservation_id', v_row.reservation_id,
        'transportation_event_id', v_row.transportation_event_id,
        'reservation_vehicle_id', v_row.reservation_vehicle_id,
        'start_date', v_row.start_date,
        'expected_return_datetime', v_row.expected_return_datetime,
        'reservation_status', v_row.reservation_status,
        'reservation_type', v_row.reservation_type,
        'requested_model', v_row.requested_model,
        'customer_id', v_row.customer_id,
        'actual_return_datetime', v_row.actual_return_datetime,
        'billed_through_datetime', v_row.billed_through_datetime,
        'current_vehicle_event_id', v_row.current_vehicle_event_id,
        'current_continuity_vehicle_id', v_row.current_continuity_vehicle_id,
        'current_contract_period_id', v_row.current_contract_period_id,
        'actual_out_at', v_row.actual_out_at,
        'actual_in_at', v_row.actual_in_at,
        'contract_out_at', v_row.contract_out_at,
        'contract_in_at', v_row.contract_in_at,
        'renewal_sequence', v_row.renewal_sequence,
        'vehicle_event_is_open', v_row.vehicle_event_is_open,
        'contract_period_is_open', v_row.contract_period_is_open,
        'reservation_has_assigned_vehicle', v_row.reservation_has_assigned_vehicle,
        'has_active_continuity', v_row.has_active_continuity
    );
end;
$$;


ALTER FUNCTION "public"."get_case_continuation_candidate_state"("p_reservation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_case_continuation_list_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            to_jsonb(x)
            order by x.start_date asc nulls last, x.reservation_id
        ),
        '[]'::jsonb
    )
    into v_items
    from (
        select
            reservation_id,
            transportation_event_id,
            reservation_vehicle_id,
            start_date,
            expected_return_datetime,
            reservation_status,
            reservation_type,
            requested_model,
            customer_id,
            actual_return_datetime,
            billed_through_datetime,
            current_vehicle_event_id,
            current_continuity_vehicle_id,
            current_contract_period_id,
            actual_out_at,
            actual_in_at,
            contract_out_at,
            contract_in_at,
            renewal_sequence,
            vehicle_event_is_open,
            contract_period_is_open,
            reservation_has_assigned_vehicle,
            has_active_continuity
        from public.v_case_continuation_candidate_state
    ) x;

    return jsonb_build_object(
        'status', 'case_continuation_list_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_case_continuation_list_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_case_reassignment_candidate_state"("p_reservation_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_case_reassignment_candidate_state
    where reservation_id = p_reservation_id
    limit 1;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    return jsonb_build_object(
        'status', 'case_reassignment_candidate_state_ready',
        'reservation_id', v_row.reservation_id,
        'transportation_event_id', v_row.transportation_event_id,
        'reservation_vehicle_id', v_row.reservation_vehicle_id,
        'start_date', v_row.start_date,
        'expected_return_datetime', v_row.expected_return_datetime,
        'reservation_status', v_row.reservation_status,
        'reservation_type', v_row.reservation_type,
        'requested_model', v_row.requested_model,
        'customer_id', v_row.customer_id,
        'current_vehicle_event_id', v_row.current_vehicle_event_id,
        'current_continuity_vehicle_id', v_row.current_continuity_vehicle_id,
        'current_contract_period_id', v_row.current_contract_period_id,
        'actual_out_at', v_row.actual_out_at,
        'contract_out_at', v_row.contract_out_at,
        'vehicle_event_is_open', v_row.vehicle_event_is_open,
        'contract_period_is_open', v_row.contract_period_is_open,
        'current_dependency_id', v_row.current_dependency_id,
        'current_dependency_type', v_row.current_dependency_type,
        'current_dependency_status', v_row.current_dependency_status,
        'current_dependency_risk_level', v_row.current_dependency_risk_level,
        'current_dependency_expected_return_snapshot', v_row.current_dependency_expected_return_snapshot,
        'has_active_continuity', v_row.has_active_continuity,
        'reservation_has_assigned_vehicle', v_row.reservation_has_assigned_vehicle
    );
end;
$$;


ALTER FUNCTION "public"."get_case_reassignment_candidate_state"("p_reservation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_case_reassignment_list_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            to_jsonb(x)
            order by x.start_date asc nulls last, x.reservation_id
        ),
        '[]'::jsonb
    )
    into v_items
    from (
        select
            reservation_id,
            transportation_event_id,
            reservation_vehicle_id,
            start_date,
            expected_return_datetime,
            reservation_status,
            reservation_type,
            requested_model,
            customer_id,
            current_vehicle_event_id,
            current_continuity_vehicle_id,
            current_contract_period_id,
            actual_out_at,
            contract_out_at,
            vehicle_event_is_open,
            contract_period_is_open,
            current_dependency_id,
            current_dependency_type,
            current_dependency_status,
            current_dependency_risk_level,
            current_dependency_expected_return_snapshot,
            has_active_continuity,
            reservation_has_assigned_vehicle
        from public.v_case_reassignment_candidate_state
    ) x;

    return jsonb_build_object(
        'status', 'case_reassignment_list_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_case_reassignment_list_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_ctp_monitoring_policy_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_ctp_monitoring_policy_state
    limit 1;

    return jsonb_build_object(
        'status', 'ctp_monitoring_policy_ready',
        'preferred_max_ctp_days', v_row.preferred_max_ctp_days,
        'preferred_max_ctp_qualified_miles', v_row.preferred_max_ctp_qualified_miles
    );
end;
$$;


ALTER FUNCTION "public"."get_ctp_monitoring_policy_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_current_reservation_dependency_state"("p_reservation_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_dep record;
begin
    select *
    into v_dep
    from public.reservation_vehicle_dependencies
    where reservation_id = p_reservation_id
      and status in ('pending_return', 'ready', 'conflict')
    order by updated_at desc nulls last, created_at desc nulls last
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'no_active_dependency',
            'reservation_id', p_reservation_id
        );
    end if;

    return jsonb_build_object(
        'status', 'active_dependency_found',
        'dependency_id', v_dep.id,
        'reservation_id', v_dep.reservation_id,
        'vehicle_id', v_dep.vehicle_id,
        'source_transportation_event_id', v_dep.source_transportation_event_id,
        'dependency_type', v_dep.dependency_type,
        'dependency_status', v_dep.status,
        'risk_level', v_dep.risk_level,
        'expected_return_snapshot', v_dep.expected_return_snapshot
    );
end;
$$;


ALTER FUNCTION "public"."get_current_reservation_dependency_state"("p_reservation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_customer_by_tekion_customer_number_state"("p_tekion_customer_number" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    if p_tekion_customer_number is null or btrim(p_tekion_customer_number) = '' then
        raise exception 'tekion_customer_number cannot be blank';
    end if;

    select *
    into v_row
    from public.v_customer_operational_state
    where tekion_customer_number = p_tekion_customer_number
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'customer_not_found',
            'tekion_customer_number', p_tekion_customer_number
        );
    end if;

    return jsonb_build_object(
        'status', 'customer_found',
        'customer_id', v_row.customer_id,
        'created_at', v_row.created_at,
        'tekion_customer_number', v_row.tekion_customer_number,
        'name', v_row.name,
        'phone', v_row.phone,
        'email', v_row.email,
        'flags', v_row.flags,
        'internal_notes', v_row.internal_notes
    );
end;
$$;


ALTER FUNCTION "public"."get_customer_by_tekion_customer_number_state"("p_tekion_customer_number" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_customer_operational_aggregate_list_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'customer_id', customer_id,
                'created_at', created_at,
                'tekion_customer_number', tekion_customer_number,
                'name', name,
                'phone', phone,
                'email', email,
                'flags', flags,
                'internal_notes', internal_notes,
                'reservation_count', reservation_count,
                'non_cancelled_reservation_count', non_cancelled_reservation_count,
                'transportation_event_count', transportation_event_count,
                'active_transportation_event_count', active_transportation_event_count,
                'open_vehicle_continuity_count', open_vehicle_continuity_count,
                'latest_expected_return_at', latest_expected_return_at
            )
            order by name asc, customer_id
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_customer_operational_aggregate_state;

    return jsonb_build_object(
        'status', 'customer_operational_aggregate_list_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_customer_operational_aggregate_list_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_customer_operational_list_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'customer_id', customer_id,
                'created_at', created_at,
                'tekion_customer_number', tekion_customer_number,
                'name', name,
                'phone', phone,
                'email', email,
                'flags', flags,
                'internal_notes', internal_notes
            )
            order by name asc, customer_id
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_customer_operational_state;

    return jsonb_build_object(
        'status', 'customer_operational_list_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_customer_operational_list_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_customer_operational_payload_state"("p_customer_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_customer_base jsonb;
    v_summary record;
    v_reservations jsonb;
    v_transportation_events jsonb;
begin
    select *
    into v_summary
    from public.v_customer_operational_aggregate_state
    where customer_id = p_customer_id
    limit 1;

    if not found then
        raise exception 'Customer % does not exist', p_customer_id;
    end if;

    v_customer_base := public.get_customer_operational_state(
        p_customer_id
    );

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'reservation_id', r.reservation_id,
                'transportation_event_id', r.transportation_event_id,
                'vehicle_id', r.vehicle_id,
                'start_date', r.start_date,
                'expected_return_datetime', r.expected_return_datetime,
                'reservation_status', r.reservation_status,
                'reservation_type', r.reservation_type,
                'reservation_notes', r.reservation_notes,
                'cancellation_reason', r.cancellation_reason,
                'requested_model', r.requested_model,
                'service_advisor', r.service_advisor,
                'ro_number', r.ro_number,
                'pay_type', r.pay_type,
                'actual_return_datetime', r.actual_return_datetime,
                'billed_through_datetime', r.billed_through_datetime
            )
            order by r.start_date asc nulls last, r.reservation_id
        ),
        '[]'::jsonb
    )
    into v_reservations
    from public.v_reservation_transportation_link_state r
    where r.customer_id = p_customer_id;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'transportation_event_id', te.transportation_event_id,
                'source_type', te.source_type,
                'source_id', te.source_id,
                'transportation_event_status', te.transportation_event_status,
                'customer_id', te.customer_id,
                'expected_return_at', te.expected_return_at,
                'closed_at', te.closed_at,
                'vehicle_event_id', te.vehicle_event_id,
                'vehicle_id', te.vehicle_id,
                'contract_period_id', te.contract_period_id,
                'actual_out_at', te.actual_out_at,
                'actual_in_at', te.actual_in_at,
                'vehicle_event_is_open', te.vehicle_event_is_open,
                'ended_reason', te.ended_reason,
                'contract_out_at', te.contract_out_at,
                'contract_in_at', te.contract_in_at,
                'renewal_sequence', te.renewal_sequence,
                'contract_period_is_open', te.contract_period_is_open
            )
            order by te.expected_return_at asc nulls last, te.transportation_event_id
        ),
        '[]'::jsonb
    )
    into v_transportation_events
    from public.v_transportation_event_operational_state te
    where te.customer_id = p_customer_id;

    return jsonb_build_object(
        'status', 'customer_operational_payload_ready',
        'customer_id', p_customer_id,
        'customer_base', v_customer_base,
        'summary', jsonb_build_object(
            'reservation_count', v_summary.reservation_count,
            'non_cancelled_reservation_count', v_summary.non_cancelled_reservation_count,
            'transportation_event_count', v_summary.transportation_event_count,
            'active_transportation_event_count', v_summary.active_transportation_event_count,
            'open_vehicle_continuity_count', v_summary.open_vehicle_continuity_count,
            'latest_expected_return_at', v_summary.latest_expected_return_at
        ),
        'reservations', v_reservations,
        'transportation_events', v_transportation_events
    );
end;
$$;


ALTER FUNCTION "public"."get_customer_operational_payload_state"("p_customer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_customer_operational_state"("p_customer_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_customer_operational_state
    where customer_id = p_customer_id
    limit 1;

    if not found then
        raise exception 'Customer % does not exist', p_customer_id;
    end if;

    return jsonb_build_object(
        'status', 'customer_operational_state_ready',
        'customer_id', v_row.customer_id,
        'created_at', v_row.created_at,
        'tekion_customer_number', v_row.tekion_customer_number,
        'name', v_row.name,
        'phone', v_row.phone,
        'email', v_row.email,
        'flags', v_row.flags,
        'internal_notes', v_row.internal_notes
    );
end;
$$;


ALTER FUNCTION "public"."get_customer_operational_state"("p_customer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dashboard_payload_state"("p_user_id" "uuid", "p_lost_rentals_start_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_lost_rentals_end_at" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_access jsonb;
    v_payload jsonb := '{}'::jsonb;
begin
    v_access := public.get_dashboard_section_access_state(p_user_id);

    -- Warning Center
    if coalesce((v_access ->> 'view_dashboard_warning_center')::boolean, false) then
        v_payload := v_payload || jsonb_build_object(
            'warning_center_counts', public.get_warning_center_counts_state(),
            'warning_center_detail', public.get_warning_center_detail_state()
        );
    end if;

    -- Upcoming Rentals / Dependencies
    if coalesce((v_access ->> 'view_dashboard_upcoming_rentals')::boolean, false) then
        v_payload := v_payload || jsonb_build_object(
            'upcoming_rental_dependencies', public.get_upcoming_rental_dependency_feed_state()
        );
    end if;

    -- Lost Rentals
    if coalesce((v_access ->> 'view_dashboard_lost_rentals')::boolean, false) then
        v_payload := v_payload || jsonb_build_object(
            'lost_rentals_summary', public.get_lost_rentals_summary_state(
                p_lost_rentals_start_at,
                p_lost_rentals_end_at
            )
        );
    end if;

    -- Utilization
    if coalesce((v_access ->> 'view_dashboard_utilization')::boolean, false) then
        v_payload := v_payload || jsonb_build_object(
            'utilization_snapshot', public.get_utilization_snapshot_state()
        );
    end if;

    -- Warranty placeholder section visibility
    if coalesce((v_access ->> 'view_dashboard_warranty')::boolean, false) then
        v_payload := v_payload || jsonb_build_object(
            'warranty_section', jsonb_build_object('status', 'section_enabled')
        );
    end if;

    -- Conflicts placeholder section visibility
    if coalesce((v_access ->> 'view_dashboard_conflicts')::boolean, false) then
        v_payload := v_payload || jsonb_build_object(
            'conflict_section', jsonb_build_object('status', 'section_enabled')
        );
    end if;

    -- AI visibility
    if coalesce((v_access ->> 'view_dashboard_ai')::boolean, false) then
        v_payload := v_payload || jsonb_build_object(
            'ai_section', jsonb_build_object('status', 'section_enabled')
        );
    end if;

    return jsonb_build_object(
        'status', 'dashboard_payload_ready',
        'dashboard_access', v_access,
        'payload', v_payload
    );
end;
$$;


ALTER FUNCTION "public"."get_dashboard_payload_state"("p_user_id" "uuid", "p_lost_rentals_start_at" timestamp with time zone, "p_lost_rentals_end_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dashboard_section_access_state"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_has_dev boolean := false;
    v_has_admin boolean := false;
    v_permissions text[];
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    select exists (
        select 1
        from public.user_roles ur
        join public.roles r on r.id = ur.role_id
        where ur.user_id = p_user_id
          and r.role_name = 'Dev'
    ) into v_has_dev;

    select exists (
        select 1
        from public.user_roles ur
        join public.roles r on r.id = ur.role_id
        where ur.user_id = p_user_id
          and r.role_name = 'Admin'
    ) into v_has_admin;

    select coalesce(array_agg(permission_key), '{}'::text[])
    into v_permissions
    from public.v_user_effective_permissions
    where user_id = p_user_id;

    if v_has_dev then
        return jsonb_build_object(
            'view_dashboard_warning_center', true,
            'view_dashboard_upcoming_rentals', true,
            'view_dashboard_lost_rentals', true,
            'view_dashboard_utilization', true,
            'view_dashboard_warranty', true,
            'view_dashboard_conflicts', true,
            'view_dashboard_ai', true
        );
    end if;

    if v_has_admin then
        return jsonb_build_object(
            'view_dashboard_warning_center', true,
            'view_dashboard_upcoming_rentals', true,
            'view_dashboard_lost_rentals', true,
            'view_dashboard_utilization', true,
            'view_dashboard_warranty', true,
            'view_dashboard_conflicts', true,
            'view_dashboard_ai', false
        );
    end if;

    return jsonb_build_object(
        'view_dashboard_warning_center', 'view_dashboard_warning_center' = any(v_permissions),
        'view_dashboard_upcoming_rentals', 'view_dashboard_upcoming_rentals' = any(v_permissions),
        'view_dashboard_lost_rentals', 'view_dashboard_lost_rentals' = any(v_permissions),
        'view_dashboard_utilization', 'view_dashboard_utilization' = any(v_permissions),
        'view_dashboard_warranty', 'view_dashboard_warranty' = any(v_permissions),
        'view_dashboard_conflicts', 'view_dashboard_conflicts' = any(v_permissions),
        'view_dashboard_ai', 'view_dashboard_ai' = any(v_permissions)
    );
end;
$$;


ALTER FUNCTION "public"."get_dashboard_section_access_state"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_email_outbound_message_state"("p_email_outbound_message_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_email_outbound_message_state
    where email_outbound_message_id = p_email_outbound_message_id
    limit 1;

    if not found then
        raise exception 'Email outbound message % does not exist', p_email_outbound_message_id;
    end if;

    return jsonb_build_object(
        'status', 'email_outbound_message_state_ready',
        'email_outbound_message_id', v_row.email_outbound_message_id,
        'email_provider', v_row.email_provider,
        'message_type', v_row.message_type,
        'template_key', v_row.template_key,
        'related_user_id', v_row.related_user_id,
        'related_user_email', v_row.related_user_email,
        'related_user_full_name', v_row.related_user_full_name,
        'related_customer_id', v_row.related_customer_id,
        'related_customer_tekion_customer_number', v_row.related_customer_tekion_customer_number,
        'related_customer_name', v_row.related_customer_name,
        'related_customer_email', v_row.related_customer_email,
        'related_reservation_id', v_row.related_reservation_id,
        'related_transportation_event_id', v_row.related_transportation_event_id,
        'to_email', v_row.to_email,
        'from_email', v_row.from_email,
        'subject', v_row.subject,
        'provider_message_id', v_row.provider_message_id,
        'send_status', v_row.send_status,
        'provider_response', v_row.provider_response,
        'queued_at', v_row.queued_at,
        'sent_at', v_row.sent_at,
        'failed_at', v_row.failed_at,
        'last_event_at', v_row.last_event_at,
        'created_by_user_id', v_row.created_by_user_id,
        'created_by_email', v_row.created_by_email,
        'created_by_full_name', v_row.created_by_full_name
    );
end;
$$;


ALTER FUNCTION "public"."get_email_outbound_message_state"("p_email_outbound_message_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_frontend_safe_service_action_contracts_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            to_jsonb(x)
            order by x.action_group asc, x.action_key asc
        ),
        '[]'::jsonb
    )
    into v_items
    from (
        select
            service_action_contract_id,
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
        from public.v_service_action_contract_state
        where frontend_safe = true
          and internal_only = false
    ) x;

    return jsonb_build_object(
        'status', 'frontend_safe_service_action_contracts_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_frontend_safe_service_action_contracts_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_live_active_case_list_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            to_jsonb(x)
            order by x.start_date asc nulls last, x.reservation_id
        ),
        '[]'::jsonb
    )
    into v_items
    from (
        select
            reservation_id,
            transportation_event_id,
            vehicle_id,
            start_date,
            expected_return_datetime,
            reservation_status,
            reservation_type,
            requested_model,
            pay_type,
            customer_id,
            customer_name,
            tekion_customer_number,
            vin,
            stock_number,
            vehicle_model,
            vehicle_status,
            transportation_event_status,
            expected_return_at,
            closed_at,
            closed_by
        from public.v_live_active_case_state
    ) x;

    return jsonb_build_object(
        'status', 'live_active_case_list_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_live_active_case_list_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_login_network_gate_state_by_email"("p_email" "text", "p_request_ip" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_user_id uuid;
begin
    if p_email is null or btrim(p_email) = '' then
        raise exception 'Email cannot be blank';
    end if;

    select id
    into v_user_id
    from public.app_users
    where lower(email) = lower(p_email)
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'login_user_not_found',
            'email', p_email
        );
    end if;

    return public.get_network_gate_state(
        v_user_id,
        p_request_ip
    );
end;
$$;


ALTER FUNCTION "public"."get_login_network_gate_state_by_email"("p_email" "text", "p_request_ip" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_lost_rentals_summary_state"("p_start_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_end_at" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_count integer := 0;
    v_total_days integer := 0;
    v_total_estimated_revenue numeric := 0;
begin
    select
        count(*),
        coalesce(sum(coalesce(requested_duration_days, 0)), 0),
        coalesce(sum(coalesce(requested_duration_days, 0) * coalesce(quoted_daily_rate, 0)), 0)
    into
        v_count,
        v_total_days,
        v_total_estimated_revenue
    from public.lost_rentals lr
    where (p_start_at is null or lr.requested_at >= p_start_at)
      and (p_end_at is null or lr.requested_at <= p_end_at);

    return jsonb_build_object(
        'status', 'lost_rentals_summary_ready',
        'lost_rental_count', v_count,
        'total_requested_days', v_total_days,
        'total_estimated_revenue', v_total_estimated_revenue
    );
end;
$$;


ALTER FUNCTION "public"."get_lost_rentals_summary_state"("p_start_at" timestamp with time zone, "p_end_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_master_operational_dashboard_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_counts jsonb;
    v_customers jsonb;
    v_vehicles jsonb;
    v_reservations jsonb;
    v_transportation_events jsonb;
    v_case_candidates jsonb;
begin
    v_counts := public.get_operational_domain_counts_state();
    v_customers := public.get_customer_operational_aggregate_list_state();
    v_vehicles := public.get_vehicle_operational_aggregate_list_state();
    v_reservations := public.get_reservation_operational_list_payload_state();
    v_transportation_events := public.get_transportation_event_unified_operational_list_state();
    v_case_candidates := public.get_case_candidate_dashboard_state();

    return jsonb_build_object(
        'status', 'master_operational_dashboard_ready',
        'counts', v_counts,
        'customers', v_customers,
        'vehicles', v_vehicles,
        'reservations', v_reservations,
        'transportation_events', v_transportation_events,
        'case_candidates', v_case_candidates
    );
end;
$$;


ALTER FUNCTION "public"."get_master_operational_dashboard_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_network_gate_state"("p_user_id" "uuid", "p_request_ip" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_settings record;
    v_match_result jsonb;
    v_access_result jsonb;
    v_network_restriction_enabled boolean := false;
    v_match_found boolean := false;
    v_outside_network_access_allowed boolean := false;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    select *
    into v_settings
    from public.v_security_admin_settings_state
    limit 1;

    v_network_restriction_enabled := coalesce(v_settings.network_restriction_enabled, false);

    if not v_network_restriction_enabled then
        return jsonb_build_object(
            'status', 'network_gate_allowed',
            'network_restriction_enabled', false,
            'matched_approved_network', false,
            'outside_network_access_allowed', false
        );
    end if;

    v_match_result := public.get_approved_network_match_state(p_request_ip);
    v_match_found := coalesce((v_match_result ->> 'matched')::boolean, false);

    if v_match_found then
        return jsonb_build_object(
            'status', 'network_gate_allowed',
            'network_restriction_enabled', true,
            'matched_approved_network', true,
            'outside_network_access_allowed', false,
            'match_result', v_match_result
        );
    end if;

    v_access_result := public.get_user_outside_network_access_state(p_user_id);
    v_outside_network_access_allowed :=
        coalesce((v_access_result ->> 'outside_network_access_allowed')::boolean, false);

    if v_outside_network_access_allowed then
        return jsonb_build_object(
            'status', 'network_gate_allowed',
            'network_restriction_enabled', true,
            'matched_approved_network', false,
            'outside_network_access_allowed', true,
            'user_access_result', v_access_result
        );
    end if;

    return jsonb_build_object(
        'status', 'network_gate_blocked',
        'network_restriction_enabled', true,
        'matched_approved_network', false,
        'outside_network_access_allowed', false,
        'match_result', v_match_result,
        'user_access_result', v_access_result
    );
end;
$$;


ALTER FUNCTION "public"."get_network_gate_state"("p_user_id" "uuid", "p_request_ip" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_operational_domain_counts_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_operational_domain_counts
    limit 1;

    return jsonb_build_object(
        'status', 'operational_domain_counts_ready',
        'customer_count', v_row.customer_count,
        'vehicle_count', v_row.vehicle_count,
        'reservation_count', v_row.reservation_count,
        'transportation_event_count', v_row.transportation_event_count,
        'open_vehicle_event_count', v_row.open_vehicle_event_count,
        'open_contract_period_count', v_row.open_contract_period_count,
        'open_billing_line_count', v_row.open_billing_line_count,
        'unresolved_dependency_count', v_row.unresolved_dependency_count,
        'unresolved_conflict_count', v_row.unresolved_conflict_count,
        'transportation_event_note_count', v_row.transportation_event_note_count
    );
end;
$$;


ALTER FUNCTION "public"."get_operational_domain_counts_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_or_create_customer_state_by_tekion"("p_tekion_customer_number" "text", "p_name" "text", "p_phone" "text" DEFAULT NULL::"text", "p_email" "text" DEFAULT NULL::"text", "p_flags" "jsonb" DEFAULT NULL::"jsonb", "p_internal_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_existing jsonb;
    v_create_result jsonb;
begin
    if p_tekion_customer_number is null or btrim(p_tekion_customer_number) = '' then
        raise exception 'tekion_customer_number cannot be blank';
    end if;

    if p_name is null or btrim(p_name) = '' then
        raise exception 'name cannot be blank';
    end if;

    v_existing := public.get_customer_by_tekion_customer_number_state(
        p_tekion_customer_number
    );

    if (v_existing ->> 'status') = 'customer_found' then
        return jsonb_build_object(
            'status', 'customer_already_exists',
            'customer_state', v_existing
        );
    end if;

    v_create_result := public.create_customer_state(
        p_tekion_customer_number,
        p_name,
        p_phone,
        p_email,
        p_flags,
        p_internal_notes
    );

    return jsonb_build_object(
        'status', 'customer_created_via_get_or_create',
        'customer_result', v_create_result
    );
end;
$$;


ALTER FUNCTION "public"."get_or_create_customer_state_by_tekion"("p_tekion_customer_number" "text", "p_name" "text", "p_phone" "text", "p_email" "text", "p_flags" "jsonb", "p_internal_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_or_create_vehicle_state_by_vin"("p_vin" "text", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text", "p_status" "text" DEFAULT 'available'::"text", "p_recon_status" "text" DEFAULT 'clean'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_existing jsonb;
    v_create_result jsonb;
begin
    if p_vin is null or btrim(p_vin) = '' then
        raise exception 'vin cannot be blank';
    end if;

    if p_stock_number is null or btrim(p_stock_number) = '' then
        raise exception 'stock_number cannot be blank';
    end if;

    if p_model is null or btrim(p_model) = '' then
        raise exception 'model cannot be blank';
    end if;

    if p_fleet_type is null or btrim(p_fleet_type) = '' then
        raise exception 'fleet_type cannot be blank';
    end if;

    if p_current_tag is null or btrim(p_current_tag) = '' then
        raise exception 'current_tag cannot be blank';
    end if;

    if p_fleet_conversion_type is null or btrim(p_fleet_conversion_type) = '' then
        raise exception 'fleet_conversion_type cannot be blank';
    end if;

    if p_mileage is null or p_mileage < 0 then
        raise exception 'mileage must be non-negative';
    end if;

    v_existing := public.get_vehicle_by_vin_state(
        p_vin
    );

    if (v_existing ->> 'status') = 'vehicle_found' then
        return jsonb_build_object(
            'status', 'vehicle_already_exists',
            'vehicle_state', v_existing
        );
    end if;

    v_create_result := public.create_vehicle_state(
        p_vin,
        p_stock_number,
        p_model,
        p_fleet_type,
        p_mileage,
        p_current_tag,
        p_fleet_conversion_type,
        p_location,
        p_notes,
        p_status,
        p_recon_status
    );

    return jsonb_build_object(
        'status', 'vehicle_created_via_get_or_create',
        'vehicle_result', v_create_result
    );
end;
$$;


ALTER FUNCTION "public"."get_or_create_vehicle_state_by_vin"("p_vin" "text", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text", "p_notes" "text", "p_status" "text", "p_recon_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_permissions_catalog_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'permission_id', p.id,
                'permission_key', p.permission_key
            )
            order by p.permission_key asc
        ),
        '[]'::jsonb
    )
    into v_items
    from public.permissions p;

    return jsonb_build_object(
        'status', 'permissions_catalog_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_permissions_catalog_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_reservation_assignment_state"("p_reservation_id" "uuid", "p_reference_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_res record;
    v_vin_lock_lead_days integer := 0;
    v_lock_window_starts_at timestamptz;
    v_is_in_lock_window boolean;
begin
    select *
    into v_res
    from public.reservations
    where id = p_reservation_id;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    select coalesce((setting_value #>> '{}')::integer, 0)
    into v_vin_lock_lead_days
    from public.admin_settings
    where setting_key = 'reservation_vin_lock_lead_days';

    v_lock_window_starts_at := v_res.start_date - make_interval(days => v_vin_lock_lead_days);
    v_is_in_lock_window := (p_reference_at >= v_lock_window_starts_at);

    return jsonb_build_object(
        'status', 'reservation_assignment_state_ready',
        'reservation_id', v_res.id,
        'transportation_event_id', v_res.transportation_event_id,
        'reservation_start_at', v_res.start_date,
        'reservation_end_at', v_res.expected_return_datetime,
        'requested_model', v_res.requested_model,
        'reservation_type', v_res.reservation_type,
        'reservation_status', v_res.status,
        'reservation_notes', v_res.notes,
        'reservation_vehicle_id', v_res.vehicle_id,
        'vin_lock_lead_days', v_vin_lock_lead_days,
        'lock_window_starts_at', v_lock_window_starts_at,
        'is_in_lock_window', v_is_in_lock_window,
        'vehicle_is_assigned', (v_res.vehicle_id is not null)
    );
end;
$$;


ALTER FUNCTION "public"."get_reservation_assignment_state"("p_reservation_id" "uuid", "p_reference_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_reservation_current_billing_state"("p_reservation_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    if not exists (
        select 1
        from public.reservations
        where id = p_reservation_id
    ) then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'reservation_id', reservation_id,
                'transportation_event_id', transportation_event_id,
                'reservation_vehicle_id', reservation_vehicle_id,
                'start_date', start_date,
                'expected_return_datetime', expected_return_datetime,
                'reservation_status', reservation_status,
                'reservation_type', reservation_type,
                'requested_model', requested_model,
                'reservation_pay_type', reservation_pay_type,
                'customer_id', customer_id,
                'parent_billing_line_id', parent_billing_line_id,
                'billing_vehicle_id', billing_vehicle_id,
                'vehicle_event_id', vehicle_event_id,
                'contract_period_id', contract_period_id,
                'pay_type', pay_type,
                'pay_type_rule_id', pay_type_rule_id,
                'parent_amount', parent_amount,
                'parent_tax_amount', parent_tax_amount,
                'start_time', start_time,
                'end_time', end_time,
                'parent_line_type', parent_line_type,
                'warranty_provider_id', warranty_provider_id,
                'default_covered_days_snapshot', default_covered_days_snapshot,
                'covered_days_override', covered_days_override,
                'default_daily_rate_snapshot', default_daily_rate_snapshot,
                'daily_rate_override', daily_rate_override,
                'paid_through_at', paid_through_at,
                'extended_from_billing_line_id', extended_from_billing_line_id,
                'parent_is_open', parent_is_open,
                'tax_billing_line_id', tax_billing_line_id,
                'tax_line_amount', tax_line_amount,
                'tax_line_is_open', tax_line_is_open
            )
            order by start_time asc nulls last, parent_billing_line_id
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_reservation_current_billing_state
    where reservation_id = p_reservation_id;

    return jsonb_build_object(
        'status', 'reservation_current_billing_state_ready',
        'reservation_id', p_reservation_id,
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_reservation_current_billing_state"("p_reservation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_reservation_extension_candidate_state"("p_reservation_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    if not exists (
        select 1
        from public.reservations
        where id = p_reservation_id
    ) then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'reservation_id', reservation_id,
                'transportation_event_id', transportation_event_id,
                'reservation_vehicle_id', reservation_vehicle_id,
                'start_date', start_date,
                'expected_return_datetime', expected_return_datetime,
                'reservation_status', reservation_status,
                'reservation_type', reservation_type,
                'requested_model', requested_model,
                'reservation_pay_type', reservation_pay_type,
                'customer_id', customer_id,
                'parent_billing_line_id', parent_billing_line_id,
                'billing_vehicle_id', billing_vehicle_id,
                'vehicle_event_id', vehicle_event_id,
                'contract_period_id', contract_period_id,
                'pay_type', pay_type,
                'pay_type_rule_id', pay_type_rule_id,
                'amount', amount,
                'tax_amount', tax_amount,
                'start_time', start_time,
                'end_time', end_time,
                'line_type', line_type,
                'warranty_provider_id', warranty_provider_id,
                'default_covered_days_snapshot', default_covered_days_snapshot,
                'covered_days_override', covered_days_override,
                'default_daily_rate_snapshot', default_daily_rate_snapshot,
                'daily_rate_override', daily_rate_override,
                'paid_through_at', paid_through_at,
                'extended_from_billing_line_id', extended_from_billing_line_id,
                'is_open', is_open,
                'current_expected_return_at', current_expected_return_at
            )
            order by start_time asc nulls last, parent_billing_line_id
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_reservation_extension_candidate_state
    where reservation_id = p_reservation_id;

    return jsonb_build_object(
        'status', 'reservation_extension_candidate_state_ready',
        'reservation_id', p_reservation_id,
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_reservation_extension_candidate_state"("p_reservation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_reservation_lifecycle_list_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'reservation_id', r.id,
                'transportation_event_id', r.transportation_event_id,
                'vehicle_id', r.vehicle_id,
                'start_date', r.start_date,
                'expected_return_datetime', r.expected_return_datetime,
                'reservation_status', r.status,
                'reservation_type', r.reservation_type,
                'reservation_notes', r.notes,
                'cancellation_reason', r.cancellation_reason,
                'start_mileage', r.start_mileage,
                'end_mileage', r.end_mileage,
                'condition_flag', r.condition_flag,
                'requested_model', r.requested_model,
                'service_advisor', r.service_advisor,
                'ro_number', r.ro_number,
                'pay_type', r.pay_type,
                'actual_return_datetime', r.actual_return_datetime,
                'billed_through_datetime', r.billed_through_datetime,
                'customer_id', r.customer_id,
                'source_type', te.source_type,
                'source_id', te.source_id,
                'transportation_event_status', te.status,
                'transportation_event_notes', te.notes,
                'expected_return_at', te.expected_return_at,
                'closed_at', te.closed_at,
                'closed_by', te.closed_by
            )
            order by r.start_date asc nulls last, r.id
        ),
        '[]'::jsonb
    )
    into v_items
    from public.reservations r
    join public.transportation_events te
      on te.id = r.transportation_event_id;

    return jsonb_build_object(
        'status', 'reservation_lifecycle_list_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_reservation_lifecycle_list_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_reservation_lifecycle_state"("p_reservation_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select
        r.id as reservation_id,
        r.transportation_event_id,
        r.vehicle_id,
        r.start_date,
        r.expected_return_datetime,
        r.status as reservation_status,
        r.reservation_type,
        r.notes as reservation_notes,
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
        te.status as transportation_event_status,
        te.notes as transportation_event_notes,
        te.expected_return_at,
        te.closed_at,
        te.closed_by
    into v_row
    from public.reservations r
    join public.transportation_events te
      on te.id = r.transportation_event_id
    where r.id = p_reservation_id
    limit 1;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    return jsonb_build_object(
        'status', 'reservation_lifecycle_state_ready',
        'reservation_id', v_row.reservation_id,
        'transportation_event_id', v_row.transportation_event_id,
        'vehicle_id', v_row.vehicle_id,
        'start_date', v_row.start_date,
        'expected_return_datetime', v_row.expected_return_datetime,
        'reservation_status', v_row.reservation_status,
        'reservation_type', v_row.reservation_type,
        'reservation_notes', v_row.reservation_notes,
        'cancellation_reason', v_row.cancellation_reason,
        'start_mileage', v_row.start_mileage,
        'end_mileage', v_row.end_mileage,
        'condition_flag', v_row.condition_flag,
        'requested_model', v_row.requested_model,
        'service_advisor', v_row.service_advisor,
        'ro_number', v_row.ro_number,
        'pay_type', v_row.pay_type,
        'actual_return_datetime', v_row.actual_return_datetime,
        'billed_through_datetime', v_row.billed_through_datetime,
        'customer_id', v_row.customer_id,
        'source_type', v_row.source_type,
        'source_id', v_row.source_id,
        'transportation_event_status', v_row.transportation_event_status,
        'transportation_event_notes', v_row.transportation_event_notes,
        'expected_return_at', v_row.expected_return_at,
        'closed_at', v_row.closed_at,
        'closed_by', v_row.closed_by
    );
end;
$$;


ALTER FUNCTION "public"."get_reservation_lifecycle_state"("p_reservation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_reservation_operational_list_payload_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'reservation_id', reservation_id,
                'transportation_event_id', transportation_event_id,
                'vehicle_id', vehicle_id,
                'start_date', start_date,
                'expected_return_datetime', expected_return_datetime,
                'reservation_status', reservation_status,
                'reservation_type', reservation_type,
                'reservation_notes', reservation_notes,
                'cancellation_reason', cancellation_reason,
                'start_mileage', start_mileage,
                'end_mileage', end_mileage,
                'condition_flag', condition_flag,
                'requested_model', requested_model,
                'service_advisor', service_advisor,
                'ro_number', ro_number,
                'pay_type', pay_type,
                'actual_return_datetime', actual_return_datetime,
                'billed_through_datetime', billed_through_datetime,
                'customer_id', customer_id,
                'source_type', source_type,
                'source_id', source_id,
                'transportation_event_status', transportation_event_status,
                'transportation_event_notes', transportation_event_notes,
                'expected_return_at', expected_return_at,
                'closed_at', closed_at,
                'closed_by', closed_by,
                'vin_lock_lead_days', vin_lock_lead_days,
                'lock_window_starts_at', lock_window_starts_at,
                'is_in_lock_window', is_in_lock_window,
                'vehicle_is_assigned', vehicle_is_assigned,
                'current_dependency_id', current_dependency_id,
                'current_dependency_type', current_dependency_type,
                'current_dependency_status', current_dependency_status,
                'current_dependency_risk_level', current_dependency_risk_level,
                'current_dependency_expected_return_snapshot', current_dependency_expected_return_snapshot,
                'current_conflict_id', current_conflict_id,
                'current_conflict_severity', current_conflict_severity,
                'current_conflict_message', current_conflict_message
            )
            order by start_date asc nulls last, reservation_id
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_reservation_operational_state;

    return jsonb_build_object(
        'status', 'reservation_operational_list_payload_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_reservation_operational_list_payload_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_reservation_operational_payload_state"("p_reservation_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_reservation record;
    v_lifecycle jsonb;
    v_assignment jsonb;
    v_candidates jsonb;
    v_dependency jsonb;
    v_billing_banner jsonb;
begin
    select *
    into v_reservation
    from public.reservations
    where id = p_reservation_id
    limit 1;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    v_lifecycle := public.get_reservation_lifecycle_state(
        p_reservation_id
    );

    v_assignment := public.get_reservation_assignment_state(
        p_reservation_id
    );

    v_candidates := public.get_reservation_vehicle_candidates_state(
        p_reservation_id
    );

    v_dependency := public.get_current_reservation_dependency_state(
        p_reservation_id
    );

    v_billing_banner := public.get_billing_dependency_banner_state(
        v_reservation.transportation_event_id
    );

    return jsonb_build_object(
        'status', 'reservation_operational_payload_ready',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'lifecycle', v_lifecycle,
        'assignment', v_assignment,
        'vehicle_candidates', v_candidates,
        'current_dependency', v_dependency,
        'billing_dependency_banner', v_billing_banner
    );
end;
$$;


ALTER FUNCTION "public"."get_reservation_operational_payload_state"("p_reservation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_reservation_transportation_link_payload_state"("p_reservation_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_reservation_transportation_link_state
    where reservation_id = p_reservation_id
    limit 1;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    return jsonb_build_object(
        'status', 'reservation_transportation_link_payload_ready',
        'reservation_id', v_row.reservation_id,
        'transportation_event_id', v_row.transportation_event_id,
        'vehicle_id', v_row.vehicle_id,
        'start_date', v_row.start_date,
        'expected_return_datetime', v_row.expected_return_datetime,
        'reservation_status', v_row.reservation_status,
        'reservation_type', v_row.reservation_type,
        'reservation_notes', v_row.reservation_notes,
        'cancellation_reason', v_row.cancellation_reason,
        'start_mileage', v_row.start_mileage,
        'end_mileage', v_row.end_mileage,
        'condition_flag', v_row.condition_flag,
        'requested_model', v_row.requested_model,
        'service_advisor', v_row.service_advisor,
        'ro_number', v_row.ro_number,
        'pay_type', v_row.pay_type,
        'actual_return_datetime', v_row.actual_return_datetime,
        'billed_through_datetime', v_row.billed_through_datetime,
        'customer_id', v_row.customer_id,
        'source_type', v_row.source_type,
        'source_id', v_row.source_id,
        'transportation_event_status', v_row.transportation_event_status,
        'transportation_event_notes', v_row.transportation_event_notes,
        'expected_return_at', v_row.expected_return_at,
        'closed_at', v_row.closed_at,
        'closed_by', v_row.closed_by
    );
end;
$$;


ALTER FUNCTION "public"."get_reservation_transportation_link_payload_state"("p_reservation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_reservation_vehicle_candidates_state"("p_reservation_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    if not exists (
        select 1
        from public.reservations
        where id = p_reservation_id
    ) then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'reservation_id', reservation_id,
                'reservation_transportation_event_id', reservation_transportation_event_id,
                'reservation_start_at', reservation_start_at,
                'reservation_end_at', reservation_end_at,
                'requested_model', requested_model,
                'reservation_type', reservation_type,
                'reservation_status', reservation_status,
                'reservation_notes', reservation_notes,
                'vehicle_id', vehicle_id,
                'vin', vin,
                'stock_number', stock_number,
                'vehicle_model', vehicle_model,
                'fleet_type', fleet_type,
                'vehicle_status', vehicle_status,
                'recon_status', recon_status,
                'location', location,
                'source_transportation_event_id', source_transportation_event_id,
                'expected_return_snapshot', expected_return_snapshot,
                'candidate_state', candidate_state
            )
            order by
                case candidate_state
                    when 'ready' then 1
                    when 'pending_return' then 2
                    else 3
                end,
                expected_return_snapshot asc nulls last,
                stock_number asc nulls last,
                vin asc nulls last
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_reservation_vehicle_candidates
    where reservation_id = p_reservation_id;

    return jsonb_build_object(
        'status', 'reservation_vehicle_candidates_ready',
        'reservation_id', p_reservation_id,
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_reservation_vehicle_candidates_state"("p_reservation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_reservation_vin_lock_lead_days_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_days integer := 0;
begin
    select coalesce((setting_value #>> '{}')::integer, 0)
    into v_days
    from public.admin_settings
    where setting_key = 'reservation_vin_lock_lead_days';

    return jsonb_build_object(
        'status', 'reservation_vin_lock_lead_days_ready',
        'reservation_vin_lock_lead_days', v_days
    );
end;
$$;


ALTER FUNCTION "public"."get_reservation_vin_lock_lead_days_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_reservation_vin_lock_window_state"("p_reservation_id" "uuid", "p_reference_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_start_at timestamptz;
    v_vehicle_id uuid;
    v_days integer := 0;
    v_lock_window_starts_at timestamptz;
    v_is_in_lock_window boolean;
begin
    select
        r.start_date,
        r.vehicle_id
    into
        v_start_at,
        v_vehicle_id
    from public.reservations r
    where r.id = p_reservation_id;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    select coalesce((setting_value #>> '{}')::integer, 0)
    into v_days
    from public.admin_settings
    where setting_key = 'reservation_vin_lock_lead_days';

    v_lock_window_starts_at := v_start_at - make_interval(days => v_days);
    v_is_in_lock_window := (p_reference_at >= v_lock_window_starts_at);

    return jsonb_build_object(
        'status', 'reservation_vin_lock_window_state_ready',
        'reservation_id', p_reservation_id,
        'reservation_start_at', v_start_at,
        'reservation_vehicle_id', v_vehicle_id,
        'reservation_vin_lock_lead_days', v_days,
        'lock_window_starts_at', v_lock_window_starts_at,
        'is_in_lock_window', v_is_in_lock_window,
        'vehicle_is_already_assigned', (v_vehicle_id is not null)
    );
end;
$$;


ALTER FUNCTION "public"."get_reservation_vin_lock_window_state"("p_reservation_id" "uuid", "p_reference_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_reservations_needing_vin_assignment_state"("p_reference_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_vin_lock_lead_days integer := 0;
    v_items jsonb;
begin
    select coalesce((setting_value #>> '{}')::integer, 0)
    into v_vin_lock_lead_days
    from public.admin_settings
    where setting_key = 'reservation_vin_lock_lead_days';

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'reservation_id', r.id,
                'transportation_event_id', r.transportation_event_id,
                'reservation_start_at', r.start_date,
                'reservation_end_at', r.expected_return_datetime,
                'requested_model', r.requested_model,
                'reservation_type', r.reservation_type,
                'reservation_status', r.status,
                'reservation_notes', r.notes,
                'reservation_vehicle_id', r.vehicle_id,
                'vin_lock_lead_days', v_vin_lock_lead_days,
                'lock_window_starts_at', r.start_date - make_interval(days => v_vin_lock_lead_days),
                'is_in_lock_window', (p_reference_at >= (r.start_date - make_interval(days => v_vin_lock_lead_days))),
                'vehicle_is_assigned', (r.vehicle_id is not null)
            )
            order by r.start_date asc nulls last
        ),
        '[]'::jsonb
    )
    into v_items
    from public.reservations r
    where (p_reference_at >= (r.start_date - make_interval(days => v_vin_lock_lead_days)))
      and r.vehicle_id is null
      and r.status is distinct from 'cancelled';

    return jsonb_build_object(
        'status', 'reservations_needing_vin_assignment_ready',
        'reference_at', p_reference_at,
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_reservations_needing_vin_assignment_state"("p_reference_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_reset_link_network_gate_state"("p_token_hash" "text", "p_request_ip" "text", "p_reference_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_settings record;
    v_token_state jsonb;
    v_user_id uuid;
    v_network_gate jsonb;
begin
    select *
    into v_settings
    from public.v_security_admin_settings_state
    limit 1;

    if coalesce(v_settings.email_password_reset_link_enabled, false) = false then
        return jsonb_build_object(
            'status', 'blocked_feature_disabled',
            'email_password_reset_link_enabled', false
        );
    end if;

    v_token_state := public.get_reset_token_validity_state(
        p_token_hash,
        p_reference_at
    );

    if (v_token_state ->> 'status') is distinct from 'valid_token' then
        return jsonb_build_object(
            'status', 'blocked_invalid_token',
            'token_state', v_token_state
        );
    end if;

    v_user_id := (v_token_state ->> 'user_id')::uuid;

    v_network_gate := public.get_network_gate_state(
        v_user_id,
        p_request_ip
    );

    if (v_network_gate ->> 'status') = 'network_gate_blocked' then
        return jsonb_build_object(
            'status', 'blocked_network_restriction',
            'token_state', v_token_state,
            'network_gate', v_network_gate
        );
    end if;

    return jsonb_build_object(
        'status', 'reset_link_network_gate_allowed',
        'token_state', v_token_state,
        'network_gate', v_network_gate
    );
end;
$$;


ALTER FUNCTION "public"."get_reset_link_network_gate_state"("p_token_hash" "text", "p_request_ip" "text", "p_reference_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_reset_token_validity_state"("p_token_hash" "text", "p_reference_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_token record;
begin
    if p_token_hash is null or btrim(p_token_hash) = '' then
        raise exception 'Token hash cannot be blank';
    end if;

    select *
    into v_token
    from public.app_user_reset_tokens
    where token_hash = p_token_hash
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'invalid_token',
            'token_found', false
        );
    end if;

    if v_token.is_active is distinct from true then
        return jsonb_build_object(
            'status', 'inactive_token',
            'token_found', true,
            'user_id', v_token.user_id
        );
    end if;

    if v_token.used_at is not null then
        return jsonb_build_object(
            'status', 'used_token',
            'token_found', true,
            'user_id', v_token.user_id
        );
    end if;

    if v_token.expires_at < p_reference_at then
        return jsonb_build_object(
            'status', 'expired_token',
            'token_found', true,
            'user_id', v_token.user_id
        );
    end if;

    return jsonb_build_object(
        'status', 'valid_token',
        'token_found', true,
        'user_id', v_token.user_id,
        'reset_mode', v_token.reset_mode,
        'issued_at', v_token.issued_at,
        'expires_at', v_token.expires_at
    );
end;
$$;


ALTER FUNCTION "public"."get_reset_token_validity_state"("p_token_hash" "text", "p_reference_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_roles_with_permissions_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'role_id', role_id,
                'role_name', role_name,
                'permission_summary', permission_summary,
                'permission_count', permission_count
            )
            order by role_name asc
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_roles_with_permissions;

    return jsonb_build_object(
        'status', 'roles_with_permissions_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_roles_with_permissions_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_security_admin_settings_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_security_admin_settings_state
    limit 1;

    return jsonb_build_object(
        'status', 'security_admin_settings_ready',
        'network_restriction_enabled', v_row.network_restriction_enabled,
        'email_password_reset_link_enabled', v_row.email_password_reset_link_enabled,
        'late_fees_enabled', v_row.late_fees_enabled,
        'reservation_vin_lock_lead_days', v_row.reservation_vin_lock_lead_days
    );
end;
$$;


ALTER FUNCTION "public"."get_security_admin_settings_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_service_action_contract_catalog_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            to_jsonb(x)
            order by x.action_group asc, x.action_key asc
        ),
        '[]'::jsonb
    )
    into v_items
    from (
        select
            service_action_contract_id,
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
        from public.v_service_action_contract_state
    ) x;

    return jsonb_build_object(
        'status', 'service_action_contract_catalog_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_service_action_contract_catalog_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_service_action_contract_state"("p_action_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    if p_action_key is null or btrim(p_action_key) = '' then
        raise exception 'action_key cannot be blank';
    end if;

    select *
    into v_row
    from public.v_service_action_contract_state
    where action_key = p_action_key
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'service_action_contract_not_found',
            'action_key', p_action_key
        );
    end if;

    return jsonb_build_object(
        'status', 'service_action_contract_ready',
        'service_action_contract_id', v_row.service_action_contract_id,
        'action_key', v_row.action_key,
        'action_group', v_row.action_group,
        'entity_scope', v_row.entity_scope,
        'db_function_name', v_row.db_function_name,
        'action_type', v_row.action_type,
        'description', v_row.description,
        'requires_authenticated_user', v_row.requires_authenticated_user,
        'requires_aal2', v_row.requires_aal2,
        'writes_data', v_row.writes_data,
        'frontend_safe', v_row.frontend_safe,
        'internal_only', v_row.internal_only,
        'required_permission', v_row.required_permission,
        'created_at', v_row.created_at,
        'updated_at', v_row.updated_at
    );
end;
$$;


ALTER FUNCTION "public"."get_service_action_contract_state"("p_action_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_transportation_event_current_billing_state"("p_transportation_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    if not exists (
        select 1
        from public.transportation_events
        where id = p_transportation_event_id
    ) then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'transportation_event_id', transportation_event_id,
                'source_type', source_type,
                'source_id', source_id,
                'transportation_event_status', transportation_event_status,
                'transportation_event_notes', transportation_event_notes,
                'customer_id', customer_id,
                'updated_at', updated_at,
                'closed_at', closed_at,
                'closed_by', closed_by,
                'expected_return_at', expected_return_at,
                'parent_billing_line_id', parent_billing_line_id,
                'reservation_id', reservation_id,
                'billing_vehicle_id', billing_vehicle_id,
                'vehicle_event_id', vehicle_event_id,
                'contract_period_id', contract_period_id,
                'pay_type', pay_type,
                'pay_type_rule_id', pay_type_rule_id,
                'parent_amount', parent_amount,
                'parent_tax_amount', parent_tax_amount,
                'start_time', start_time,
                'end_time', end_time,
                'parent_line_type', parent_line_type,
                'warranty_provider_id', warranty_provider_id,
                'default_covered_days_snapshot', default_covered_days_snapshot,
                'covered_days_override', covered_days_override,
                'default_daily_rate_snapshot', default_daily_rate_snapshot,
                'daily_rate_override', daily_rate_override,
                'paid_through_at', paid_through_at,
                'extended_from_billing_line_id', extended_from_billing_line_id,
                'parent_is_open', parent_is_open,
                'tax_billing_line_id', tax_billing_line_id,
                'tax_line_amount', tax_line_amount,
                'tax_line_is_open', tax_line_is_open
            )
            order by start_time asc nulls last, parent_billing_line_id
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_transportation_event_current_billing_state
    where transportation_event_id = p_transportation_event_id;

    return jsonb_build_object(
        'status', 'transportation_event_current_billing_state_ready',
        'transportation_event_id', p_transportation_event_id,
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_transportation_event_current_billing_state"("p_transportation_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_transportation_event_current_dependency_state"("p_transportation_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_transportation_event_current_dependency_state
    where transportation_event_id = p_transportation_event_id
    limit 1;

    if not found then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    return jsonb_build_object(
        'status',
            case
                when v_row.source_type is distinct from 'reservation' then 'transportation_event_not_reservation_sourced'
                when v_row.dependency_id is null then 'no_active_dependency_for_transportation_event'
                else 'transportation_event_current_dependency_state_ready'
            end,
        'transportation_event_id', v_row.transportation_event_id,
        'source_type', v_row.source_type,
        'source_id', v_row.source_id,
        'transportation_event_status', v_row.transportation_event_status,
        'customer_id', v_row.customer_id,
        'expected_return_at', v_row.expected_return_at,
        'closed_at', v_row.closed_at,
        'closed_by', v_row.closed_by,
        'dependency_id', v_row.dependency_id,
        'reservation_id', v_row.reservation_id,
        'vehicle_id', v_row.vehicle_id,
        'source_transportation_event_id', v_row.source_transportation_event_id,
        'dependency_type', v_row.dependency_type,
        'dependency_status', v_row.dependency_status,
        'risk_level', v_row.risk_level,
        'expected_return_snapshot', v_row.expected_return_snapshot,
        'dependency_notes', v_row.dependency_notes,
        'dependency_created_at', v_row.dependency_created_at,
        'dependency_updated_at', v_row.dependency_updated_at,
        'conflict_id', v_row.conflict_id,
        'conflict_type', v_row.conflict_type,
        'conflict_severity', v_row.conflict_severity,
        'conflict_message', v_row.conflict_message,
        'conflict_is_resolved', v_row.conflict_is_resolved
    );
end;
$$;


ALTER FUNCTION "public"."get_transportation_event_current_dependency_state"("p_transportation_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_transportation_event_extension_candidate_state"("p_transportation_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    if not exists (
        select 1
        from public.transportation_events
        where id = p_transportation_event_id
    ) then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'transportation_event_id', transportation_event_id,
                'source_type', source_type,
                'source_id', source_id,
                'transportation_event_status', transportation_event_status,
                'transportation_event_notes', transportation_event_notes,
                'customer_id', customer_id,
                'updated_at', updated_at,
                'closed_at', closed_at,
                'closed_by', closed_by,
                'expected_return_at', expected_return_at,
                'parent_billing_line_id', parent_billing_line_id,
                'reservation_id', reservation_id,
                'billing_vehicle_id', billing_vehicle_id,
                'vehicle_event_id', vehicle_event_id,
                'contract_period_id', contract_period_id,
                'pay_type', pay_type,
                'pay_type_rule_id', pay_type_rule_id,
                'amount', amount,
                'tax_amount', tax_amount,
                'start_time', start_time,
                'end_time', end_time,
                'line_type', line_type,
                'warranty_provider_id', warranty_provider_id,
                'default_covered_days_snapshot', default_covered_days_snapshot,
                'covered_days_override', covered_days_override,
                'default_daily_rate_snapshot', default_daily_rate_snapshot,
                'daily_rate_override', daily_rate_override,
                'paid_through_at', paid_through_at,
                'extended_from_billing_line_id', extended_from_billing_line_id,
                'is_open', is_open,
                'current_expected_return_at', current_expected_return_at
            )
            order by start_time asc nulls last, parent_billing_line_id
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_transportation_event_extension_candidate_state
    where transportation_event_id = p_transportation_event_id;

    return jsonb_build_object(
        'status', 'transportation_event_extension_candidate_state_ready',
        'transportation_event_id', p_transportation_event_id,
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_transportation_event_extension_candidate_state"("p_transportation_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_transportation_event_note_history_state"("p_transportation_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_notes jsonb;
begin
    if not exists (
        select 1
        from public.transportation_events
        where id = p_transportation_event_id
    ) then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'note_id', h.note_id,
                'transportation_event_id', h.transportation_event_id,
                'note_type', h.note_type,
                'note_text', h.note_text,
                'entered_at', h.entered_at,
                'entered_by_user_id', h.entered_by_user_id,
                'entered_by_name', h.entered_by_name
            )
            order by h.entered_at asc
        ),
        '[]'::jsonb
    )
    into v_notes
    from public.v_transportation_event_note_history h
    where h.transportation_event_id = p_transportation_event_id;

    return jsonb_build_object(
        'status', 'note_history_ready',
        'transportation_event_id', p_transportation_event_id,
        'notes', v_notes
    );
end;
$$;


ALTER FUNCTION "public"."get_transportation_event_note_history_state"("p_transportation_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_transportation_event_operational_list_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'transportation_event_id', transportation_event_id,
                'source_type', source_type,
                'source_id', source_id,
                'transportation_event_status', transportation_event_status,
                'customer_id', customer_id,
                'expected_return_at', expected_return_at,
                'closed_at', closed_at,
                'vehicle_event_id', vehicle_event_id,
                'vehicle_id', vehicle_id,
                'contract_period_id', contract_period_id,
                'actual_out_at', actual_out_at,
                'actual_in_at', actual_in_at,
                'vehicle_event_is_open', vehicle_event_is_open,
                'ended_reason', ended_reason,
                'contract_out_at', contract_out_at,
                'contract_in_at', contract_in_at,
                'renewal_sequence', renewal_sequence,
                'contract_period_is_open', contract_period_is_open
            )
            order by expected_return_at asc nulls last, transportation_event_id
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_transportation_event_operational_state;

    return jsonb_build_object(
        'status', 'transportation_event_operational_list_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_transportation_event_operational_list_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_transportation_event_operational_payload_state"("p_transportation_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_te record;
    v_current_continuity jsonb;
    v_current_billing_lines jsonb;
    v_extendable_billing_lines jsonb;
    v_note_history jsonb;
    v_billing_banner jsonb;
begin
    select *
    into v_te
    from public.transportation_events
    where id = p_transportation_event_id
    limit 1;

    if not found then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    -- current continuity
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'vehicle_event_id', c.vehicle_event_id,
                'vehicle_id', c.vehicle_id,
                'contract_period_id', c.contract_period_id,
                'actual_out_at', c.actual_out_at,
                'actual_in_at', c.actual_in_at,
                'vehicle_event_is_open', c.vehicle_event_is_open,
                'ended_reason', c.ended_reason,
                'contract_out_at', c.contract_out_at,
                'contract_in_at', c.contract_in_at,
                'renewal_sequence', c.renewal_sequence,
                'contract_period_is_open', c.contract_period_is_open
            )
        ),
        '[]'::jsonb
    )
    into v_current_continuity
    from public.v_current_vehicle_continuity c
    where c.transportation_event_id = p_transportation_event_id;

    -- current open billing lines
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'parent_billing_line_id', b.parent_billing_line_id,
                'reservation_id', b.reservation_id,
                'vehicle_id', b.vehicle_id,
                'vehicle_event_id', b.vehicle_event_id,
                'contract_period_id', b.contract_period_id,
                'pay_type', b.pay_type,
                'pay_type_rule_id', b.pay_type_rule_id,
                'parent_amount', b.parent_amount,
                'parent_tax_amount', b.parent_tax_amount,
                'start_time', b.start_time,
                'end_time', b.end_time,
                'parent_line_type', b.parent_line_type,
                'warranty_provider_id', b.warranty_provider_id,
                'default_covered_days_snapshot', b.default_covered_days_snapshot,
                'covered_days_override', b.covered_days_override,
                'default_daily_rate_snapshot', b.default_daily_rate_snapshot,
                'daily_rate_override', b.daily_rate_override,
                'paid_through_at', b.paid_through_at,
                'extended_from_billing_line_id', b.extended_from_billing_line_id,
                'parent_is_open', b.parent_is_open,
                'tax_billing_line_id', b.tax_billing_line_id,
                'tax_line_amount', b.tax_line_amount,
                'tax_line_is_open', b.tax_line_is_open
            )
            order by b.start_time asc nulls last, b.parent_billing_line_id
        ),
        '[]'::jsonb
    )
    into v_current_billing_lines
    from public.v_current_open_billing_lines b
    where b.transportation_event_id = p_transportation_event_id;

    -- current extendable billing lines
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'parent_billing_line_id', e.parent_billing_line_id,
                'reservation_id', e.reservation_id,
                'vehicle_id', e.vehicle_id,
                'vehicle_event_id', e.vehicle_event_id,
                'contract_period_id', e.contract_period_id,
                'pay_type', e.pay_type,
                'pay_type_rule_id', e.pay_type_rule_id,
                'amount', e.amount,
                'tax_amount', e.tax_amount,
                'start_time', e.start_time,
                'end_time', e.end_time,
                'line_type', e.line_type,
                'warranty_provider_id', e.warranty_provider_id,
                'default_covered_days_snapshot', e.default_covered_days_snapshot,
                'covered_days_override', e.covered_days_override,
                'default_daily_rate_snapshot', e.default_daily_rate_snapshot,
                'daily_rate_override', e.daily_rate_override,
                'paid_through_at', e.paid_through_at,
                'extended_from_billing_line_id', e.extended_from_billing_line_id,
                'is_open', e.is_open,
                'current_expected_return_at', e.current_expected_return_at
            )
            order by e.start_time asc nulls last, e.parent_billing_line_id
        ),
        '[]'::jsonb
    )
    into v_extendable_billing_lines
    from public.v_extension_commit_candidates e
    where e.transportation_event_id = p_transportation_event_id;

    -- note history
    v_note_history := public.get_transportation_event_note_history_state(
        p_transportation_event_id
    );

    -- billing dependency banner
    v_billing_banner := public.get_billing_dependency_banner_state(
        p_transportation_event_id
    );

    return jsonb_build_object(
        'status', 'transportation_event_operational_payload_ready',
        'transportation_event_id', v_te.id,
        'source_type', v_te.source_type,
        'source_id', v_te.source_id,
        'transportation_event_status', v_te.status,
        'customer_id', v_te.customer_id,
        'expected_return_at', v_te.expected_return_at,
        'closed_at', v_te.closed_at,
        'current_continuity', v_current_continuity,
        'current_billing_lines', v_current_billing_lines,
        'extendable_billing_lines', v_extendable_billing_lines,
        'note_history', v_note_history,
        'billing_dependency_banner', v_billing_banner
    );
end;
$$;


ALTER FUNCTION "public"."get_transportation_event_operational_payload_state"("p_transportation_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_transportation_event_state"("p_transportation_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_transportation_event_state
    where transportation_event_id = p_transportation_event_id
    limit 1;

    if not found then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    return jsonb_build_object(
        'status', 'transportation_event_state_ready',
        'transportation_event_id', v_row.transportation_event_id,
        'source_type', v_row.source_type,
        'source_id', v_row.source_id,
        'transportation_event_status', v_row.status,
        'notes', v_row.notes,
        'customer_id', v_row.customer_id,
        'updated_at', v_row.updated_at,
        'closed_at', v_row.closed_at,
        'closed_by', v_row.closed_by,
        'expected_return_at', v_row.expected_return_at
    );
end;
$$;


ALTER FUNCTION "public"."get_transportation_event_state"("p_transportation_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_transportation_event_unified_operational_list_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            to_jsonb(x)
            order by x.expected_return_at asc nulls last, x.transportation_event_id
        ),
        '[]'::jsonb
    )
    into v_items
    from (
        select
            transportation_event_id,
            source_type,
            source_id,
            transportation_event_status,
            transportation_event_notes,
            customer_id,
            updated_at,
            closed_at,
            closed_by,
            expected_return_at,
            vehicle_event_id,
            vehicle_id,
            contract_period_id,
            actual_out_at,
            actual_in_at,
            vehicle_event_is_open,
            ended_reason,
            contract_out_at,
            contract_in_at,
            renewal_sequence,
            contract_period_is_open,
            current_parent_billing_line_id,
            current_billing_reservation_id,
            current_billing_vehicle_id,
            current_billing_pay_type,
            current_billing_parent_amount,
            current_billing_parent_tax_amount,
            current_billing_start_time,
            current_billing_end_time,
            current_billing_line_type,
            current_billing_paid_through_at,
            current_billing_is_open,
            current_dependency_id,
            current_dependency_reservation_id,
            current_dependency_vehicle_id,
            current_dependency_source_transportation_event_id,
            current_dependency_type,
            current_dependency_status,
            current_dependency_risk_level,
            current_dependency_expected_return_snapshot,
            current_conflict_id,
            current_conflict_type,
            current_conflict_severity,
            current_conflict_message,
            current_conflict_is_resolved,
            extension_candidate_parent_billing_line_id,
            extension_candidate_reservation_id,
            extension_candidate_billing_vehicle_id,
            extension_candidate_pay_type,
            extension_candidate_amount,
            extension_candidate_tax_amount,
            extension_candidate_start_time,
            extension_candidate_paid_through_at,
            extension_candidate_is_open,
            extension_candidate_current_expected_return_at
        from public.v_transportation_event_unified_operational_state
    ) x;

    return jsonb_build_object(
        'status', 'transportation_event_unified_operational_list_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_transportation_event_unified_operational_list_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_transportation_event_unified_operational_payload_state"("p_transportation_event_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_te record;
    v_base_state jsonb;
    v_operational_payload jsonb;
    v_current_billing_state jsonb;
    v_current_dependency_state jsonb;
    v_extension_candidate_state jsonb;
begin
    select *
    into v_te
    from public.transportation_events
    where id = p_transportation_event_id
    limit 1;

    if not found then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    v_base_state := public.get_transportation_event_state(
        p_transportation_event_id
    );

    v_operational_payload := public.get_transportation_event_operational_payload_state(
        p_transportation_event_id
    );

    v_current_billing_state := public.get_transportation_event_current_billing_state(
        p_transportation_event_id
    );

    v_current_dependency_state := public.get_transportation_event_current_dependency_state(
        p_transportation_event_id
    );

    v_extension_candidate_state := public.get_transportation_event_extension_candidate_state(
        p_transportation_event_id
    );

    return jsonb_build_object(
        'status', 'transportation_event_unified_operational_payload_ready',
        'transportation_event_id', p_transportation_event_id,
        'base_state', v_base_state,
        'operational_payload', v_operational_payload,
        'current_billing_state', v_current_billing_state,
        'current_dependency_state', v_current_dependency_state,
        'extension_candidate_state', v_extension_candidate_state
    );
end;
$$;


ALTER FUNCTION "public"."get_transportation_event_unified_operational_payload_state"("p_transportation_event_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_unified_case_payload_state"("p_reservation_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_reservation record;
    v_customer_payload jsonb;
    v_reservation_payload jsonb;
    v_transportation_payload jsonb;
    v_vehicle_payload jsonb := null;
begin
    select *
    into v_reservation
    from public.reservations
    where id = p_reservation_id
    limit 1;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    v_customer_payload := public.get_customer_operational_payload_state(
        v_reservation.customer_id
    );

    v_reservation_payload := public.get_reservation_operational_payload_state(
        p_reservation_id
    );

    v_transportation_payload := public.get_transportation_event_unified_operational_payload_state(
        v_reservation.transportation_event_id
    );

    if v_reservation.vehicle_id is not null then
        v_vehicle_payload := public.get_vehicle_operational_payload_state(
            v_reservation.vehicle_id
        );
    end if;

    return jsonb_build_object(
        'status', 'unified_case_payload_ready',
        'reservation_id', p_reservation_id,
        'customer_id', v_reservation.customer_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'vehicle_id', v_reservation.vehicle_id,
        'customer_payload', v_customer_payload,
        'reservation_payload', v_reservation_payload,
        'transportation_event_payload', v_transportation_payload,
        'vehicle_payload', v_vehicle_payload
    );
end;
$$;


ALTER FUNCTION "public"."get_unified_case_payload_state"("p_reservation_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_upcoming_rental_dependency_feed_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'dependency_id', dependency_id,
                'reservation_id', reservation_id,
                'reservation_start_at', reservation_start_at,
                'reservation_end_at', reservation_end_at,
                'requested_model', requested_model,
                'reservation_type', reservation_type,
                'reservation_status', reservation_status,
                'reservation_notes', reservation_notes,
                'vehicle_id', vehicle_id,
                'source_transportation_event_id', source_transportation_event_id,
                'dependency_type', dependency_type,
                'dependency_status', dependency_status,
                'risk_level', risk_level,
                'expected_return_snapshot', expected_return_snapshot,
                'conflict_id', conflict_id,
                'conflict_type', conflict_type,
                'conflict_severity', conflict_severity,
                'conflict_message', conflict_message
            )
            order by reservation_start_at asc nulls last
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_upcoming_rental_dependency_feed;

    return jsonb_build_object(
        'status', 'dependency_feed_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_upcoming_rental_dependency_feed_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_admin_detail_payload_state"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_user record;
    v_roles jsonb;
    v_security jsonb;
    v_reset_artifacts jsonb;
    v_dashboard_access jsonb;
begin
    select *
    into v_user
    from public.app_users
    where id = p_user_id
    limit 1;

    if not found then
        raise exception 'User % does not exist', p_user_id;
    end if;

    v_roles := public.get_user_role_names_state(p_user_id);
    v_security := public.get_user_security_detail_state(p_user_id);
    v_reset_artifacts := public.get_user_reset_artifact_state(p_user_id);
    v_dashboard_access := public.get_dashboard_section_access_state(p_user_id);

    return jsonb_build_object(
        'status', 'user_admin_detail_payload_ready',
        'user_id', v_user.id,
        'auth_user_id', v_user.auth_user_id,
        'email', v_user.email,
        'full_name', v_user.full_name,
        'phone', v_user.phone,
        'is_active', v_user.is_active,
        'last_login', v_user.last_login,
        'notes', v_user.notes,
        'roles', v_roles,
        'security', v_security,
        'reset_artifacts', v_reset_artifacts,
        'dashboard_access', v_dashboard_access
    );
end;
$$;


ALTER FUNCTION "public"."get_user_admin_detail_payload_state"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_admin_list_payload_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'user_id', user_id,
                'email', email,
                'is_active', is_active,
                'failed_login_count', failed_login_count,
                'last_failed_login_at', last_failed_login_at,
                'locked_until', locked_until,
                'lockout_count', lockout_count,
                'post_lockout_final_attempt_allowed', post_lockout_final_attempt_allowed,
                'is_disabled', is_disabled,
                'disabled_at', disabled_at,
                'disabled_reason', disabled_reason,
                'password_reset_pending', password_reset_pending,
                'temporary_password_issued_at', temporary_password_issued_at,
                'temporary_password_expires_at', temporary_password_expires_at,
                'outside_network_access_allowed', outside_network_access_allowed,
                'last_successful_login_at', last_successful_login_at,
                'security_status', security_status,
                'role_summary', role_summary
            )
            order by email asc
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_user_admin_list_summary;

    return jsonb_build_object(
        'status', 'user_admin_list_payload_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_user_admin_list_payload_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_admin_setting_access_state"("p_user_id" "uuid", "p_setting_key" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_requirement jsonb;
    v_required_permission text;
    v_has_requirement boolean := false;
    v_allowed boolean := false;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    if p_setting_key is null or btrim(p_setting_key) = '' then
        raise exception 'setting_key cannot be blank';
    end if;

    v_requirement := public.get_admin_setting_permission_requirement_state(
        p_setting_key
    );

    if (v_requirement ->> 'status') = 'admin_setting_not_found' then
        return jsonb_build_object(
            'status', 'admin_setting_not_found',
            'user_id', p_user_id,
            'setting_key', p_setting_key
        );
    end if;

    v_required_permission := v_requirement ->> 'required_permission';
    v_has_requirement := coalesce((v_requirement ->> 'has_permission_requirement')::boolean, false);

    if v_has_requirement and v_required_permission is not null then
        select exists (
            select 1
            from public.v_user_effective_permissions up
            where up.user_id = p_user_id
              and up.permission_key = v_required_permission
        )
        into v_allowed;
    else
        v_allowed := false;
    end if;

    return jsonb_build_object(
        'status', 'user_admin_setting_access_ready',
        'user_id', p_user_id,
        'setting_key', p_setting_key,
        'required_permission', v_required_permission,
        'has_permission_requirement', v_has_requirement,
        'allowed', v_allowed
    );
end;
$$;


ALTER FUNCTION "public"."get_user_admin_setting_access_state"("p_user_id" "uuid", "p_setting_key" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_admin_settings_access_matrix_state"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'setting_key', c.setting_key,
                'required_permission', c.required_permission,
                'has_permission_requirement', c.has_permission_requirement,
                'allowed',
                    case
                        when c.has_permission_requirement = true and c.required_permission is not null then
                            exists (
                                select 1
                                from public.v_user_effective_permissions up
                                where up.user_id = p_user_id
                                  and up.permission_key = c.required_permission
                            )
                        else false
                    end
            )
            order by c.setting_key asc
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_admin_settings_catalog c;

    return jsonb_build_object(
        'status', 'user_admin_settings_access_matrix_ready',
        'user_id', p_user_id,
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_user_admin_settings_access_matrix_state"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_auth_access_gate_state"("p_user_id" "uuid", "p_current_aal" "text" DEFAULT 'aal1'::"text", "p_checked_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
    v_gate_status text;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    if p_current_aal is null or btrim(p_current_aal) = '' then
        raise exception 'current_aal cannot be blank';
    end if;

    if p_current_aal not in ('aal1', 'aal2') then
        raise exception 'current_aal must be either aal1 or aal2';
    end if;

    select *
    into v_row
    from public.v_user_auth_entry_orchestration_state
    where user_id = p_user_id
    limit 1;

    v_gate_status :=
        case
            when v_row.is_active = false then 'inactive_user'
            when v_row.is_disabled = true then 'disabled_user'
            when v_row.locked_until is not null and v_row.locked_until > p_checked_at then 'locked_user'
            when v_row.password_reset_pending = true then 'password_reset_required'
            when v_row.mfa_required_for_all_users = true
                 and coalesce(v_row.has_mfa_enrolled_event, false) = false
                then 'mfa_enrollment_required'
            when v_row.mfa_required_for_all_users = true
                 and p_current_aal <> 'aal2'
                then 'mfa_challenge_required'
            else 'auth_access_ready'
        end;

    return jsonb_build_object(
        'status', v_gate_status,
        'checked_at', p_checked_at,
        'current_aal', p_current_aal,
        'user_id', v_row.user_id,
        'auth_user_id', v_row.auth_user_id,
        'email', v_row.email,
        'full_name', v_row.full_name,
        'is_active', v_row.is_active,
        'is_disabled', v_row.is_disabled,
        'disabled_at', v_row.disabled_at,
        'disabled_reason', v_row.disabled_reason,
        'failed_login_count', v_row.failed_login_count,
        'last_failed_login_at', v_row.last_failed_login_at,
        'locked_until', v_row.locked_until,
        'lockout_count', v_row.lockout_count,
        'post_lockout_final_attempt_allowed', v_row.post_lockout_final_attempt_allowed,
        'password_reset_pending', v_row.password_reset_pending,
        'temporary_password_issued_at', v_row.temporary_password_issued_at,
        'temporary_password_expires_at', v_row.temporary_password_expires_at,
        'outside_network_access_allowed', v_row.outside_network_access_allowed,
        'last_successful_login_at', v_row.last_successful_login_at,
        'mfa_required_for_all_users', v_row.mfa_required_for_all_users,
        'has_mfa_enrolled_event', v_row.has_mfa_enrolled_event,
        'last_mfa_enrolled_at', v_row.last_mfa_enrolled_at,
        'latest_auth_security_event_id', v_row.latest_auth_security_event_id,
        'latest_auth_event_type', v_row.latest_auth_event_type,
        'latest_auth_factor_type', v_row.latest_auth_factor_type,
        'latest_auth_event_status', v_row.latest_auth_event_status,
        'latest_auth_event_details', v_row.latest_auth_event_details,
        'latest_auth_recorded_at', v_row.latest_auth_recorded_at,
        'base_auth_gate_status', v_row.base_auth_gate_status
    );
end;
$$;


ALTER FUNCTION "public"."get_user_auth_access_gate_state"("p_user_id" "uuid", "p_current_aal" "text", "p_checked_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_auth_access_gate_state_by_email"("p_email" "text", "p_current_aal" "text" DEFAULT 'aal1'::"text", "p_checked_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
    v_gate_status text;
begin
    if p_email is null or btrim(p_email) = '' then
        raise exception 'email cannot be blank';
    end if;

    if p_current_aal is null or btrim(p_current_aal) = '' then
        raise exception 'current_aal cannot be blank';
    end if;

    if p_current_aal not in ('aal1', 'aal2') then
        raise exception 'current_aal must be either aal1 or aal2';
    end if;

    select *
    into v_row
    from public.v_user_auth_entry_orchestration_state
    where lower(email) = lower(p_email)
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'auth_user_not_found',
            'email', p_email,
            'checked_at', p_checked_at
        );
    end if;

    v_gate_status :=
        case
            when v_row.is_active = false then 'inactive_user'
            when v_row.is_disabled = true then 'disabled_user'
            when v_row.locked_until is not null and v_row.locked_until > p_checked_at then 'locked_user'
            when v_row.password_reset_pending = true then 'password_reset_required'
            when v_row.mfa_required_for_all_users = true
                 and coalesce(v_row.has_mfa_enrolled_event, false) = false
                then 'mfa_enrollment_required'
            when v_row.mfa_required_for_all_users = true
                 and p_current_aal <> 'aal2'
                then 'mfa_challenge_required'
            else 'auth_access_ready'
        end;

    return jsonb_build_object(
        'status', v_gate_status,
        'checked_at', p_checked_at,
        'current_aal', p_current_aal,
        'user_id', v_row.user_id,
        'auth_user_id', v_row.auth_user_id,
        'email', v_row.email,
        'full_name', v_row.full_name,
        'is_active', v_row.is_active,
        'is_disabled', v_row.is_disabled,
        'disabled_at', v_row.disabled_at,
        'disabled_reason', v_row.disabled_reason,
        'failed_login_count', v_row.failed_login_count,
        'last_failed_login_at', v_row.last_failed_login_at,
        'locked_until', v_row.locked_until,
        'lockout_count', v_row.lockout_count,
        'post_lockout_final_attempt_allowed', v_row.post_lockout_final_attempt_allowed,
        'password_reset_pending', v_row.password_reset_pending,
        'temporary_password_issued_at', v_row.temporary_password_issued_at,
        'temporary_password_expires_at', v_row.temporary_password_expires_at,
        'outside_network_access_allowed', v_row.outside_network_access_allowed,
        'last_successful_login_at', v_row.last_successful_login_at,
        'mfa_required_for_all_users', v_row.mfa_required_for_all_users,
        'has_mfa_enrolled_event', v_row.has_mfa_enrolled_event,
        'last_mfa_enrolled_at', v_row.last_mfa_enrolled_at,
        'latest_auth_security_event_id', v_row.latest_auth_security_event_id,
        'latest_auth_event_type', v_row.latest_auth_event_type,
        'latest_auth_factor_type', v_row.latest_auth_factor_type,
        'latest_auth_event_status', v_row.latest_auth_event_status,
        'latest_auth_event_details', v_row.latest_auth_event_details,
        'latest_auth_recorded_at', v_row.latest_auth_recorded_at,
        'base_auth_gate_status', v_row.base_auth_gate_status
    );
end;
$$;


ALTER FUNCTION "public"."get_user_auth_access_gate_state_by_email"("p_email" "text", "p_current_aal" "text", "p_checked_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_auth_security_event_history_state"("p_user_id" "uuid", "p_limit" integer DEFAULT 50) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
    v_effective_limit integer;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    v_effective_limit := greatest(coalesce(p_limit, 50), 1);

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'auth_security_event_id', auth_security_event_id,
                'user_id', user_id,
                'email', email,
                'full_name', full_name,
                'event_type', event_type,
                'factor_type', factor_type,
                'event_status', event_status,
                'details', details,
                'recorded_by_user_id', recorded_by_user_id,
                'recorded_by_email', recorded_by_email,
                'recorded_by_full_name', recorded_by_full_name,
                'recorded_at', recorded_at
            )
            order by recorded_at desc, auth_security_event_id desc
        ),
        '[]'::jsonb
    )
    into v_items
    from (
        select *
        from public.v_user_auth_security_event_history
        where user_id = p_user_id
        order by recorded_at desc, auth_security_event_id desc
        limit v_effective_limit
    ) x;

    return jsonb_build_object(
        'status', 'user_auth_security_event_history_ready',
        'user_id', p_user_id,
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_user_auth_security_event_history_state"("p_user_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_email_outbound_history_state"("p_user_id" "uuid", "p_limit" integer DEFAULT 50) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
    v_effective_limit integer;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    v_effective_limit := greatest(coalesce(p_limit, 50), 1);

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'email_outbound_message_id', email_outbound_message_id,
                'email_provider', email_provider,
                'message_type', message_type,
                'template_key', template_key,
                'to_email', to_email,
                'from_email', from_email,
                'subject', subject,
                'provider_message_id', provider_message_id,
                'send_status', send_status,
                'queued_at', queued_at,
                'sent_at', sent_at,
                'failed_at', failed_at,
                'last_event_at', last_event_at,
                'related_reservation_id', related_reservation_id,
                'related_transportation_event_id', related_transportation_event_id,
                'created_by_user_id', created_by_user_id,
                'created_by_email', created_by_email
            )
            order by queued_at desc, email_outbound_message_id desc
        ),
        '[]'::jsonb
    )
    into v_items
    from (
        select *
        from public.v_email_outbound_message_state
        where related_user_id = p_user_id
        order by queued_at desc, email_outbound_message_id desc
        limit v_effective_limit
    ) x;

    return jsonb_build_object(
        'status', 'user_email_outbound_history_ready',
        'user_id', p_user_id,
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_user_email_outbound_history_state"("p_user_id" "uuid", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_login_precheck_state_by_email"("p_email" "text", "p_reference_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_user_id uuid;
    v_row record;
    v_is_locked boolean := false;
    v_post_lockout_final_attempt_stage boolean := false;
    v_temp_password_is_expired boolean := false;
begin
    if p_email is null or btrim(p_email) = '' then
        raise exception 'Email cannot be blank';
    end if;

    select id
    into v_user_id
    from public.app_users
    where lower(email) = lower(p_email)
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'login_user_not_found',
            'email', p_email
        );
    end if;

    perform public.ensure_user_security_state(v_user_id);

    select
        u.id as user_id,
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
        s.last_successful_login_at
    into v_row
    from public.app_users u
    join public.app_user_security s
      on s.user_id = u.id
    where u.id = v_user_id
    limit 1;

    v_is_locked := (v_row.locked_until is not null and p_reference_at < v_row.locked_until);

    v_post_lockout_final_attempt_stage :=
        (
            v_row.locked_until is not null
            and p_reference_at >= v_row.locked_until
            and coalesce(v_row.post_lockout_final_attempt_allowed, false) = true
            and coalesce(v_row.is_disabled, false) = false
        );

    v_temp_password_is_expired :=
        (
            v_row.temporary_password_expires_at is not null
            and p_reference_at > v_row.temporary_password_expires_at
        );

    return jsonb_build_object(
        'status', 'login_precheck_ready',
        'user_id', v_row.user_id,
        'email', v_row.email,
        'is_active', v_row.is_active,
        'failed_login_count', v_row.failed_login_count,
        'last_failed_login_at', v_row.last_failed_login_at,
        'locked_until', v_row.locked_until,
        'lockout_count', v_row.lockout_count,
        'is_locked', v_is_locked,
        'post_lockout_final_attempt_allowed', v_row.post_lockout_final_attempt_allowed,
        'post_lockout_final_attempt_stage', v_post_lockout_final_attempt_stage,
        'is_disabled', v_row.is_disabled,
        'disabled_at', v_row.disabled_at,
        'disabled_reason', v_row.disabled_reason,
        'password_reset_pending', v_row.password_reset_pending,
        'temporary_password_issued_at', v_row.temporary_password_issued_at,
        'temporary_password_expires_at', v_row.temporary_password_expires_at,
        'temporary_password_is_expired', v_temp_password_is_expired,
        'outside_network_access_allowed', v_row.outside_network_access_allowed,
        'last_successful_login_at', v_row.last_successful_login_at,
        'auth_status',
            case
                when coalesce(v_row.is_disabled, false) then 'disabled'
                when v_is_locked then 'locked'
                when coalesce(v_row.password_reset_pending, false) then 'password_reset_pending'
                when coalesce(v_row.is_active, false) = false then 'inactive'
                else 'active'
            end
    );
end;
$$;


ALTER FUNCTION "public"."get_user_login_precheck_state_by_email"("p_email" "text", "p_reference_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_outside_network_access_state"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_allowed boolean := false;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    perform public.ensure_user_security_state(p_user_id);

    select outside_network_access_allowed
    into v_allowed
    from public.app_user_security
    where user_id = p_user_id;

    return jsonb_build_object(
        'status', 'user_outside_network_access_ready',
        'user_id', p_user_id,
        'outside_network_access_allowed', coalesce(v_allowed, false)
    );
end;
$$;


ALTER FUNCTION "public"."get_user_outside_network_access_state"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_reset_artifact_state"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    perform public.ensure_user_security_state(p_user_id);

    select *
    into v_row
    from public.v_user_reset_artifact_state
    where user_id = p_user_id
    limit 1;

    return jsonb_build_object(
        'status', 'user_reset_artifact_state_ready',
        'user_id', v_row.user_id,
        'auth_user_id', v_row.auth_user_id,
        'email', v_row.email,
        'full_name', v_row.full_name,
        'phone', v_row.phone,
        'is_active', v_row.is_active,
        'password_reset_pending', v_row.password_reset_pending,
        'temporary_password_issued_at', v_row.temporary_password_issued_at,
        'temporary_password_expires_at', v_row.temporary_password_expires_at,
        'temporary_password_issued_by', v_row.temporary_password_issued_by,
        'is_disabled', v_row.is_disabled,
        'locked_until', v_row.locked_until,
        'post_lockout_final_attempt_allowed', v_row.post_lockout_final_attempt_allowed,
        'reset_token_id', v_row.reset_token_id,
        'token_hash', v_row.token_hash,
        'reset_mode', v_row.reset_mode,
        'token_issued_at', v_row.token_issued_at,
        'token_expires_at', v_row.token_expires_at,
        'token_issued_by_user_id', v_row.token_issued_by_user_id,
        'token_notes', v_row.token_notes,
        'active_usable_token_count', v_row.active_usable_token_count
    );
end;
$$;


ALTER FUNCTION "public"."get_user_reset_artifact_state"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_reset_entry_state_by_email"("p_email" "text", "p_reference_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_user_id uuid;
    v_user_state jsonb;
    v_settings record;
    v_temp_password_is_expired boolean := false;
    v_recommended_reset_mode text;
begin
    if p_email is null or btrim(p_email) = '' then
        raise exception 'Email cannot be blank';
    end if;

    select id
    into v_user_id
    from public.app_users
    where lower(email) = lower(p_email)
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'reset_user_not_found',
            'email', p_email
        );
    end if;

    select *
    into v_settings
    from public.v_security_admin_settings_state
    limit 1;

    v_user_state := public.get_user_login_precheck_state_by_email(
        p_email,
        p_reference_at
    );

    v_temp_password_is_expired :=
        coalesce((v_user_state ->> 'temporary_password_is_expired')::boolean, false);

    v_recommended_reset_mode :=
        case
            when coalesce(v_settings.email_password_reset_link_enabled, false) = true then 'email_link'
            else 'temporary_password'
        end;

    return jsonb_build_object(
        'status', 'reset_entry_state_ready',
        'email', p_email,
        'user_id', (v_user_state ->> 'user_id')::uuid,
        'email_password_reset_link_enabled', v_settings.email_password_reset_link_enabled,
        'recommended_reset_mode', v_recommended_reset_mode,
        'password_reset_pending', coalesce((v_user_state ->> 'password_reset_pending')::boolean, false),
        'temporary_password_issued_at', (v_user_state ->> 'temporary_password_issued_at'),
        'temporary_password_expires_at', (v_user_state ->> 'temporary_password_expires_at'),
        'temporary_password_is_expired', v_temp_password_is_expired,
        'is_disabled', coalesce((v_user_state ->> 'is_disabled')::boolean, false),
        'auth_status', (v_user_state ->> 'auth_status')
    );
end;
$$;


ALTER FUNCTION "public"."get_user_reset_entry_state_by_email"("p_email" "text", "p_reference_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_role_names_state"("p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_roles jsonb;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    select coalesce(
        jsonb_agg(role_name order by role_name),
        '[]'::jsonb
    )
    into v_roles
    from (
        select distinct r.role_name
        from public.user_roles ur
        join public.roles r
          on r.id = ur.role_id
        where ur.user_id = p_user_id
    ) x(role_name);

    return jsonb_build_object(
        'status', 'user_roles_ready',
        'user_id', p_user_id,
        'roles', v_roles
    );
end;
$$;


ALTER FUNCTION "public"."get_user_role_names_state"("p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_security_detail_state"("p_user_id" "uuid", "p_reference_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
    v_is_locked boolean := false;
    v_post_lockout_final_attempt_stage boolean := false;
    v_temp_password_is_expired boolean := false;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    perform public.ensure_user_security_state(p_user_id);

    select
        u.id as user_id,
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
        s.last_successful_login_at
    into v_row
    from public.app_users u
    join public.app_user_security s
      on s.user_id = u.id
    where u.id = p_user_id
    limit 1;

    v_is_locked := (v_row.locked_until is not null and p_reference_at < v_row.locked_until);

    v_post_lockout_final_attempt_stage :=
        (
            v_row.locked_until is not null
            and p_reference_at >= v_row.locked_until
            and coalesce(v_row.post_lockout_final_attempt_allowed, false) = true
            and coalesce(v_row.is_disabled, false) = false
        );

    v_temp_password_is_expired :=
        (
            v_row.temporary_password_expires_at is not null
            and p_reference_at > v_row.temporary_password_expires_at
        );

    return jsonb_build_object(
        'status', 'user_security_detail_ready',
        'user_id', v_row.user_id,
        'auth_user_id', v_row.auth_user_id,
        'email', v_row.email,
        'full_name', v_row.full_name,
        'phone', v_row.phone,
        'is_active', v_row.is_active,
        'failed_login_count', v_row.failed_login_count,
        'last_failed_login_at', v_row.last_failed_login_at,
        'locked_until', v_row.locked_until,
        'lockout_count', v_row.lockout_count,
        'is_locked', v_is_locked,
        'post_lockout_final_attempt_allowed', v_row.post_lockout_final_attempt_allowed,
        'post_lockout_final_attempt_stage', v_post_lockout_final_attempt_stage,
        'is_disabled', v_row.is_disabled,
        'disabled_at', v_row.disabled_at,
        'disabled_reason', v_row.disabled_reason,
        'password_reset_pending', v_row.password_reset_pending,
        'temporary_password_issued_at', v_row.temporary_password_issued_at,
        'temporary_password_expires_at', v_row.temporary_password_expires_at,
        'temporary_password_is_expired', v_temp_password_is_expired,
        'temporary_password_issued_by', v_row.temporary_password_issued_by,
        'outside_network_access_allowed', v_row.outside_network_access_allowed,
        'last_successful_login_at', v_row.last_successful_login_at
    );
end;
$$;


ALTER FUNCTION "public"."get_user_security_detail_state"("p_user_id" "uuid", "p_reference_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_utilization_snapshot_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_total_vehicles integer := 0;
    v_vehicles_out integer := 0;
    v_vehicles_available integer := 0;
begin
    select count(*)
    into v_total_vehicles
    from public.vehicles;

    select count(distinct ve.vehicle_id)
    into v_vehicles_out
    from public.vehicle_events ve
    where ve.is_open = true;

    v_vehicles_available := greatest(v_total_vehicles - v_vehicles_out, 0);

    return jsonb_build_object(
        'status', 'utilization_snapshot_ready',
        'total_vehicles', v_total_vehicles,
        'vehicles_out', v_vehicles_out,
        'vehicles_available', v_vehicles_available
    );
end;
$$;


ALTER FUNCTION "public"."get_utilization_snapshot_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_vehicle_by_vin_state"("p_vin" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    if p_vin is null or btrim(p_vin) = '' then
        raise exception 'vin cannot be blank';
    end if;

    select *
    into v_row
    from public.v_vehicle_operational_state
    where vin = p_vin
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'vehicle_not_found',
            'vin', p_vin
        );
    end if;

    return jsonb_build_object(
        'status', 'vehicle_found',
        'vehicle_id', v_row.vehicle_id,
        'created_at', v_row.created_at,
        'vin', v_row.vin,
        'stock_number', v_row.stock_number,
        'model', v_row.model,
        'fleet_type', v_row.fleet_type,
        'vehicle_status', v_row.status,
        'mileage', v_row.mileage,
        'recon_status', v_row.recon_status,
        'current_tag', v_row.current_tag,
        'fleet_conversion_type', v_row.fleet_conversion_type,
        'location', v_row.location,
        'notes', v_row.notes,
        'active_transportation_event_id', v_row.active_transportation_event_id,
        'vehicle_event_id', v_row.vehicle_event_id,
        'contract_period_id', v_row.contract_period_id,
        'actual_out_at', v_row.actual_out_at,
        'contract_out_at', v_row.contract_out_at,
        'renewal_sequence', v_row.renewal_sequence,
        'vehicle_event_is_open', v_row.vehicle_event_is_open,
        'contract_period_is_open', v_row.contract_period_is_open
    );
end;
$$;


ALTER FUNCTION "public"."get_vehicle_by_vin_state"("p_vin" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_vehicle_ctp_monitoring_list_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            to_jsonb(x)
            order by x.ctp_program_active desc, x.vin asc
        ),
        '[]'::jsonb
    )
    into v_items
    from (
        select
            vehicle_id,
            vin,
            stock_number,
            model,
            fleet_type,
            vehicle_status,
            current_mileage,
            ctp_program_active,
            ctp_program_entered_at,
            ctp_entry_mileage,
            ctp_monitoring_notes,
            preferred_max_ctp_days,
            preferred_max_ctp_qualified_miles,
            current_ctp_day_number,
            current_ctp_qualified_miles,
            is_at_or_over_preferred_ctp_days,
            is_at_or_over_preferred_ctp_qualified_miles,
            ctp_monitoring_status
        from public.v_vehicle_ctp_monitoring_state
    ) x;

    return jsonb_build_object(
        'status', 'vehicle_ctp_monitoring_list_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_vehicle_ctp_monitoring_list_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_vehicle_ctp_monitoring_state"("p_vehicle_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_vehicle_ctp_monitoring_state
    where vehicle_id = p_vehicle_id
    limit 1;

    if not found then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    return jsonb_build_object(
        'status', 'vehicle_ctp_monitoring_state_ready',
        'vehicle_id', v_row.vehicle_id,
        'vin', v_row.vin,
        'stock_number', v_row.stock_number,
        'model', v_row.model,
        'fleet_type', v_row.fleet_type,
        'vehicle_status', v_row.vehicle_status,
        'current_mileage', v_row.current_mileage,
        'ctp_program_active', v_row.ctp_program_active,
        'ctp_program_entered_at', v_row.ctp_program_entered_at,
        'ctp_entry_mileage', v_row.ctp_entry_mileage,
        'ctp_monitoring_notes', v_row.ctp_monitoring_notes,
        'preferred_max_ctp_days', v_row.preferred_max_ctp_days,
        'preferred_max_ctp_qualified_miles', v_row.preferred_max_ctp_qualified_miles,
        'current_ctp_day_number', v_row.current_ctp_day_number,
        'current_ctp_qualified_miles', v_row.current_ctp_qualified_miles,
        'is_at_or_over_preferred_ctp_days', v_row.is_at_or_over_preferred_ctp_days,
        'is_at_or_over_preferred_ctp_qualified_miles', v_row.is_at_or_over_preferred_ctp_qualified_miles,
        'ctp_monitoring_status', v_row.ctp_monitoring_status
    );
end;
$$;


ALTER FUNCTION "public"."get_vehicle_ctp_monitoring_state"("p_vehicle_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_vehicle_operational_aggregate_list_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_items jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'vehicle_id', vehicle_id,
                'created_at', created_at,
                'vin', vin,
                'stock_number', stock_number,
                'model', model,
                'fleet_type', fleet_type,
                'vehicle_status', vehicle_status,
                'mileage', mileage,
                'recon_status', recon_status,
                'current_tag', current_tag,
                'fleet_conversion_type', fleet_conversion_type,
                'location', location,
                'notes', notes,
                'active_transportation_event_id', active_transportation_event_id,
                'vehicle_event_id', vehicle_event_id,
                'contract_period_id', contract_period_id,
                'actual_out_at', actual_out_at,
                'contract_out_at', contract_out_at,
                'renewal_sequence', renewal_sequence,
                'vehicle_event_is_open', vehicle_event_is_open,
                'contract_period_is_open', contract_period_is_open,
                'latest_expected_return_at', latest_expected_return_at,
                'assigned_reservation_count', assigned_reservation_count,
                'candidate_reservation_count', candidate_reservation_count,
                'unresolved_dependency_count', unresolved_dependency_count,
                'unresolved_conflict_count', unresolved_conflict_count
            )
            order by model asc, stock_number asc, vehicle_id
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_vehicle_operational_aggregate_state;

    return jsonb_build_object(
        'status', 'vehicle_operational_aggregate_list_ready',
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_vehicle_operational_aggregate_list_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_vehicle_operational_payload_state"("p_vehicle_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_summary record;
    v_vehicle_base jsonb;
    v_assigned_reservations jsonb;
    v_unresolved_dependencies jsonb;
    v_current_billing_lines jsonb;
begin
    select *
    into v_summary
    from public.v_vehicle_operational_aggregate_state
    where vehicle_id = p_vehicle_id
    limit 1;

    if not found then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    v_vehicle_base := public.get_vehicle_operational_state(
        p_vehicle_id
    );

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'reservation_id', r.reservation_id,
                'transportation_event_id', r.transportation_event_id,
                'vehicle_id', r.vehicle_id,
                'start_date', r.start_date,
                'expected_return_datetime', r.expected_return_datetime,
                'reservation_status', r.reservation_status,
                'reservation_type', r.reservation_type,
                'reservation_notes', r.reservation_notes,
                'cancellation_reason', r.cancellation_reason,
                'requested_model', r.requested_model,
                'service_advisor', r.service_advisor,
                'ro_number', r.ro_number,
                'pay_type', r.pay_type,
                'actual_return_datetime', r.actual_return_datetime,
                'billed_through_datetime', r.billed_through_datetime,
                'customer_id', r.customer_id
            )
            order by r.start_date asc nulls last, r.reservation_id
        ),
        '[]'::jsonb
    )
    into v_assigned_reservations
    from public.v_reservation_transportation_link_state r
    where r.vehicle_id = p_vehicle_id
      and r.reservation_status is distinct from 'cancelled';

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'dependency_id', d.dependency_id,
                'reservation_id', d.reservation_id,
                'vehicle_id', d.vehicle_id,
                'source_transportation_event_id', d.source_transportation_event_id,
                'dependency_type', d.dependency_type,
                'status', d.status,
                'risk_level', d.risk_level,
                'expected_return_snapshot', d.expected_return_snapshot,
                'notes', d.notes,
                'created_at', d.created_at,
                'updated_at', d.updated_at,
                'created_by_user_id', d.created_by_user_id,
                'updated_by_user_id', d.updated_by_user_id
            )
            order by d.updated_at desc nulls last, d.created_at desc nulls last, d.dependency_id
        ),
        '[]'::jsonb
    )
    into v_unresolved_dependencies
    from public.v_unresolved_reservation_dependencies d
    where d.vehicle_id = p_vehicle_id;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'parent_billing_line_id', b.parent_billing_line_id,
                'transportation_event_id', b.transportation_event_id,
                'reservation_id', b.reservation_id,
                'vehicle_id', b.vehicle_id,
                'vehicle_event_id', b.vehicle_event_id,
                'contract_period_id', b.contract_period_id,
                'pay_type', b.pay_type,
                'pay_type_rule_id', b.pay_type_rule_id,
                'parent_amount', b.parent_amount,
                'parent_tax_amount', b.parent_tax_amount,
                'start_time', b.start_time,
                'end_time', b.end_time,
                'parent_line_type', b.parent_line_type,
                'warranty_provider_id', b.warranty_provider_id,
                'default_covered_days_snapshot', b.default_covered_days_snapshot,
                'covered_days_override', b.covered_days_override,
                'default_daily_rate_snapshot', b.default_daily_rate_snapshot,
                'daily_rate_override', b.daily_rate_override,
                'paid_through_at', b.paid_through_at,
                'extended_from_billing_line_id', b.extended_from_billing_line_id,
                'parent_is_open', b.parent_is_open,
                'tax_billing_line_id', b.tax_billing_line_id,
                'tax_line_amount', b.tax_line_amount,
                'tax_line_is_open', b.tax_line_is_open
            )
            order by b.start_time asc nulls last, b.parent_billing_line_id
        ),
        '[]'::jsonb
    )
    into v_current_billing_lines
    from public.v_current_open_billing_lines b
    where b.vehicle_id = p_vehicle_id;

    return jsonb_build_object(
        'status', 'vehicle_operational_payload_ready',
        'vehicle_id', p_vehicle_id,
        'vehicle_base', v_vehicle_base,
        'summary', jsonb_build_object(
            'assigned_reservation_count', v_summary.assigned_reservation_count,
            'candidate_reservation_count', v_summary.candidate_reservation_count,
            'unresolved_dependency_count', v_summary.unresolved_dependency_count,
            'unresolved_conflict_count', v_summary.unresolved_conflict_count,
            'latest_expected_return_at', v_summary.latest_expected_return_at
        ),
        'assigned_reservations', v_assigned_reservations,
        'unresolved_dependencies', v_unresolved_dependencies,
        'current_billing_lines', v_current_billing_lines
    );
end;
$$;


ALTER FUNCTION "public"."get_vehicle_operational_payload_state"("p_vehicle_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_vehicle_operational_state"("p_vehicle_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_vehicle_operational_state
    where vehicle_id = p_vehicle_id
    limit 1;

    if not found then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    return jsonb_build_object(
        'status', 'vehicle_operational_state_ready',
        'vehicle_id', v_row.vehicle_id,
        'created_at', v_row.created_at,
        'vin', v_row.vin,
        'stock_number', v_row.stock_number,
        'model', v_row.model,
        'fleet_type', v_row.fleet_type,
        'vehicle_status', v_row.status,
        'mileage', v_row.mileage,
        'recon_status', v_row.recon_status,
        'current_tag', v_row.current_tag,
        'fleet_conversion_type', v_row.fleet_conversion_type,
        'location', v_row.location,
        'notes', v_row.notes,
        'active_transportation_event_id', v_row.active_transportation_event_id,
        'vehicle_event_id', v_row.vehicle_event_id,
        'contract_period_id', v_row.contract_period_id,
        'actual_out_at', v_row.actual_out_at,
        'contract_out_at', v_row.contract_out_at,
        'renewal_sequence', v_row.renewal_sequence,
        'vehicle_event_is_open', v_row.vehicle_event_is_open,
        'contract_period_is_open', v_row.contract_period_is_open
    );
end;
$$;


ALTER FUNCTION "public"."get_vehicle_operational_state"("p_vehicle_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_vehicle_qr_action_entry_state"("p_vehicle_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    select *
    into v_row
    from public.v_vehicle_qr_action_entry_state
    where vehicle_id = p_vehicle_id
    limit 1;

    if not found then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    return jsonb_build_object(
        'status', 'vehicle_qr_action_entry_state_ready',
        'vehicle_id', v_row.vehicle_id,
        'vin', v_row.vin,
        'stock_number', v_row.stock_number,
        'model', v_row.model,
        'fleet_type', v_row.fleet_type,
        'vehicle_status', v_row.vehicle_status,
        'mileage', v_row.mileage,
        'location', v_row.location,
        'vehicle_qr_code_id', v_row.vehicle_qr_code_id,
        'qr_token', v_row.qr_token,
        'landing_mode', v_row.landing_mode,
        'qr_is_active', v_row.qr_is_active,
        'qr_issued_at', v_row.qr_issued_at,
        'vehicle_is_available_now', v_row.vehicle_is_available_now,
        'available_scan_actions', v_row.available_scan_actions
    );
end;
$$;


ALTER FUNCTION "public"."get_vehicle_qr_action_entry_state"("p_vehicle_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_vehicle_scan_session_state"("p_vehicle_scan_session_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_session record;
    v_items jsonb;
begin
    select *
    into v_session
    from public.v_vehicle_scan_session_history
    where vehicle_scan_session_id = p_vehicle_scan_session_id
    limit 1;

    if not found then
        raise exception 'Vehicle scan session % does not exist', p_vehicle_scan_session_id;
    end if;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'vehicle_scan_event_id', vehicle_scan_event_id,
                'vehicle_id', vehicle_id,
                'vin', vin,
                'stock_number', stock_number,
                'model', model,
                'vehicle_qr_code_id', vehicle_qr_code_id,
                'qr_token', qr_token,
                'scan_session_id', scan_session_id,
                'session_type', session_type,
                'scanned_by_user_id', scanned_by_user_id,
                'scanned_by_email', scanned_by_email,
                'scanned_by_full_name', scanned_by_full_name,
                'action_type', action_type,
                'result_status', result_status,
                'scanned_at', scanned_at,
                'related_reservation_id', related_reservation_id,
                'related_transportation_event_id', related_transportation_event_id,
                'metadata', metadata
            )
            order by scanned_at desc, vehicle_scan_event_id desc
        ),
        '[]'::jsonb
    )
    into v_items
    from public.v_vehicle_scan_event_history
    where scan_session_id = p_vehicle_scan_session_id;

    return jsonb_build_object(
        'status', 'vehicle_scan_session_state_ready',
        'vehicle_scan_session_id', v_session.vehicle_scan_session_id,
        'session_type', v_session.session_type,
        'started_by_user_id', v_session.started_by_user_id,
        'started_by_email', v_session.started_by_email,
        'started_by_full_name', v_session.started_by_full_name,
        'started_at', v_session.started_at,
        'ended_at', v_session.ended_at,
        'session_status', v_session.session_status,
        'notes', v_session.notes,
        'scan_event_count', v_session.scan_event_count,
        'items', v_items
    );
end;
$$;


ALTER FUNCTION "public"."get_vehicle_scan_session_state"("p_vehicle_scan_session_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_warning_center_counts_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_critical_count integer := 0;
    v_warning_count integer := 0;
    v_review_count integer := 0;
begin
    -- Critical from unresolved conflicts and critical dependency states
    select count(*)
    into v_critical_count
    from (
        select c.id
        from public.reservation_conflicts c
        where c.is_resolved = false
          and c.severity = 'critical'

        union

        select d.id
        from public.reservation_vehicle_dependencies d
        where d.status = 'conflict'
           or d.risk_level = 'critical'
    ) x;

    -- Warning from dependency risk levels and urgent reminder states
    select count(*)
    into v_warning_count
    from (
        select d.id
        from public.reservation_vehicle_dependencies d
        where d.status in ('pending_return', 'ready', 'conflict')
          and d.risk_level in ('at_risk', 'must_return')

        union

        select m.contract_period_id
        from public.v_contract_period_monitoring m
        where m.reminder_state in ('renew_now', 'swap_required')
    ) x;

    -- Review Needed from lower-urgency dependency/reminder states
    select count(*)
    into v_review_count
    from (
        select d.id
        from public.reservation_vehicle_dependencies d
        where d.status in ('pending_return', 'ready', 'conflict')
          and d.risk_level = 'depends_on_return'

        union

        select m.contract_period_id
        from public.v_contract_period_monitoring m
        where m.reminder_state in ('renew_soon')
    ) x;

    return jsonb_build_object(
        'status', 'warning_center_counts_ready',
        'critical_count', v_critical_count,
        'warning_count', v_warning_count,
        'review_count', v_review_count
    );
end;
$$;


ALTER FUNCTION "public"."get_warning_center_counts_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_warning_center_detail_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_critical jsonb;
    v_warning jsonb;
    v_review jsonb;
begin
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'item_type', item_type,
                'source_id', source_id,
                'reservation_id', reservation_id,
                'vehicle_id', vehicle_id,
                'risk_level', risk_level,
                'source_status', source_status,
                'expected_return_snapshot', expected_return_snapshot,
                'contract_period_id', contract_period_id,
                'reminder_state', reminder_state,
                'message', message
            )
        ),
        '[]'::jsonb
    )
    into v_critical
    from public.v_warning_center_critical_items;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'item_type', item_type,
                'source_id', source_id,
                'reservation_id', reservation_id,
                'vehicle_id', vehicle_id,
                'risk_level', risk_level,
                'source_status', source_status,
                'expected_return_snapshot', expected_return_snapshot,
                'contract_period_id', contract_period_id,
                'reminder_state', reminder_state,
                'message', message
            )
        ),
        '[]'::jsonb
    )
    into v_warning
    from public.v_warning_center_warning_items;

    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'item_type', item_type,
                'source_id', source_id,
                'reservation_id', reservation_id,
                'vehicle_id', vehicle_id,
                'risk_level', risk_level,
                'source_status', source_status,
                'expected_return_snapshot', expected_return_snapshot,
                'contract_period_id', contract_period_id,
                'reminder_state', reminder_state,
                'message', message
            )
        ),
        '[]'::jsonb
    )
    into v_review
    from public.v_warning_center_review_items;

    return jsonb_build_object(
        'status', 'warning_center_detail_ready',
        'critical', v_critical,
        'warning', v_warning,
        'review_needed', v_review
    );
end;
$$;


ALTER FUNCTION "public"."get_warning_center_detail_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."invalidate_reset_tokens_for_user_state"("p_user_id" "uuid", "p_invalidated_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_count integer := 0;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    update public.app_user_reset_tokens
    set
        is_active = false,
        updated_at = p_invalidated_at
    where user_id = p_user_id
      and is_active = true
      and used_at is null;

    get diagnostics v_count = row_count;

    return jsonb_build_object(
        'status', 'reset_tokens_invalidated',
        'user_id', p_user_id,
        'invalidated_count', v_count,
        'invalidated_at', p_invalidated_at
    );
end;
$$;


ALTER FUNCTION "public"."invalidate_reset_tokens_for_user_state"("p_user_id" "uuid", "p_invalidated_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."issue_admin_password_reset_package_state"("p_target_user_id" "uuid", "p_admin_user_id" "uuid", "p_issue_email_link" boolean DEFAULT false, "p_token_hash" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text", "p_issued_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_settings record;
    v_reset_state_result jsonb;
    v_token_id uuid := null;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_target_user_id
    ) then
        raise exception 'Target user % does not exist', p_target_user_id;
    end if;

    if not exists (
        select 1
        from public.app_users
        where id = p_admin_user_id
    ) then
        raise exception 'Admin user % does not exist', p_admin_user_id;
    end if;

    select *
    into v_settings
    from public.v_security_admin_settings_state
    limit 1;

    -- Start/reset the DB-side admin reset pending state
    v_reset_state_result := public.begin_admin_password_reset_state(
        p_target_user_id,
        p_admin_user_id,
        p_issued_at
    );

    -- Optionally issue an email-link token if enabled
    if p_issue_email_link then
        if coalesce(v_settings.email_password_reset_link_enabled, false) = false then
            raise exception 'Email password reset link feature is disabled';
        end if;

        if p_token_hash is null or btrim(p_token_hash) = '' then
            raise exception 'token_hash is required when issuing email reset-link state';
        end if;

        v_token_id := public.create_reset_token_state(
            p_target_user_id,
            p_token_hash,
            'email_link',
            p_admin_user_id,
            p_issued_at,
            p_notes
        );
    end if;

    return jsonb_build_object(
        'status', 'admin_password_reset_package_issued',
        'target_user_id', p_target_user_id,
        'admin_user_id', p_admin_user_id,
        'reset_state_result', v_reset_state_result,
        'email_link_issued', p_issue_email_link,
        'reset_token_id', v_token_id
    );
end;
$$;


ALTER FUNCTION "public"."issue_admin_password_reset_package_state"("p_target_user_id" "uuid", "p_admin_user_id" "uuid", "p_issue_email_link" boolean, "p_token_hash" "text", "p_notes" "text", "p_issued_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."issue_new_user_password_setup_package_state"("p_user_id" "uuid", "p_admin_user_id" "uuid", "p_issue_email_link" boolean DEFAULT false, "p_token_hash" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text", "p_issued_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_settings record;
    v_reset_state_result jsonb;
    v_token_id uuid := null;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    if not exists (
        select 1
        from public.app_users
        where id = p_admin_user_id
    ) then
        raise exception 'Admin user % does not exist', p_admin_user_id;
    end if;

    select *
    into v_settings
    from public.v_security_admin_settings_state
    limit 1;

    -- Reuse admin reset pending state for new-user first-login setup
    v_reset_state_result := public.begin_admin_password_reset_state(
        p_user_id,
        p_admin_user_id,
        p_issued_at
    );

    if p_issue_email_link then
        if coalesce(v_settings.email_password_reset_link_enabled, false) = false then
            raise exception 'Email password reset link feature is disabled';
        end if;

        if p_token_hash is null or btrim(p_token_hash) = '' then
            raise exception 'token_hash is required when issuing email reset-link state';
        end if;

        v_token_id := public.create_reset_token_state(
            p_user_id,
            p_token_hash,
            'email_link',
            p_admin_user_id,
            p_issued_at,
            p_notes
        );
    end if;

    return jsonb_build_object(
        'status', 'new_user_password_setup_package_issued',
        'user_id', p_user_id,
        'admin_user_id', p_admin_user_id,
        'reset_state_result', v_reset_state_result,
        'email_link_issued', p_issue_email_link,
        'reset_token_id', v_token_id
    );
end;
$$;


ALTER FUNCTION "public"."issue_new_user_password_setup_package_state"("p_user_id" "uuid", "p_admin_user_id" "uuid", "p_issue_email_link" boolean, "p_token_hash" "text", "p_notes" "text", "p_issued_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."issue_vehicle_qr_code_state"("p_vehicle_id" "uuid", "p_issued_by_user_id" "uuid" DEFAULT NULL::"uuid", "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_qr_id uuid;
    v_qr_token text;
begin
    if not exists (
        select 1
        from public.vehicles
        where id = p_vehicle_id
    ) then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    if p_issued_by_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_issued_by_user_id
       ) then
        raise exception 'Issued-by user % does not exist', p_issued_by_user_id;
    end if;

    update public.vehicle_qr_codes
    set
        is_active = false,
        retired_at = now()
    where vehicle_id = p_vehicle_id
      and is_active = true;

    v_qr_token := gen_random_uuid()::text;

    insert into public.vehicle_qr_codes (
        vehicle_id,
        qr_token,
        landing_mode,
        is_active,
        issued_at,
        issued_by_user_id,
        notes
    )
    values (
        p_vehicle_id,
        v_qr_token,
        'vehicle_action_hub',
        true,
        now(),
        p_issued_by_user_id,
        p_notes
    )
    returning id into v_qr_id;

    return jsonb_build_object(
        'status', 'vehicle_qr_code_issued',
        'vehicle_qr_code_id', v_qr_id,
        'vehicle_id', p_vehicle_id,
        'qr_token', v_qr_token
    );
end;
$$;


ALTER FUNCTION "public"."issue_vehicle_qr_code_state"("p_vehicle_id" "uuid", "p_issued_by_user_id" "uuid", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_email_outbound_message_failed_state"("p_email_outbound_message_id" "uuid", "p_provider_response" "jsonb" DEFAULT NULL::"jsonb", "p_failed_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.email_outbound_messages
        where id = p_email_outbound_message_id
    ) then
        raise exception 'Email outbound message % does not exist', p_email_outbound_message_id;
    end if;

    update public.email_outbound_messages
    set
        send_status = 'failed',
        provider_response = p_provider_response,
        failed_at = p_failed_at,
        last_event_at = p_failed_at
    where id = p_email_outbound_message_id;

    return jsonb_build_object(
        'status', 'email_outbound_message_marked_failed',
        'email_outbound_message_id', p_email_outbound_message_id,
        'failed_at', p_failed_at
    );
end;
$$;


ALTER FUNCTION "public"."mark_email_outbound_message_failed_state"("p_email_outbound_message_id" "uuid", "p_provider_response" "jsonb", "p_failed_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_email_outbound_message_sent_state"("p_email_outbound_message_id" "uuid", "p_provider_message_id" "text", "p_provider_response" "jsonb" DEFAULT NULL::"jsonb", "p_sent_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.email_outbound_messages
        where id = p_email_outbound_message_id
    ) then
        raise exception 'Email outbound message % does not exist', p_email_outbound_message_id;
    end if;

    if p_provider_message_id is null or btrim(p_provider_message_id) = '' then
        raise exception 'provider_message_id cannot be blank';
    end if;

    update public.email_outbound_messages
    set
        provider_message_id = p_provider_message_id,
        send_status = 'sent',
        provider_response = p_provider_response,
        sent_at = p_sent_at,
        last_event_at = p_sent_at
    where id = p_email_outbound_message_id;

    return jsonb_build_object(
        'status', 'email_outbound_message_marked_sent',
        'email_outbound_message_id', p_email_outbound_message_id,
        'provider_message_id', p_provider_message_id,
        'sent_at', p_sent_at
    );
end;
$$;


ALTER FUNCTION "public"."mark_email_outbound_message_sent_state"("p_email_outbound_message_id" "uuid", "p_provider_message_id" "text", "p_provider_response" "jsonb", "p_sent_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."queue_email_outbound_message_state"("p_message_type" "text", "p_to_email" "text", "p_from_email" "text", "p_subject" "text" DEFAULT NULL::"text", "p_template_key" "text" DEFAULT NULL::"text", "p_related_user_id" "uuid" DEFAULT NULL::"uuid", "p_related_customer_id" "uuid" DEFAULT NULL::"uuid", "p_related_reservation_id" "uuid" DEFAULT NULL::"uuid", "p_related_transportation_event_id" "uuid" DEFAULT NULL::"uuid", "p_created_by_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_message_id uuid;
begin
    if p_message_type is null or btrim(p_message_type) = '' then
        raise exception 'message_type cannot be blank';
    end if;

    if p_to_email is null or btrim(p_to_email) = '' then
        raise exception 'to_email cannot be blank';
    end if;

    if p_from_email is null or btrim(p_from_email) = '' then
        raise exception 'from_email cannot be blank';
    end if;

    if p_related_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_related_user_id
       ) then
        raise exception 'Related user % does not exist', p_related_user_id;
    end if;

    if p_related_customer_id is not null
       and not exists (
            select 1
            from public.customers
            where id = p_related_customer_id
       ) then
        raise exception 'Related customer % does not exist', p_related_customer_id;
    end if;

    if p_related_reservation_id is not null
       and not exists (
            select 1
            from public.reservations
            where id = p_related_reservation_id
       ) then
        raise exception 'Related reservation % does not exist', p_related_reservation_id;
    end if;

    if p_related_transportation_event_id is not null
       and not exists (
            select 1
            from public.transportation_events
            where id = p_related_transportation_event_id
       ) then
        raise exception 'Related transportation event % does not exist', p_related_transportation_event_id;
    end if;

    if p_created_by_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_created_by_user_id
       ) then
        raise exception 'Created-by user % does not exist', p_created_by_user_id;
    end if;

    insert into public.email_outbound_messages (
        email_provider,
        message_type,
        template_key,
        related_user_id,
        related_customer_id,
        related_reservation_id,
        related_transportation_event_id,
        to_email,
        from_email,
        subject,
        send_status,
        queued_at,
        created_by_user_id
    )
    values (
        'resend',
        p_message_type,
        p_template_key,
        p_related_user_id,
        p_related_customer_id,
        p_related_reservation_id,
        p_related_transportation_event_id,
        p_to_email,
        p_from_email,
        p_subject,
        'queued',
        now(),
        p_created_by_user_id
    )
    returning id into v_message_id;

    return jsonb_build_object(
        'status', 'email_outbound_message_queued',
        'email_outbound_message_id', v_message_id,
        'message_type', p_message_type,
        'to_email', p_to_email,
        'from_email', p_from_email
    );
end;
$$;


ALTER FUNCTION "public"."queue_email_outbound_message_state"("p_message_type" "text", "p_to_email" "text", "p_from_email" "text", "p_subject" "text", "p_template_key" "text", "p_related_user_id" "uuid", "p_related_customer_id" "uuid", "p_related_reservation_id" "uuid", "p_related_transportation_event_id" "uuid", "p_created_by_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reassign_active_case_to_vehicle_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone, "p_actor_user_id" "uuid" DEFAULT NULL::"uuid", "p_resolve_current_dependency" boolean DEFAULT true) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_action_result jsonb;
    v_unified_payload jsonb;
begin
    v_action_result := public.reassign_active_case_to_vehicle_state(
        p_reservation_id,
        p_new_vehicle_id,
        p_swap_time,
        p_actor_user_id,
        p_resolve_current_dependency
    );

    v_unified_payload := public.get_unified_case_payload_state(
        p_reservation_id
    );

    return jsonb_build_object(
        'status', 'case_reassigned_and_loaded',
        'reservation_id', p_reservation_id,
        'action_result', v_action_result,
        'unified_case_payload', v_unified_payload
    );
end;
$$;


ALTER FUNCTION "public"."reassign_active_case_to_vehicle_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone, "p_actor_user_id" "uuid", "p_resolve_current_dependency" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reassign_active_case_to_vehicle_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone, "p_actor_user_id" "uuid" DEFAULT NULL::"uuid", "p_resolve_current_dependency" boolean DEFAULT true) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_candidate record;
    v_swap_result jsonb;
    v_dependency_resolution_result jsonb := null;
begin
    select *
    into v_candidate
    from public.v_case_reassignment_candidate_state
    where reservation_id = p_reservation_id
    limit 1;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if not exists (
        select 1
        from public.vehicles
        where id = p_new_vehicle_id
    ) then
        raise exception 'Vehicle % does not exist', p_new_vehicle_id;
    end if;

    if p_actor_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_actor_user_id
       ) then
        raise exception 'Actor user % does not exist', p_actor_user_id;
    end if;

    if p_swap_time is null then
        raise exception 'swap_time cannot be null';
    end if;

    if coalesce(v_candidate.has_active_continuity, false) = false then
        raise exception 'Reservation % does not currently have active continuity to swap', p_reservation_id;
    end if;

    v_swap_result := public.swap_reservation_vehicle_state(
        p_reservation_id,
        p_new_vehicle_id,
        p_swap_time
    );

    if p_resolve_current_dependency
       and v_candidate.current_dependency_id is not null then
        v_dependency_resolution_result := public.resolve_reservation_dependency_as_reassigned_state(
            p_reservation_id,
            p_actor_user_id
        );
    end if;

    return jsonb_build_object(
        'status', 'active_case_reassigned_to_vehicle',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_candidate.transportation_event_id,
        'old_vehicle_event_id', v_candidate.current_vehicle_event_id,
        'new_vehicle_id', p_new_vehicle_id,
        'swap_time', p_swap_time,
        'swap_result', v_swap_result,
        'dependency_resolution_result', v_dependency_resolution_result
    );
end;
$$;


ALTER FUNCTION "public"."reassign_active_case_to_vehicle_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone, "p_actor_user_id" "uuid", "p_resolve_current_dependency" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_email_provider_webhook_event_state"("p_provider_name" "text", "p_event_type" "text", "p_provider_message_id" "text" DEFAULT NULL::"text", "p_email_outbound_message_id" "uuid" DEFAULT NULL::"uuid", "p_provider_event_id" "text" DEFAULT NULL::"text", "p_event_payload" "jsonb" DEFAULT NULL::"jsonb", "p_occurred_at" timestamp with time zone DEFAULT "now"(), "p_received_at" timestamp with time zone DEFAULT "now"(), "p_processed_status" "text" DEFAULT 'received'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_event_id uuid;
    v_message_id uuid;
    v_new_message_status text := null;
begin
    if p_provider_name is null or btrim(p_provider_name) = '' then
        raise exception 'provider_name cannot be blank';
    end if;

    if p_event_type is null or btrim(p_event_type) = '' then
        raise exception 'event_type cannot be blank';
    end if;

    if p_email_outbound_message_id is not null
       and not exists (
            select 1
            from public.email_outbound_messages
            where id = p_email_outbound_message_id
       ) then
        raise exception 'Email outbound message % does not exist', p_email_outbound_message_id;
    end if;

    v_message_id := p_email_outbound_message_id;

    if v_message_id is null and p_provider_message_id is not null then
        select id
        into v_message_id
        from public.email_outbound_messages
        where provider_message_id = p_provider_message_id
        order by queued_at desc, id desc
        limit 1;
    end if;

    insert into public.email_provider_webhook_events (
        email_outbound_message_id,
        provider_name,
        provider_event_id,
        provider_message_id,
        event_type,
        event_payload,
        occurred_at,
        received_at,
        processed_status
    )
    values (
        v_message_id,
        p_provider_name,
        p_provider_event_id,
        p_provider_message_id,
        p_event_type,
        p_event_payload,
        p_occurred_at,
        p_received_at,
        p_processed_status
    )
    returning id into v_event_id;

    v_new_message_status :=
        case
            when lower(p_event_type) in ('email.sent', 'sent') then 'sent'
            when lower(p_event_type) in ('email.delivered', 'delivered') then 'delivered'
            when lower(p_event_type) in ('email.bounced', 'bounced') then 'bounced'
            when lower(p_event_type) in ('email.complained', 'complained') then 'complained'
            when lower(p_event_type) in ('email.opened', 'opened') then 'opened'
            when lower(p_event_type) in ('email.clicked', 'clicked') then 'clicked'
            else null
        end;

    if v_message_id is not null then
        update public.email_outbound_messages
        set
            last_event_at = greatest(coalesce(last_event_at, p_occurred_at), p_occurred_at),
            send_status = coalesce(v_new_message_status, send_status)
        where id = v_message_id;
    end if;

    return jsonb_build_object(
        'status', 'email_provider_webhook_event_recorded',
        'email_webhook_event_id', v_event_id,
        'email_outbound_message_id', v_message_id,
        'provider_name', p_provider_name,
        'event_type', p_event_type,
        'provider_message_id', p_provider_message_id,
        'processed_status', p_processed_status
    );
end;
$$;


ALTER FUNCTION "public"."record_email_provider_webhook_event_state"("p_provider_name" "text", "p_event_type" "text", "p_provider_message_id" "text", "p_email_outbound_message_id" "uuid", "p_provider_event_id" "text", "p_event_payload" "jsonb", "p_occurred_at" timestamp with time zone, "p_received_at" timestamp with time zone, "p_processed_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_failed_login_attempt"("p_user_id" "uuid", "p_attempted_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_state public.app_user_security%rowtype;
    v_new_failed_count integer;
begin
    perform public.ensure_user_security_state(p_user_id);

    select *
    into v_state
    from public.app_user_security
    where user_id = p_user_id
    for update;

    -- Already disabled
    if v_state.is_disabled then
        return jsonb_build_object(
            'status', 'disabled',
            'failed_login_count', v_state.failed_login_count,
            'locked_until', v_state.locked_until,
            'is_disabled', v_state.is_disabled
        );
    end if;

    -- Still inside active lockout window
    if v_state.locked_until is not null and p_attempted_at < v_state.locked_until then
        return jsonb_build_object(
            'status', 'locked',
            'failed_login_count', v_state.failed_login_count,
            'locked_until', v_state.locked_until,
            'is_disabled', v_state.is_disabled
        );
    end if;

    -- Post-lockout final-attempt failure => disable account
    if v_state.post_lockout_final_attempt_allowed
       and v_state.locked_until is not null
       and p_attempted_at >= v_state.locked_until then

        update public.app_user_security
        set
            is_disabled = true,
            disabled_at = p_attempted_at,
            disabled_reason = 'failed_login_after_lockout',
            updated_at = now()
        where user_id = p_user_id;

        return jsonb_build_object(
            'status', 'disabled_after_post_lockout_failure',
            'failed_login_count', v_state.failed_login_count,
            'locked_until', null,
            'is_disabled', true
        );
    end if;

    v_new_failed_count := coalesce(v_state.failed_login_count, 0) + 1;

    -- 3rd cumulative failure => lock for 24 hours
    if v_new_failed_count >= 3 then
        update public.app_user_security
        set
            failed_login_count = v_new_failed_count,
            last_failed_login_at = p_attempted_at,
            locked_until = p_attempted_at + interval '24 hours',
            lockout_count = coalesce(lockout_count, 0) + 1,
            post_lockout_final_attempt_allowed = true,
            updated_at = now()
        where user_id = p_user_id;

        return jsonb_build_object(
            'status', 'locked_24h',
            'failed_login_count', v_new_failed_count,
            'locked_until', p_attempted_at + interval '24 hours',
            'is_disabled', false
        );
    end if;

    update public.app_user_security
    set
        failed_login_count = v_new_failed_count,
        last_failed_login_at = p_attempted_at,
        updated_at = now()
    where user_id = p_user_id;

    return jsonb_build_object(
        'status', 'failed',
        'failed_login_count', v_new_failed_count,
        'locked_until', null,
        'is_disabled', false
    );
end;
$$;


ALTER FUNCTION "public"."record_failed_login_attempt"("p_user_id" "uuid", "p_attempted_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_successful_login"("p_user_id" "uuid", "p_logged_in_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    perform public.ensure_user_security_state(p_user_id);

    update public.app_user_security
    set
        failed_login_count = 0,
        last_failed_login_at = null,
        locked_until = null,
        post_lockout_final_attempt_allowed = false,
        last_successful_login_at = p_logged_in_at,
        updated_at = now()
    where user_id = p_user_id;

    return jsonb_build_object(
        'status', 'login_success',
        'failed_login_count', 0,
        'locked_until', null,
        'is_disabled', false
    );
end;
$$;


ALTER FUNCTION "public"."record_successful_login"("p_user_id" "uuid", "p_logged_in_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_user_auth_security_event_state"("p_user_id" "uuid", "p_event_type" "text", "p_factor_type" "text" DEFAULT NULL::"text", "p_event_status" "text" DEFAULT NULL::"text", "p_details" "jsonb" DEFAULT NULL::"jsonb", "p_recorded_by_user_id" "uuid" DEFAULT NULL::"uuid", "p_recorded_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_event_id uuid;
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    if p_event_type is null or btrim(p_event_type) = '' then
        raise exception 'event_type cannot be blank';
    end if;

    if p_recorded_by_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_recorded_by_user_id
       ) then
        raise exception 'Recorded-by user % does not exist', p_recorded_by_user_id;
    end if;

    insert into public.user_auth_security_events (
        user_id,
        event_type,
        factor_type,
        event_status,
        details,
        recorded_by_user_id,
        recorded_at
    )
    values (
        p_user_id,
        p_event_type,
        p_factor_type,
        p_event_status,
        p_details,
        p_recorded_by_user_id,
        p_recorded_at
    )
    returning id into v_event_id;

    return jsonb_build_object(
        'status', 'user_auth_security_event_recorded',
        'auth_security_event_id', v_event_id,
        'user_id', p_user_id,
        'event_type', p_event_type,
        'factor_type', p_factor_type,
        'event_status', p_event_status,
        'recorded_at', p_recorded_at
    );
end;
$$;


ALTER FUNCTION "public"."record_user_auth_security_event_state"("p_user_id" "uuid", "p_event_type" "text", "p_factor_type" "text", "p_event_status" "text", "p_details" "jsonb", "p_recorded_by_user_id" "uuid", "p_recorded_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_user_mfa_event_state"("p_user_id" "uuid", "p_event_type" "text", "p_event_status" "text" DEFAULT NULL::"text", "p_details" "jsonb" DEFAULT NULL::"jsonb", "p_recorded_by_user_id" "uuid" DEFAULT NULL::"uuid", "p_recorded_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if p_event_type is null or btrim(p_event_type) = '' then
        raise exception 'event_type cannot be blank';
    end if;

    return public.record_user_auth_security_event_state(
        p_user_id,
        p_event_type,
        'totp_authenticator',
        p_event_status,
        p_details,
        p_recorded_by_user_id,
        p_recorded_at
    );
end;
$$;


ALTER FUNCTION "public"."record_user_mfa_event_state"("p_user_id" "uuid", "p_event_type" "text", "p_event_status" "text", "p_details" "jsonb", "p_recorded_by_user_id" "uuid", "p_recorded_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_vehicle_scan_event_state"("p_vehicle_id" "uuid", "p_action_type" "text", "p_scanned_by_user_id" "uuid", "p_scan_session_id" "uuid" DEFAULT NULL::"uuid", "p_vehicle_qr_token" "text" DEFAULT NULL::"text", "p_related_reservation_id" "uuid" DEFAULT NULL::"uuid", "p_related_transportation_event_id" "uuid" DEFAULT NULL::"uuid", "p_metadata" "jsonb" DEFAULT NULL::"jsonb", "p_scanned_at" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_vehicle_qr_code_id uuid := null;
    v_scan_event_id uuid;
begin
    if not exists (
        select 1
        from public.vehicles
        where id = p_vehicle_id
    ) then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    if p_action_type is null or btrim(p_action_type) = '' then
        raise exception 'action_type cannot be blank';
    end if;

    if not exists (
        select 1
        from public.app_users
        where id = p_scanned_by_user_id
    ) then
        raise exception 'Scanned-by user % does not exist', p_scanned_by_user_id;
    end if;

    if p_scan_session_id is not null
       and not exists (
            select 1
            from public.vehicle_scan_sessions
            where id = p_scan_session_id
       ) then
        raise exception 'Vehicle scan session % does not exist', p_scan_session_id;
    end if;

    if p_related_reservation_id is not null
       and not exists (
            select 1
            from public.reservations
            where id = p_related_reservation_id
       ) then
        raise exception 'Related reservation % does not exist', p_related_reservation_id;
    end if;

    if p_related_transportation_event_id is not null
       and not exists (
            select 1
            from public.transportation_events
            where id = p_related_transportation_event_id
       ) then
        raise exception 'Related transportation event % does not exist', p_related_transportation_event_id;
    end if;

    if p_vehicle_qr_token is not null then
        select id
        into v_vehicle_qr_code_id
        from public.vehicle_qr_codes
        where vehicle_id = p_vehicle_id
          and qr_token = p_vehicle_qr_token
          and is_active = true
        order by issued_at desc, id desc
        limit 1;

        if v_vehicle_qr_code_id is null then
            raise exception 'Active QR token % does not match vehicle %', p_vehicle_qr_token, p_vehicle_id;
        end if;
    end if;

    insert into public.vehicle_scan_events (
        vehicle_id,
        vehicle_qr_code_id,
        scan_session_id,
        scanned_by_user_id,
        action_type,
        result_status,
        scanned_at,
        related_reservation_id,
        related_transportation_event_id,
        metadata
    )
    values (
        p_vehicle_id,
        v_vehicle_qr_code_id,
        p_scan_session_id,
        p_scanned_by_user_id,
        p_action_type,
        'recorded',
        p_scanned_at,
        p_related_reservation_id,
        p_related_transportation_event_id,
        p_metadata
    )
    returning id into v_scan_event_id;

    return jsonb_build_object(
        'status', 'vehicle_scan_event_recorded',
        'vehicle_scan_event_id', v_scan_event_id,
        'vehicle_id', p_vehicle_id,
        'action_type', p_action_type,
        'scan_session_id', p_scan_session_id,
        'vehicle_qr_code_id', v_vehicle_qr_code_id,
        'scanned_at', p_scanned_at
    );
end;
$$;


ALTER FUNCTION "public"."record_vehicle_scan_event_state"("p_vehicle_id" "uuid", "p_action_type" "text", "p_scanned_by_user_id" "uuid", "p_scan_session_id" "uuid", "p_vehicle_qr_token" "text", "p_related_reservation_id" "uuid", "p_related_transportation_event_id" "uuid", "p_metadata" "jsonb", "p_scanned_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_user_role_state"("p_user_id" "uuid", "p_role_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    if not exists (
        select 1
        from public.roles
        where id = p_role_id
    ) then
        raise exception 'Role % does not exist', p_role_id;
    end if;

    delete from public.user_roles
    where user_id = p_user_id
      and role_id = p_role_id;

    return jsonb_build_object(
        'status', 'role_removed_if_present',
        'user_id', p_user_id,
        'role_id', p_role_id
    );
end;
$$;


ALTER FUNCTION "public"."remove_user_role_state"("p_user_id" "uuid", "p_role_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."renew_reservation_same_vehicle_state"("p_reservation_id" "uuid", "p_new_contract_out_at" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_reservation record;
    v_current_continuity record;
    v_renew_result jsonb;
begin
    select *
    into v_reservation
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_new_contract_out_at is null then
        raise exception 'new_contract_out_at cannot be null';
    end if;

    if p_new_contract_out_at < v_reservation.start_date then
        raise exception 'new_contract_out_at % is before reservation start_date %',
            p_new_contract_out_at,
            v_reservation.start_date;
    end if;

    select *
    into v_current_continuity
    from public.v_current_vehicle_continuity
    where transportation_event_id = v_reservation.transportation_event_id
    limit 1;

    if not found then
        raise exception 'No active vehicle continuity exists for reservation %', p_reservation_id;
    end if;

    v_renew_result := public.renew_same_vehicle_state(
        v_current_continuity.vehicle_event_id,
        p_new_contract_out_at
    );

    return jsonb_build_object(
        'status', 'reservation_same_vehicle_renewed',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'vehicle_event_id', v_current_continuity.vehicle_event_id,
        'new_contract_out_at', p_new_contract_out_at,
        'continuity_renew_result', v_renew_result
    );
end;
$$;


ALTER FUNCTION "public"."renew_reservation_same_vehicle_state"("p_reservation_id" "uuid", "p_new_contract_out_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."renew_same_vehicle_state"("p_vehicle_event_id" "uuid", "p_new_contract_out_at" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_vehicle_event record;
    v_old_contract_period record;
    v_new_contract_period_id uuid;
    v_new_sequence integer;
begin
    select *
    into v_vehicle_event
    from public.vehicle_events
    where id = p_vehicle_event_id
      and is_open = true
    for update;

    if not found then
        raise exception 'Open vehicle_event % does not exist', p_vehicle_event_id;
    end if;

    select *
    into v_old_contract_period
    from public.contract_periods
    where vehicle_event_id = p_vehicle_event_id
      and is_open = true
    for update;

    if not found then
        raise exception 'Open contract_period for vehicle_event % does not exist', p_vehicle_event_id;
    end if;

    if p_new_contract_out_at < v_old_contract_period.contract_out_at then
        raise exception 'new contract_out_at % is before current contract_out_at %',
            p_new_contract_out_at,
            v_old_contract_period.contract_out_at;
    end if;

    update public.contract_periods
    set
        contract_in_at = p_new_contract_out_at,
        is_open = false
    where id = v_old_contract_period.id;

    v_new_sequence := coalesce(v_old_contract_period.renewal_sequence, 0) + 1;

    insert into public.contract_periods (
        vehicle_event_id,
        contract_out_at,
        contract_in_at,
        renewal_sequence,
        is_open
    )
    values (
        p_vehicle_event_id,
        p_new_contract_out_at,
        null,
        v_new_sequence,
        true
    )
    returning id into v_new_contract_period_id;

    return jsonb_build_object(
        'status', 'renewed_same_vehicle',
        'vehicle_event_id', p_vehicle_event_id,
        'old_contract_period_id', v_old_contract_period.id,
        'new_contract_period_id', v_new_contract_period_id,
        'renewal_sequence', v_new_sequence
    );
end;
$$;


ALTER FUNCTION "public"."renew_same_vehicle_state"("p_vehicle_event_id" "uuid", "p_new_contract_out_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reopen_transportation_event_state"("p_transportation_event_id" "uuid", "p_reopen_note" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_current_notes text;
begin
    if not exists (
        select 1
        from public.transportation_events
        where id = p_transportation_event_id
    ) then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    select notes
    into v_current_notes
    from public.transportation_events
    where id = p_transportation_event_id
    for update;

    update public.transportation_events
    set
        status = 'active',
        closed_at = null,
        closed_by = null,
        notes = case
            when p_reopen_note is null or btrim(p_reopen_note) = '' then v_current_notes
            when v_current_notes is null or btrim(v_current_notes) = '' then p_reopen_note
            else v_current_notes || E'\n' || p_reopen_note
        end,
        updated_at = now()
    where id = p_transportation_event_id;

    return jsonb_build_object(
        'status', 'transportation_event_reopened',
        'transportation_event_id', p_transportation_event_id
    );
end;
$$;


ALTER FUNCTION "public"."reopen_transportation_event_state"("p_transportation_event_id" "uuid", "p_reopen_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_dependencies_for_vehicle_return_state"("p_vehicle_id" "uuid", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_dependency_ids uuid[];
    v_ready_count integer := 0;
    v_conflict_count integer := 0;
begin
    if not exists (
        select 1
        from public.vehicles
        where id = p_vehicle_id
    ) then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    if p_actor_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_actor_user_id
       ) then
        raise exception 'Actor user % does not exist', p_actor_user_id;
    end if;

    select coalesce(array_agg(id), '{}'::uuid[])
    into v_dependency_ids
    from public.reservation_vehicle_dependencies
    where vehicle_id = p_vehicle_id
      and status in ('pending_return', 'conflict');

    update public.reservation_vehicle_dependencies
    set
        status = 'ready',
        risk_level = 'normal',
        source_transportation_event_id = null,
        expected_return_snapshot = null,
        updated_by_user_id = p_actor_user_id,
        updated_at = now()
    where vehicle_id = p_vehicle_id
      and status in ('pending_return', 'conflict');

    get diagnostics v_ready_count = row_count;

    update public.reservation_conflicts
    set is_resolved = true
    where reservation_vehicle_dependency_id = any(v_dependency_ids)
      and is_resolved = false;

    get diagnostics v_conflict_count = row_count;

    return jsonb_build_object(
        'status', 'vehicle_return_dependency_resolution_ready',
        'vehicle_id', p_vehicle_id,
        'dependencies_moved_to_ready', v_ready_count,
        'conflicts_resolved', v_conflict_count
    );
end;
$$;


ALTER FUNCTION "public"."resolve_dependencies_for_vehicle_return_state"("p_vehicle_id" "uuid", "p_actor_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_extended_warranty_provider_default_state"("p_provider_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_row record;
begin
    if not exists (
        select 1
        from public.warranty_providers
        where id = p_provider_id
    ) then
        raise exception 'Warranty provider % does not exist', p_provider_id;
    end if;

    select *
    into v_row
    from public.v_active_extended_warranty_provider_rules
    where provider_id = p_provider_id
    order by updated_at desc nulls last, created_at desc nulls last, rule_id desc
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'no_active_extended_warranty_rule',
            'provider_id', p_provider_id
        );
    end if;

    return jsonb_build_object(
        'status', 'extended_warranty_provider_default_ready',
        'provider_id', v_row.provider_id,
        'provider_name', v_row.provider_name,
        'provider_type', v_row.provider_type,
        'provider_default_daily_rate', v_row.provider_default_daily_rate,
        'rule_id', v_row.rule_id,
        'covered_days', v_row.covered_days,
        'requires_approval', v_row.requires_approval,
        'rule_daily_rate', v_row.rule_daily_rate,
        'resolved_daily_rate', v_row.resolved_daily_rate
    );
end;
$$;


ALTER FUNCTION "public"."resolve_extended_warranty_provider_default_state"("p_provider_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_linked_conflicts_for_dependency_state"("p_dependency_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_count integer := 0;
begin
    if not exists (
        select 1
        from public.reservation_vehicle_dependencies
        where id = p_dependency_id
    ) then
        raise exception 'Dependency % does not exist', p_dependency_id;
    end if;

    update public.reservation_conflicts
    set is_resolved = true
    where reservation_vehicle_dependency_id = p_dependency_id
      and is_resolved = false;

    get diagnostics v_count = row_count;

    return jsonb_build_object(
        'status', 'linked_conflicts_resolved',
        'dependency_id', p_dependency_id,
        'resolved_conflict_count', v_count
    );
end;
$$;


ALTER FUNCTION "public"."resolve_linked_conflicts_for_dependency_state"("p_dependency_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_over_due_pay_type_default_state"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_rule record;
begin
    select *
    into v_rule
    from public.v_current_pay_type_rules
    where pay_type = 'Over Due'
    order by sort_order asc nulls last
    limit 1;

    if not found then
        raise exception 'Over Due pay type does not exist in current pay type rules';
    end if;

    return jsonb_build_object(
        'status', 'over_due_pay_type_ready',
        'pay_type_rule_id', v_rule.pay_type_rule_id,
        'pay_type', v_rule.pay_type,
        'is_active', v_rule.is_active,
        'is_taxable', v_rule.is_taxable,
        'default_daily_amount', v_rule.default_daily_amount,
        'sort_order', v_rule.sort_order,
        'description', v_rule.description
    );
end;
$$;


ALTER FUNCTION "public"."resolve_over_due_pay_type_default_state"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_pay_type_rule_state"("p_pay_type" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_rule record;
begin
    select
        id,
        pay_type,
        is_active,
        is_taxable,
        default_daily_amount,
        sort_order,
        description
    into v_rule
    from public.pay_type_rules
    where pay_type = p_pay_type
    limit 1;

    if not found then
        raise exception 'Pay type % does not exist in public.pay_type_rules', p_pay_type;
    end if;

    return jsonb_build_object(
        'pay_type_rule_id', v_rule.id,
        'pay_type', v_rule.pay_type,
        'is_active', v_rule.is_active,
        'is_taxable', v_rule.is_taxable,
        'default_daily_amount', v_rule.default_daily_amount,
        'sort_order', v_rule.sort_order,
        'description', v_rule.description
    );
end;
$$;


ALTER FUNCTION "public"."resolve_pay_type_rule_state"("p_pay_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_reservation_conflict_state"("p_conflict_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_conflict record;
begin
    select *
    into v_conflict
    from public.reservation_conflicts
    where id = p_conflict_id
    for update;

    if not found then
        raise exception 'Conflict % does not exist', p_conflict_id;
    end if;

    update public.reservation_conflicts
    set
        is_resolved = true
    where id = p_conflict_id;

    return jsonb_build_object(
        'status', 'conflict_resolved',
        'conflict_id', p_conflict_id
    );
end;
$$;


ALTER FUNCTION "public"."resolve_reservation_conflict_state"("p_conflict_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_reservation_dependency_as_reassigned_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_dependency record;
    v_result jsonb;
begin
    if not exists (
        select 1
        from public.reservations
        where id = p_reservation_id
    ) then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_actor_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_actor_user_id
       ) then
        raise exception 'Actor user % does not exist', p_actor_user_id;
    end if;

    select *
    into v_dependency
    from public.reservation_vehicle_dependencies
    where reservation_id = p_reservation_id
      and status in ('pending_return', 'ready', 'conflict')
    order by updated_at desc nulls last, created_at desc nulls last
    limit 1
    for update;

    if not found then
        return jsonb_build_object(
            'status', 'no_active_dependency_for_reservation',
            'reservation_id', p_reservation_id
        );
    end if;

    v_result := public.resolve_reservation_dependency_state(
        v_dependency.id,
        'reassigned',
        p_actor_user_id
    );

    return jsonb_build_object(
        'status', 'reservation_dependency_resolved_as_reassigned',
        'reservation_id', p_reservation_id,
        'dependency_id', v_dependency.id,
        'resolution_result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."resolve_reservation_dependency_as_reassigned_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_reservation_dependency_as_removed_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_dependency record;
    v_result jsonb;
begin
    if not exists (
        select 1
        from public.reservations
        where id = p_reservation_id
    ) then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_actor_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_actor_user_id
       ) then
        raise exception 'Actor user % does not exist', p_actor_user_id;
    end if;

    select *
    into v_dependency
    from public.reservation_vehicle_dependencies
    where reservation_id = p_reservation_id
      and status in ('pending_return', 'ready', 'conflict')
    order by updated_at desc nulls last, created_at desc nulls last
    limit 1
    for update;

    if not found then
        return jsonb_build_object(
            'status', 'no_active_dependency_for_reservation',
            'reservation_id', p_reservation_id
        );
    end if;

    v_result := public.resolve_reservation_dependency_state(
        v_dependency.id,
        'removed',
        p_actor_user_id
    );

    return jsonb_build_object(
        'status', 'reservation_dependency_resolved_as_removed',
        'reservation_id', p_reservation_id,
        'dependency_id', v_dependency.id,
        'resolution_result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."resolve_reservation_dependency_as_removed_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_reservation_dependency_state"("p_dependency_id" "uuid", "p_resolution_type" "text", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_dep record;
    v_conflict_result jsonb;
begin
    if p_resolution_type not in ('reassigned', 'vehicle_returned_available', 'removed', 'cancelled', 'other') then
        raise exception 'Invalid resolution_type: %', p_resolution_type;
    end if;

    select *
    into v_dep
    from public.reservation_vehicle_dependencies
    where id = p_dependency_id
    for update;

    if not found then
        raise exception 'Dependency % does not exist', p_dependency_id;
    end if;

    if p_actor_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_actor_user_id
       ) then
        raise exception 'Actor user % does not exist', p_actor_user_id;
    end if;

    update public.reservation_vehicle_dependencies
    set
        status = 'resolved',
        resolution_type = p_resolution_type,
        resolved_at = now(),
        resolved_by_user_id = p_actor_user_id,
        updated_by_user_id = p_actor_user_id,
        updated_at = now()
    where id = p_dependency_id;

    v_conflict_result := public.resolve_linked_conflicts_for_dependency_state(p_dependency_id);

    return jsonb_build_object(
        'status', 'dependency_resolved',
        'dependency_id', p_dependency_id,
        'resolution_type', p_resolution_type,
        'conflict_result', v_conflict_result
    );
end;
$$;


ALTER FUNCTION "public"."resolve_reservation_dependency_state"("p_dependency_id" "uuid", "p_resolution_type" "text", "p_actor_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_transportation_event_dependency_as_reassigned_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_te record;
    v_result jsonb;
begin
    select *
    into v_te
    from public.transportation_events
    where id = p_transportation_event_id
    limit 1;

    if not found then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    if v_te.source_type is distinct from 'reservation' or v_te.source_id is null then
        return jsonb_build_object(
            'status', 'transportation_event_not_reservation_sourced',
            'transportation_event_id', p_transportation_event_id
        );
    end if;

    v_result := public.resolve_reservation_dependency_as_reassigned_state(
        v_te.source_id,
        p_actor_user_id
    );

    return jsonb_build_object(
        'status', 'transportation_event_dependency_resolved_as_reassigned',
        'transportation_event_id', p_transportation_event_id,
        'reservation_id', v_te.source_id,
        'resolution_result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."resolve_transportation_event_dependency_as_reassigned_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_transportation_event_dependency_as_removed_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_te record;
    v_result jsonb;
begin
    select *
    into v_te
    from public.transportation_events
    where id = p_transportation_event_id
    limit 1;

    if not found then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    if v_te.source_type is distinct from 'reservation' or v_te.source_id is null then
        return jsonb_build_object(
            'status', 'transportation_event_not_reservation_sourced',
            'transportation_event_id', p_transportation_event_id
        );
    end if;

    v_result := public.resolve_reservation_dependency_as_removed_state(
        v_te.source_id,
        p_actor_user_id
    );

    return jsonb_build_object(
        'status', 'transportation_event_dependency_resolved_as_removed',
        'transportation_event_id', p_transportation_event_id,
        'reservation_id', v_te.source_id,
        'resolution_result', v_result
    );
end;
$$;


ALTER FUNCTION "public"."resolve_transportation_event_dependency_as_removed_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."restart_reservation_same_vehicle_after_gap_state"("p_reservation_id" "uuid", "p_new_actual_out_at" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_reservation record;
    v_restart_result jsonb;
begin
    select *
    into v_reservation
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if v_reservation.vehicle_id is null then
        raise exception 'Reservation % does not currently have an assigned vehicle_id', p_reservation_id;
    end if;

    if p_new_actual_out_at is null then
        raise exception 'new_actual_out_at cannot be null';
    end if;

    if p_new_actual_out_at < v_reservation.start_date then
        raise exception 'new_actual_out_at % is before reservation start_date %',
            p_new_actual_out_at,
            v_reservation.start_date;
    end if;

    v_restart_result := public.restart_same_vehicle_after_gap(
        v_reservation.transportation_event_id,
        v_reservation.vehicle_id,
        p_new_actual_out_at
    );

    return jsonb_build_object(
        'status', 'reservation_same_vehicle_restarted_after_gap',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'vehicle_id', v_reservation.vehicle_id,
        'new_actual_out_at', p_new_actual_out_at,
        'continuity_restart_result', v_restart_result
    );
end;
$$;


ALTER FUNCTION "public"."restart_reservation_same_vehicle_after_gap_state"("p_reservation_id" "uuid", "p_new_actual_out_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."return_reservation_vehicle_use_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer DEFAULT NULL::integer, "p_note" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_reservation record;
    v_current_continuity record;
    v_return_result jsonb;
    v_actual_return_result jsonb;
begin
    select *
    into v_reservation
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_actual_in_at is null then
        raise exception 'actual_in_at cannot be null';
    end if;

    if p_actual_in_at < v_reservation.start_date then
        raise exception 'actual_in_at % is before reservation start_date %',
            p_actual_in_at,
            v_reservation.start_date;
    end if;

    select *
    into v_current_continuity
    from public.v_current_vehicle_continuity
    where transportation_event_id = v_reservation.transportation_event_id
    limit 1;

    if not found then
        raise exception 'No active vehicle continuity exists for reservation %', p_reservation_id;
    end if;

    v_return_result := public.return_vehicle_state(
        v_current_continuity.vehicle_event_id,
        p_actual_in_at,
        'returned'
    );

    v_actual_return_result := public.set_reservation_actual_return_state(
        p_reservation_id,
        p_actual_in_at,
        p_end_mileage,
        p_note
    );

    return jsonb_build_object(
        'status', 'reservation_vehicle_use_returned',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'vehicle_event_id', v_current_continuity.vehicle_event_id,
        'actual_in_at', p_actual_in_at,
        'continuity_return_result', v_return_result,
        'reservation_actual_return_result', v_actual_return_result
    );
end;
$$;


ALTER FUNCTION "public"."return_reservation_vehicle_use_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer, "p_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."return_vehicle_state"("p_vehicle_event_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_ended_reason" "text" DEFAULT 'returned'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_vehicle_event record;
    v_contract_period record;
begin
    select *
    into v_vehicle_event
    from public.vehicle_events
    where id = p_vehicle_event_id
      and is_open = true
    for update;

    if not found then
        raise exception 'Open vehicle_event % does not exist', p_vehicle_event_id;
    end if;

    if p_actual_in_at < v_vehicle_event.actual_out_at then
        raise exception 'actual_in_at % is before actual_out_at %',
            p_actual_in_at,
            v_vehicle_event.actual_out_at;
    end if;

    select *
    into v_contract_period
    from public.contract_periods
    where vehicle_event_id = p_vehicle_event_id
      and is_open = true
    for update;

    if not found then
        raise exception 'Open contract_period for vehicle_event % does not exist', p_vehicle_event_id;
    end if;

    update public.contract_periods
    set
        contract_in_at = p_actual_in_at,
        is_open = false
    where id = v_contract_period.id;

    update public.vehicle_events
    set
        actual_in_at = p_actual_in_at,
        is_open = false,
        ended_reason = p_ended_reason
    where id = p_vehicle_event_id;

    return jsonb_build_object(
        'status', 'returned',
        'vehicle_event_id', p_vehicle_event_id,
        'contract_period_id', v_contract_period.id
    );
end;
$$;


ALTER FUNCTION "public"."return_vehicle_state"("p_vehicle_event_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_ended_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."select_soft_lock_candidate_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid", "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_candidate record;
    v_dependency_result jsonb;
begin
    if not exists (
        select 1
        from public.reservations
        where id = p_reservation_id
    ) then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_actor_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_actor_user_id
       ) then
        raise exception 'Actor user % does not exist', p_actor_user_id;
    end if;

    select *
    into v_candidate
    from public.v_reservation_vehicle_candidates
    where reservation_id = p_reservation_id
      and candidate_state in ('ready', 'pending_return')
    order by
        case candidate_state
            when 'ready' then 1
            when 'pending_return' then 2
            else 3
        end,
        expected_return_snapshot asc nulls last,
        stock_number asc nulls last,
        vin asc nulls last
    limit 1;

    if not found then
        return jsonb_build_object(
            'status', 'soft_lock_no_candidate',
            'reservation_id', p_reservation_id
        );
    end if;

    v_dependency_result := public.upsert_reservation_dependency_state(
        p_reservation_id,
        v_candidate.vehicle_id,
        v_candidate.source_transportation_event_id,
        'soft_lock',
        case
            when v_candidate.candidate_state = 'ready' then 'ready'
            else 'pending_return'
        end,
        case
            when v_candidate.candidate_state = 'ready' then 'normal'
            else 'depends_on_return'
        end,
        v_candidate.expected_return_snapshot,
        p_notes,
        p_actor_user_id
    );

    return jsonb_build_object(
        'status',
            case
                when v_candidate.candidate_state = 'ready' then 'soft_lock_ready'
                else 'soft_lock_depends_on_return'
            end,
        'reservation_id', p_reservation_id,
        'vehicle_id', v_candidate.vehicle_id,
        'candidate_state', v_candidate.candidate_state,
        'source_transportation_event_id', v_candidate.source_transportation_event_id,
        'expected_return_snapshot', v_candidate.expected_return_snapshot,
        'dependency_result', v_dependency_result
    );
end;
$$;


ALTER FUNCTION "public"."select_soft_lock_candidate_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_approved_network_active_state"("p_network_id" "uuid", "p_is_active" boolean, "p_updated_by_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.approved_networks
        where id = p_network_id
    ) then
        raise exception 'Approved network % does not exist', p_network_id;
    end if;

    if p_updated_by_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_updated_by_user_id
       ) then
        raise exception 'User % does not exist', p_updated_by_user_id;
    end if;

    update public.approved_networks
    set
        is_active = p_is_active,
        updated_at = now(),
        updated_by_user_id = p_updated_by_user_id
    where id = p_network_id;

    return jsonb_build_object(
        'status',
            case when p_is_active then 'approved_network_activated' else 'approved_network_deactivated' end,
        'approved_network_id', p_network_id,
        'is_active', p_is_active
    );
end;
$$;


ALTER FUNCTION "public"."set_approved_network_active_state"("p_network_id" "uuid", "p_is_active" boolean, "p_updated_by_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_email_password_reset_link_enabled_state"("p_enabled" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    insert into public.admin_settings (
        setting_key,
        setting_value,
        description
    )
    values (
        'email_password_reset_link_enabled',
        to_jsonb(p_enabled),
        'Whether users may use email reset-link flow instead of temporary-password-only reset flow'
    )
    on conflict (setting_key)
    do update set
        setting_value = excluded.setting_value,
        description = excluded.description;

    return jsonb_build_object(
        'status', 'email_password_reset_link_setting_updated',
        'email_password_reset_link_enabled', p_enabled
    );
end;
$$;


ALTER FUNCTION "public"."set_email_password_reset_link_enabled_state"("p_enabled" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_expected_return_state"("p_transportation_event_id" "uuid", "p_new_expected_return_at" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_old_expected_return_at timestamptz;
begin
    if not exists (
        select 1
        from public.transportation_events
        where id = p_transportation_event_id
    ) then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    select expected_return_at
    into v_old_expected_return_at
    from public.transportation_events
    where id = p_transportation_event_id
    for update;

    update public.transportation_events
    set
        expected_return_at = p_new_expected_return_at
    where id = p_transportation_event_id;

    return jsonb_build_object(
        'status', 'expected_return_updated',
        'transportation_event_id', p_transportation_event_id,
        'old_expected_return_at', v_old_expected_return_at,
        'new_expected_return_at', p_new_expected_return_at
    );
end;
$$;


ALTER FUNCTION "public"."set_expected_return_state"("p_transportation_event_id" "uuid", "p_new_expected_return_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_extended_warranty_rule_active_state"("p_rule_id" "uuid", "p_is_active" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.extended_warranty_rules
        where id = p_rule_id
    ) then
        raise exception 'Extended warranty rule % does not exist', p_rule_id;
    end if;

    update public.extended_warranty_rules
    set
        is_active = p_is_active,
        updated_at = now()
    where id = p_rule_id;

    return jsonb_build_object(
        'status',
            case when p_is_active then 'extended_warranty_rule_activated' else 'extended_warranty_rule_deactivated' end,
        'rule_id', p_rule_id,
        'is_active', p_is_active
    );
end;
$$;


ALTER FUNCTION "public"."set_extended_warranty_rule_active_state"("p_rule_id" "uuid", "p_is_active" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_late_fee_rule_active_state"("p_rule_id" "uuid", "p_is_active" boolean, "p_updated_by" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.late_fee_rules
        where id = p_rule_id
    ) then
        raise exception 'Late fee rule % does not exist', p_rule_id;
    end if;

    if p_updated_by is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_updated_by
       ) then
        raise exception 'User % does not exist', p_updated_by;
    end if;

    update public.late_fee_rules
    set
        is_active = p_is_active,
        updated_at = now(),
        updated_by = p_updated_by
    where id = p_rule_id;

    return jsonb_build_object(
        'status',
            case when p_is_active then 'late_fee_rule_activated' else 'late_fee_rule_deactivated' end,
        'late_fee_rule_id', p_rule_id,
        'is_active', p_is_active
    );
end;
$$;


ALTER FUNCTION "public"."set_late_fee_rule_active_state"("p_rule_id" "uuid", "p_is_active" boolean, "p_updated_by" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_late_fees_enabled_state"("p_enabled" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    insert into public.admin_settings (
        setting_key,
        setting_value,
        description
    )
    values (
        'late_fees_enabled',
        to_jsonb(p_enabled),
        'Global on/off switch for rental late fee engine'
    )
    on conflict (setting_key)
    do update set
        setting_value = excluded.setting_value,
        description = excluded.description;

    return jsonb_build_object(
        'status', 'late_fees_enabled_updated',
        'late_fees_enabled', p_enabled
    );
end;
$$;


ALTER FUNCTION "public"."set_late_fees_enabled_state"("p_enabled" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_mfa_required_for_all_users_state"("p_required" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    insert into public.admin_settings (
        setting_key,
        setting_value,
        description
    )
    values (
        'mfa_required_for_all_users',
        to_jsonb(p_required),
        'Require MFA (TOTP/authenticator app) for all users before normal app access'
    )
    on conflict (setting_key)
    do update set
        setting_value = excluded.setting_value,
        description = excluded.description;

    return jsonb_build_object(
        'status', 'mfa_required_for_all_users_updated',
        'mfa_required_for_all_users', p_required
    );
end;
$$;


ALTER FUNCTION "public"."set_mfa_required_for_all_users_state"("p_required" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_network_restriction_enabled_state"("p_enabled" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    insert into public.admin_settings (
        setting_key,
        setting_value,
        description
    )
    values (
        'network_restriction_enabled',
        to_jsonb(p_enabled),
        'Whether application access is restricted to approved networks unless a user has outside-network access'
    )
    on conflict (setting_key)
    do update set
        setting_value = excluded.setting_value,
        description = excluded.description;

    return jsonb_build_object(
        'status', 'network_restriction_updated',
        'network_restriction_enabled', p_enabled
    );
end;
$$;


ALTER FUNCTION "public"."set_network_restriction_enabled_state"("p_enabled" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_preferred_max_ctp_days_state"("p_preferred_max_ctp_days" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if p_preferred_max_ctp_days is null or p_preferred_max_ctp_days < 1 then
        raise exception 'preferred_max_ctp_days must be at least 1';
    end if;

    insert into public.admin_settings (
        setting_key,
        setting_value,
        description
    )
    values (
        'preferred_max_ctp_days',
        to_jsonb(p_preferred_max_ctp_days),
        'Preferred maximum days in CTP program before vehicle should be reviewed'
    )
    on conflict (setting_key)
    do update set
        setting_value = excluded.setting_value,
        description = excluded.description;

    return jsonb_build_object(
        'status', 'preferred_max_ctp_days_updated',
        'preferred_max_ctp_days', p_preferred_max_ctp_days
    );
end;
$$;


ALTER FUNCTION "public"."set_preferred_max_ctp_days_state"("p_preferred_max_ctp_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_preferred_max_ctp_qualified_miles_state"("p_preferred_max_ctp_qualified_miles" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if p_preferred_max_ctp_qualified_miles is null or p_preferred_max_ctp_qualified_miles < 0 then
        raise exception 'preferred_max_ctp_qualified_miles must be 0 or greater';
    end if;

    insert into public.admin_settings (
        setting_key,
        setting_value,
        description
    )
    values (
        'preferred_max_ctp_qualified_miles',
        to_jsonb(p_preferred_max_ctp_qualified_miles),
        'Preferred maximum qualified miles in CTP program before vehicle should be reviewed'
    )
    on conflict (setting_key)
    do update set
        setting_value = excluded.setting_value,
        description = excluded.description;

    return jsonb_build_object(
        'status', 'preferred_max_ctp_qualified_miles_updated',
        'preferred_max_ctp_qualified_miles', p_preferred_max_ctp_qualified_miles
    );
end;
$$;


ALTER FUNCTION "public"."set_preferred_max_ctp_qualified_miles_state"("p_preferred_max_ctp_qualified_miles" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_reservation_actual_return_state"("p_reservation_id" "uuid", "p_actual_return_datetime" timestamp with time zone, "p_end_mileage" integer DEFAULT NULL::integer, "p_note" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_reservation record;
    v_current_notes text;
begin
    select *
    into v_reservation
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_actual_return_datetime is null then
        raise exception 'actual_return_datetime cannot be null';
    end if;

    if p_actual_return_datetime < v_reservation.start_date then
        raise exception 'actual_return_datetime % is before start_date %',
            p_actual_return_datetime,
            v_reservation.start_date;
    end if;

    if p_end_mileage is not null and p_end_mileage < 0 then
        raise exception 'end_mileage must be non-negative';
    end if;

    select notes
    into v_current_notes
    from public.reservations
    where id = p_reservation_id;

    update public.reservations
    set
        actual_return_datetime = p_actual_return_datetime,
        end_mileage = p_end_mileage,
        notes = case
            when p_note is null or btrim(p_note) = '' then v_current_notes
            when v_current_notes is null or btrim(v_current_notes) = '' then p_note
            else v_current_notes || E'\n' || p_note
        end
    where id = p_reservation_id;

    return jsonb_build_object(
        'status', 'reservation_actual_return_set',
        'reservation_id', p_reservation_id,
        'actual_return_datetime', p_actual_return_datetime,
        'end_mileage', p_end_mileage
    );
end;
$$;


ALTER FUNCTION "public"."set_reservation_actual_return_state"("p_reservation_id" "uuid", "p_actual_return_datetime" timestamp with time zone, "p_end_mileage" integer, "p_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_reservation_billed_through_state"("p_reservation_id" "uuid", "p_billed_through_datetime" timestamp with time zone, "p_note" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_reservation record;
    v_current_notes text;
begin
    select *
    into v_reservation
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if p_billed_through_datetime is null then
        raise exception 'billed_through_datetime cannot be null';
    end if;

    if p_billed_through_datetime < v_reservation.start_date then
        raise exception 'billed_through_datetime % is before start_date %',
            p_billed_through_datetime,
            v_reservation.start_date;
    end if;

    select notes
    into v_current_notes
    from public.reservations
    where id = p_reservation_id;

    update public.reservations
    set
        billed_through_datetime = p_billed_through_datetime,
        notes = case
            when p_note is null or btrim(p_note) = '' then v_current_notes
            when v_current_notes is null or btrim(v_current_notes) = '' then p_note
            else v_current_notes || E'\n' || p_note
        end
    where id = p_reservation_id;

    return jsonb_build_object(
        'status', 'reservation_billed_through_set',
        'reservation_id', p_reservation_id,
        'billed_through_datetime', p_billed_through_datetime
    );
end;
$$;


ALTER FUNCTION "public"."set_reservation_billed_through_state"("p_reservation_id" "uuid", "p_billed_through_datetime" timestamp with time zone, "p_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_reservation_vin_lock_lead_days_state"("p_days" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if p_days is null then
        raise exception 'reservation_vin_lock_lead_days cannot be null';
    end if;

    if p_days < 0 then
        raise exception 'reservation_vin_lock_lead_days % cannot be negative', p_days;
    end if;

    update public.admin_settings
    set
        setting_value = to_jsonb(p_days)
    where setting_key = 'reservation_vin_lock_lead_days';

    return jsonb_build_object(
        'status', 'reservation_vin_lock_lead_days_updated',
        'reservation_vin_lock_lead_days', p_days
    );
end;
$$;


ALTER FUNCTION "public"."set_reservation_vin_lock_lead_days_state"("p_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    new.updated_at = now();
    return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_user_active_state"("p_user_id" "uuid", "p_is_active" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.app_users
        where id = p_user_id
    ) then
        raise exception 'User % does not exist', p_user_id;
    end if;

    update public.app_users
    set is_active = p_is_active
    where id = p_user_id;

    return jsonb_build_object(
        'status', case when p_is_active then 'activated' else 'deactivated' end,
        'user_id', p_user_id,
        'is_active', p_is_active
    );
end;
$$;


ALTER FUNCTION "public"."set_user_active_state"("p_user_id" "uuid", "p_is_active" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_user_outside_network_access_state"("p_user_id" "uuid", "p_allowed" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    perform public.ensure_user_security_state(p_user_id);

    update public.app_user_security
    set
        outside_network_access_allowed = p_allowed,
        updated_at = now()
    where user_id = p_user_id;

    return jsonb_build_object(
        'status', 'outside_network_access_updated',
        'user_id', p_user_id,
        'outside_network_access_allowed', p_allowed
    );
end;
$$;


ALTER FUNCTION "public"."set_user_outside_network_access_state"("p_user_id" "uuid", "p_allowed" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_vehicle_ctp_entry_state"("p_vehicle_id" "uuid", "p_ctp_program_entered_at" timestamp with time zone, "p_ctp_entry_mileage" integer, "p_ctp_program_active" boolean DEFAULT true, "p_ctp_monitoring_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.vehicles
        where id = p_vehicle_id
    ) then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    if p_ctp_program_active = true and p_ctp_program_entered_at is null then
        raise exception 'ctp_program_entered_at cannot be null when ctp_program_active is true';
    end if;

    if p_ctp_program_active = true and (p_ctp_entry_mileage is null or p_ctp_entry_mileage < 0) then
        raise exception 'ctp_entry_mileage must be non-negative when ctp_program_active is true';
    end if;

    update public.vehicles
    set
        ctp_program_active = p_ctp_program_active,
        ctp_program_entered_at = p_ctp_program_entered_at,
        ctp_entry_mileage = p_ctp_entry_mileage,
        ctp_monitoring_notes = p_ctp_monitoring_notes
    where id = p_vehicle_id;

    return jsonb_build_object(
        'status', 'vehicle_ctp_entry_state_updated',
        'vehicle_id', p_vehicle_id,
        'ctp_program_active', p_ctp_program_active,
        'ctp_program_entered_at', p_ctp_program_entered_at,
        'ctp_entry_mileage', p_ctp_entry_mileage,
        'ctp_monitoring_notes', p_ctp_monitoring_notes
    );
end;
$$;


ALTER FUNCTION "public"."set_vehicle_ctp_entry_state"("p_vehicle_id" "uuid", "p_ctp_program_entered_at" timestamp with time zone, "p_ctp_entry_mileage" integer, "p_ctp_program_active" boolean, "p_ctp_monitoring_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_vehicle_status_state"("p_vehicle_id" "uuid", "p_status" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.vehicles
        where id = p_vehicle_id
    ) then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    if p_status is null or btrim(p_status) = '' then
        raise exception 'status cannot be blank';
    end if;

    update public.vehicles
    set status = p_status
    where id = p_vehicle_id;

    return jsonb_build_object(
        'status', 'vehicle_status_updated',
        'vehicle_id', p_vehicle_id,
        'vehicle_status', p_status
    );
end;
$$;


ALTER FUNCTION "public"."set_vehicle_status_state"("p_vehicle_id" "uuid", "p_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_warranty_provider_active_state"("p_provider_id" "uuid", "p_is_active" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.warranty_providers
        where id = p_provider_id
    ) then
        raise exception 'Warranty provider % does not exist', p_provider_id;
    end if;

    update public.warranty_providers
    set
        is_active = p_is_active,
        updated_at = now()
    where id = p_provider_id;

    return jsonb_build_object(
        'status',
            case when p_is_active then 'warranty_provider_activated' else 'warranty_provider_deactivated' end,
        'provider_id', p_provider_id,
        'is_active', p_is_active
    );
end;
$$;


ALTER FUNCTION "public"."set_warranty_provider_active_state"("p_provider_id" "uuid", "p_is_active" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_reservation_vehicle_use_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_actual_out_at" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_reservation record;
    v_start_result jsonb;
begin
    select *
    into v_reservation
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if not exists (
        select 1
        from public.vehicles
        where id = p_vehicle_id
    ) then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    if p_actual_out_at is null then
        raise exception 'actual_out_at cannot be null';
    end if;

    if p_actual_out_at < v_reservation.start_date then
        raise exception 'actual_out_at % is before reservation start_date %',
            p_actual_out_at,
            v_reservation.start_date;
    end if;

    v_start_result := public.start_vehicle_use_state(
        v_reservation.transportation_event_id,
        p_vehicle_id,
        p_actual_out_at
    );

    update public.reservations
    set vehicle_id = p_vehicle_id
    where id = p_reservation_id;

    return jsonb_build_object(
        'status', 'reservation_vehicle_use_started',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'vehicle_id', p_vehicle_id,
        'actual_out_at', p_actual_out_at,
        'continuity_result', v_start_result
    );
end;
$$;


ALTER FUNCTION "public"."start_reservation_vehicle_use_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_actual_out_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_vehicle_scan_session_state"("p_session_type" "text", "p_started_by_user_id" "uuid", "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_session_id uuid;
begin
    if p_session_type is null or btrim(p_session_type) = '' then
        raise exception 'session_type cannot be blank';
    end if;

    if not exists (
        select 1
        from public.app_users
        where id = p_started_by_user_id
    ) then
        raise exception 'Started-by user % does not exist', p_started_by_user_id;
    end if;

    insert into public.vehicle_scan_sessions (
        session_type,
        started_by_user_id,
        started_at,
        session_status,
        notes
    )
    values (
        p_session_type,
        p_started_by_user_id,
        now(),
        'active',
        p_notes
    )
    returning id into v_session_id;

    return jsonb_build_object(
        'status', 'vehicle_scan_session_started',
        'vehicle_scan_session_id', v_session_id,
        'session_type', p_session_type,
        'started_by_user_id', p_started_by_user_id
    );
end;
$$;


ALTER FUNCTION "public"."start_vehicle_scan_session_state"("p_session_type" "text", "p_started_by_user_id" "uuid", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_vehicle_use_state"("p_transportation_event_id" "uuid", "p_vehicle_id" "uuid", "p_actual_out_at" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_existing_open_vehicle_event_id uuid;
    v_new_vehicle_event_id uuid;
    v_new_contract_period_id uuid;
begin
    if not exists (
        select 1
        from public.transportation_events
        where id = p_transportation_event_id
    ) then
        raise exception 'Transportation event % does not exist', p_transportation_event_id;
    end if;

    if not exists (
        select 1
        from public.vehicles
        where id = p_vehicle_id
    ) then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    select ve.id
    into v_existing_open_vehicle_event_id
    from public.vehicle_events ve
    where ve.transportation_event_id = p_transportation_event_id
      and ve.is_open = true
    limit 1;

    if v_existing_open_vehicle_event_id is not null then
        raise exception 'Transportation event % already has an open vehicle_event %',
            p_transportation_event_id,
            v_existing_open_vehicle_event_id;
    end if;

    insert into public.vehicle_events (
        transportation_event_id,
        vehicle_id,
        actual_out_at,
        actual_in_at,
        is_open,
        ended_reason
    )
    values (
        p_transportation_event_id,
        p_vehicle_id,
        p_actual_out_at,
        null,
        true,
        null
    )
    returning id into v_new_vehicle_event_id;

    insert into public.contract_periods (
        vehicle_event_id,
        contract_out_at,
        contract_in_at,
        renewal_sequence,
        is_open
    )
    values (
        v_new_vehicle_event_id,
        p_actual_out_at,
        null,
        0,
        true
    )
    returning id into v_new_contract_period_id;

    return jsonb_build_object(
        'status', 'started',
        'vehicle_event_id', v_new_vehicle_event_id,
        'contract_period_id', v_new_contract_period_id
    );
end;
$$;


ALTER FUNCTION "public"."start_vehicle_use_state"("p_transportation_event_id" "uuid", "p_vehicle_id" "uuid", "p_actual_out_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."swap_reservation_vehicle_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_reservation record;
    v_current_continuity record;
    v_swap_result jsonb;
begin
    select *
    into v_reservation
    from public.reservations
    where id = p_reservation_id
    for update;

    if not found then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if not exists (
        select 1
        from public.vehicles
        where id = p_new_vehicle_id
    ) then
        raise exception 'Vehicle % does not exist', p_new_vehicle_id;
    end if;

    if p_swap_time is null then
        raise exception 'swap_time cannot be null';
    end if;

    if p_swap_time < v_reservation.start_date then
        raise exception 'swap_time % is before reservation start_date %',
            p_swap_time,
            v_reservation.start_date;
    end if;

    select *
    into v_current_continuity
    from public.v_current_vehicle_continuity
    where transportation_event_id = v_reservation.transportation_event_id
    limit 1;

    if not found then
        raise exception 'No active vehicle continuity exists for reservation %', p_reservation_id;
    end if;

    v_swap_result := public.swap_vehicle_state(
        v_current_continuity.vehicle_event_id,
        p_new_vehicle_id,
        p_swap_time
    );

    update public.reservations
    set vehicle_id = p_new_vehicle_id
    where id = p_reservation_id;

    return jsonb_build_object(
        'status', 'reservation_vehicle_swapped',
        'reservation_id', p_reservation_id,
        'transportation_event_id', v_reservation.transportation_event_id,
        'old_vehicle_event_id', v_current_continuity.vehicle_event_id,
        'new_vehicle_id', p_new_vehicle_id,
        'swap_time', p_swap_time,
        'continuity_swap_result', v_swap_result
    );
end;
$$;


ALTER FUNCTION "public"."swap_reservation_vehicle_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."swap_vehicle_state"("p_old_vehicle_event_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_old_vehicle_event record;
    v_old_contract_period record;
    v_new_vehicle_event_id uuid;
    v_new_contract_period_id uuid;
begin
    select *
    into v_old_vehicle_event
    from public.vehicle_events
    where id = p_old_vehicle_event_id
      and is_open = true
    for update;

    if not found then
        raise exception 'Open vehicle_event % does not exist', p_old_vehicle_event_id;
    end if;

    if not exists (
        select 1
        from public.vehicles
        where id = p_new_vehicle_id
    ) then
        raise exception 'Vehicle % does not exist', p_new_vehicle_id;
    end if;

    if p_swap_time < v_old_vehicle_event.actual_out_at then
        raise exception 'swap_time % is before actual_out_at %',
            p_swap_time,
            v_old_vehicle_event.actual_out_at;
    end if;

    select *
    into v_old_contract_period
    from public.contract_periods
    where vehicle_event_id = p_old_vehicle_event_id
      and is_open = true
    for update;

    if not found then
        raise exception 'Open contract_period for vehicle_event % does not exist', p_old_vehicle_event_id;
    end if;

    update public.contract_periods
    set
        contract_in_at = p_swap_time,
        is_open = false
    where id = v_old_contract_period.id;

    update public.vehicle_events
    set
        actual_in_at = p_swap_time,
        is_open = false,
        ended_reason = 'swapped'
    where id = p_old_vehicle_event_id;

    insert into public.vehicle_events (
        transportation_event_id,
        vehicle_id,
        actual_out_at,
        actual_in_at,
        is_open,
        ended_reason
    )
    values (
        v_old_vehicle_event.transportation_event_id,
        p_new_vehicle_id,
        p_swap_time,
        null,
        true,
        null
    )
    returning id into v_new_vehicle_event_id;

    insert into public.contract_periods (
        vehicle_event_id,
        contract_out_at,
        contract_in_at,
        renewal_sequence,
        is_open
    )
    values (
        v_new_vehicle_event_id,
        p_swap_time,
        null,
        0,
        true
    )
    returning id into v_new_contract_period_id;

    return jsonb_build_object(
        'status', 'swapped_vehicle',
        'old_vehicle_event_id', p_old_vehicle_event_id,
        'old_contract_period_id', v_old_contract_period.id,
        'new_vehicle_event_id', v_new_vehicle_event_id,
        'new_contract_period_id', v_new_contract_period_id
    );
end;
$$;


ALTER FUNCTION "public"."swap_vehicle_state"("p_old_vehicle_event_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_approved_network_state"("p_network_id" "uuid", "p_label" "text", "p_network_value" "text", "p_network_type" "text", "p_notes" "text" DEFAULT NULL::"text", "p_updated_by_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.approved_networks
        where id = p_network_id
    ) then
        raise exception 'Approved network % does not exist', p_network_id;
    end if;

    if p_label is null or btrim(p_label) = '' then
        raise exception 'Approved network label cannot be blank';
    end if;

    if p_network_value is null or btrim(p_network_value) = '' then
        raise exception 'Approved network value cannot be blank';
    end if;

    if p_network_type is null or btrim(p_network_type) = '' then
        raise exception 'Approved network type cannot be blank';
    end if;

    if p_updated_by_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_updated_by_user_id
       ) then
        raise exception 'User % does not exist', p_updated_by_user_id;
    end if;

    update public.approved_networks
    set
        label = p_label,
        network_value = p_network_value,
        network_type = p_network_type,
        notes = p_notes,
        updated_at = now(),
        updated_by_user_id = p_updated_by_user_id
    where id = p_network_id;

    return jsonb_build_object(
        'status', 'approved_network_updated',
        'approved_network_id', p_network_id
    );
end;
$$;


ALTER FUNCTION "public"."update_approved_network_state"("p_network_id" "uuid", "p_label" "text", "p_network_value" "text", "p_network_type" "text", "p_notes" "text", "p_updated_by_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_customer_state"("p_customer_id" "uuid", "p_name" "text", "p_phone" "text" DEFAULT NULL::"text", "p_email" "text" DEFAULT NULL::"text", "p_flags" "jsonb" DEFAULT NULL::"jsonb", "p_internal_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.customers
        where id = p_customer_id
    ) then
        raise exception 'Customer % does not exist', p_customer_id;
    end if;

    if p_name is null or btrim(p_name) = '' then
        raise exception 'name cannot be blank';
    end if;

    update public.customers
    set
        name = p_name,
        phone = p_phone,
        email = p_email,
        flags = p_flags,
        internal_notes = p_internal_notes
    where id = p_customer_id;

    return jsonb_build_object(
        'status', 'customer_updated',
        'customer_id', p_customer_id
    );
end;
$$;


ALTER FUNCTION "public"."update_customer_state"("p_customer_id" "uuid", "p_name" "text", "p_phone" "text", "p_email" "text", "p_flags" "jsonb", "p_internal_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_extended_warranty_rule_state"("p_rule_id" "uuid", "p_covered_days" integer, "p_requires_approval" boolean, "p_daily_rate" numeric DEFAULT NULL::numeric, "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.extended_warranty_rules
        where id = p_rule_id
    ) then
        raise exception 'Extended warranty rule % does not exist', p_rule_id;
    end if;

    if p_covered_days is not null and p_covered_days < 0 then
        raise exception 'covered_days cannot be negative';
    end if;

    if p_daily_rate is not null and p_daily_rate < 0 then
        raise exception 'daily_rate cannot be negative';
    end if;

    update public.extended_warranty_rules
    set
        covered_days = coalesce(p_covered_days, 0),
        requires_approval = coalesce(p_requires_approval, false),
        daily_rate = p_daily_rate,
        notes = p_notes,
        updated_at = now()
    where id = p_rule_id;

    return jsonb_build_object(
        'status', 'extended_warranty_rule_updated',
        'rule_id', p_rule_id
    );
end;
$$;


ALTER FUNCTION "public"."update_extended_warranty_rule_state"("p_rule_id" "uuid", "p_covered_days" integer, "p_requires_approval" boolean, "p_daily_rate" numeric, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_late_fee_rule_state"("p_rule_id" "uuid", "p_rule_kind" "text", "p_threshold_unit" "text", "p_threshold_value" integer, "p_fee_amount" numeric DEFAULT NULL::numeric, "p_sort_order" integer DEFAULT 0, "p_description" "text" DEFAULT NULL::"text", "p_updated_by" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.late_fee_rules
        where id = p_rule_id
    ) then
        raise exception 'Late fee rule % does not exist', p_rule_id;
    end if;

    if p_rule_kind is null or btrim(p_rule_kind) = '' then
        raise exception 'rule_kind cannot be blank';
    end if;

    if p_threshold_unit is null or btrim(p_threshold_unit) = '' then
        raise exception 'threshold_unit cannot be blank';
    end if;

    if p_threshold_value is null or p_threshold_value < 0 then
        raise exception 'threshold_value must be non-negative';
    end if;

    if p_fee_amount is not null and p_fee_amount < 0 then
        raise exception 'fee_amount cannot be negative';
    end if;

    if p_sort_order is null or p_sort_order < 0 then
        raise exception 'sort_order must be non-negative';
    end if;

    if p_updated_by is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_updated_by
       ) then
        raise exception 'User % does not exist', p_updated_by;
    end if;

    update public.late_fee_rules
    set
        rule_kind = p_rule_kind,
        threshold_unit = p_threshold_unit,
        threshold_value = p_threshold_value,
        fee_amount = p_fee_amount,
        sort_order = p_sort_order,
        description = p_description,
        updated_at = now(),
        updated_by = p_updated_by
    where id = p_rule_id;

    return jsonb_build_object(
        'status', 'late_fee_rule_updated',
        'late_fee_rule_id', p_rule_id
    );
end;
$$;


ALTER FUNCTION "public"."update_late_fee_rule_state"("p_rule_id" "uuid", "p_rule_kind" "text", "p_threshold_unit" "text", "p_threshold_value" integer, "p_fee_amount" numeric, "p_sort_order" integer, "p_description" "text", "p_updated_by" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_vehicle_core_state"("p_vehicle_id" "uuid", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text", "p_recon_status" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.vehicles
        where id = p_vehicle_id
    ) then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    if p_stock_number is null or btrim(p_stock_number) = '' then
        raise exception 'stock_number cannot be blank';
    end if;

    if p_model is null or btrim(p_model) = '' then
        raise exception 'model cannot be blank';
    end if;

    if p_fleet_type is null or btrim(p_fleet_type) = '' then
        raise exception 'fleet_type cannot be blank';
    end if;

    if p_current_tag is null or btrim(p_current_tag) = '' then
        raise exception 'current_tag cannot be blank';
    end if;

    if p_fleet_conversion_type is null or btrim(p_fleet_conversion_type) = '' then
        raise exception 'fleet_conversion_type cannot be blank';
    end if;

    if p_mileage is null or p_mileage < 0 then
        raise exception 'mileage must be non-negative';
    end if;

    if p_recon_status is not null and btrim(p_recon_status) = '' then
        raise exception 'recon_status cannot be blank when provided';
    end if;

    update public.vehicles
    set
        stock_number = p_stock_number,
        model = p_model,
        fleet_type = p_fleet_type,
        mileage = p_mileage,
        current_tag = p_current_tag,
        fleet_conversion_type = p_fleet_conversion_type,
        location = p_location,
        notes = p_notes,
        recon_status = coalesce(p_recon_status, recon_status)
    where id = p_vehicle_id;

    return jsonb_build_object(
        'status', 'vehicle_updated',
        'vehicle_id', p_vehicle_id
    );
end;
$$;


ALTER FUNCTION "public"."update_vehicle_core_state"("p_vehicle_id" "uuid", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text", "p_notes" "text", "p_recon_status" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_warranty_provider_state"("p_provider_id" "uuid", "p_name" "text", "p_provider_type" "text", "p_default_daily_rate" numeric DEFAULT NULL::numeric, "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
begin
    if not exists (
        select 1
        from public.warranty_providers
        where id = p_provider_id
    ) then
        raise exception 'Warranty provider % does not exist', p_provider_id;
    end if;

    if p_name is null or btrim(p_name) = '' then
        raise exception 'Provider name cannot be blank';
    end if;

    if p_provider_type is null or btrim(p_provider_type) = '' then
        raise exception 'Provider type cannot be blank';
    end if;

    if p_default_daily_rate is not null and p_default_daily_rate < 0 then
        raise exception 'Default daily rate cannot be negative';
    end if;

    update public.warranty_providers
    set
        name = p_name,
        provider_type = p_provider_type,
        default_daily_rate = p_default_daily_rate,
        notes = p_notes,
        updated_at = now()
    where id = p_provider_id;

    return jsonb_build_object(
        'status', 'warranty_provider_updated',
        'provider_id', p_provider_id
    );
end;
$$;


ALTER FUNCTION "public"."update_warranty_provider_state"("p_provider_id" "uuid", "p_name" "text", "p_provider_type" "text", "p_default_daily_rate" numeric, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."upsert_reservation_dependency_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_source_transportation_event_id" "uuid" DEFAULT NULL::"uuid", "p_dependency_type" "text" DEFAULT 'soft_lock'::"text", "p_status" "text" DEFAULT 'pending_return'::"text", "p_risk_level" "text" DEFAULT 'depends_on_return'::"text", "p_expected_return_snapshot" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_notes" "text" DEFAULT NULL::"text", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
declare
    v_existing_same record;
    v_new_id uuid;
    v_prior_dependency_ids uuid[];
begin
    if p_dependency_type not in ('soft_lock', 'hard_lock') then
        raise exception 'Invalid dependency_type: %', p_dependency_type;
    end if;

    if p_status not in ('pending_return', 'ready', 'conflict', 'resolved', 'cancelled') then
        raise exception 'Invalid dependency status: %', p_status;
    end if;

    if p_risk_level not in ('normal', 'depends_on_return', 'at_risk', 'must_return', 'critical') then
        raise exception 'Invalid risk_level: %', p_risk_level;
    end if;

    if not exists (
        select 1
        from public.reservations
        where id = p_reservation_id
    ) then
        raise exception 'Reservation % does not exist', p_reservation_id;
    end if;

    if not exists (
        select 1
        from public.vehicles
        where id = p_vehicle_id
    ) then
        raise exception 'Vehicle % does not exist', p_vehicle_id;
    end if;

    if p_source_transportation_event_id is not null
       and not exists (
            select 1
            from public.transportation_events
            where id = p_source_transportation_event_id
       ) then
        raise exception 'Transportation event % does not exist', p_source_transportation_event_id;
    end if;

    if p_actor_user_id is not null
       and not exists (
            select 1
            from public.app_users
            where id = p_actor_user_id
       ) then
        raise exception 'Actor user % does not exist', p_actor_user_id;
    end if;

    -- Try to update the same unresolved dependency row
    select *
    into v_existing_same
    from public.reservation_vehicle_dependencies
    where reservation_id = p_reservation_id
      and vehicle_id = p_vehicle_id
      and dependency_type = p_dependency_type
      and status in ('pending_return', 'ready', 'conflict')
    order by updated_at desc nulls last, created_at desc nulls last
    limit 1
    for update;

    if found then
        update public.reservation_vehicle_dependencies
        set
            source_transportation_event_id = p_source_transportation_event_id,
            status = p_status,
            risk_level = p_risk_level,
            expected_return_snapshot = p_expected_return_snapshot,
            notes = p_notes,
            updated_by_user_id = p_actor_user_id,
            updated_at = now()
        where id = v_existing_same.id;

        return jsonb_build_object(
            'status', 'dependency_updated',
            'dependency_id', v_existing_same.id,
            'reservation_id', p_reservation_id,
            'vehicle_id', p_vehicle_id,
            'dependency_type', p_dependency_type,
            'dependency_status', p_status,
            'risk_level', p_risk_level
        );
    end if;

    -- Capture prior unresolved dependency ids for this reservation
    select coalesce(array_agg(id), '{}'::uuid[])
    into v_prior_dependency_ids
    from public.reservation_vehicle_dependencies
    where reservation_id = p_reservation_id
      and status in ('pending_return', 'ready', 'conflict');

    -- Resolve prior unresolved dependency rows for this reservation
    update public.reservation_vehicle_dependencies
    set
        status = 'resolved',
        resolution_type = 'other',
        resolved_at = now(),
        resolved_by_user_id = p_actor_user_id,
        updated_by_user_id = p_actor_user_id,
        updated_at = now()
    where reservation_id = p_reservation_id
      and status in ('pending_return', 'ready', 'conflict');

    -- Resolve any linked conflicts on those prior dependencies
    update public.reservation_conflicts
    set is_resolved = true
    where reservation_vehicle_dependency_id = any(v_prior_dependency_ids)
      and is_resolved = false;

    -- Create the new unresolved dependency row
    insert into public.reservation_vehicle_dependencies (
        reservation_id,
        vehicle_id,
        source_transportation_event_id,
        dependency_type,
        status,
        risk_level,
        expected_return_snapshot,
        notes,
        created_by_user_id,
        updated_by_user_id,
        created_at,
        updated_at
    )
    values (
        p_reservation_id,
        p_vehicle_id,
        p_source_transportation_event_id,
        p_dependency_type,
        p_status,
        p_risk_level,
        p_expected_return_snapshot,
        p_notes,
        p_actor_user_id,
        p_actor_user_id,
        now(),
        now()
    )
    returning id into v_new_id;

    return jsonb_build_object(
        'status', 'dependency_created',
        'dependency_id', v_new_id,
        'reservation_id', p_reservation_id,
        'vehicle_id', p_vehicle_id,
        'dependency_type', p_dependency_type,
        'dependency_status', p_status,
        'risk_level', p_risk_level
    );
end;
$$;


ALTER FUNCTION "public"."upsert_reservation_dependency_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_source_transportation_event_id" "uuid", "p_dependency_type" "text", "p_status" "text", "p_risk_level" "text", "p_expected_return_snapshot" timestamp with time zone, "p_notes" "text", "p_actor_user_id" "uuid") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."active_vehicle_assignments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "transportation_event_id" "uuid" NOT NULL,
    "vehicle_id" "uuid" NOT NULL,
    "assigned_at" timestamp with time zone DEFAULT "now"(),
    "assignment_source" "text" NOT NULL,
    "assigned_by" "text",
    "is_active" boolean DEFAULT true
);


ALTER TABLE "public"."active_vehicle_assignments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."admin_setting_permissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "setting_key" "text" NOT NULL,
    "required_permission" "text" NOT NULL
);


ALTER TABLE "public"."admin_setting_permissions" OWNER TO "postgres";


COMMENT ON TABLE "public"."admin_setting_permissions" IS 'Maps admin settings to required permissions for secure access control.';



CREATE TABLE IF NOT EXISTS "public"."admin_settings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "setting_key" "text" NOT NULL,
    "setting_value" "jsonb" NOT NULL,
    "description" "text"
);


ALTER TABLE "public"."admin_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_user_reset_tokens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "token_hash" "text" NOT NULL,
    "reset_mode" "text" NOT NULL,
    "issued_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "used_at" timestamp with time zone,
    "is_active" boolean DEFAULT true NOT NULL,
    "issued_by_user_id" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "app_user_reset_tokens_reset_mode_check" CHECK (("reset_mode" = ANY (ARRAY['email_link'::"text", 'admin_reset'::"text"]))),
    CONSTRAINT "ck_app_user_reset_tokens_expiry_order" CHECK (("expires_at" >= "issued_at")),
    CONSTRAINT "ck_app_user_reset_tokens_used_order" CHECK ((("used_at" IS NULL) OR ("used_at" >= "issued_at")))
);


ALTER TABLE "public"."app_user_reset_tokens" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_user_security" (
    "user_id" "uuid" NOT NULL,
    "failed_login_count" integer DEFAULT 0 NOT NULL,
    "last_failed_login_at" timestamp with time zone,
    "locked_until" timestamp with time zone,
    "post_lockout_final_attempt_allowed" boolean DEFAULT false NOT NULL,
    "is_disabled" boolean DEFAULT false NOT NULL,
    "disabled_at" timestamp with time zone,
    "disabled_reason" "text",
    "password_reset_pending" boolean DEFAULT false NOT NULL,
    "temporary_password_issued_at" timestamp with time zone,
    "temporary_password_expires_at" timestamp with time zone,
    "temporary_password_issued_by" "uuid",
    "outside_network_access_allowed" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "lockout_count" integer DEFAULT 0 NOT NULL,
    "last_successful_login_at" timestamp with time zone,
    CONSTRAINT "ck_app_user_security_failed_login_count" CHECK (("failed_login_count" >= 0)),
    CONSTRAINT "ck_app_user_security_lockout_count" CHECK (("lockout_count" >= 0)),
    CONSTRAINT "ck_app_user_security_temp_password_time_order" CHECK ((("temporary_password_expires_at" IS NULL) OR ("temporary_password_issued_at" IS NULL) OR ("temporary_password_expires_at" >= "temporary_password_issued_at")))
);


ALTER TABLE "public"."app_user_security" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "auth_user_id" "uuid" NOT NULL,
    "full_name" "text",
    "email" "text" NOT NULL,
    "phone" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "last_login" timestamp with time zone,
    "notes" "text"
);


ALTER TABLE "public"."app_users" OWNER TO "postgres";


COMMENT ON TABLE "public"."app_users" IS 'Internal system user mapping linked to Supabase Auth users. Used for role assignment, audit logging, and approval workflows.';



COMMENT ON COLUMN "public"."app_users"."email" IS 'Login identity email. Must be unique and not null.';



CREATE TABLE IF NOT EXISTS "public"."approval_actions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "transportation_event_id" "uuid",
    "reservation_id" "uuid",
    "action_type" "text" NOT NULL,
    "requested_by" "uuid",
    "approved_by" "uuid",
    "status" "text" DEFAULT 'pending'::"text",
    "reason" "text",
    "metadata" "jsonb"
);


ALTER TABLE "public"."approval_actions" OWNER TO "postgres";


COMMENT ON TABLE "public"."approval_actions" IS 'Tracks administrative approvals and overrides such as warranty extensions and billing overrides.';



CREATE TABLE IF NOT EXISTS "public"."approved_networks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "label" "text" NOT NULL,
    "network_value" "text" NOT NULL,
    "network_type" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by_user_id" "uuid",
    "updated_by_user_id" "uuid",
    CONSTRAINT "approved_networks_network_type_check" CHECK (("network_type" = ANY (ARRAY['single_ip'::"text", 'cidr'::"text"])))
);


ALTER TABLE "public"."approved_networks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "entity_type" "text" NOT NULL,
    "entity_id" "text" NOT NULL,
    "action_type" "text" NOT NULL,
    "field_name" "text",
    "old_value" "text",
    "new_value" "text",
    "metadata" "jsonb",
    "actor_user_id" "text" NOT NULL
);


ALTER TABLE "public"."audit_log" OWNER TO "postgres";


COMMENT ON TABLE "public"."audit_log" IS 'Central system audit log that records all user and system actions across reservations, vehicles, customers, and administrative settings. Tracks who made a change, what was changed, when it occurred, and the before/after values for full traceability and accountability.';



COMMENT ON COLUMN "public"."audit_log"."id" IS 'Unique identifier for each audit log entry. Automatically generated UUID used to uniquely identify and reference individual audit records throughout the system.';



COMMENT ON COLUMN "public"."audit_log"."created_at" IS 'The exact date and time the audit event was recorded. Used to establish a chronological history of actions performed within the system.';



COMMENT ON COLUMN "public"."audit_log"."entity_type" IS 'Identifies the type of record affected by the action. Used to group audit events by system area such as reservations, users, vehicles, rentals, loaners, quotes, or settings.';



COMMENT ON COLUMN "public"."audit_log"."entity_id" IS 'Stores the unique identifier of the specific record affected by the audit event. Used together with entity_type to locate the exact reservation, user, vehicle, or system record that was changed.';



COMMENT ON COLUMN "public"."audit_log"."action_type" IS 'Defines the type of action performed within the system. Used to categorize audit events such as creation, updates, deletions, status changes, advisor changes, permission updates, and other system-driven or user-driven actions.';



COMMENT ON COLUMN "public"."audit_log"."field_name" IS 'Specifies the exact field that was modified during an update action. Used to provide granular detail about what changed within a record, such as status, return_date, pay_type, or service_advisor.';



COMMENT ON COLUMN "public"."audit_log"."old_value" IS 'Stores the previous value of a field before it was changed. Used to provide historical comparison and track exactly what data was modified during an update event.';



COMMENT ON COLUMN "public"."audit_log"."new_value" IS 'Stores the updated value of a field after a change has been made. Used together with old_value to show exactly how data was modified during an audit event.';



COMMENT ON COLUMN "public"."audit_log"."metadata" IS 'Optional flexible JSON field used to store additional context about the audit event that does not fit into standard columns, such as device information, IP address, notes, or extended system data.';



CREATE TABLE IF NOT EXISTS "public"."billing_event_totals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "transportation_event_id" "uuid",
    "warranty_total" numeric DEFAULT 0,
    "extended_warranty_total" numeric DEFAULT 0,
    "customer_pay_total" numeric DEFAULT 0,
    "tax_total" numeric DEFAULT 0,
    "grand_total" numeric DEFAULT 0
);


ALTER TABLE "public"."billing_event_totals" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."billing_lines" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "transportation_event_id" "uuid" NOT NULL,
    "reservation_id" "uuid",
    "vehicle_id" "uuid",
    "pay_type" "text" NOT NULL,
    "amount" numeric DEFAULT 0,
    "tax_amount" numeric DEFAULT 0,
    "start_time" timestamp with time zone,
    "end_time" timestamp with time zone,
    "source_rule" "text",
    "vehicle_event_id" "uuid",
    "contract_period_id" "uuid",
    "pay_type_rule_id" "uuid",
    "line_type" "text",
    "parent_billing_line_id" "uuid",
    "warranty_provider_id" "uuid",
    "default_covered_days_snapshot" integer,
    "covered_days_override" integer,
    "is_open" boolean DEFAULT true NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "paid_through_at" timestamp with time zone,
    "extended_from_billing_line_id" "uuid",
    "default_daily_rate_snapshot" numeric(12,2),
    "daily_rate_override" numeric(12,2),
    CONSTRAINT "ck_billing_lines_amount_nonnegative" CHECK ((("amount" IS NULL) OR ("amount" >= (0)::numeric))),
    CONSTRAINT "ck_billing_lines_covered_days_override" CHECK ((("covered_days_override" IS NULL) OR ("covered_days_override" >= 0))),
    CONSTRAINT "ck_billing_lines_default_covered_days_snapshot" CHECK ((("default_covered_days_snapshot" IS NULL) OR ("default_covered_days_snapshot" >= 0))),
    CONSTRAINT "ck_billing_lines_line_type" CHECK ((("line_type" IS NULL) OR ("line_type" = ANY (ARRAY['initial_assignment'::"text", 'same_vehicle_renewal'::"text", 'pay_type_split'::"text", 'new_vehicle_segment'::"text", 'new_event_after_gap'::"text", 'rental_extension'::"text", 'tax'::"text", 'late_fee'::"text", 'loaner_overdue'::"text"])))),
    CONSTRAINT "ck_billing_lines_paid_through_order" CHECK ((("paid_through_at" IS NULL) OR ("start_time" IS NULL) OR ("paid_through_at" >= "start_time"))),
    CONSTRAINT "ck_billing_lines_tax_amount_nonnegative" CHECK ((("tax_amount" IS NULL) OR ("tax_amount" >= (0)::numeric))),
    CONSTRAINT "ck_billing_lines_time_order" CHECK ((("end_time" IS NULL) OR ("end_time" >= "start_time")))
);


ALTER TABLE "public"."billing_lines" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contract_periods" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vehicle_event_id" "uuid" NOT NULL,
    "contract_out_at" timestamp with time zone NOT NULL,
    "contract_in_at" timestamp with time zone,
    "renewal_sequence" integer DEFAULT 0 NOT NULL,
    "is_open" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    CONSTRAINT "ck_contract_periods_open_state" CHECK (((("is_open" = true) AND ("contract_in_at" IS NULL)) OR (("is_open" = false) AND ("contract_in_at" IS NOT NULL)))),
    CONSTRAINT "ck_contract_periods_sequence" CHECK (("renewal_sequence" >= 0)),
    CONSTRAINT "ck_contract_periods_time_order" CHECK ((("contract_in_at" IS NULL) OR ("contract_in_at" >= "contract_out_at")))
);


ALTER TABLE "public"."contract_periods" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_preferences" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "customer_id" "uuid",
    "allow_sms" boolean DEFAULT false,
    "allow_email" boolean DEFAULT false,
    "allow_phone" boolean DEFAULT false,
    "vip_flag" boolean DEFAULT false,
    "frequent_renter" boolean DEFAULT false
);


ALTER TABLE "public"."customer_preferences" OWNER TO "postgres";


COMMENT ON TABLE "public"."customer_preferences" IS 'Stores communication preferences and lightweight customer flags.';



CREATE TABLE IF NOT EXISTS "public"."customers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "tekion_customer_number" "text" NOT NULL,
    "name" "text" NOT NULL,
    "phone" "text",
    "email" "text",
    "flags" "jsonb",
    "internal_notes" "text"
);


ALTER TABLE "public"."customers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."email_outbound_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email_provider" "text" DEFAULT 'resend'::"text" NOT NULL,
    "message_type" "text" NOT NULL,
    "template_key" "text",
    "related_user_id" "uuid",
    "related_customer_id" "uuid",
    "related_reservation_id" "uuid",
    "related_transportation_event_id" "uuid",
    "to_email" "text" NOT NULL,
    "from_email" "text" NOT NULL,
    "subject" "text",
    "provider_message_id" "text",
    "send_status" "text" DEFAULT 'queued'::"text" NOT NULL,
    "provider_response" "jsonb",
    "queued_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sent_at" timestamp with time zone,
    "failed_at" timestamp with time zone,
    "last_event_at" timestamp with time zone,
    "created_by_user_id" "uuid"
);


ALTER TABLE "public"."email_outbound_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."email_provider_webhook_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email_outbound_message_id" "uuid",
    "provider_name" "text" DEFAULT 'resend'::"text" NOT NULL,
    "provider_event_id" "text",
    "provider_message_id" "text",
    "event_type" "text" NOT NULL,
    "event_payload" "jsonb",
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "received_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "processed_status" "text" DEFAULT 'received'::"text" NOT NULL
);


ALTER TABLE "public"."email_provider_webhook_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."engine_runs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "run_id" "text" NOT NULL,
    "trigger_type" "text" NOT NULL,
    "reservation_id" "text",
    "status" "text" DEFAULT 'completed'::"text",
    "conflicts_count" integer DEFAULT 0,
    "audit_events_count" integer DEFAULT 0,
    "metadata" "jsonb"
);


ALTER TABLE "public"."engine_runs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."extended_warranty_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "provider_id" "uuid",
    "covered_days" integer DEFAULT 0,
    "requires_approval" boolean DEFAULT false,
    "daily_rate" numeric(12,2),
    "is_active" boolean DEFAULT true NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "notes" "text"
);


ALTER TABLE "public"."extended_warranty_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."fleet_policies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "vehicle_class" "text" NOT NULL,
    "model_lock_window_days" integer NOT NULL,
    "overbook_threshold" integer,
    "is_active" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."fleet_policies" OWNER TO "postgres";


COMMENT ON TABLE "public"."fleet_policies" IS 'Stores configurable operational rules that control how vehicle classes behave within the fleet system. This includes allocation rules such as when reservations transition from model-level forecasting to VIN-level locking, capacity buffers, and other admin-controlled policy settings. These rules are used by the reservation and availability engine to enforce consistent fleet behavior without requiring code changes.';



COMMENT ON COLUMN "public"."fleet_policies"."id" IS 'Unique identifier for the fleet policy record. Used as the primary key for referencing policy rules applied to vehicle classes.';



COMMENT ON COLUMN "public"."fleet_policies"."created_at" IS 'Timestamp indicating when the policy record was created in the system. Used for audit and historical tracking of policy changes over time.';



COMMENT ON COLUMN "public"."fleet_policies"."vehicle_class" IS 'The vehicle class this policy applies to (e.g., Loaner SUV, Rental Compact). Determines which fleet grouping the rule affects for capacity and allocation logic.';



COMMENT ON COLUMN "public"."fleet_policies"."model_lock_window_days" IS 'The number of days before a reservation start date at which a model-level reservation must be converted to a specific VIN assignment. Used to control when forecasted inventory becomes physically allocated vehicles.';



COMMENT ON COLUMN "public"."fleet_policies"."overbook_threshold" IS 'Optional buffer value used to allow controlled over-allocation of a vehicle class beyond defined daily limits. Used to manage operational flexibility during high demand periods.';



COMMENT ON COLUMN "public"."fleet_policies"."is_active" IS 'Indicates whether this policy record is currently active and should be used in system calculations. Inactive policies are ignored by reservation and allocation logic.';



CREATE TABLE IF NOT EXISTS "public"."gm_warranty_rates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "less_than_24hr_rate" numeric DEFAULT 0,
    "over_24hr_rate" numeric DEFAULT 0,
    "customer_pay_rate" numeric DEFAULT 0,
    "tax_rate" numeric DEFAULT 0
);


ALTER TABLE "public"."gm_warranty_rates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."late_fee_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "rule_kind" "text" NOT NULL,
    "threshold_unit" "text" NOT NULL,
    "threshold_value" integer NOT NULL,
    "fee_amount" numeric(12,2),
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    CONSTRAINT "ck_late_fee_rules_fee_amount" CHECK ((("fee_amount" IS NULL) OR ("fee_amount" >= (0)::numeric))),
    CONSTRAINT "ck_late_fee_rules_sort_order" CHECK (("sort_order" >= 0)),
    CONSTRAINT "ck_late_fee_rules_threshold_value" CHECK (("threshold_value" >= 0)),
    CONSTRAINT "late_fee_rules_rule_kind_check" CHECK (("rule_kind" = ANY (ARRAY['grace_period'::"text", 'fixed_fee'::"text", 'full_day_trigger'::"text"]))),
    CONSTRAINT "late_fee_rules_threshold_unit_check" CHECK (("threshold_unit" = ANY (ARRAY['minutes'::"text", 'hours'::"text", 'days'::"text"])))
);


ALTER TABLE "public"."late_fee_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lost_rentals" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "vehicle_class" "text",
    "model_requested" "text",
    "requested_start_at" timestamp with time zone,
    "requested_end_at" timestamp with time zone,
    "requested_duration_days" integer,
    "quoted_daily_rate" numeric(12,2),
    "customer_id" "uuid",
    "transportation_event_id" "uuid",
    "reservation_id" "uuid",
    "reason" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by_user_id" "uuid",
    "updated_by_user_id" "uuid",
    CONSTRAINT "ck_lost_rentals_duration_nonnegative" CHECK ((("requested_duration_days" IS NULL) OR ("requested_duration_days" >= 0))),
    CONSTRAINT "ck_lost_rentals_rate_nonnegative" CHECK ((("quoted_daily_rate" IS NULL) OR ("quoted_daily_rate" >= (0)::numeric))),
    CONSTRAINT "ck_lost_rentals_time_order" CHECK ((("requested_end_at" IS NULL) OR ("requested_start_at" IS NULL) OR ("requested_end_at" >= "requested_start_at")))
);


ALTER TABLE "public"."lost_rentals" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notification_delivery_queue" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "notification_type" "text" NOT NULL,
    "message" "text" NOT NULL,
    "related_event_id" "uuid",
    "target_user_id" "uuid",
    "channel" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text",
    "sent_at" timestamp with time zone
);


ALTER TABLE "public"."notification_delivery_queue" OWNER TO "postgres";


COMMENT ON TABLE "public"."notification_delivery_queue" IS 'Queue system for delivering notifications across channels.';



CREATE TABLE IF NOT EXISTS "public"."notification_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "notification_type" "text" NOT NULL,
    "message" "text" NOT NULL,
    "related_event_id" "uuid",
    "sent_to" "jsonb",
    "status" "text" DEFAULT 'sent'::"text"
);


ALTER TABLE "public"."notification_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notification_recipients" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid",
    "channel" "text" NOT NULL,
    "is_enabled" boolean DEFAULT true
);


ALTER TABLE "public"."notification_recipients" OWNER TO "postgres";


COMMENT ON TABLE "public"."notification_recipients" IS 'Defines how users receive notifications (email, SMS, in-app).';



CREATE TABLE IF NOT EXISTS "public"."notification_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "rule_name" "text" NOT NULL,
    "trigger_event" "text" NOT NULL,
    "severity" "text" DEFAULT 'info'::"text",
    "notify_admin" boolean DEFAULT true,
    "notify_service" boolean DEFAULT false,
    "cooldown_minutes" integer DEFAULT 1440,
    "is_active" boolean DEFAULT true
);


ALTER TABLE "public"."notification_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "type" "text" NOT NULL,
    "message" "text" NOT NULL,
    "related_event_id" "uuid",
    "is_read" boolean DEFAULT false
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pay_type_rules" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "pay_type" "text" NOT NULL,
    "tax_applicable" boolean DEFAULT false,
    "priority" integer DEFAULT 0,
    "stacking_allowed" boolean DEFAULT true,
    "active" boolean DEFAULT true,
    "is_active" boolean DEFAULT true NOT NULL,
    "is_taxable" boolean DEFAULT false NOT NULL,
    "default_daily_amount" numeric(12,2),
    "sort_order" integer DEFAULT 0 NOT NULL,
    "description" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_pay_type_rules_default_daily_amount" CHECK ((("default_daily_amount" IS NULL) OR ("default_daily_amount" >= (0)::numeric))),
    CONSTRAINT "ck_pay_type_rules_sort_order" CHECK (("sort_order" >= 0))
);


ALTER TABLE "public"."pay_type_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."permissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "permission_key" "text" NOT NULL,
    "description" "text"
);


ALTER TABLE "public"."permissions" OWNER TO "postgres";


COMMENT ON TABLE "public"."permissions" IS 'Defines granular system permissions such as warranty.approve_override, billing.edit_rates.';



CREATE TABLE IF NOT EXISTS "public"."quotes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "vehicle_class" "text" NOT NULL,
    "start_date" timestamp with time zone NOT NULL,
    "expected_return_datetime" timestamp with time zone NOT NULL,
    "status" "text" NOT NULL,
    "notes" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "converted_to_reservation_id" "uuid",
    "customer_id" "uuid"
);


ALTER TABLE "public"."quotes" OWNER TO "postgres";


COMMENT ON TABLE "public"."quotes" IS 'Stores all quote requests for vehicle rentals and loaners. Represents non-binding customer intent before reservation confirmation. Quotes are used for availability checking, sales follow-up, and future capacity projection, but do not block fleet availability.';



COMMENT ON COLUMN "public"."quotes"."id" IS 'Unique identifier for each quote record. Used as the primary key to reference and track individual quote requests across the system.';



COMMENT ON COLUMN "public"."quotes"."created_at" IS 'Timestamp indicating when the quote was created in the system. Used for tracking quote history, sorting, and auditing when customer requests were generated.';



COMMENT ON COLUMN "public"."quotes"."vehicle_class" IS 'Defines the class/category of vehicle being requested in the quote. This is used for availability projection, pricing logic, and matching against fleet capacity limits.';



COMMENT ON COLUMN "public"."quotes"."start_date" IS 'The beginning date and time of the requested quote period. Used to determine availability, calculate overlaps with reservations, and evaluate fleet capacity across the requested range.';



COMMENT ON COLUMN "public"."quotes"."expected_return_datetime" IS 'The ending date and time of the requested quote period. Defines the full range of the customer’s requested vehicle usage and is used for availability checks, overlap detection, and capacity projection.';



COMMENT ON COLUMN "public"."quotes"."status" IS 'The ending date and time of the requested quote period. Defines the full range of the customer’s requested vehicle usage and is used for availability checks, overlap detection, and capacity projection.';



COMMENT ON COLUMN "public"."quotes"."notes" IS 'Internal notes field used by staff to record context, customer preferences, pricing discussions, or any additional information relevant to the quote that is not structured elsewhere.';



COMMENT ON COLUMN "public"."quotes"."is_active" IS 'Indicates whether the quote is currently active and should be considered in availability projections, dashboards, and operational views.';



COMMENT ON COLUMN "public"."quotes"."converted_to_reservation_id" IS 'Stores the reservation ID that this quote was converted into. Used to maintain traceability between a quote and its final confirmed reservation once the booking is completed.';



CREATE TABLE IF NOT EXISTS "public"."rental_model_limits" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "vehicle_class" "text" NOT NULL,
    "daily_limit" integer NOT NULL
);


ALTER TABLE "public"."rental_model_limits" OWNER TO "postgres";


COMMENT ON TABLE "public"."rental_model_limits" IS 'Defines maximum daily reservation capacity per vehicle class. Used by the scheduling system to enforce fleet availability limits for rentals and loaners.';



COMMENT ON COLUMN "public"."rental_model_limits"."id" IS 'Unique system-generated identifier for each vehicle class capacity rule. Used as the primary key for referencing and managing rental model limit records across the scheduling system.';



COMMENT ON COLUMN "public"."rental_model_limits"."created_at" IS 'Timestamp indicating when the vehicle class capacity rule was created in the system. Used for auditing changes to fleet capacity settings and tracking configuration history over time.';



COMMENT ON COLUMN "public"."rental_model_limits"."vehicle_class" IS 'Defines the vehicle class that this capacity rule applies to (e.g., Trax, Equinox, Loaner). Used to group vehicles for scheduling limits and enforce daily availability constraints per class.';



COMMENT ON COLUMN "public"."rental_model_limits"."daily_limit" IS 'Maximum number of reservations allowed per day for this vehicle class. Used by the scheduling system to enforce fleet capacity limits and prevent overbooking of available units.';



CREATE TABLE IF NOT EXISTS "public"."reservation_conflicts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reservation_id" "uuid" NOT NULL,
    "vehicle_class" "text" NOT NULL,
    "conflict_type" "text" NOT NULL,
    "severity" "text" NOT NULL,
    "message" "text" NOT NULL,
    "is_resolved" boolean DEFAULT false NOT NULL,
    "resolved_at" timestamp with time zone,
    "created_by" "text" NOT NULL,
    "reservation_vehicle_dependency_id" "uuid"
);


ALTER TABLE "public"."reservation_conflicts" OWNER TO "postgres";


COMMENT ON TABLE "public"."reservation_conflicts" IS 'Stores detected scheduling conflicts when reserved bookings exceed vehicle class capacity limits. Used for persistent warnings, calendar indicators, and operational resolution tracking.';



COMMENT ON COLUMN "public"."reservation_conflicts"."id" IS 'Unique system-generated identifier for each conflict record. Used as the primary key to reference and manage individual scheduling conflicts across reservations, capacity limits, and operational alerts.';



COMMENT ON COLUMN "public"."reservation_conflicts"."created_at" IS 'Timestamp indicating when the conflict record was generated. Used for audit tracking, reporting, and understanding when scheduling conflicts first occurred in the system.';



COMMENT ON COLUMN "public"."reservation_conflicts"."reservation_id" IS 'The reservation record that triggered this conflict. Used to link each conflict to the specific booking causing a capacity violation or scheduling issue.';



COMMENT ON COLUMN "public"."reservation_conflicts"."vehicle_class" IS 'The vehicle class associated with the conflict (e.g. Trax, Equinox, Loaner). Used to determine which rental model limit applies when evaluating capacity rules and generating scheduling conflicts.';



COMMENT ON COLUMN "public"."reservation_conflicts"."conflict_type" IS 'Defines the type of scheduling conflict detected for this record. Used to categorize why the conflict was created (e.g. capacity exceeded, overlap detected, or manual override warning).';



COMMENT ON COLUMN "public"."reservation_conflicts"."severity" IS 'Indicates the urgency level of the conflict. Used to prioritize alerts in the UI, determine visual emphasis on the calendar, and guide operational response.';



COMMENT ON COLUMN "public"."reservation_conflicts"."message" IS 'Human-readable explanation of the conflict. This message is displayed in the UI to explain why the conflict was created, providing clear context for staff to understand and resolve the issue.';



COMMENT ON COLUMN "public"."reservation_conflicts"."is_resolved" IS 'Indicates whether the conflict has been reviewed and resolved. Used to control whether the conflict is still active and should appear in warnings, dashboards, and scheduling alerts.';



COMMENT ON COLUMN "public"."reservation_conflicts"."resolved_at" IS 'Timestamp indicating when the conflict was marked as resolved. Used for audit history and tracking how long scheduling issues remained open before being addressed.';



COMMENT ON COLUMN "public"."reservation_conflicts"."created_by" IS 'Identifier of the user or system process that created the conflict record. Used for audit tracking, accountability, and identifying whether the conflict was system-generated or manually flagged.';



CREATE TABLE IF NOT EXISTS "public"."reservation_vehicle_dependencies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "reservation_id" "uuid" NOT NULL,
    "vehicle_id" "uuid" NOT NULL,
    "source_transportation_event_id" "uuid",
    "dependency_type" "text" NOT NULL,
    "status" "text" DEFAULT 'pending_return'::"text" NOT NULL,
    "risk_level" "text" DEFAULT 'normal'::"text" NOT NULL,
    "expected_return_snapshot" timestamp with time zone,
    "resolution_type" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by_user_id" "uuid",
    "updated_by_user_id" "uuid",
    "resolved_at" timestamp with time zone,
    "resolved_by_user_id" "uuid",
    CONSTRAINT "reservation_vehicle_dependencies_dependency_type_check" CHECK (("dependency_type" = ANY (ARRAY['soft_lock'::"text", 'hard_lock'::"text"]))),
    CONSTRAINT "reservation_vehicle_dependencies_resolution_type_check" CHECK (("resolution_type" = ANY (ARRAY['reassigned'::"text", 'vehicle_returned_available'::"text", 'removed'::"text", 'cancelled'::"text", 'other'::"text"]))),
    CONSTRAINT "reservation_vehicle_dependencies_risk_level_check" CHECK (("risk_level" = ANY (ARRAY['normal'::"text", 'depends_on_return'::"text", 'at_risk'::"text", 'must_return'::"text", 'critical'::"text"]))),
    CONSTRAINT "reservation_vehicle_dependencies_status_check" CHECK (("status" = ANY (ARRAY['pending_return'::"text", 'ready'::"text", 'conflict'::"text", 'resolved'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."reservation_vehicle_dependencies" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."reservations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "vehicle_id" "uuid",
    "start_date" timestamp with time zone NOT NULL,
    "expected_return_datetime" timestamp with time zone NOT NULL,
    "status" "text" DEFAULT 'quote'::"text" NOT NULL,
    "reservation_type" "text" DEFAULT 'rental'::"text" NOT NULL,
    "notes" "text",
    "cancellation_reason" "text",
    "start_mileage" integer,
    "end_mileage" integer,
    "condition_flag" boolean DEFAULT false NOT NULL,
    "requested_model" "text" NOT NULL,
    "service_advisor" "text",
    "ro_number" "text",
    "pay_type" "text" DEFAULT 'customer'::"text" NOT NULL,
    "actual_return_datetime" timestamp with time zone,
    "billed_through_datetime" timestamp with time zone,
    "transportation_event_id" "uuid" NOT NULL,
    "customer_id" "uuid"
);


ALTER TABLE "public"."reservations" OWNER TO "postgres";


COMMENT ON TABLE "public"."reservations" IS 'Core transaction table for all vehicle reservations including rentals and loaner assignments. Tracks vehicle allocation, customer assignment, time-based usage periods, extensions, swaps, cancellations, and no-shows. Serves as the primary source of truth for operational scheduling, availability conflicts, and billing workflow integration.';



COMMENT ON COLUMN "public"."reservations"."id" IS 'Unique identifier for each reservation record. Used as the primary system key for linking reservations to vehicles, customers, billing entries, swaps, and audit logs.';



COMMENT ON COLUMN "public"."reservations"."created_at" IS 'Timestamp indicating when the reservation record was created in the system. Used for auditing, reporting, reservation aging logic, and operational tracking.';



COMMENT ON COLUMN "public"."reservations"."vehicle_id" IS 'References the vehicle assigned to this reservation. Used to link reservations to fleet inventory and enforce availability rules.';



COMMENT ON COLUMN "public"."reservations"."start_date" IS 'Date and time when the reservation begins and the vehicle is officially assigned to the customer.';



COMMENT ON COLUMN "public"."reservations"."expected_return_datetime" IS 'Date and time when the reservation ends and the vehicle is expected to be returned or made available for reassignment.';



COMMENT ON COLUMN "public"."reservations"."status" IS 'Current lifecycle status of the reservation or quote. Controls operational workflow, vehicle availability, customer progression, and billing behavior. Typical values include Quote, Reserved, Active, Completed, Cancelled, and No-Show.';



COMMENT ON COLUMN "public"."reservations"."reservation_type" IS 'Defines the operational category of the reservation. Used to distinguish how the reservation is handled in scheduling, reporting, and fleet usage (e.g. rental vs loaner).';



COMMENT ON COLUMN "public"."reservations"."notes" IS 'Internal notes about the reservation for staff use. Used to store special instructions, customer requests, exceptions, damage notes, or operational comments that do not fit into structured fields.';



COMMENT ON COLUMN "public"."reservations"."cancellation_reason" IS 'Reason why a reservation was cancelled. Used for operational reporting, customer behavior tracking, and policy enforcement analysis.';



COMMENT ON COLUMN "public"."reservations"."start_mileage" IS 'Odometer reading of the vehicle at the start of the reservation when it is handed over to the customer. Used for mileage tracking, billing rules, and vehicle usage history.';



COMMENT ON COLUMN "public"."reservations"."end_mileage" IS 'Odometer reading of the vehicle at the end of the reservation when it is returned. Used to calculate total mileage used during the reservation and support billing, usage tracking, and vehicle wear analysis.';



COMMENT ON COLUMN "public"."reservations"."condition_flag" IS 'Indicates whether any damage, abnormal wear, or condition issue was noted during or after the reservation return inspection. Used as a quick operational flag for follow-up or billing review.';



COMMENT ON COLUMN "public"."reservations"."requested_model" IS 'Requested model for reservations before a specific vehicle_id is assigned during the VIN-lock window.';



COMMENT ON COLUMN "public"."reservations"."service_advisor" IS 'References the assigned service advisor for a loaner reservation. Used for operational tracking, RO coordination, and reporting. Allows tracking of which advisor is responsible for a vehicle during its loan period.';



COMMENT ON COLUMN "public"."reservations"."ro_number" IS 'References the Repair Order (RO) number associated with a loaner reservation. Used to link dealership service work to the loaner vehicle, enabling tracking of service-related vehicle usage and reporting.';



COMMENT ON COLUMN "public"."reservations"."pay_type" IS 'Defines who is financially responsible for the reservation. Used for billing logic, reporting, and ownership tracking. Determines whether the charge is customer-paid, internal dealership, warranty, insurance, or other defined payment categories.';



COMMENT ON COLUMN "public"."reservations"."actual_return_datetime" IS 'The date and time the vehicle was physically returned and checked back into the dealership. This represents the actual completion of a rental or loaner period and is used for historical tracking, utilization reporting, and lifecycle closure. This field is only populated once the vehicle has been returned and is NULL while the vehicle is still out on an active reservation.';



COMMENT ON COLUMN "public"."reservations"."billed_through_datetime" IS 'The date and time through which the vehicle is billed for usage. This field may differ from the expected or actual return times and is used for financial tracking, billing adjustments, and charge calculation. It represents the financial cutoff point for the reservation and is independent of operational return status.';



COMMENT ON COLUMN "public"."reservations"."transportation_event_id" IS 'Unique identifier that represents a single continuous transportation event for a customer, such as a rental or loaner request. This ID groups all related reservations, vehicle swaps, extensions, and lifecycle changes under one unified record, regardless of how many vehicles are involved throughout the duration of the event. It serves as the parent-level tracking key for the entire transaction from start to completion.';



CREATE TABLE IF NOT EXISTS "public"."role_permissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "role_id" "uuid",
    "permission_id" "uuid"
);


ALTER TABLE "public"."role_permissions" OWNER TO "postgres";


COMMENT ON TABLE "public"."role_permissions" IS 'Maps permissions to roles.';



CREATE TABLE IF NOT EXISTS "public"."roles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "role_name" "text" NOT NULL,
    "description" "text",
    "is_system_role" boolean DEFAULT false
);


ALTER TABLE "public"."roles" OWNER TO "postgres";


COMMENT ON TABLE "public"."roles" IS 'Defines system roles such as Admin, Service Manager, Advisor, Billing Viewer.';



CREATE TABLE IF NOT EXISTS "public"."service_action_contracts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "action_key" "text" NOT NULL,
    "action_group" "text" NOT NULL,
    "entity_scope" "text" NOT NULL,
    "db_function_name" "text" NOT NULL,
    "action_type" "text" NOT NULL,
    "description" "text",
    "requires_authenticated_user" boolean DEFAULT true NOT NULL,
    "requires_aal2" boolean DEFAULT false NOT NULL,
    "writes_data" boolean DEFAULT false NOT NULL,
    "frontend_safe" boolean DEFAULT true NOT NULL,
    "internal_only" boolean DEFAULT false NOT NULL,
    "required_permission" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."service_action_contracts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tags" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "tag_name" "text" NOT NULL,
    "tag_type" "text" NOT NULL,
    "expires_at" timestamp with time zone,
    "status" "text" DEFAULT 'active'::"text" NOT NULL
);


ALTER TABLE "public"."tags" OWNER TO "postgres";


COMMENT ON TABLE "public"."tags" IS 'Master tag registry used for fleet control. Tags define operational restrictions and permissions for vehicles (e.g. Loaner, Rental, EV Protected). Includes assignment rules, expiration tracking, and admin control.';



COMMENT ON COLUMN "public"."tags"."id" IS 'Unique system identifier for each tag record. Used internally for database relationships and does not change.';



COMMENT ON COLUMN "public"."tags"."created_at" IS 'Timestamp when the tag record was created or assigned. Used for audit tracking and historical reporting of tag changes over time.';



COMMENT ON COLUMN "public"."tags"."tag_name" IS 'Human-readable tag identifier used to classify vehicles (e.g. LOANER, RENTAL, EV_PROTECTED). Defines operational rules applied to vehicles assigned this tag.';



COMMENT ON COLUMN "public"."tags"."tag_type" IS 'Defines the operational category of the tag. Determines system behavior rules for vehicles assigned this tag (e.g. LOANER_RULE, RENTAL_RULE, RESTRICTION, PROTECTED, SWAP_CONTROL).';



COMMENT ON COLUMN "public"."tags"."expires_at" IS 'Expiration date and time for the tag assignment. Used for automated warning alerts, renewal notifications, and enforcing time-limited operational restrictions.';



COMMENT ON COLUMN "public"."tags"."status" IS 'Operational status of the tag. Determines whether the tag can be assigned to vehicles and used in system logic. Common values: active, inactive, expired.';



CREATE TABLE IF NOT EXISTS "public"."transportation_event_notes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "transportation_event_id" "uuid" NOT NULL,
    "note_type" "text" NOT NULL,
    "reason_code" "text",
    "note_text" "text",
    "old_estimated_return" timestamp with time zone,
    "new_estimated_return" timestamp with time zone,
    "entered_by_user_id" "uuid",
    "entered_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source_context" "text",
    CONSTRAINT "ck_transportation_event_notes_est_return_reason" CHECK ((("note_type" <> 'estimated_return_change'::"text") OR ("reason_code" IS NOT NULL))),
    CONSTRAINT "transportation_event_notes_note_type_check" CHECK (("note_type" = ANY (ARRAY['general_case_note'::"text", 'estimated_return_change'::"text", 'billing_note'::"text"]))),
    CONSTRAINT "transportation_event_notes_source_context_check" CHECK ((("source_context" IS NULL) OR ("source_context" = ANY (ARRAY['case'::"text", 'billing'::"text", 'reservation'::"text"]))))
);


ALTER TABLE "public"."transportation_event_notes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."transportation_event_state_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "transportation_event_id" "uuid" NOT NULL,
    "previous_status" "text",
    "new_status" "text" NOT NULL,
    "changed_at" timestamp with time zone DEFAULT "now"(),
    "changed_by" "text",
    "metadata" "jsonb"
);


ALTER TABLE "public"."transportation_event_state_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."transportation_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "source_type" "text" NOT NULL,
    "source_id" "uuid",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "notes" "text",
    "customer_id" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "closed_at" timestamp with time zone,
    "closed_by" "uuid",
    "expected_return_at" timestamp with time zone
);


ALTER TABLE "public"."transportation_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_auth_security_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "factor_type" "text",
    "event_status" "text",
    "details" "jsonb",
    "recorded_by_user_id" "uuid",
    "recorded_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_auth_security_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_roles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid",
    "role_id" "uuid"
);


ALTER TABLE "public"."user_roles" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_roles" IS 'Maps users to roles for access control.';



CREATE OR REPLACE VIEW "public"."v_active_approved_networks" WITH ("security_invoker"='true') AS
 SELECT "id",
    "label",
    "network_value",
    "network_type",
    "is_active",
    "notes",
    "created_at",
    "updated_at",
    "created_by_user_id",
    "updated_by_user_id"
   FROM "public"."approved_networks" "an"
  WHERE ("is_active" = true);


ALTER VIEW "public"."v_active_approved_networks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."warranty_providers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "name" "text" NOT NULL,
    "provider_type" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "default_daily_rate" numeric(12,2),
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "notes" "text"
);


ALTER TABLE "public"."warranty_providers" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_active_extended_warranty_provider_rules" WITH ("security_invoker"='true') AS
 SELECT "wp"."id" AS "provider_id",
    "wp"."name" AS "provider_name",
    "wp"."provider_type",
    "wp"."is_active" AS "provider_is_active",
    "wp"."default_daily_rate" AS "provider_default_daily_rate",
    "ewr"."id" AS "rule_id",
    "ewr"."covered_days",
    "ewr"."requires_approval",
    "ewr"."daily_rate" AS "rule_daily_rate",
    "ewr"."is_active" AS "rule_is_active",
    "ewr"."created_at",
    "ewr"."updated_at",
    COALESCE("ewr"."daily_rate", "wp"."default_daily_rate") AS "resolved_daily_rate"
   FROM ("public"."warranty_providers" "wp"
     JOIN "public"."extended_warranty_rules" "ewr" ON (("ewr"."provider_id" = "wp"."id")))
  WHERE (("wp"."is_active" = true) AND ("ewr"."is_active" = true));


ALTER VIEW "public"."v_active_extended_warranty_provider_rules" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_active_hard_lock_conflicts" WITH ("security_invoker"='true') AS
 SELECT "d"."id" AS "dependency_id",
    "d"."reservation_id",
    "d"."vehicle_id",
    "d"."source_transportation_event_id",
    "d"."dependency_type",
    "d"."status" AS "dependency_status",
    "d"."risk_level",
    "d"."expected_return_snapshot",
    "c"."id" AS "conflict_id",
    "c"."conflict_type",
    "c"."severity",
    "c"."message",
    "c"."is_resolved"
   FROM ("public"."reservation_vehicle_dependencies" "d"
     LEFT JOIN "public"."reservation_conflicts" "c" ON ((("c"."reservation_vehicle_dependency_id" = "d"."id") AND ("c"."is_resolved" = false))))
  WHERE (("d"."dependency_type" = 'hard_lock'::"text") AND ("d"."status" = ANY (ARRAY['ready'::"text", 'conflict'::"text"])));


ALTER VIEW "public"."v_active_hard_lock_conflicts" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_active_late_fee_rules" WITH ("security_invoker"='true') AS
 SELECT "id" AS "late_fee_rule_id",
    "is_active",
    "sort_order",
    "rule_kind",
    "threshold_unit",
    "threshold_value",
    "fee_amount",
    "description",
    "created_at",
    "updated_at",
    "created_by",
    "updated_by"
   FROM "public"."late_fee_rules" "lfr"
  WHERE ("is_active" = true);


ALTER VIEW "public"."v_active_late_fee_rules" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_active_usable_reset_tokens" WITH ("security_invoker"='true') AS
 SELECT "id" AS "reset_token_id",
    "user_id",
    "token_hash",
    "reset_mode",
    "issued_at",
    "expires_at",
    "used_at",
    "is_active",
    "issued_by_user_id",
    "notes"
   FROM "public"."app_user_reset_tokens" "t"
  WHERE (("is_active" = true) AND ("used_at" IS NULL) AND ("expires_at" >= "now"()));


ALTER VIEW "public"."v_active_usable_reset_tokens" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_admin_settings_catalog" WITH ("security_invoker"='true') AS
 SELECT "s"."id" AS "admin_setting_id",
    "s"."setting_key",
    "s"."setting_value",
    "s"."description",
    "asp"."required_permission",
    ("asp"."required_permission" IS NOT NULL) AS "has_permission_requirement"
   FROM ("public"."admin_settings" "s"
     LEFT JOIN "public"."admin_setting_permissions" "asp" ON (("asp"."setting_key" = "s"."setting_key")));


ALTER VIEW "public"."v_admin_settings_catalog" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_app_users_with_roles" WITH ("security_invoker"='true') AS
 SELECT "u"."id" AS "user_id",
    "u"."auth_user_id",
    "u"."full_name",
    "u"."email",
    "u"."phone",
    "u"."is_active",
    "u"."last_login",
    "u"."notes",
    COALESCE("string_agg"(DISTINCT "r"."role_name", ', '::"text" ORDER BY "r"."role_name") FILTER (WHERE ("r"."role_name" IS NOT NULL)), ''::"text") AS "role_summary"
   FROM (("public"."app_users" "u"
     LEFT JOIN "public"."user_roles" "ur" ON (("ur"."user_id" = "u"."id")))
     LEFT JOIN "public"."roles" "r" ON (("r"."id" = "ur"."role_id")))
  GROUP BY "u"."id", "u"."auth_user_id", "u"."full_name", "u"."email", "u"."phone", "u"."is_active", "u"."last_login", "u"."notes";


ALTER VIEW "public"."v_app_users_with_roles" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_auth_security_policy_state" AS
 SELECT COALESCE(( SELECT ("admin_settings"."setting_value")::boolean AS "setting_value"
           FROM "public"."admin_settings"
          WHERE ("admin_settings"."setting_key" = 'mfa_required_for_all_users'::"text")
         LIMIT 1), true) AS "mfa_required_for_all_users",
    COALESCE(( SELECT ("admin_settings"."setting_value")::boolean AS "setting_value"
           FROM "public"."admin_settings"
          WHERE ("admin_settings"."setting_key" = 'network_restriction_enabled'::"text")
         LIMIT 1), false) AS "network_restriction_enabled",
    COALESCE(( SELECT ("admin_settings"."setting_value")::boolean AS "setting_value"
           FROM "public"."admin_settings"
          WHERE ("admin_settings"."setting_key" = 'email_password_reset_link_enabled'::"text")
         LIMIT 1), false) AS "email_password_reset_link_enabled",
    COALESCE(( SELECT ("admin_settings"."setting_value")::integer AS "setting_value"
           FROM "public"."admin_settings"
          WHERE ("admin_settings"."setting_key" = 'reservation_vin_lock_lead_days'::"text")
         LIMIT 1), 0) AS "reservation_vin_lock_lead_days",
    COALESCE(( SELECT ("admin_settings"."setting_value")::boolean AS "setting_value"
           FROM "public"."admin_settings"
          WHERE ("admin_settings"."setting_key" = 'late_fees_enabled'::"text")
         LIMIT 1), false) AS "late_fees_enabled";


ALTER VIEW "public"."v_auth_security_policy_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_current_open_billing_lines" WITH ("security_invoker"='true') AS
 SELECT "p"."id" AS "parent_billing_line_id",
    "p"."transportation_event_id",
    "p"."reservation_id",
    "p"."vehicle_id",
    "p"."vehicle_event_id",
    "p"."contract_period_id",
    "p"."pay_type",
    "p"."pay_type_rule_id",
    "p"."amount" AS "parent_amount",
    "p"."tax_amount" AS "parent_tax_amount",
    "p"."start_time",
    "p"."end_time",
    "p"."line_type" AS "parent_line_type",
    "p"."warranty_provider_id",
    "p"."default_covered_days_snapshot",
    "p"."covered_days_override",
    "p"."default_daily_rate_snapshot",
    "p"."daily_rate_override",
    "p"."paid_through_at",
    "p"."extended_from_billing_line_id",
    "p"."is_open" AS "parent_is_open",
    "t"."id" AS "tax_billing_line_id",
    "t"."amount" AS "tax_line_amount",
    "t"."is_open" AS "tax_line_is_open"
   FROM ("public"."billing_lines" "p"
     LEFT JOIN "public"."billing_lines" "t" ON ((("t"."parent_billing_line_id" = "p"."id") AND ("t"."line_type" = 'tax'::"text"))))
  WHERE (("p"."is_open" = true) AND ("p"."line_type" IS DISTINCT FROM 'tax'::"text"));


ALTER VIEW "public"."v_current_open_billing_lines" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vehicle_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "transportation_event_id" "uuid" NOT NULL,
    "vehicle_id" "uuid" NOT NULL,
    "actual_out_at" timestamp with time zone NOT NULL,
    "actual_in_at" timestamp with time zone,
    "is_open" boolean DEFAULT true NOT NULL,
    "ended_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "updated_by" "uuid",
    CONSTRAINT "ck_vehicle_events_open_state" CHECK (((("is_open" = true) AND ("actual_in_at" IS NULL)) OR (("is_open" = false) AND ("actual_in_at" IS NOT NULL)))),
    CONSTRAINT "ck_vehicle_events_time_order" CHECK ((("actual_in_at" IS NULL) OR ("actual_in_at" >= "actual_out_at"))),
    CONSTRAINT "vehicle_events_ended_reason_check" CHECK (("ended_reason" = ANY (ARRAY['returned'::"text", 'swapped'::"text", 'case_closed'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."vehicle_events" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_current_vehicle_continuity" WITH ("security_invoker"='true') AS
 SELECT "ve"."id" AS "vehicle_event_id",
    "ve"."transportation_event_id",
    "ve"."vehicle_id",
    "ve"."actual_out_at",
    "ve"."actual_in_at",
    "ve"."is_open" AS "vehicle_event_is_open",
    "ve"."ended_reason",
    "cp"."id" AS "contract_period_id",
    "cp"."contract_out_at",
    "cp"."contract_in_at",
    "cp"."renewal_sequence",
    "cp"."is_open" AS "contract_period_is_open"
   FROM ("public"."vehicle_events" "ve"
     JOIN "public"."contract_periods" "cp" ON (("cp"."vehicle_event_id" = "ve"."id")))
  WHERE (("ve"."is_open" = true) AND ("cp"."is_open" = true));


ALTER VIEW "public"."v_current_vehicle_continuity" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_reservation_transportation_link_state" WITH ("security_invoker"='true') AS
 SELECT "r"."id" AS "reservation_id",
    "r"."transportation_event_id",
    "r"."vehicle_id",
    "r"."start_date",
    "r"."expected_return_datetime",
    "r"."status" AS "reservation_status",
    "r"."reservation_type",
    "r"."notes" AS "reservation_notes",
    "r"."cancellation_reason",
    "r"."start_mileage",
    "r"."end_mileage",
    "r"."condition_flag",
    "r"."requested_model",
    "r"."service_advisor",
    "r"."ro_number",
    "r"."pay_type",
    "r"."actual_return_datetime",
    "r"."billed_through_datetime",
    "r"."customer_id",
    "te"."source_type",
    "te"."source_id",
    "te"."status" AS "transportation_event_status",
    "te"."notes" AS "transportation_event_notes",
    "te"."expected_return_at",
    "te"."closed_at",
    "te"."closed_by"
   FROM ("public"."reservations" "r"
     JOIN "public"."transportation_events" "te" ON (("te"."id" = "r"."transportation_event_id")));


ALTER VIEW "public"."v_reservation_transportation_link_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_reservation_current_billing_state" WITH ("security_invoker"='true') AS
 SELECT "r"."reservation_id",
    "r"."transportation_event_id",
    "r"."vehicle_id" AS "reservation_vehicle_id",
    "r"."start_date",
    "r"."expected_return_datetime",
    "r"."reservation_status",
    "r"."reservation_type",
    "r"."requested_model",
    "r"."pay_type" AS "reservation_pay_type",
    "r"."customer_id",
    "b"."parent_billing_line_id",
    "b"."vehicle_id" AS "billing_vehicle_id",
    "b"."vehicle_event_id",
    "b"."contract_period_id",
    "b"."pay_type",
    "b"."pay_type_rule_id",
    "b"."parent_amount",
    "b"."parent_tax_amount",
    "b"."start_time",
    "b"."end_time",
    "b"."parent_line_type",
    "b"."warranty_provider_id",
    "b"."default_covered_days_snapshot",
    "b"."covered_days_override",
    "b"."default_daily_rate_snapshot",
    "b"."daily_rate_override",
    "b"."paid_through_at",
    "b"."extended_from_billing_line_id",
    "b"."parent_is_open",
    "b"."tax_billing_line_id",
    "b"."tax_line_amount",
    "b"."tax_line_is_open"
   FROM ("public"."v_reservation_transportation_link_state" "r"
     LEFT JOIN "public"."v_current_open_billing_lines" "b" ON (("b"."reservation_id" = "r"."reservation_id")));


ALTER VIEW "public"."v_reservation_current_billing_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_case_activation_state" WITH ("security_invoker"='true') AS
 SELECT "r"."reservation_id",
    "r"."transportation_event_id",
    "r"."vehicle_id" AS "reservation_vehicle_id",
    "r"."start_date",
    "r"."expected_return_datetime",
    "r"."reservation_status",
    "r"."reservation_type",
    "r"."requested_model",
    "r"."pay_type" AS "reservation_pay_type",
    "r"."customer_id",
    "c"."vehicle_event_id" AS "current_vehicle_event_id",
    "c"."vehicle_id" AS "current_continuity_vehicle_id",
    "c"."contract_period_id" AS "current_contract_period_id",
    "c"."actual_out_at",
    "c"."contract_out_at",
    "c"."vehicle_event_is_open",
    "c"."contract_period_is_open",
    "b"."parent_billing_line_id",
    "b"."pay_type" AS "billing_pay_type",
    "b"."parent_amount",
    "b"."parent_tax_amount",
    "b"."start_time" AS "billing_start_time",
    "b"."end_time" AS "billing_end_time",
    "b"."paid_through_at",
    "b"."parent_is_open" AS "billing_is_open",
    ("c"."vehicle_event_id" IS NOT NULL) AS "has_active_continuity",
    ("b"."parent_billing_line_id" IS NOT NULL) AS "has_open_billing_line"
   FROM (("public"."v_reservation_transportation_link_state" "r"
     LEFT JOIN "public"."v_current_vehicle_continuity" "c" ON (("c"."transportation_event_id" = "r"."transportation_event_id")))
     LEFT JOIN LATERAL ( SELECT "b_1"."reservation_id",
            "b_1"."transportation_event_id",
            "b_1"."reservation_vehicle_id",
            "b_1"."start_date",
            "b_1"."expected_return_datetime",
            "b_1"."reservation_status",
            "b_1"."reservation_type",
            "b_1"."requested_model",
            "b_1"."reservation_pay_type",
            "b_1"."customer_id",
            "b_1"."parent_billing_line_id",
            "b_1"."billing_vehicle_id",
            "b_1"."vehicle_event_id",
            "b_1"."contract_period_id",
            "b_1"."pay_type",
            "b_1"."pay_type_rule_id",
            "b_1"."parent_amount",
            "b_1"."parent_tax_amount",
            "b_1"."start_time",
            "b_1"."end_time",
            "b_1"."parent_line_type",
            "b_1"."warranty_provider_id",
            "b_1"."default_covered_days_snapshot",
            "b_1"."covered_days_override",
            "b_1"."default_daily_rate_snapshot",
            "b_1"."daily_rate_override",
            "b_1"."paid_through_at",
            "b_1"."extended_from_billing_line_id",
            "b_1"."parent_is_open",
            "b_1"."tax_billing_line_id",
            "b_1"."tax_line_amount",
            "b_1"."tax_line_is_open"
           FROM "public"."v_reservation_current_billing_state" "b_1"
          WHERE (("b_1"."reservation_id" = "r"."reservation_id") AND ("b_1"."parent_billing_line_id" IS NOT NULL))
          ORDER BY "b_1"."start_time" DESC NULLS LAST, "b_1"."parent_billing_line_id" DESC
         LIMIT 1) "b" ON (true));


ALTER VIEW "public"."v_case_activation_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_case_completion_candidate_state" WITH ("security_invoker"='true') AS
 SELECT "r"."reservation_id",
    "r"."transportation_event_id",
    "r"."vehicle_id" AS "reservation_vehicle_id",
    "r"."start_date",
    "r"."expected_return_datetime",
    "r"."reservation_status",
    "r"."reservation_type",
    "r"."reservation_notes",
    "r"."actual_return_datetime",
    "r"."billed_through_datetime",
    "r"."customer_id",
    "r"."transportation_event_status",
    "r"."expected_return_at",
    "r"."closed_at",
    "r"."closed_by",
    "c"."vehicle_event_id",
    "c"."contract_period_id",
    "c"."actual_out_at",
    "c"."actual_in_at",
    "c"."vehicle_event_is_open",
    "c"."contract_period_is_open",
    "b"."parent_billing_line_id",
    "b"."start_time" AS "billing_start_time",
    "b"."end_time" AS "billing_end_time",
    "b"."paid_through_at",
    "b"."parent_is_open" AS "billing_is_open",
    ("c"."vehicle_event_id" IS NOT NULL) AS "has_active_continuity",
    ("b"."parent_billing_line_id" IS NOT NULL) AS "has_open_billing_line"
   FROM (("public"."v_reservation_transportation_link_state" "r"
     LEFT JOIN "public"."v_current_vehicle_continuity" "c" ON (("c"."transportation_event_id" = "r"."transportation_event_id")))
     LEFT JOIN LATERAL ( SELECT "b_1"."reservation_id",
            "b_1"."transportation_event_id",
            "b_1"."reservation_vehicle_id",
            "b_1"."start_date",
            "b_1"."expected_return_datetime",
            "b_1"."reservation_status",
            "b_1"."reservation_type",
            "b_1"."requested_model",
            "b_1"."reservation_pay_type",
            "b_1"."customer_id",
            "b_1"."parent_billing_line_id",
            "b_1"."billing_vehicle_id",
            "b_1"."vehicle_event_id",
            "b_1"."contract_period_id",
            "b_1"."pay_type",
            "b_1"."pay_type_rule_id",
            "b_1"."parent_amount",
            "b_1"."parent_tax_amount",
            "b_1"."start_time",
            "b_1"."end_time",
            "b_1"."parent_line_type",
            "b_1"."warranty_provider_id",
            "b_1"."default_covered_days_snapshot",
            "b_1"."covered_days_override",
            "b_1"."default_daily_rate_snapshot",
            "b_1"."daily_rate_override",
            "b_1"."paid_through_at",
            "b_1"."extended_from_billing_line_id",
            "b_1"."parent_is_open",
            "b_1"."tax_billing_line_id",
            "b_1"."tax_line_amount",
            "b_1"."tax_line_is_open"
           FROM "public"."v_reservation_current_billing_state" "b_1"
          WHERE (("b_1"."reservation_id" = "r"."reservation_id") AND ("b_1"."parent_billing_line_id" IS NOT NULL))
          ORDER BY "b_1"."start_time" DESC NULLS LAST, "b_1"."parent_billing_line_id" DESC
         LIMIT 1) "b" ON (true));


ALTER VIEW "public"."v_case_completion_candidate_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_case_continuation_candidate_state" WITH ("security_invoker"='true') AS
 SELECT "r"."reservation_id",
    "r"."transportation_event_id",
    "r"."vehicle_id" AS "reservation_vehicle_id",
    "r"."start_date",
    "r"."expected_return_datetime",
    "r"."reservation_status",
    "r"."reservation_type",
    "r"."requested_model",
    "r"."customer_id",
    "r"."actual_return_datetime",
    "r"."billed_through_datetime",
    "c"."vehicle_event_id" AS "current_vehicle_event_id",
    "c"."vehicle_id" AS "current_continuity_vehicle_id",
    "c"."contract_period_id" AS "current_contract_period_id",
    "c"."actual_out_at",
    "c"."actual_in_at",
    "c"."contract_out_at",
    "c"."contract_in_at",
    "c"."renewal_sequence",
    "c"."vehicle_event_is_open",
    "c"."contract_period_is_open",
    ("r"."vehicle_id" IS NOT NULL) AS "reservation_has_assigned_vehicle",
    ("c"."vehicle_event_id" IS NOT NULL) AS "has_active_continuity"
   FROM ("public"."v_reservation_transportation_link_state" "r"
     LEFT JOIN "public"."v_current_vehicle_continuity" "c" ON (("c"."transportation_event_id" = "r"."transportation_event_id")));


ALTER VIEW "public"."v_case_continuation_candidate_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_reservation_assignment_state" WITH ("security_invoker"='true') AS
 WITH "vin_lock_setting" AS (
         SELECT COALESCE((("admin_settings"."setting_value" #>> '{}'::"text"[]))::integer, 0) AS "vin_lock_lead_days"
           FROM "public"."admin_settings"
          WHERE ("admin_settings"."setting_key" = 'reservation_vin_lock_lead_days'::"text")
        )
 SELECT "r"."id" AS "reservation_id",
    "r"."transportation_event_id",
    "r"."vehicle_id",
    "r"."start_date",
    "r"."expected_return_datetime",
    "r"."requested_model",
    "r"."reservation_type",
    "r"."status" AS "reservation_status",
    "r"."notes" AS "reservation_notes",
    "s"."vin_lock_lead_days",
    ("r"."start_date" - "make_interval"("days" => "s"."vin_lock_lead_days")) AS "lock_window_starts_at",
    ("now"() >= ("r"."start_date" - "make_interval"("days" => "s"."vin_lock_lead_days"))) AS "is_in_lock_window",
    ("r"."vehicle_id" IS NOT NULL) AS "vehicle_is_assigned"
   FROM ("public"."reservations" "r"
     CROSS JOIN "vin_lock_setting" "s");


ALTER VIEW "public"."v_reservation_assignment_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_reservation_operational_state" WITH ("security_invoker"='true') AS
 SELECT "r"."reservation_id",
    "r"."transportation_event_id",
    "r"."vehicle_id",
    "r"."start_date",
    "r"."expected_return_datetime",
    "r"."reservation_status",
    "r"."reservation_type",
    "r"."reservation_notes",
    "r"."cancellation_reason",
    "r"."start_mileage",
    "r"."end_mileage",
    "r"."condition_flag",
    "r"."requested_model",
    "r"."service_advisor",
    "r"."ro_number",
    "r"."pay_type",
    "r"."actual_return_datetime",
    "r"."billed_through_datetime",
    "r"."customer_id",
    "r"."source_type",
    "r"."source_id",
    "r"."transportation_event_status",
    "r"."transportation_event_notes",
    "r"."expected_return_at",
    "r"."closed_at",
    "r"."closed_by",
    "a"."vin_lock_lead_days",
    "a"."lock_window_starts_at",
    "a"."is_in_lock_window",
    "a"."vehicle_is_assigned",
    "dep"."dependency_id" AS "current_dependency_id",
    "dep"."dependency_type" AS "current_dependency_type",
    "dep"."status" AS "current_dependency_status",
    "dep"."risk_level" AS "current_dependency_risk_level",
    "dep"."expected_return_snapshot" AS "current_dependency_expected_return_snapshot",
    "dep"."conflict_id" AS "current_conflict_id",
    "dep"."conflict_severity" AS "current_conflict_severity",
    "dep"."conflict_message" AS "current_conflict_message"
   FROM (("public"."v_reservation_transportation_link_state" "r"
     LEFT JOIN "public"."v_reservation_assignment_state" "a" ON (("a"."reservation_id" = "r"."reservation_id")))
     LEFT JOIN LATERAL ( SELECT "d"."id" AS "dependency_id",
            "d"."dependency_type",
            "d"."status",
            "d"."risk_level",
            "d"."expected_return_snapshot",
            "c"."id" AS "conflict_id",
            "c"."severity" AS "conflict_severity",
            "c"."message" AS "conflict_message"
           FROM ("public"."reservation_vehicle_dependencies" "d"
             LEFT JOIN "public"."reservation_conflicts" "c" ON ((("c"."reservation_vehicle_dependency_id" = "d"."id") AND ("c"."is_resolved" = false))))
          WHERE (("d"."reservation_id" = "r"."reservation_id") AND ("d"."status" = ANY (ARRAY['pending_return'::"text", 'ready'::"text", 'conflict'::"text"])))
          ORDER BY "d"."updated_at" DESC NULLS LAST, "d"."created_at" DESC NULLS LAST
         LIMIT 1) "dep" ON (true));


ALTER VIEW "public"."v_reservation_operational_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_case_reassignment_candidate_state" WITH ("security_invoker"='true') AS
 SELECT "r"."reservation_id",
    "r"."transportation_event_id",
    "r"."vehicle_id" AS "reservation_vehicle_id",
    "r"."start_date",
    "r"."expected_return_datetime",
    "r"."reservation_status",
    "r"."reservation_type",
    "r"."requested_model",
    "r"."customer_id",
    "c"."vehicle_event_id" AS "current_vehicle_event_id",
    "c"."vehicle_id" AS "current_continuity_vehicle_id",
    "c"."contract_period_id" AS "current_contract_period_id",
    "c"."actual_out_at",
    "c"."contract_out_at",
    "c"."vehicle_event_is_open",
    "c"."contract_period_is_open",
    "dep"."current_dependency_id",
    "dep"."current_dependency_type",
    "dep"."current_dependency_status",
    "dep"."current_dependency_risk_level",
    "dep"."current_dependency_expected_return_snapshot",
    ("c"."vehicle_event_id" IS NOT NULL) AS "has_active_continuity",
    ("r"."vehicle_id" IS NOT NULL) AS "reservation_has_assigned_vehicle"
   FROM (("public"."v_reservation_operational_state" "r"
     LEFT JOIN "public"."v_current_vehicle_continuity" "c" ON (("c"."transportation_event_id" = "r"."transportation_event_id")))
     LEFT JOIN LATERAL ( SELECT "d"."id" AS "current_dependency_id",
            "d"."dependency_type" AS "current_dependency_type",
            "d"."status" AS "current_dependency_status",
            "d"."risk_level" AS "current_dependency_risk_level",
            "d"."expected_return_snapshot" AS "current_dependency_expected_return_snapshot"
           FROM "public"."reservation_vehicle_dependencies" "d"
          WHERE (("d"."reservation_id" = "r"."reservation_id") AND ("d"."status" = ANY (ARRAY['pending_return'::"text", 'ready'::"text", 'conflict'::"text"])))
          ORDER BY "d"."updated_at" DESC NULLS LAST, "d"."created_at" DESC NULLS LAST, "d"."id" DESC
         LIMIT 1) "dep" ON (true));


ALTER VIEW "public"."v_case_reassignment_candidate_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_contract_period_monitoring" WITH ("security_invoker"='true') AS
 SELECT "cp"."id" AS "contract_period_id",
    "cp"."vehicle_event_id",
    "ve"."transportation_event_id",
    "ve"."vehicle_id",
    "cp"."contract_out_at",
    "cp"."contract_in_at",
    "cp"."renewal_sequence",
    "cp"."is_open",
    "public"."business_contract_days"("cp"."contract_out_at", "cp"."contract_in_at") AS "contract_day_count",
        CASE
            WHEN ("public"."business_contract_days"("cp"."contract_out_at", "cp"."contract_in_at") >= 30) THEN 'swap_required'::"text"
            WHEN ("public"."business_contract_days"("cp"."contract_out_at", "cp"."contract_in_at") >= 25) THEN 'renew_now'::"text"
            WHEN ("public"."business_contract_days"("cp"."contract_out_at", "cp"."contract_in_at") >= 20) THEN 'renew_soon'::"text"
            ELSE 'none'::"text"
        END AS "reminder_state"
   FROM ("public"."contract_periods" "cp"
     JOIN "public"."vehicle_events" "ve" ON (("ve"."id" = "cp"."vehicle_event_id")));


ALTER VIEW "public"."v_contract_period_monitoring" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_ctp_monitoring_policy_state" AS
 SELECT COALESCE(( SELECT ("admin_settings"."setting_value")::integer AS "setting_value"
           FROM "public"."admin_settings"
          WHERE ("admin_settings"."setting_key" = 'preferred_max_ctp_days'::"text")
         LIMIT 1), 60) AS "preferred_max_ctp_days",
    COALESCE(( SELECT ("admin_settings"."setting_value")::integer AS "setting_value"
           FROM "public"."admin_settings"
          WHERE ("admin_settings"."setting_key" = 'preferred_max_ctp_qualified_miles'::"text")
         LIMIT 1), 2000) AS "preferred_max_ctp_qualified_miles";


ALTER VIEW "public"."v_ctp_monitoring_policy_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_current_extendable_billing_lines" WITH ("security_invoker"='true') AS
 SELECT "id" AS "parent_billing_line_id",
    "transportation_event_id",
    "reservation_id",
    "vehicle_id",
    "vehicle_event_id",
    "contract_period_id",
    "pay_type",
    "pay_type_rule_id",
    "amount",
    "tax_amount",
    "start_time",
    "end_time",
    "line_type",
    "warranty_provider_id",
    "default_covered_days_snapshot",
    "covered_days_override",
    "default_daily_rate_snapshot",
    "daily_rate_override",
    "paid_through_at",
    "extended_from_billing_line_id",
    "is_open"
   FROM "public"."billing_lines" "p"
  WHERE (("is_open" = true) AND ("paid_through_at" IS NOT NULL) AND ("line_type" IS DISTINCT FROM 'tax'::"text"));


ALTER VIEW "public"."v_current_extendable_billing_lines" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_current_pay_type_rules" WITH ("security_invoker"='true') AS
 SELECT "id" AS "pay_type_rule_id",
    "pay_type",
    "is_active",
    "is_taxable",
    "default_daily_amount",
    "sort_order",
    "description"
   FROM "public"."pay_type_rules" "p"
  WHERE ("is_active" = true);


ALTER VIEW "public"."v_current_pay_type_rules" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_customer_operational_aggregate_state" WITH ("security_invoker"='true') AS
 SELECT "c"."id" AS "customer_id",
    "c"."created_at",
    "c"."tekion_customer_number",
    "c"."name",
    "c"."phone",
    "c"."email",
    "c"."flags",
    "c"."internal_notes",
    "count"(DISTINCT "r"."id") AS "reservation_count",
    "count"(DISTINCT "r"."id") FILTER (WHERE ("r"."status" IS DISTINCT FROM 'cancelled'::"text")) AS "non_cancelled_reservation_count",
    "count"(DISTINCT "te"."id") AS "transportation_event_count",
    "count"(DISTINCT "te"."id") FILTER (WHERE ("te"."status" = 'active'::"text")) AS "active_transportation_event_count",
    "count"(DISTINCT "vc"."vehicle_event_id") AS "open_vehicle_continuity_count",
    "max"("te"."expected_return_at") AS "latest_expected_return_at"
   FROM ((("public"."customers" "c"
     LEFT JOIN "public"."reservations" "r" ON (("r"."customer_id" = "c"."id")))
     LEFT JOIN "public"."transportation_events" "te" ON (("te"."customer_id" = "c"."id")))
     LEFT JOIN "public"."v_current_vehicle_continuity" "vc" ON (("vc"."transportation_event_id" = "te"."id")))
  GROUP BY "c"."id", "c"."created_at", "c"."tekion_customer_number", "c"."name", "c"."phone", "c"."email", "c"."flags", "c"."internal_notes";


ALTER VIEW "public"."v_customer_operational_aggregate_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_customer_operational_state" WITH ("security_invoker"='true') AS
 SELECT "id" AS "customer_id",
    "created_at",
    "tekion_customer_number",
    "name",
    "phone",
    "email",
    "flags",
    "internal_notes"
   FROM "public"."customers" "c";


ALTER VIEW "public"."v_customer_operational_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_email_outbound_message_state" AS
 SELECT "m"."id" AS "email_outbound_message_id",
    "m"."email_provider",
    "m"."message_type",
    "m"."template_key",
    "m"."related_user_id",
    "u"."email" AS "related_user_email",
    "u"."full_name" AS "related_user_full_name",
    "m"."related_customer_id",
    "c"."tekion_customer_number" AS "related_customer_tekion_customer_number",
    "c"."name" AS "related_customer_name",
    "c"."email" AS "related_customer_email",
    "m"."related_reservation_id",
    "m"."related_transportation_event_id",
    "m"."to_email",
    "m"."from_email",
    "m"."subject",
    "m"."provider_message_id",
    "m"."send_status",
    "m"."provider_response",
    "m"."queued_at",
    "m"."sent_at",
    "m"."failed_at",
    "m"."last_event_at",
    "m"."created_by_user_id",
    "cb"."email" AS "created_by_email",
    "cb"."full_name" AS "created_by_full_name"
   FROM ((("public"."email_outbound_messages" "m"
     LEFT JOIN "public"."app_users" "u" ON (("u"."id" = "m"."related_user_id")))
     LEFT JOIN "public"."customers" "c" ON (("c"."id" = "m"."related_customer_id")))
     LEFT JOIN "public"."app_users" "cb" ON (("cb"."id" = "m"."created_by_user_id")));


ALTER VIEW "public"."v_email_outbound_message_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_email_webhook_event_history" AS
 SELECT "e"."id" AS "email_webhook_event_id",
    "e"."email_outbound_message_id",
    "m"."message_type",
    "m"."template_key",
    "m"."to_email",
    "m"."from_email",
    "m"."subject",
    "m"."send_status" AS "current_message_send_status",
    "m"."related_user_id",
    "u"."email" AS "related_user_email",
    "u"."full_name" AS "related_user_full_name",
    "m"."related_customer_id",
    "c"."tekion_customer_number" AS "related_customer_tekion_customer_number",
    "c"."name" AS "related_customer_name",
    "m"."related_reservation_id",
    "m"."related_transportation_event_id",
    "e"."provider_name",
    "e"."provider_event_id",
    "e"."provider_message_id",
    "e"."event_type",
    "e"."event_payload",
    "e"."occurred_at",
    "e"."received_at",
    "e"."processed_status"
   FROM ((("public"."email_provider_webhook_events" "e"
     LEFT JOIN "public"."email_outbound_messages" "m" ON (("m"."id" = "e"."email_outbound_message_id")))
     LEFT JOIN "public"."app_users" "u" ON (("u"."id" = "m"."related_user_id")))
     LEFT JOIN "public"."customers" "c" ON (("c"."id" = "m"."related_customer_id")));


ALTER VIEW "public"."v_email_webhook_event_history" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_extended_warranty_rule_catalog" WITH ("security_invoker"='true') AS
 SELECT "ewr"."id" AS "rule_id",
    "ewr"."provider_id",
    "wp"."name" AS "provider_name",
    "wp"."provider_type",
    "ewr"."covered_days",
    "ewr"."requires_approval",
    "ewr"."daily_rate",
    "ewr"."is_active",
    "ewr"."notes",
    "ewr"."created_at",
    "ewr"."updated_at"
   FROM ("public"."extended_warranty_rules" "ewr"
     LEFT JOIN "public"."warranty_providers" "wp" ON (("wp"."id" = "ewr"."provider_id")));


ALTER VIEW "public"."v_extended_warranty_rule_catalog" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_extension_commit_candidates" WITH ("security_invoker"='true') AS
 SELECT "b"."parent_billing_line_id",
    "b"."transportation_event_id",
    "b"."reservation_id",
    "b"."vehicle_id",
    "b"."vehicle_event_id",
    "b"."contract_period_id",
    "b"."pay_type",
    "b"."pay_type_rule_id",
    "b"."amount",
    "b"."tax_amount",
    "b"."start_time",
    "b"."end_time",
    "b"."line_type",
    "b"."warranty_provider_id",
    "b"."default_covered_days_snapshot",
    "b"."covered_days_override",
    "b"."default_daily_rate_snapshot",
    "b"."daily_rate_override",
    "b"."paid_through_at",
    "b"."extended_from_billing_line_id",
    "b"."is_open",
    "te"."expected_return_at" AS "current_expected_return_at"
   FROM ("public"."v_current_extendable_billing_lines" "b"
     JOIN "public"."transportation_events" "te" ON (("te"."id" = "b"."transportation_event_id")));


ALTER VIEW "public"."v_extension_commit_candidates" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_late_fee_rule_catalog" WITH ("security_invoker"='true') AS
 SELECT "id" AS "late_fee_rule_id",
    "is_active",
    "sort_order",
    "rule_kind",
    "threshold_unit",
    "threshold_value",
    "fee_amount",
    "description",
    "created_at",
    "updated_at",
    "created_by",
    "updated_by"
   FROM "public"."late_fee_rules" "lfr";


ALTER VIEW "public"."v_late_fee_rule_catalog" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vehicles" (
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vin" "text" NOT NULL,
    "stock_number" "text" NOT NULL,
    "model" "text" NOT NULL,
    "fleet_type" "text" NOT NULL,
    "status" "text" DEFAULT 'available'::"text" NOT NULL,
    "mileage" integer NOT NULL,
    "recon_status" "text" DEFAULT 'clean'::"text" NOT NULL,
    "current_tag" "text" NOT NULL,
    "fleet_conversion_type" "text" NOT NULL,
    "location" "text",
    "notes" "text",
    "ctp_program_active" boolean DEFAULT false NOT NULL,
    "ctp_program_entered_at" timestamp with time zone,
    "ctp_entry_mileage" integer,
    "ctp_monitoring_notes" "text"
);


ALTER TABLE "public"."vehicles" OWNER TO "postgres";


COMMENT ON TABLE "public"."vehicles" IS 'Core fleet inventory table. Stores all dealership vehicles including loaners and rentals. Controls fleet status, availability, tagging, mileage tracking, and serves as the foundation for reservations, swaps, and conflict logic.';



COMMENT ON COLUMN "public"."vehicles"."id" IS 'Unique system identifier for each vehicle record. Used internally by the database and never changes.';



COMMENT ON COLUMN "public"."vehicles"."vin" IS 'Vehicle Identification Number (VIN). Unique real-world manufacturer identifier for the vehicle. Does not change and is used for tracking across all dealership systems.';



COMMENT ON COLUMN "public"."vehicles"."stock_number" IS 'Dealership stock identifier used for operational tracking. Format typically follows CL#### for loaners and R#### for rentals. This value may change if fleet classification changes, but VIN remains constant.';



COMMENT ON COLUMN "public"."vehicles"."model" IS 'Vehicle model name (e.g., Trax, Equinox, Silverado). Used for fleet categorization, availability forecasting, and upgrade/downgrade suggestions.';



COMMENT ON COLUMN "public"."vehicles"."fleet_type" IS 'Defines operational classification of the vehicle. Determines system rules for usage, availability, and conflict logic. Expected values include Loaner, Rental, or Flexible.';



COMMENT ON COLUMN "public"."vehicles"."status" IS 'Current operational status of the vehicle. Controls real-time availability in reservations, swaps, and conflict logic. Common values: available, reserved, active, maintenance, recon_hold, swap_locked, hard_block.';



COMMENT ON COLUMN "public"."vehicles"."mileage" IS 'Current vehicle mileage. Used for maintenance tracking, loaner usage monitoring, and abuse detection rules.';



COMMENT ON COLUMN "public"."vehicles"."recon_status" IS 'Indicates whether vehicle is clean and ready for use or requires recon/cleaning. Used for availability filtering, loaner approval prompts, and recon hold status logic.';



COMMENT ON COLUMN "public"."vehicles"."current_tag" IS 'Current active operational tag assigned to the vehicle (e.g., LOANER, RENTAL, EV_PROTECTED). Controls eligibility rules, availability restrictions, and tag-based permissions. Links to tag management system with expiration tracking.';



COMMENT ON COLUMN "public"."vehicles"."fleet_conversion_type" IS 'Records fleet classification changes for the vehicle (e.g., Loaner to Rental or Rental to Loaner). Used for audit tracking and operational history. Does not alter VIN or system ID.';



COMMENT ON COLUMN "public"."vehicles"."location" IS 'Current physical or operational location of the vehicle (e.g. Main Lot, Airport or other location). Used for future fleet logistics and is not required for core system operation.';



COMMENT ON COLUMN "public"."vehicles"."notes" IS 'Internal notes for administrative or operational use. Used to document exceptions, warnings, special handling instructions, or context for fleet decisions. Does not affect system logic.';



CREATE OR REPLACE VIEW "public"."v_live_active_case_state" WITH ("security_invoker"='true') AS
 SELECT "r"."reservation_id",
    "r"."transportation_event_id",
    "r"."vehicle_id",
    "r"."start_date",
    "r"."expected_return_datetime",
    "r"."reservation_status",
    "r"."reservation_type",
    "r"."requested_model",
    "r"."pay_type",
    "r"."customer_id",
    "c"."name" AS "customer_name",
    "c"."tekion_customer_number",
    "v"."vin",
    "v"."stock_number",
    "v"."model" AS "vehicle_model",
    "v"."status" AS "vehicle_status",
    "r"."transportation_event_status",
    "r"."expected_return_at",
    "r"."closed_at",
    "r"."closed_by"
   FROM (("public"."v_reservation_operational_state" "r"
     LEFT JOIN "public"."customers" "c" ON (("c"."id" = "r"."customer_id")))
     LEFT JOIN "public"."vehicles" "v" ON (("v"."id" = "r"."vehicle_id")))
  WHERE (("r"."reservation_status" IS DISTINCT FROM 'cancelled'::"text") AND ("r"."transportation_event_status" = 'active'::"text"));


ALTER VIEW "public"."v_live_active_case_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_operational_domain_counts" WITH ("security_invoker"='true') AS
 SELECT ( SELECT "count"(*) AS "count"
           FROM "public"."customers") AS "customer_count",
    ( SELECT "count"(*) AS "count"
           FROM "public"."vehicles") AS "vehicle_count",
    ( SELECT "count"(*) AS "count"
           FROM "public"."reservations") AS "reservation_count",
    ( SELECT "count"(*) AS "count"
           FROM "public"."transportation_events") AS "transportation_event_count",
    ( SELECT "count"(*) AS "count"
           FROM "public"."vehicle_events"
          WHERE ("vehicle_events"."is_open" = true)) AS "open_vehicle_event_count",
    ( SELECT "count"(*) AS "count"
           FROM "public"."contract_periods"
          WHERE ("contract_periods"."is_open" = true)) AS "open_contract_period_count",
    ( SELECT "count"(*) AS "count"
           FROM "public"."billing_lines"
          WHERE (("billing_lines"."is_open" = true) AND ("billing_lines"."line_type" IS DISTINCT FROM 'tax'::"text"))) AS "open_billing_line_count",
    ( SELECT "count"(*) AS "count"
           FROM "public"."reservation_vehicle_dependencies"
          WHERE ("reservation_vehicle_dependencies"."status" = ANY (ARRAY['pending_return'::"text", 'ready'::"text", 'conflict'::"text"]))) AS "unresolved_dependency_count",
    ( SELECT "count"(*) AS "count"
           FROM "public"."reservation_conflicts"
          WHERE ("reservation_conflicts"."is_resolved" = false)) AS "unresolved_conflict_count",
    ( SELECT "count"(*) AS "count"
           FROM "public"."transportation_event_notes") AS "transportation_event_note_count";


ALTER VIEW "public"."v_operational_domain_counts" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_reservation_extension_candidate_state" WITH ("security_invoker"='true') AS
 SELECT "r"."reservation_id",
    "r"."transportation_event_id",
    "r"."vehicle_id" AS "reservation_vehicle_id",
    "r"."start_date",
    "r"."expected_return_datetime",
    "r"."reservation_status",
    "r"."reservation_type",
    "r"."requested_model",
    "r"."pay_type" AS "reservation_pay_type",
    "r"."customer_id",
    "e"."parent_billing_line_id",
    "e"."vehicle_id" AS "billing_vehicle_id",
    "e"."vehicle_event_id",
    "e"."contract_period_id",
    "e"."pay_type",
    "e"."pay_type_rule_id",
    "e"."amount",
    "e"."tax_amount",
    "e"."start_time",
    "e"."end_time",
    "e"."line_type",
    "e"."warranty_provider_id",
    "e"."default_covered_days_snapshot",
    "e"."covered_days_override",
    "e"."default_daily_rate_snapshot",
    "e"."daily_rate_override",
    "e"."paid_through_at",
    "e"."extended_from_billing_line_id",
    "e"."is_open",
    "e"."current_expected_return_at"
   FROM ("public"."v_reservation_transportation_link_state" "r"
     LEFT JOIN "public"."v_extension_commit_candidates" "e" ON (("e"."reservation_id" = "r"."reservation_id")));


ALTER VIEW "public"."v_reservation_extension_candidate_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_reservation_vehicle_candidates" WITH ("security_invoker"='true') AS
 SELECT "r"."id" AS "reservation_id",
    "r"."transportation_event_id" AS "reservation_transportation_event_id",
    "r"."start_date" AS "reservation_start_at",
    "r"."expected_return_datetime" AS "reservation_end_at",
    "r"."requested_model",
    "r"."reservation_type",
    "r"."status" AS "reservation_status",
    "r"."notes" AS "reservation_notes",
    "v"."id" AS "vehicle_id",
    "v"."vin",
    "v"."stock_number",
    "v"."model" AS "vehicle_model",
    "v"."fleet_type",
    "v"."status" AS "vehicle_status",
    "v"."recon_status",
    "v"."location",
    "c"."transportation_event_id" AS "source_transportation_event_id",
    "te"."expected_return_at" AS "expected_return_snapshot",
        CASE
            WHEN ("c"."vehicle_event_id" IS NOT NULL) THEN 'pending_return'::"text"
            WHEN ("v"."status" = 'available'::"text") THEN 'ready'::"text"
            ELSE 'unavailable'::"text"
        END AS "candidate_state"
   FROM ((("public"."reservations" "r"
     JOIN "public"."vehicles" "v" ON (("v"."model" = "r"."requested_model")))
     LEFT JOIN "public"."v_current_vehicle_continuity" "c" ON (("c"."vehicle_id" = "v"."id")))
     LEFT JOIN "public"."transportation_events" "te" ON (("te"."id" = "c"."transportation_event_id")))
  WHERE ("r"."status" IS DISTINCT FROM 'cancelled'::"text");


ALTER VIEW "public"."v_reservation_vehicle_candidates" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_reservations_needing_vin_assignment" WITH ("security_invoker"='true') AS
 SELECT "reservation_id",
    "transportation_event_id",
    "start_date",
    "expected_return_datetime",
    "requested_model",
    "reservation_type",
    "reservation_status",
    "reservation_notes",
    "vehicle_id",
    "vin_lock_lead_days",
    "lock_window_starts_at",
    "is_in_lock_window",
    "vehicle_is_assigned"
   FROM "public"."v_reservation_assignment_state" "ras"
  WHERE (("is_in_lock_window" = true) AND ("vehicle_is_assigned" = false) AND ("reservation_status" IS DISTINCT FROM 'cancelled'::"text"));


ALTER VIEW "public"."v_reservations_needing_vin_assignment" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_roles_with_permissions" WITH ("security_invoker"='true') AS
 SELECT "r"."id" AS "role_id",
    "r"."role_name",
    COALESCE("string_agg"(DISTINCT "p"."permission_key", ', '::"text" ORDER BY "p"."permission_key") FILTER (WHERE ("p"."permission_key" IS NOT NULL)), ''::"text") AS "permission_summary",
    "count"(DISTINCT "p"."id") AS "permission_count"
   FROM (("public"."roles" "r"
     LEFT JOIN "public"."role_permissions" "rp" ON (("rp"."role_id" = "r"."id")))
     LEFT JOIN "public"."permissions" "p" ON (("p"."id" = "rp"."permission_id")))
  GROUP BY "r"."id", "r"."role_name";


ALTER VIEW "public"."v_roles_with_permissions" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_security_admin_settings_state" WITH ("security_invoker"='true') AS
 WITH "settings" AS (
         SELECT "admin_settings"."setting_key",
            "admin_settings"."setting_value"
           FROM "public"."admin_settings"
        )
 SELECT COALESCE(( SELECT (("settings"."setting_value" #>> '{}'::"text"[]))::boolean AS "bool"
           FROM "settings"
          WHERE ("settings"."setting_key" = 'network_restriction_enabled'::"text")), false) AS "network_restriction_enabled",
    COALESCE(( SELECT (("settings"."setting_value" #>> '{}'::"text"[]))::boolean AS "bool"
           FROM "settings"
          WHERE ("settings"."setting_key" = 'email_password_reset_link_enabled'::"text")), false) AS "email_password_reset_link_enabled",
    COALESCE(( SELECT (("settings"."setting_value" #>> '{}'::"text"[]))::boolean AS "bool"
           FROM "settings"
          WHERE ("settings"."setting_key" = 'late_fees_enabled'::"text")), false) AS "late_fees_enabled",
    COALESCE(( SELECT (("settings"."setting_value" #>> '{}'::"text"[]))::integer AS "int4"
           FROM "settings"
          WHERE ("settings"."setting_key" = 'reservation_vin_lock_lead_days'::"text")), 0) AS "reservation_vin_lock_lead_days";


ALTER VIEW "public"."v_security_admin_settings_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_service_action_contract_state" AS
 SELECT "id" AS "service_action_contract_id",
    "action_key",
    "action_group",
    "entity_scope",
    "db_function_name",
    "action_type",
    "description",
    "requires_authenticated_user",
    "requires_aal2",
    "writes_data",
    "frontend_safe",
    "internal_only",
    "required_permission",
    "created_at",
    "updated_at"
   FROM "public"."service_action_contracts";


ALTER VIEW "public"."v_service_action_contract_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_transportation_event_state" WITH ("security_invoker"='true') AS
 SELECT "id" AS "transportation_event_id",
    "source_type",
    "source_id",
    "status",
    "notes",
    "customer_id",
    "updated_at",
    "closed_at",
    "closed_by",
    "expected_return_at"
   FROM "public"."transportation_events" "te";


ALTER VIEW "public"."v_transportation_event_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_transportation_event_current_billing_state" WITH ("security_invoker"='true') AS
 SELECT "te"."transportation_event_id",
    "te"."source_type",
    "te"."source_id",
    "te"."status" AS "transportation_event_status",
    "te"."notes" AS "transportation_event_notes",
    "te"."customer_id",
    "te"."updated_at",
    "te"."closed_at",
    "te"."closed_by",
    "te"."expected_return_at",
    "b"."parent_billing_line_id",
    "b"."reservation_id",
    "b"."vehicle_id" AS "billing_vehicle_id",
    "b"."vehicle_event_id",
    "b"."contract_period_id",
    "b"."pay_type",
    "b"."pay_type_rule_id",
    "b"."parent_amount",
    "b"."parent_tax_amount",
    "b"."start_time",
    "b"."end_time",
    "b"."parent_line_type",
    "b"."warranty_provider_id",
    "b"."default_covered_days_snapshot",
    "b"."covered_days_override",
    "b"."default_daily_rate_snapshot",
    "b"."daily_rate_override",
    "b"."paid_through_at",
    "b"."extended_from_billing_line_id",
    "b"."parent_is_open",
    "b"."tax_billing_line_id",
    "b"."tax_line_amount",
    "b"."tax_line_is_open"
   FROM ("public"."v_transportation_event_state" "te"
     LEFT JOIN "public"."v_current_open_billing_lines" "b" ON (("b"."transportation_event_id" = "te"."transportation_event_id")));


ALTER VIEW "public"."v_transportation_event_current_billing_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_transportation_event_current_dependency_state" WITH ("security_invoker"='true') AS
 SELECT "te"."transportation_event_id",
    "te"."source_type",
    "te"."source_id",
    "te"."status" AS "transportation_event_status",
    "te"."customer_id",
    "te"."expected_return_at",
    "te"."closed_at",
    "te"."closed_by",
    "dep"."dependency_id",
    "dep"."reservation_id",
    "dep"."vehicle_id",
    "dep"."source_transportation_event_id",
    "dep"."dependency_type",
    "dep"."status" AS "dependency_status",
    "dep"."risk_level",
    "dep"."expected_return_snapshot",
    "dep"."notes" AS "dependency_notes",
    "dep"."created_at" AS "dependency_created_at",
    "dep"."updated_at" AS "dependency_updated_at",
    "c"."conflict_id",
    "c"."conflict_type",
    "c"."conflict_severity",
    "c"."conflict_message",
    "c"."is_resolved" AS "conflict_is_resolved"
   FROM (("public"."v_transportation_event_state" "te"
     LEFT JOIN LATERAL ( SELECT "d"."id" AS "dependency_id",
            "d"."reservation_id",
            "d"."vehicle_id",
            "d"."source_transportation_event_id",
            "d"."dependency_type",
            "d"."status",
            "d"."risk_level",
            "d"."expected_return_snapshot",
            "d"."notes",
            "d"."created_at",
            "d"."updated_at"
           FROM "public"."reservation_vehicle_dependencies" "d"
          WHERE (("te"."source_type" = 'reservation'::"text") AND ("te"."source_id" IS NOT NULL) AND ("d"."reservation_id" = "te"."source_id") AND ("d"."status" = ANY (ARRAY['pending_return'::"text", 'ready'::"text", 'conflict'::"text"])))
          ORDER BY "d"."updated_at" DESC NULLS LAST, "d"."created_at" DESC NULLS LAST, "d"."id" DESC
         LIMIT 1) "dep" ON (true))
     LEFT JOIN LATERAL ( SELECT "rc"."id" AS "conflict_id",
            "rc"."conflict_type",
            "rc"."severity" AS "conflict_severity",
            "rc"."message" AS "conflict_message",
            "rc"."is_resolved"
           FROM "public"."reservation_conflicts" "rc"
          WHERE (("rc"."reservation_vehicle_dependency_id" = "dep"."dependency_id") AND ("rc"."is_resolved" = false))
          ORDER BY "rc"."id" DESC
         LIMIT 1) "c" ON (true));


ALTER VIEW "public"."v_transportation_event_current_dependency_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_transportation_event_extension_candidate_state" WITH ("security_invoker"='true') AS
 SELECT "te"."transportation_event_id",
    "te"."source_type",
    "te"."source_id",
    "te"."status" AS "transportation_event_status",
    "te"."notes" AS "transportation_event_notes",
    "te"."customer_id",
    "te"."updated_at",
    "te"."closed_at",
    "te"."closed_by",
    "te"."expected_return_at",
    "e"."parent_billing_line_id",
    "e"."reservation_id",
    "e"."vehicle_id" AS "billing_vehicle_id",
    "e"."vehicle_event_id",
    "e"."contract_period_id",
    "e"."pay_type",
    "e"."pay_type_rule_id",
    "e"."amount",
    "e"."tax_amount",
    "e"."start_time",
    "e"."end_time",
    "e"."line_type",
    "e"."warranty_provider_id",
    "e"."default_covered_days_snapshot",
    "e"."covered_days_override",
    "e"."default_daily_rate_snapshot",
    "e"."daily_rate_override",
    "e"."paid_through_at",
    "e"."extended_from_billing_line_id",
    "e"."is_open",
    "e"."current_expected_return_at"
   FROM ("public"."v_transportation_event_state" "te"
     LEFT JOIN "public"."v_extension_commit_candidates" "e" ON (("e"."transportation_event_id" = "te"."transportation_event_id")));


ALTER VIEW "public"."v_transportation_event_extension_candidate_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_transportation_event_note_history" WITH ("security_invoker"='true') AS
 SELECT "n"."id" AS "note_id",
    "n"."transportation_event_id",
    "n"."note_type",
    "n"."note_text",
    "n"."entered_at",
    "n"."entered_by_user_id",
    "u"."full_name" AS "entered_by_name"
   FROM ("public"."transportation_event_notes" "n"
     LEFT JOIN "public"."app_users" "u" ON (("u"."id" = "n"."entered_by_user_id")));


ALTER VIEW "public"."v_transportation_event_note_history" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_transportation_event_operational_state" WITH ("security_invoker"='true') AS
 SELECT "te"."id" AS "transportation_event_id",
    "te"."source_type",
    "te"."source_id",
    "te"."status" AS "transportation_event_status",
    "te"."customer_id",
    "te"."expected_return_at",
    "te"."closed_at",
    "c"."vehicle_event_id",
    "c"."vehicle_id",
    "c"."contract_period_id",
    "c"."actual_out_at",
    "c"."actual_in_at",
    "c"."vehicle_event_is_open",
    "c"."ended_reason",
    "c"."contract_out_at",
    "c"."contract_in_at",
    "c"."renewal_sequence",
    "c"."contract_period_is_open"
   FROM ("public"."transportation_events" "te"
     LEFT JOIN "public"."v_current_vehicle_continuity" "c" ON (("c"."transportation_event_id" = "te"."id")));


ALTER VIEW "public"."v_transportation_event_operational_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_transportation_event_unified_operational_state" WITH ("security_invoker"='true') AS
 SELECT "te"."transportation_event_id",
    "te"."source_type",
    "te"."source_id",
    "te"."status" AS "transportation_event_status",
    "te"."notes" AS "transportation_event_notes",
    "te"."customer_id",
    "te"."updated_at",
    "te"."closed_at",
    "te"."closed_by",
    "te"."expected_return_at",
    "op"."vehicle_event_id",
    "op"."vehicle_id",
    "op"."contract_period_id",
    "op"."actual_out_at",
    "op"."actual_in_at",
    "op"."vehicle_event_is_open",
    "op"."ended_reason",
    "op"."contract_out_at",
    "op"."contract_in_at",
    "op"."renewal_sequence",
    "op"."contract_period_is_open",
    "bill"."parent_billing_line_id" AS "current_parent_billing_line_id",
    "bill"."reservation_id" AS "current_billing_reservation_id",
    "bill"."billing_vehicle_id" AS "current_billing_vehicle_id",
    "bill"."pay_type" AS "current_billing_pay_type",
    "bill"."parent_amount" AS "current_billing_parent_amount",
    "bill"."parent_tax_amount" AS "current_billing_parent_tax_amount",
    "bill"."start_time" AS "current_billing_start_time",
    "bill"."end_time" AS "current_billing_end_time",
    "bill"."parent_line_type" AS "current_billing_line_type",
    "bill"."paid_through_at" AS "current_billing_paid_through_at",
    "bill"."parent_is_open" AS "current_billing_is_open",
    "dep"."dependency_id" AS "current_dependency_id",
    "dep"."reservation_id" AS "current_dependency_reservation_id",
    "dep"."vehicle_id" AS "current_dependency_vehicle_id",
    "dep"."source_transportation_event_id" AS "current_dependency_source_transportation_event_id",
    "dep"."dependency_type" AS "current_dependency_type",
    "dep"."dependency_status" AS "current_dependency_status",
    "dep"."risk_level" AS "current_dependency_risk_level",
    "dep"."expected_return_snapshot" AS "current_dependency_expected_return_snapshot",
    "dep"."conflict_id" AS "current_conflict_id",
    "dep"."conflict_type" AS "current_conflict_type",
    "dep"."conflict_severity" AS "current_conflict_severity",
    "dep"."conflict_message" AS "current_conflict_message",
    "dep"."conflict_is_resolved" AS "current_conflict_is_resolved",
    "ext"."parent_billing_line_id" AS "extension_candidate_parent_billing_line_id",
    "ext"."reservation_id" AS "extension_candidate_reservation_id",
    "ext"."billing_vehicle_id" AS "extension_candidate_billing_vehicle_id",
    "ext"."pay_type" AS "extension_candidate_pay_type",
    "ext"."amount" AS "extension_candidate_amount",
    "ext"."tax_amount" AS "extension_candidate_tax_amount",
    "ext"."start_time" AS "extension_candidate_start_time",
    "ext"."paid_through_at" AS "extension_candidate_paid_through_at",
    "ext"."is_open" AS "extension_candidate_is_open",
    "ext"."current_expected_return_at" AS "extension_candidate_current_expected_return_at"
   FROM (((("public"."v_transportation_event_state" "te"
     LEFT JOIN "public"."v_transportation_event_operational_state" "op" ON (("op"."transportation_event_id" = "te"."transportation_event_id")))
     LEFT JOIN LATERAL ( SELECT "b"."transportation_event_id",
            "b"."source_type",
            "b"."source_id",
            "b"."transportation_event_status",
            "b"."transportation_event_notes",
            "b"."customer_id",
            "b"."updated_at",
            "b"."closed_at",
            "b"."closed_by",
            "b"."expected_return_at",
            "b"."parent_billing_line_id",
            "b"."reservation_id",
            "b"."billing_vehicle_id",
            "b"."vehicle_event_id",
            "b"."contract_period_id",
            "b"."pay_type",
            "b"."pay_type_rule_id",
            "b"."parent_amount",
            "b"."parent_tax_amount",
            "b"."start_time",
            "b"."end_time",
            "b"."parent_line_type",
            "b"."warranty_provider_id",
            "b"."default_covered_days_snapshot",
            "b"."covered_days_override",
            "b"."default_daily_rate_snapshot",
            "b"."daily_rate_override",
            "b"."paid_through_at",
            "b"."extended_from_billing_line_id",
            "b"."parent_is_open",
            "b"."tax_billing_line_id",
            "b"."tax_line_amount",
            "b"."tax_line_is_open"
           FROM "public"."v_transportation_event_current_billing_state" "b"
          WHERE (("b"."transportation_event_id" = "te"."transportation_event_id") AND ("b"."parent_billing_line_id" IS NOT NULL))
          ORDER BY "b"."start_time" DESC NULLS LAST, "b"."parent_billing_line_id" DESC
         LIMIT 1) "bill" ON (true))
     LEFT JOIN "public"."v_transportation_event_current_dependency_state" "dep" ON (("dep"."transportation_event_id" = "te"."transportation_event_id")))
     LEFT JOIN LATERAL ( SELECT "e"."transportation_event_id",
            "e"."source_type",
            "e"."source_id",
            "e"."transportation_event_status",
            "e"."transportation_event_notes",
            "e"."customer_id",
            "e"."updated_at",
            "e"."closed_at",
            "e"."closed_by",
            "e"."expected_return_at",
            "e"."parent_billing_line_id",
            "e"."reservation_id",
            "e"."billing_vehicle_id",
            "e"."vehicle_event_id",
            "e"."contract_period_id",
            "e"."pay_type",
            "e"."pay_type_rule_id",
            "e"."amount",
            "e"."tax_amount",
            "e"."start_time",
            "e"."end_time",
            "e"."line_type",
            "e"."warranty_provider_id",
            "e"."default_covered_days_snapshot",
            "e"."covered_days_override",
            "e"."default_daily_rate_snapshot",
            "e"."daily_rate_override",
            "e"."paid_through_at",
            "e"."extended_from_billing_line_id",
            "e"."is_open",
            "e"."current_expected_return_at"
           FROM "public"."v_transportation_event_extension_candidate_state" "e"
          WHERE (("e"."transportation_event_id" = "te"."transportation_event_id") AND ("e"."parent_billing_line_id" IS NOT NULL))
          ORDER BY "e"."start_time" DESC NULLS LAST, "e"."parent_billing_line_id" DESC
         LIMIT 1) "ext" ON (true));


ALTER VIEW "public"."v_transportation_event_unified_operational_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_unresolved_reservation_conflicts" WITH ("security_invoker"='true') AS
 SELECT "id" AS "conflict_id",
    "reservation_id",
    "reservation_vehicle_dependency_id",
    "conflict_type",
    "severity",
    "message",
    "is_resolved"
   FROM "public"."reservation_conflicts" "c"
  WHERE ("is_resolved" = false);


ALTER VIEW "public"."v_unresolved_reservation_conflicts" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_unresolved_reservation_dependencies" WITH ("security_invoker"='true') AS
 SELECT "id" AS "dependency_id",
    "reservation_id",
    "vehicle_id",
    "source_transportation_event_id",
    "dependency_type",
    "status",
    "risk_level",
    "expected_return_snapshot",
    "notes",
    "created_at",
    "updated_at",
    "created_by_user_id",
    "updated_by_user_id"
   FROM "public"."reservation_vehicle_dependencies" "d"
  WHERE ("status" = ANY (ARRAY['pending_return'::"text", 'ready'::"text", 'conflict'::"text"]));


ALTER VIEW "public"."v_unresolved_reservation_dependencies" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_upcoming_rental_dependency_feed" WITH ("security_invoker"='true') AS
 SELECT "d"."id" AS "dependency_id",
    "d"."reservation_id",
    "r"."start_date" AS "reservation_start_at",
    "r"."expected_return_datetime" AS "reservation_end_at",
    "r"."requested_model",
    "r"."reservation_type",
    "r"."status" AS "reservation_status",
    "r"."notes" AS "reservation_notes",
    "to_jsonb"("r".*) AS "reservation_payload",
    "d"."vehicle_id",
    "d"."source_transportation_event_id",
    "d"."dependency_type",
    "d"."status" AS "dependency_status",
    "d"."risk_level",
    "d"."expected_return_snapshot",
    "c"."id" AS "conflict_id",
    "c"."conflict_type",
    "c"."severity" AS "conflict_severity",
    "c"."message" AS "conflict_message",
    "c"."is_resolved"
   FROM (("public"."reservation_vehicle_dependencies" "d"
     JOIN "public"."reservations" "r" ON (("r"."id" = "d"."reservation_id")))
     LEFT JOIN "public"."reservation_conflicts" "c" ON ((("c"."reservation_vehicle_dependency_id" = "d"."id") AND ("c"."is_resolved" = false))))
  WHERE ("d"."status" = ANY (ARRAY['pending_return'::"text", 'ready'::"text", 'conflict'::"text"]));


ALTER VIEW "public"."v_upcoming_rental_dependency_feed" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_user_account_admin_status" WITH ("security_invoker"='true') AS
 SELECT "u"."id" AS "user_id",
    "u"."email",
    "u"."is_active",
    "s"."failed_login_count",
    "s"."last_failed_login_at",
    "s"."locked_until",
    "s"."lockout_count",
    "s"."post_lockout_final_attempt_allowed",
    "s"."is_disabled",
    "s"."disabled_at",
    "s"."disabled_reason",
    "s"."password_reset_pending",
    "s"."temporary_password_issued_at",
    "s"."temporary_password_expires_at",
    "s"."temporary_password_issued_by",
    "s"."outside_network_access_allowed",
    "s"."last_successful_login_at",
        CASE
            WHEN "s"."is_disabled" THEN 'disabled'::"text"
            WHEN (("s"."locked_until" IS NOT NULL) AND ("s"."locked_until" > "now"())) THEN 'locked'::"text"
            WHEN "s"."password_reset_pending" THEN 'password_reset_pending'::"text"
            WHEN "u"."is_active" THEN 'active'::"text"
            ELSE 'inactive'::"text"
        END AS "security_status"
   FROM ("public"."app_users" "u"
     JOIN "public"."app_user_security" "s" ON (("s"."user_id" = "u"."id")));


ALTER VIEW "public"."v_user_account_admin_status" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_user_admin_list_summary" WITH ("security_invoker"='true') AS
 SELECT "u"."id" AS "user_id",
    "u"."email",
    "u"."is_active",
    "s"."failed_login_count",
    "s"."last_failed_login_at",
    "s"."locked_until",
    "s"."lockout_count",
    "s"."post_lockout_final_attempt_allowed",
    "s"."is_disabled",
    "s"."disabled_at",
    "s"."disabled_reason",
    "s"."password_reset_pending",
    "s"."temporary_password_issued_at",
    "s"."temporary_password_expires_at",
    "s"."outside_network_access_allowed",
    "s"."last_successful_login_at",
        CASE
            WHEN "s"."is_disabled" THEN 'disabled'::"text"
            WHEN (("s"."locked_until" IS NOT NULL) AND ("s"."locked_until" > "now"())) THEN 'locked'::"text"
            WHEN "s"."password_reset_pending" THEN 'password_reset_pending'::"text"
            WHEN "u"."is_active" THEN 'active'::"text"
            ELSE 'inactive'::"text"
        END AS "security_status",
    COALESCE("string_agg"(DISTINCT "r"."role_name", ', '::"text" ORDER BY "r"."role_name") FILTER (WHERE ("r"."role_name" IS NOT NULL)), ''::"text") AS "role_summary"
   FROM ((("public"."app_users" "u"
     JOIN "public"."app_user_security" "s" ON (("s"."user_id" = "u"."id")))
     LEFT JOIN "public"."user_roles" "ur" ON (("ur"."user_id" = "u"."id")))
     LEFT JOIN "public"."roles" "r" ON (("r"."id" = "ur"."role_id")))
  GROUP BY "u"."id", "u"."email", "u"."is_active", "s"."failed_login_count", "s"."last_failed_login_at", "s"."locked_until", "s"."lockout_count", "s"."post_lockout_final_attempt_allowed", "s"."is_disabled", "s"."disabled_at", "s"."disabled_reason", "s"."password_reset_pending", "s"."temporary_password_issued_at", "s"."temporary_password_expires_at", "s"."outside_network_access_allowed", "s"."last_successful_login_at";


ALTER VIEW "public"."v_user_admin_list_summary" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_user_auth_security_event_history" AS
 SELECT "e"."id" AS "auth_security_event_id",
    "e"."user_id",
    "u"."email",
    "u"."full_name",
    "e"."event_type",
    "e"."factor_type",
    "e"."event_status",
    "e"."details",
    "e"."recorded_by_user_id",
    "rb"."email" AS "recorded_by_email",
    "rb"."full_name" AS "recorded_by_full_name",
    "e"."recorded_at"
   FROM (("public"."user_auth_security_events" "e"
     JOIN "public"."app_users" "u" ON (("u"."id" = "e"."user_id")))
     LEFT JOIN "public"."app_users" "rb" ON (("rb"."id" = "e"."recorded_by_user_id")));


ALTER VIEW "public"."v_user_auth_security_event_history" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_user_auth_entry_orchestration_state" AS
 WITH "latest_auth_event" AS (
         SELECT "e"."user_id",
            "e"."auth_security_event_id",
            "e"."event_type",
            "e"."factor_type",
            "e"."event_status",
            "e"."details",
            "e"."recorded_by_user_id",
            "e"."recorded_by_email",
            "e"."recorded_by_full_name",
            "e"."recorded_at",
            "row_number"() OVER (PARTITION BY "e"."user_id" ORDER BY "e"."recorded_at" DESC, "e"."auth_security_event_id" DESC) AS "rn"
           FROM "public"."v_user_auth_security_event_history" "e"
        ), "mfa_enrollment_flags" AS (
         SELECT "e"."user_id",
            "bool_or"(("e"."event_type" = ANY (ARRAY['mfa_enrolled'::"text", 'backup_factor_registered'::"text"]))) AS "has_mfa_enrolled_event",
            "max"("e"."recorded_at") FILTER (WHERE ("e"."event_type" = ANY (ARRAY['mfa_enrolled'::"text", 'backup_factor_registered'::"text"]))) AS "last_mfa_enrolled_at"
           FROM "public"."v_user_auth_security_event_history" "e"
          GROUP BY "e"."user_id"
        )
 SELECT "u"."id" AS "user_id",
    "u"."auth_user_id",
    "u"."email",
    "u"."full_name",
    "u"."phone",
    "u"."is_active",
    "u"."last_login",
    "u"."notes",
    "s"."failed_login_count",
    "s"."last_failed_login_at",
    "s"."locked_until",
    "s"."lockout_count",
    "s"."post_lockout_final_attempt_allowed",
    "s"."is_disabled",
    "s"."disabled_at",
    "s"."disabled_reason",
    "s"."password_reset_pending",
    "s"."temporary_password_issued_at",
    "s"."temporary_password_expires_at",
    "s"."outside_network_access_allowed",
    "s"."last_successful_login_at",
    "policy"."mfa_required_for_all_users",
    "policy"."network_restriction_enabled",
    "policy"."email_password_reset_link_enabled",
    COALESCE("m"."has_mfa_enrolled_event", false) AS "has_mfa_enrolled_event",
    "m"."last_mfa_enrolled_at",
    "lae"."auth_security_event_id" AS "latest_auth_security_event_id",
    "lae"."event_type" AS "latest_auth_event_type",
    "lae"."factor_type" AS "latest_auth_factor_type",
    "lae"."event_status" AS "latest_auth_event_status",
    "lae"."details" AS "latest_auth_event_details",
    "lae"."recorded_by_user_id" AS "latest_auth_recorded_by_user_id",
    "lae"."recorded_by_email" AS "latest_auth_recorded_by_email",
    "lae"."recorded_by_full_name" AS "latest_auth_recorded_by_full_name",
    "lae"."recorded_at" AS "latest_auth_recorded_at",
        CASE
            WHEN ("u"."is_active" = false) THEN 'inactive_user'::"text"
            WHEN ("s"."is_disabled" = true) THEN 'disabled_user'::"text"
            WHEN (("s"."locked_until" IS NOT NULL) AND ("s"."locked_until" > "now"())) THEN 'locked_user'::"text"
            WHEN ("s"."password_reset_pending" = true) THEN 'password_reset_required'::"text"
            WHEN (("policy"."mfa_required_for_all_users" = true) AND (COALESCE("m"."has_mfa_enrolled_event", false) = false)) THEN 'mfa_enrollment_required'::"text"
            ELSE 'auth_entry_ready_for_session_check'::"text"
        END AS "base_auth_gate_status"
   FROM (((("public"."app_users" "u"
     JOIN "public"."app_user_security" "s" ON (("s"."user_id" = "u"."id")))
     CROSS JOIN "public"."v_auth_security_policy_state" "policy")
     LEFT JOIN "mfa_enrollment_flags" "m" ON (("m"."user_id" = "u"."id")))
     LEFT JOIN "latest_auth_event" "lae" ON ((("lae"."user_id" = "u"."id") AND ("lae"."rn" = 1))));


ALTER VIEW "public"."v_user_auth_entry_orchestration_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_user_auth_entry_state" WITH ("security_invoker"='true') AS
 SELECT "u"."id" AS "user_id",
    "u"."auth_user_id",
    "u"."email",
    "u"."full_name",
    "u"."phone",
    "u"."is_active",
    "s"."failed_login_count",
    "s"."last_failed_login_at",
    "s"."locked_until",
    "s"."lockout_count",
    "s"."post_lockout_final_attempt_allowed",
    "s"."is_disabled",
    "s"."disabled_at",
    "s"."disabled_reason",
    "s"."password_reset_pending",
    "s"."temporary_password_issued_at",
    "s"."temporary_password_expires_at",
    "s"."temporary_password_issued_by",
    "s"."outside_network_access_allowed",
    "s"."last_successful_login_at",
        CASE
            WHEN "s"."is_disabled" THEN 'disabled'::"text"
            WHEN (("s"."locked_until" IS NOT NULL) AND ("now"() < "s"."locked_until")) THEN 'locked'::"text"
            WHEN "s"."password_reset_pending" THEN 'password_reset_pending'::"text"
            WHEN ("u"."is_active" = false) THEN 'inactive'::"text"
            ELSE 'active'::"text"
        END AS "auth_status",
    (("s"."temporary_password_expires_at" IS NOT NULL) AND ("now"() > "s"."temporary_password_expires_at")) AS "temporary_password_is_expired"
   FROM ("public"."app_users" "u"
     JOIN "public"."app_user_security" "s" ON (("s"."user_id" = "u"."id")));


ALTER VIEW "public"."v_user_auth_entry_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_user_effective_permissions" WITH ("security_invoker"='true') AS
 SELECT DISTINCT "u"."id" AS "user_id",
    "p"."permission_key"
   FROM ((("public"."app_users" "u"
     JOIN "public"."user_roles" "ur" ON (("ur"."user_id" = "u"."id")))
     JOIN "public"."role_permissions" "rp" ON (("rp"."role_id" = "ur"."role_id")))
     JOIN "public"."permissions" "p" ON (("p"."id" = "rp"."permission_id")));


ALTER VIEW "public"."v_user_effective_permissions" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_user_reset_artifact_state" WITH ("security_invoker"='true') AS
 WITH "ranked_tokens" AS (
         SELECT "t"."reset_token_id",
            "t"."user_id",
            "t"."token_hash",
            "t"."reset_mode",
            "t"."issued_at",
            "t"."expires_at",
            "t"."issued_by_user_id",
            "t"."notes",
            "row_number"() OVER (PARTITION BY "t"."user_id" ORDER BY "t"."expires_at" DESC NULLS LAST, "t"."issued_at" DESC NULLS LAST, "t"."reset_token_id" DESC) AS "rn",
            "count"(*) OVER (PARTITION BY "t"."user_id") AS "active_usable_token_count"
           FROM "public"."v_active_usable_reset_tokens" "t"
        )
 SELECT "u"."id" AS "user_id",
    "u"."auth_user_id",
    "u"."email",
    "u"."full_name",
    "u"."phone",
    "u"."is_active",
    "s"."password_reset_pending",
    "s"."temporary_password_issued_at",
    "s"."temporary_password_expires_at",
    "s"."temporary_password_issued_by",
    "s"."is_disabled",
    "s"."locked_until",
    "s"."post_lockout_final_attempt_allowed",
    "rt"."reset_token_id",
    "rt"."token_hash",
    "rt"."reset_mode",
    "rt"."issued_at" AS "token_issued_at",
    "rt"."expires_at" AS "token_expires_at",
    "rt"."issued_by_user_id" AS "token_issued_by_user_id",
    "rt"."notes" AS "token_notes",
    COALESCE("rt"."active_usable_token_count", (0)::bigint) AS "active_usable_token_count"
   FROM (("public"."app_users" "u"
     JOIN "public"."app_user_security" "s" ON (("s"."user_id" = "u"."id")))
     LEFT JOIN "ranked_tokens" "rt" ON ((("rt"."user_id" = "u"."id") AND ("rt"."rn" = 1))));


ALTER VIEW "public"."v_user_reset_artifact_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_users_requiring_password_reset" WITH ("security_invoker"='true') AS
 SELECT "u"."id" AS "user_id",
    "u"."auth_user_id",
    "u"."email",
    "u"."full_name",
    "u"."phone",
    "u"."is_active",
    "s"."password_reset_pending",
    "s"."temporary_password_issued_at",
    "s"."temporary_password_expires_at",
    "s"."temporary_password_issued_by",
    "s"."is_disabled",
    "s"."locked_until",
    "s"."post_lockout_final_attempt_allowed",
    "s"."outside_network_access_allowed"
   FROM ("public"."app_users" "u"
     JOIN "public"."app_user_security" "s" ON (("s"."user_id" = "u"."id")))
  WHERE ("s"."password_reset_pending" = true);


ALTER VIEW "public"."v_users_requiring_password_reset" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_vehicle_ctp_monitoring_state" AS
 SELECT "v"."id" AS "vehicle_id",
    "v"."created_at",
    "v"."vin",
    "v"."stock_number",
    "v"."model",
    "v"."fleet_type",
    "v"."status" AS "vehicle_status",
    "v"."mileage" AS "current_mileage",
    "v"."recon_status",
    "v"."current_tag",
    "v"."fleet_conversion_type",
    "v"."location",
    "v"."notes",
    "v"."ctp_program_active",
    "v"."ctp_program_entered_at",
    "v"."ctp_entry_mileage",
    "v"."ctp_monitoring_notes",
    "policy"."preferred_max_ctp_days",
    "policy"."preferred_max_ctp_qualified_miles",
        CASE
            WHEN (("v"."ctp_program_active" = true) AND ("v"."ctp_program_entered_at" IS NOT NULL)) THEN GREATEST(((CURRENT_DATE - ("v"."ctp_program_entered_at")::"date") + 1), 1)
            ELSE NULL::integer
        END AS "current_ctp_day_number",
        CASE
            WHEN (("v"."ctp_program_active" = true) AND ("v"."ctp_entry_mileage" IS NOT NULL)) THEN GREATEST(("v"."mileage" - "v"."ctp_entry_mileage"), 0)
            ELSE NULL::integer
        END AS "current_ctp_qualified_miles",
        CASE
            WHEN (("v"."ctp_program_active" = true) AND ("v"."ctp_program_entered_at" IS NOT NULL) AND (GREATEST(((CURRENT_DATE - ("v"."ctp_program_entered_at")::"date") + 1), 1) >= "policy"."preferred_max_ctp_days")) THEN true
            ELSE false
        END AS "is_at_or_over_preferred_ctp_days",
        CASE
            WHEN (("v"."ctp_program_active" = true) AND ("v"."ctp_entry_mileage" IS NOT NULL) AND (GREATEST(("v"."mileage" - "v"."ctp_entry_mileage"), 0) >= "policy"."preferred_max_ctp_qualified_miles")) THEN true
            ELSE false
        END AS "is_at_or_over_preferred_ctp_qualified_miles",
        CASE
            WHEN ("v"."ctp_program_active" = false) THEN 'not_in_ctp_program'::"text"
            WHEN ("v"."ctp_program_entered_at" IS NULL) THEN 'missing_ctp_entry_date'::"text"
            WHEN ("v"."ctp_entry_mileage" IS NULL) THEN 'missing_ctp_entry_mileage'::"text"
            WHEN (("v"."ctp_program_active" = true) AND ("v"."ctp_program_entered_at" IS NOT NULL) AND (GREATEST(((CURRENT_DATE - ("v"."ctp_program_entered_at")::"date") + 1), 1) >= "policy"."preferred_max_ctp_days") AND (("v"."ctp_program_active" = true) AND ("v"."ctp_entry_mileage" IS NOT NULL) AND (GREATEST(("v"."mileage" - "v"."ctp_entry_mileage"), 0) >= "policy"."preferred_max_ctp_qualified_miles"))) THEN 'at_or_over_both_preferred_thresholds'::"text"
            WHEN (("v"."ctp_program_active" = true) AND ("v"."ctp_program_entered_at" IS NOT NULL) AND (GREATEST(((CURRENT_DATE - ("v"."ctp_program_entered_at")::"date") + 1), 1) >= "policy"."preferred_max_ctp_days")) THEN 'at_or_over_preferred_days'::"text"
            WHEN (("v"."ctp_program_active" = true) AND ("v"."ctp_entry_mileage" IS NOT NULL) AND (GREATEST(("v"."mileage" - "v"."ctp_entry_mileage"), 0) >= "policy"."preferred_max_ctp_qualified_miles")) THEN 'at_or_over_preferred_miles'::"text"
            ELSE 'within_preferred_ctp_thresholds'::"text"
        END AS "ctp_monitoring_status"
   FROM ("public"."vehicles" "v"
     CROSS JOIN "public"."v_ctp_monitoring_policy_state" "policy");


ALTER VIEW "public"."v_vehicle_ctp_monitoring_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_vehicle_operational_state" WITH ("security_invoker"='true') AS
 SELECT "v"."id" AS "vehicle_id",
    "v"."created_at",
    "v"."vin",
    "v"."stock_number",
    "v"."model",
    "v"."fleet_type",
    "v"."status",
    "v"."mileage",
    "v"."recon_status",
    "v"."current_tag",
    "v"."fleet_conversion_type",
    "v"."location",
    "v"."notes",
    "c"."transportation_event_id" AS "active_transportation_event_id",
    "c"."vehicle_event_id",
    "c"."contract_period_id",
    "c"."actual_out_at",
    "c"."contract_out_at",
    "c"."renewal_sequence",
    "c"."vehicle_event_is_open",
    "c"."contract_period_is_open"
   FROM ("public"."vehicles" "v"
     LEFT JOIN "public"."v_current_vehicle_continuity" "c" ON (("c"."vehicle_id" = "v"."id")));


ALTER VIEW "public"."v_vehicle_operational_state" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_vehicle_operational_aggregate_state" WITH ("security_invoker"='true') AS
 SELECT "v"."vehicle_id",
    "v"."created_at",
    "v"."vin",
    "v"."stock_number",
    "v"."model",
    "v"."fleet_type",
    "v"."status" AS "vehicle_status",
    "v"."mileage",
    "v"."recon_status",
    "v"."current_tag",
    "v"."fleet_conversion_type",
    "v"."location",
    "v"."notes",
    "v"."active_transportation_event_id",
    "v"."vehicle_event_id",
    "v"."contract_period_id",
    "v"."actual_out_at",
    "v"."contract_out_at",
    "v"."renewal_sequence",
    "v"."vehicle_event_is_open",
    "v"."contract_period_is_open",
    "te"."expected_return_at" AS "latest_expected_return_at",
    COALESCE("ar"."assigned_reservation_count", (0)::bigint) AS "assigned_reservation_count",
    COALESCE("cr"."candidate_reservation_count", (0)::bigint) AS "candidate_reservation_count",
    COALESCE("dep"."unresolved_dependency_count", (0)::bigint) AS "unresolved_dependency_count",
    COALESCE("dep"."unresolved_conflict_count", (0)::bigint) AS "unresolved_conflict_count"
   FROM (((("public"."v_vehicle_operational_state" "v"
     LEFT JOIN "public"."transportation_events" "te" ON (("te"."id" = "v"."active_transportation_event_id")))
     LEFT JOIN LATERAL ( SELECT "count"(*) AS "assigned_reservation_count"
           FROM "public"."reservations" "r"
          WHERE (("r"."vehicle_id" = "v"."vehicle_id") AND ("r"."status" IS DISTINCT FROM 'cancelled'::"text"))) "ar" ON (true))
     LEFT JOIN LATERAL ( SELECT "count"(*) AS "candidate_reservation_count"
           FROM "public"."reservations" "r"
          WHERE (("r"."requested_model" = "v"."model") AND ("r"."status" IS DISTINCT FROM 'cancelled'::"text"))) "cr" ON (true))
     LEFT JOIN LATERAL ( SELECT "count"(DISTINCT "d"."id") AS "unresolved_dependency_count",
            "count"(DISTINCT "c"."id") AS "unresolved_conflict_count"
           FROM ("public"."reservation_vehicle_dependencies" "d"
             LEFT JOIN "public"."reservation_conflicts" "c" ON ((("c"."reservation_vehicle_dependency_id" = "d"."id") AND ("c"."is_resolved" = false))))
          WHERE (("d"."vehicle_id" = "v"."vehicle_id") AND ("d"."status" = ANY (ARRAY['pending_return'::"text", 'ready'::"text", 'conflict'::"text"])))) "dep" ON (true));


ALTER VIEW "public"."v_vehicle_operational_aggregate_state" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vehicle_qr_codes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vehicle_id" "uuid" NOT NULL,
    "qr_token" "text" NOT NULL,
    "landing_mode" "text" DEFAULT 'vehicle_action_hub'::"text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "issued_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "retired_at" timestamp with time zone,
    "issued_by_user_id" "uuid",
    "notes" "text"
);


ALTER TABLE "public"."vehicle_qr_codes" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_vehicle_qr_action_entry_state" AS
 SELECT "v"."id" AS "vehicle_id",
    "v"."created_at",
    "v"."vin",
    "v"."stock_number",
    "v"."model",
    "v"."fleet_type",
    "v"."status" AS "vehicle_status",
    "v"."mileage",
    "v"."recon_status",
    "v"."current_tag",
    "v"."fleet_conversion_type",
    "v"."location",
    "v"."notes",
    "q"."id" AS "vehicle_qr_code_id",
    "q"."qr_token",
    "q"."landing_mode",
    "q"."is_active" AS "qr_is_active",
    "q"."issued_at" AS "qr_issued_at",
    "q"."retired_at" AS "qr_retired_at",
    "q"."issued_by_user_id" AS "qr_issued_by_user_id",
        CASE
            WHEN ("v"."status" = 'available'::"text") THEN true
            ELSE false
        END AS "vehicle_is_available_now",
    "jsonb_build_array"('quote', 'reserve', 'rent', 'ctp_lot_inventory_mark_present', 'swap_customer_to_this_vehicle') AS "available_scan_actions"
   FROM ("public"."vehicles" "v"
     LEFT JOIN LATERAL ( SELECT "q_1"."id",
            "q_1"."vehicle_id",
            "q_1"."qr_token",
            "q_1"."landing_mode",
            "q_1"."is_active",
            "q_1"."issued_at",
            "q_1"."retired_at",
            "q_1"."issued_by_user_id",
            "q_1"."notes"
           FROM "public"."vehicle_qr_codes" "q_1"
          WHERE (("q_1"."vehicle_id" = "v"."id") AND ("q_1"."is_active" = true))
          ORDER BY "q_1"."issued_at" DESC, "q_1"."id" DESC
         LIMIT 1) "q" ON (true));


ALTER VIEW "public"."v_vehicle_qr_action_entry_state" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vehicle_scan_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vehicle_id" "uuid" NOT NULL,
    "vehicle_qr_code_id" "uuid",
    "scan_session_id" "uuid",
    "scanned_by_user_id" "uuid" NOT NULL,
    "action_type" "text" NOT NULL,
    "result_status" "text" DEFAULT 'recorded'::"text" NOT NULL,
    "scanned_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "related_reservation_id" "uuid",
    "related_transportation_event_id" "uuid",
    "metadata" "jsonb"
);


ALTER TABLE "public"."vehicle_scan_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vehicle_scan_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "session_type" "text" NOT NULL,
    "started_by_user_id" "uuid" NOT NULL,
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ended_at" timestamp with time zone,
    "session_status" "text" DEFAULT 'active'::"text" NOT NULL,
    "notes" "text"
);


ALTER TABLE "public"."vehicle_scan_sessions" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_vehicle_scan_event_history" AS
 SELECT "e"."id" AS "vehicle_scan_event_id",
    "e"."vehicle_id",
    "v"."vin",
    "v"."stock_number",
    "v"."model",
    "e"."vehicle_qr_code_id",
    "q"."qr_token",
    "e"."scan_session_id",
    "s"."session_type",
    "e"."scanned_by_user_id",
    "u"."email" AS "scanned_by_email",
    "u"."full_name" AS "scanned_by_full_name",
    "e"."action_type",
    "e"."result_status",
    "e"."scanned_at",
    "e"."related_reservation_id",
    "e"."related_transportation_event_id",
    "e"."metadata"
   FROM (((("public"."vehicle_scan_events" "e"
     JOIN "public"."vehicles" "v" ON (("v"."id" = "e"."vehicle_id")))
     LEFT JOIN "public"."vehicle_qr_codes" "q" ON (("q"."id" = "e"."vehicle_qr_code_id")))
     LEFT JOIN "public"."vehicle_scan_sessions" "s" ON (("s"."id" = "e"."scan_session_id")))
     JOIN "public"."app_users" "u" ON (("u"."id" = "e"."scanned_by_user_id")));


ALTER VIEW "public"."v_vehicle_scan_event_history" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_vehicle_scan_session_history" AS
 SELECT "s"."id" AS "vehicle_scan_session_id",
    "s"."session_type",
    "s"."started_by_user_id",
    "u"."email" AS "started_by_email",
    "u"."full_name" AS "started_by_full_name",
    "s"."started_at",
    "s"."ended_at",
    "s"."session_status",
    "s"."notes",
    "count"("e"."id") AS "scan_event_count"
   FROM (("public"."vehicle_scan_sessions" "s"
     JOIN "public"."app_users" "u" ON (("u"."id" = "s"."started_by_user_id")))
     LEFT JOIN "public"."vehicle_scan_events" "e" ON (("e"."scan_session_id" = "s"."id")))
  GROUP BY "s"."id", "s"."session_type", "s"."started_by_user_id", "u"."email", "u"."full_name", "s"."started_at", "s"."ended_at", "s"."session_status", "s"."notes";


ALTER VIEW "public"."v_vehicle_scan_session_history" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_warning_center_critical_items" WITH ("security_invoker"='true') AS
 SELECT 'dependency_conflict'::"text" AS "item_type",
    "d"."id" AS "source_id",
    "d"."reservation_id",
    "d"."vehicle_id",
    "d"."risk_level",
    "d"."status" AS "source_status",
    "d"."expected_return_snapshot",
    NULL::"uuid" AS "contract_period_id",
    NULL::"text" AS "reminder_state",
    COALESCE("c"."message", 'Critical dependency/conflict'::"text") AS "message"
   FROM ("public"."reservation_vehicle_dependencies" "d"
     LEFT JOIN "public"."reservation_conflicts" "c" ON ((("c"."reservation_vehicle_dependency_id" = "d"."id") AND ("c"."is_resolved" = false))))
  WHERE (("d"."status" = 'conflict'::"text") OR ("d"."risk_level" = 'critical'::"text"))
UNION ALL
 SELECT 'reservation_conflict'::"text" AS "item_type",
    NULL::"uuid" AS "source_id",
    "c"."reservation_id",
    NULL::"uuid" AS "vehicle_id",
    'critical'::"text" AS "risk_level",
    'conflict'::"text" AS "source_status",
    NULL::timestamp with time zone AS "expected_return_snapshot",
    NULL::"uuid" AS "contract_period_id",
    NULL::"text" AS "reminder_state",
    COALESCE("c"."message", 'Critical unresolved reservation conflict'::"text") AS "message"
   FROM "public"."reservation_conflicts" "c"
  WHERE (("c"."is_resolved" = false) AND ("c"."severity" = 'critical'::"text"));


ALTER VIEW "public"."v_warning_center_critical_items" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_warning_center_review_items" WITH ("security_invoker"='true') AS
 SELECT 'dependency_review'::"text" AS "item_type",
    "d"."id" AS "source_id",
    "d"."reservation_id",
    "d"."vehicle_id",
    "d"."risk_level",
    "d"."status" AS "source_status",
    "d"."expected_return_snapshot",
    NULL::"uuid" AS "contract_period_id",
    NULL::"text" AS "reminder_state",
    'Dependency should be reviewed'::"text" AS "message"
   FROM "public"."reservation_vehicle_dependencies" "d"
  WHERE (("d"."status" = ANY (ARRAY['pending_return'::"text", 'ready'::"text", 'conflict'::"text"])) AND ("d"."risk_level" = 'depends_on_return'::"text"))
UNION ALL
 SELECT 'contract_review'::"text" AS "item_type",
    NULL::"uuid" AS "source_id",
    NULL::"uuid" AS "reservation_id",
    NULL::"uuid" AS "vehicle_id",
    NULL::"text" AS "risk_level",
    NULL::"text" AS "source_status",
    NULL::timestamp with time zone AS "expected_return_snapshot",
    "m"."contract_period_id",
    "m"."reminder_state",
    'Contract/reminder should be reviewed'::"text" AS "message"
   FROM "public"."v_contract_period_monitoring" "m"
  WHERE ("m"."reminder_state" = 'renew_soon'::"text");


ALTER VIEW "public"."v_warning_center_review_items" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_warning_center_warning_items" WITH ("security_invoker"='true') AS
 SELECT 'dependency_warning'::"text" AS "item_type",
    "d"."id" AS "source_id",
    "d"."reservation_id",
    "d"."vehicle_id",
    "d"."risk_level",
    "d"."status" AS "source_status",
    "d"."expected_return_snapshot",
    NULL::"uuid" AS "contract_period_id",
    NULL::"text" AS "reminder_state",
    'Dependency requires near-term attention'::"text" AS "message"
   FROM "public"."reservation_vehicle_dependencies" "d"
  WHERE (("d"."status" = ANY (ARRAY['pending_return'::"text", 'ready'::"text", 'conflict'::"text"])) AND ("d"."risk_level" = ANY (ARRAY['at_risk'::"text", 'must_return'::"text"])))
UNION ALL
 SELECT 'contract_reminder'::"text" AS "item_type",
    NULL::"uuid" AS "source_id",
    NULL::"uuid" AS "reservation_id",
    NULL::"uuid" AS "vehicle_id",
    NULL::"text" AS "risk_level",
    NULL::"text" AS "source_status",
    NULL::timestamp with time zone AS "expected_return_snapshot",
    "m"."contract_period_id",
    "m"."reminder_state",
    'Contract/reminder action needed soon'::"text" AS "message"
   FROM "public"."v_contract_period_monitoring" "m"
  WHERE ("m"."reminder_state" = ANY (ARRAY['renew_now'::"text", 'swap_required'::"text"]));


ALTER VIEW "public"."v_warning_center_warning_items" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_warranty_provider_catalog" WITH ("security_invoker"='true') AS
 SELECT "id" AS "provider_id",
    "name",
    "provider_type",
    "is_active",
    "default_daily_rate",
    "notes",
    "created_at",
    "updated_at"
   FROM "public"."warranty_providers" "wp";


ALTER VIEW "public"."v_warranty_provider_catalog" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vehicle_stock_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vehicle_id" "uuid" NOT NULL,
    "stock_number" "text" NOT NULL,
    "applied_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "removed_at" timestamp with time zone,
    "is_active" boolean DEFAULT true NOT NULL,
    "changed_by_user_id" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "ck_vehicle_stock_history_open_state" CHECK (((("is_active" = true) AND ("removed_at" IS NULL)) OR (("is_active" = false) AND ("removed_at" IS NOT NULL)))),
    CONSTRAINT "ck_vehicle_stock_history_time_order" CHECK ((("removed_at" IS NULL) OR ("removed_at" >= "applied_at")))
);


ALTER TABLE "public"."vehicle_stock_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vehicle_swaps" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "transportation_event_id" "uuid" NOT NULL,
    "old_vehicle_id" "uuid",
    "new_vehicle_id" "uuid",
    "swapped_at" timestamp with time zone DEFAULT "now"(),
    "reason" "text",
    "actor_user_id" "text"
);


ALTER TABLE "public"."vehicle_swaps" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vehicle_tags" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "vehicle_id" "uuid" NOT NULL,
    "tag_id" "uuid",
    "applied_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "removed_at" timestamp with time zone,
    "is_active" boolean DEFAULT true NOT NULL,
    "applied_by_user_id" "uuid",
    "removed_by_user_id" "uuid",
    "notes" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."vehicle_tags" OWNER TO "postgres";


COMMENT ON TABLE "public"."vehicle_tags" IS 'Tracks assignment of tags to vehicles over time. Supports active tag state, historical tracking, and audit-friendly tag lifecycle management.';



COMMENT ON COLUMN "public"."vehicle_tags"."id" IS 'Primary identifier for each vehicle tag assignment record.';



COMMENT ON COLUMN "public"."vehicle_tags"."created_at" IS 'Primary identifier for each vehicle tag assignment record.';



COMMENT ON COLUMN "public"."vehicle_tags"."vehicle_id" IS 'References the vehicle this tag assignment applies to. Used to track which vehicle currently has or previously had a specific tag (loaner, rental, EV protected, etc.).';



COMMENT ON COLUMN "public"."vehicle_tags"."tag_id" IS 'References the tag assigned to the vehicle.';



COMMENT ON COLUMN "public"."vehicle_tags"."applied_at" IS 'Date and time the tag was assigned to the vehicle. Used for tag history, reporting, audit tracking, and determining how long a vehicle carried a specific tag.';



COMMENT ON COLUMN "public"."vehicle_tags"."removed_at" IS 'Date and time the tag was removed from the vehicle. Remains empty while the tag assignment is active. Used to preserve complete tag history and determine assignment duration.';



COMMENT ON COLUMN "public"."vehicle_tags"."is_active" IS 'Indicates whether this tag assignment is currently active on the vehicle. Used for fast operational lookups without having to calculate active status from removed_at every time.';



CREATE TABLE IF NOT EXISTS "public"."warranty_alerts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "transportation_event_id" "uuid",
    "ro_number" "text",
    "provider_name" "text",
    "status" "text" DEFAULT 'open'::"text",
    "message" "text"
);


ALTER TABLE "public"."warranty_alerts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."warranty_cases" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "transportation_event_id" "uuid" NOT NULL,
    "reservation_id" "uuid",
    "provider_id" "uuid",
    "provider_name" "text",
    "approval_status" "text" DEFAULT 'pending'::"text",
    "approved_at" timestamp with time zone,
    "approved_days" integer,
    "current_day_count" integer DEFAULT 0,
    "last_checked_at" timestamp with time zone,
    "requires_manual_review" boolean DEFAULT false,
    "escalation_level" integer DEFAULT 0,
    "metadata" "jsonb"
);


ALTER TABLE "public"."warranty_cases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."warranty_day_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "warranty_case_id" "uuid" NOT NULL,
    "transportation_event_id" "uuid" NOT NULL,
    "day_index" integer NOT NULL,
    "date_used" "date" NOT NULL,
    "billing_state" "text" NOT NULL,
    "tax_applied" numeric DEFAULT 0,
    "amount_applied" numeric DEFAULT 0
);


ALTER TABLE "public"."warranty_day_ledger" OWNER TO "postgres";


ALTER TABLE ONLY "public"."active_vehicle_assignments"
    ADD CONSTRAINT "active_vehicle_assignments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."active_vehicle_assignments"
    ADD CONSTRAINT "active_vehicle_assignments_transportation_event_id_key" UNIQUE ("transportation_event_id");



ALTER TABLE ONLY "public"."admin_setting_permissions"
    ADD CONSTRAINT "admin_setting_permissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admin_settings"
    ADD CONSTRAINT "admin_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."admin_settings"
    ADD CONSTRAINT "admin_settings_setting_key_key" UNIQUE ("setting_key");



ALTER TABLE ONLY "public"."app_user_reset_tokens"
    ADD CONSTRAINT "app_user_reset_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."app_user_security"
    ADD CONSTRAINT "app_user_security_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."app_users"
    ADD CONSTRAINT "app_users_auth_user_id_key" UNIQUE ("auth_user_id");



ALTER TABLE ONLY "public"."app_users"
    ADD CONSTRAINT "app_users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."approval_actions"
    ADD CONSTRAINT "approval_actions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."approved_networks"
    ADD CONSTRAINT "approved_networks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_id_key" UNIQUE ("id");



ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_event_totals"
    ADD CONSTRAINT "billing_event_totals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."billing_event_totals"
    ADD CONSTRAINT "billing_event_totals_transportation_event_id_key" UNIQUE ("transportation_event_id");



ALTER TABLE ONLY "public"."billing_lines"
    ADD CONSTRAINT "billing_lines_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."contract_periods"
    ADD CONSTRAINT "contract_periods_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_preferences"
    ADD CONSTRAINT "customer_preferences_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_tekion_customer_number_key" UNIQUE ("tekion_customer_number");



ALTER TABLE ONLY "public"."email_outbound_messages"
    ADD CONSTRAINT "email_outbound_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."email_provider_webhook_events"
    ADD CONSTRAINT "email_provider_webhook_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."engine_runs"
    ADD CONSTRAINT "engine_runs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."engine_runs"
    ADD CONSTRAINT "engine_runs_run_id_key" UNIQUE ("run_id");



ALTER TABLE ONLY "public"."extended_warranty_rules"
    ADD CONSTRAINT "extended_warranty_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."fleet_policies"
    ADD CONSTRAINT "fleet_policies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."gm_warranty_rates"
    ADD CONSTRAINT "gm_warranty_rates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."late_fee_rules"
    ADD CONSTRAINT "late_fee_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lost_rentals"
    ADD CONSTRAINT "lost_rentals_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_delivery_queue"
    ADD CONSTRAINT "notification_delivery_queue_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_log"
    ADD CONSTRAINT "notification_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_recipients"
    ADD CONSTRAINT "notification_recipients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_rules"
    ADD CONSTRAINT "notification_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_rules"
    ADD CONSTRAINT "notification_rules_rule_name_key" UNIQUE ("rule_name");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pay_type_rules"
    ADD CONSTRAINT "pay_type_rules_pay_type_key" UNIQUE ("pay_type");



ALTER TABLE ONLY "public"."pay_type_rules"
    ADD CONSTRAINT "pay_type_rules_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."permissions"
    ADD CONSTRAINT "permissions_permission_key_key" UNIQUE ("permission_key");



ALTER TABLE ONLY "public"."permissions"
    ADD CONSTRAINT "permissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."quotes"
    ADD CONSTRAINT "quotes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rental_model_limits"
    ADD CONSTRAINT "rental_model_limits_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rental_model_limits"
    ADD CONSTRAINT "rental_model_limits_vehicle_class_key" UNIQUE ("vehicle_class");



ALTER TABLE ONLY "public"."reservation_conflicts"
    ADD CONSTRAINT "reservation_conflicts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reservation_vehicle_dependencies"
    ADD CONSTRAINT "reservation_vehicle_dependencies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reservations"
    ADD CONSTRAINT "reservations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."role_permissions"
    ADD CONSTRAINT "role_permissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."roles"
    ADD CONSTRAINT "roles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."roles"
    ADD CONSTRAINT "roles_role_name_key" UNIQUE ("role_name");



ALTER TABLE ONLY "public"."service_action_contracts"
    ADD CONSTRAINT "service_action_contracts_action_key_key" UNIQUE ("action_key");



ALTER TABLE ONLY "public"."service_action_contracts"
    ADD CONSTRAINT "service_action_contracts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tags"
    ADD CONSTRAINT "tags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tags"
    ADD CONSTRAINT "tags_tag_name_key" UNIQUE ("tag_name");



ALTER TABLE ONLY "public"."transportation_event_notes"
    ADD CONSTRAINT "transportation_event_notes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."transportation_event_state_history"
    ADD CONSTRAINT "transportation_event_state_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."transportation_events"
    ADD CONSTRAINT "transportation_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_auth_security_events"
    ADD CONSTRAINT "user_auth_security_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vehicle_events"
    ADD CONSTRAINT "vehicle_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vehicle_qr_codes"
    ADD CONSTRAINT "vehicle_qr_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vehicle_qr_codes"
    ADD CONSTRAINT "vehicle_qr_codes_qr_token_key" UNIQUE ("qr_token");



ALTER TABLE ONLY "public"."vehicle_scan_events"
    ADD CONSTRAINT "vehicle_scan_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vehicle_scan_sessions"
    ADD CONSTRAINT "vehicle_scan_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vehicle_stock_history"
    ADD CONSTRAINT "vehicle_stock_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vehicle_swaps"
    ADD CONSTRAINT "vehicle_swaps_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vehicle_tags"
    ADD CONSTRAINT "vehicle_tags_id_key" UNIQUE ("id");



ALTER TABLE ONLY "public"."vehicle_tags"
    ADD CONSTRAINT "vehicle_tags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vehicles"
    ADD CONSTRAINT "vehicles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vehicles"
    ADD CONSTRAINT "vehicles_vin_key" UNIQUE ("vin");



ALTER TABLE ONLY "public"."warranty_alerts"
    ADD CONSTRAINT "warranty_alerts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."warranty_cases"
    ADD CONSTRAINT "warranty_cases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."warranty_day_ledger"
    ADD CONSTRAINT "warranty_day_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."warranty_providers"
    ADD CONSTRAINT "warranty_providers_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."warranty_providers"
    ADD CONSTRAINT "warranty_providers_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_active_assignments_vehicle" ON "public"."active_vehicle_assignments" USING "btree" ("vehicle_id");



CREATE INDEX "idx_active_vehicle_assignments_vehicle" ON "public"."active_vehicle_assignments" USING "btree" ("vehicle_id");



CREATE INDEX "idx_audit_actor" ON "public"."audit_log" USING "btree" ("actor_user_id");



CREATE INDEX "idx_audit_entity" ON "public"."audit_log" USING "btree" ("entity_type", "entity_id");



CREATE INDEX "idx_billing_lines_event" ON "public"."billing_lines" USING "btree" ("transportation_event_id");



CREATE INDEX "idx_billing_lines_reservation" ON "public"."billing_lines" USING "btree" ("reservation_id");



CREATE INDEX "idx_billing_lines_vehicle" ON "public"."billing_lines" USING "btree" ("vehicle_id");



CREATE INDEX "idx_email_outbound_messages_provider_message_id" ON "public"."email_outbound_messages" USING "btree" ("provider_message_id");



CREATE INDEX "idx_email_outbound_messages_related_customer_id" ON "public"."email_outbound_messages" USING "btree" ("related_customer_id");



CREATE INDEX "idx_email_outbound_messages_related_reservation_id" ON "public"."email_outbound_messages" USING "btree" ("related_reservation_id");



CREATE INDEX "idx_email_outbound_messages_related_transportation_event_id" ON "public"."email_outbound_messages" USING "btree" ("related_transportation_event_id");



CREATE INDEX "idx_email_outbound_messages_related_user_id" ON "public"."email_outbound_messages" USING "btree" ("related_user_id");



CREATE INDEX "idx_email_outbound_messages_send_status" ON "public"."email_outbound_messages" USING "btree" ("send_status");



CREATE INDEX "idx_email_provider_webhook_events_event_type" ON "public"."email_provider_webhook_events" USING "btree" ("event_type");



CREATE INDEX "idx_email_provider_webhook_events_message_id" ON "public"."email_provider_webhook_events" USING "btree" ("email_outbound_message_id");



CREATE INDEX "idx_email_provider_webhook_events_occurred_at" ON "public"."email_provider_webhook_events" USING "btree" ("occurred_at" DESC);



CREATE INDEX "idx_email_provider_webhook_events_provider_message_id" ON "public"."email_provider_webhook_events" USING "btree" ("provider_message_id");



CREATE INDEX "idx_notifications_event" ON "public"."notifications" USING "btree" ("related_event_id");



CREATE INDEX "idx_notifications_read" ON "public"."notifications" USING "btree" ("is_read");



CREATE INDEX "idx_quotes_customer" ON "public"."quotes" USING "btree" ("customer_id");



CREATE INDEX "idx_quotes_start_date" ON "public"."quotes" USING "btree" ("start_date");



CREATE INDEX "idx_quotes_status" ON "public"."quotes" USING "btree" ("status");



CREATE INDEX "idx_reservations_customer" ON "public"."reservations" USING "btree" ("customer_id");



CREATE INDEX "idx_reservations_requested_model" ON "public"."reservations" USING "btree" ("requested_model");



CREATE INDEX "idx_reservations_return_date" ON "public"."reservations" USING "btree" ("expected_return_datetime");



CREATE INDEX "idx_reservations_ro" ON "public"."reservations" USING "btree" ("ro_number");



CREATE INDEX "idx_reservations_start_date" ON "public"."reservations" USING "btree" ("start_date");



CREATE INDEX "idx_reservations_status" ON "public"."reservations" USING "btree" ("status");



CREATE INDEX "idx_reservations_transportation_event" ON "public"."reservations" USING "btree" ("transportation_event_id");



CREATE INDEX "idx_reservations_vehicle" ON "public"."reservations" USING "btree" ("vehicle_id");



CREATE INDEX "idx_service_action_contracts_action_group" ON "public"."service_action_contracts" USING "btree" ("action_group");



CREATE INDEX "idx_service_action_contracts_entity_scope" ON "public"."service_action_contracts" USING "btree" ("entity_scope");



CREATE INDEX "idx_service_action_contracts_frontend_safe" ON "public"."service_action_contracts" USING "btree" ("frontend_safe");



CREATE INDEX "idx_service_action_contracts_internal_only" ON "public"."service_action_contracts" USING "btree" ("internal_only");



CREATE INDEX "idx_transportation_events_customer" ON "public"."transportation_events" USING "btree" ("customer_id");



CREATE INDEX "idx_transportation_events_status" ON "public"."transportation_events" USING "btree" ("status");



CREATE INDEX "idx_user_auth_security_events_event_type" ON "public"."user_auth_security_events" USING "btree" ("event_type");



CREATE INDEX "idx_user_auth_security_events_user_id_recorded_at" ON "public"."user_auth_security_events" USING "btree" ("user_id", "recorded_at" DESC);



CREATE INDEX "idx_vehicle_qr_codes_is_active" ON "public"."vehicle_qr_codes" USING "btree" ("is_active");



CREATE INDEX "idx_vehicle_qr_codes_vehicle_id" ON "public"."vehicle_qr_codes" USING "btree" ("vehicle_id");



CREATE INDEX "idx_vehicle_scan_events_action_type" ON "public"."vehicle_scan_events" USING "btree" ("action_type");



CREATE INDEX "idx_vehicle_scan_events_scan_session_id" ON "public"."vehicle_scan_events" USING "btree" ("scan_session_id");



CREATE INDEX "idx_vehicle_scan_events_scanned_by_user_id" ON "public"."vehicle_scan_events" USING "btree" ("scanned_by_user_id");



CREATE INDEX "idx_vehicle_scan_events_vehicle_id_scanned_at" ON "public"."vehicle_scan_events" USING "btree" ("vehicle_id", "scanned_at" DESC);



CREATE INDEX "idx_vehicle_scan_sessions_session_status" ON "public"."vehicle_scan_sessions" USING "btree" ("session_status");



CREATE INDEX "idx_vehicle_scan_sessions_session_type" ON "public"."vehicle_scan_sessions" USING "btree" ("session_type");



CREATE INDEX "idx_vehicle_scan_sessions_started_by_user_id" ON "public"."vehicle_scan_sessions" USING "btree" ("started_by_user_id");



CREATE INDEX "idx_vehicle_swaps_event" ON "public"."vehicle_swaps" USING "btree" ("transportation_event_id");



CREATE INDEX "idx_vehicles_fleet_type" ON "public"."vehicles" USING "btree" ("fleet_type");



CREATE INDEX "idx_vehicles_location" ON "public"."vehicles" USING "btree" ("location");



CREATE INDEX "idx_vehicles_status" ON "public"."vehicles" USING "btree" ("status");



CREATE INDEX "idx_vehicles_stock_number" ON "public"."vehicles" USING "btree" ("stock_number");



CREATE INDEX "idx_warranty_cases_event" ON "public"."warranty_cases" USING "btree" ("transportation_event_id");



CREATE INDEX "idx_warranty_cases_provider" ON "public"."warranty_cases" USING "btree" ("provider_id");



CREATE INDEX "idx_warranty_cases_status" ON "public"."warranty_cases" USING "btree" ("approval_status");



CREATE INDEX "ix_app_user_reset_tokens_expires_at" ON "public"."app_user_reset_tokens" USING "btree" ("expires_at");



CREATE INDEX "ix_app_user_reset_tokens_is_active" ON "public"."app_user_reset_tokens" USING "btree" ("is_active");



CREATE INDEX "ix_app_user_reset_tokens_reset_mode" ON "public"."app_user_reset_tokens" USING "btree" ("reset_mode");



CREATE INDEX "ix_app_user_reset_tokens_token_hash" ON "public"."app_user_reset_tokens" USING "btree" ("token_hash");



CREATE INDEX "ix_app_user_reset_tokens_user_id" ON "public"."app_user_reset_tokens" USING "btree" ("user_id");



CREATE INDEX "ix_app_user_security_is_disabled" ON "public"."app_user_security" USING "btree" ("is_disabled");



CREATE INDEX "ix_app_user_security_last_successful_login_at" ON "public"."app_user_security" USING "btree" ("last_successful_login_at");



CREATE INDEX "ix_app_user_security_locked_until" ON "public"."app_user_security" USING "btree" ("locked_until");



CREATE INDEX "ix_app_user_security_lockout_count" ON "public"."app_user_security" USING "btree" ("lockout_count");



CREATE INDEX "ix_app_user_security_outside_network_access_allowed" ON "public"."app_user_security" USING "btree" ("outside_network_access_allowed");



CREATE INDEX "ix_app_user_security_password_reset_pending" ON "public"."app_user_security" USING "btree" ("password_reset_pending");



CREATE INDEX "ix_approved_networks_is_active" ON "public"."approved_networks" USING "btree" ("is_active");



CREATE INDEX "ix_approved_networks_network_value" ON "public"."approved_networks" USING "btree" ("network_value");



CREATE INDEX "ix_billing_lines_contract_period_id" ON "public"."billing_lines" USING "btree" ("contract_period_id");



CREATE INDEX "ix_billing_lines_extended_from_billing_line_id" ON "public"."billing_lines" USING "btree" ("extended_from_billing_line_id");



CREATE INDEX "ix_billing_lines_line_type" ON "public"."billing_lines" USING "btree" ("line_type");



CREATE INDEX "ix_billing_lines_paid_through_at" ON "public"."billing_lines" USING "btree" ("paid_through_at");



CREATE INDEX "ix_billing_lines_parent_billing_line_id" ON "public"."billing_lines" USING "btree" ("parent_billing_line_id");



CREATE INDEX "ix_billing_lines_pay_type_rule_id" ON "public"."billing_lines" USING "btree" ("pay_type_rule_id");



CREATE INDEX "ix_billing_lines_vehicle_event_id" ON "public"."billing_lines" USING "btree" ("vehicle_event_id");



CREATE INDEX "ix_billing_lines_warranty_provider_id" ON "public"."billing_lines" USING "btree" ("warranty_provider_id");



CREATE INDEX "ix_contract_periods_vehicle_event_id" ON "public"."contract_periods" USING "btree" ("vehicle_event_id");



CREATE INDEX "ix_late_fee_rules_is_active" ON "public"."late_fee_rules" USING "btree" ("is_active");



CREATE INDEX "ix_late_fee_rules_rule_kind" ON "public"."late_fee_rules" USING "btree" ("rule_kind");



CREATE INDEX "ix_late_fee_rules_sort_order" ON "public"."late_fee_rules" USING "btree" ("sort_order");



CREATE INDEX "ix_lost_rentals_customer_id" ON "public"."lost_rentals" USING "btree" ("customer_id");



CREATE INDEX "ix_lost_rentals_model_requested" ON "public"."lost_rentals" USING "btree" ("model_requested");



CREATE INDEX "ix_lost_rentals_requested_at" ON "public"."lost_rentals" USING "btree" ("requested_at");



CREATE INDEX "ix_lost_rentals_transportation_event_id" ON "public"."lost_rentals" USING "btree" ("transportation_event_id");



CREATE INDEX "ix_lost_rentals_vehicle_class" ON "public"."lost_rentals" USING "btree" ("vehicle_class");



CREATE INDEX "ix_pay_type_rules_is_active" ON "public"."pay_type_rules" USING "btree" ("is_active");



CREATE INDEX "ix_pay_type_rules_sort_order" ON "public"."pay_type_rules" USING "btree" ("sort_order");



CREATE INDEX "ix_reservation_conflicts_dependency_id" ON "public"."reservation_conflicts" USING "btree" ("reservation_vehicle_dependency_id");



CREATE INDEX "ix_reservation_vehicle_dependencies_dependency_type" ON "public"."reservation_vehicle_dependencies" USING "btree" ("dependency_type");



CREATE INDEX "ix_reservation_vehicle_dependencies_reservation_id" ON "public"."reservation_vehicle_dependencies" USING "btree" ("reservation_id");



CREATE INDEX "ix_reservation_vehicle_dependencies_risk_level" ON "public"."reservation_vehicle_dependencies" USING "btree" ("risk_level");



CREATE INDEX "ix_reservation_vehicle_dependencies_source_transportation_event" ON "public"."reservation_vehicle_dependencies" USING "btree" ("source_transportation_event_id");



CREATE INDEX "ix_reservation_vehicle_dependencies_status" ON "public"."reservation_vehicle_dependencies" USING "btree" ("status");



CREATE INDEX "ix_reservation_vehicle_dependencies_vehicle_id" ON "public"."reservation_vehicle_dependencies" USING "btree" ("vehicle_id");



CREATE INDEX "ix_transportation_event_notes_entered_by" ON "public"."transportation_event_notes" USING "btree" ("entered_by_user_id");



CREATE INDEX "ix_transportation_event_notes_event_entered_at" ON "public"."transportation_event_notes" USING "btree" ("transportation_event_id", "entered_at" DESC);



CREATE INDEX "ix_transportation_event_notes_event_id" ON "public"."transportation_event_notes" USING "btree" ("transportation_event_id");



CREATE INDEX "ix_transportation_event_notes_note_type" ON "public"."transportation_event_notes" USING "btree" ("note_type");



CREATE INDEX "ix_transportation_event_state_history_changed_at" ON "public"."transportation_event_state_history" USING "btree" ("changed_at");



CREATE INDEX "ix_transportation_event_state_history_event_id" ON "public"."transportation_event_state_history" USING "btree" ("transportation_event_id");



CREATE INDEX "ix_transportation_events_closed_at" ON "public"."transportation_events" USING "btree" ("closed_at");



CREATE INDEX "ix_transportation_events_expected_return_at" ON "public"."transportation_events" USING "btree" ("expected_return_at");



CREATE INDEX "ix_transportation_events_source_type" ON "public"."transportation_events" USING "btree" ("source_type");



CREATE INDEX "ix_vehicle_events_transportation_event_id" ON "public"."vehicle_events" USING "btree" ("transportation_event_id");



CREATE INDEX "ix_vehicle_events_vehicle_id" ON "public"."vehicle_events" USING "btree" ("vehicle_id");



CREATE INDEX "ix_vehicle_stock_history_is_active" ON "public"."vehicle_stock_history" USING "btree" ("is_active");



CREATE INDEX "ix_vehicle_stock_history_stock_number" ON "public"."vehicle_stock_history" USING "btree" ("stock_number");



CREATE INDEX "ix_vehicle_stock_history_vehicle_id" ON "public"."vehicle_stock_history" USING "btree" ("vehicle_id");



CREATE INDEX "ix_vehicle_tags_applied_by_user_id" ON "public"."vehicle_tags" USING "btree" ("applied_by_user_id");



CREATE INDEX "ix_vehicle_tags_is_active" ON "public"."vehicle_tags" USING "btree" ("is_active");



CREATE INDEX "ix_vehicle_tags_removed_by_user_id" ON "public"."vehicle_tags" USING "btree" ("removed_by_user_id");



CREATE INDEX "ix_vehicle_tags_tag_vehicle_active" ON "public"."vehicle_tags" USING "btree" ("tag_id", "vehicle_id", "is_active");



CREATE UNIQUE INDEX "ux_admin_setting_permissions_setting_permission" ON "public"."admin_setting_permissions" USING "btree" ("setting_key", "required_permission");



CREATE UNIQUE INDEX "ux_app_users_email_lower" ON "public"."app_users" USING "btree" ("lower"("email"));



CREATE UNIQUE INDEX "ux_billing_lines_one_tax_child_per_parent" ON "public"."billing_lines" USING "btree" ("parent_billing_line_id") WHERE ("line_type" = 'tax'::"text");



CREATE UNIQUE INDEX "ux_contract_periods_one_open_per_vehicle_event" ON "public"."contract_periods" USING "btree" ("vehicle_event_id") WHERE ("is_open" = true);



CREATE UNIQUE INDEX "ux_role_permissions_role_permission" ON "public"."role_permissions" USING "btree" ("role_id", "permission_id");



CREATE UNIQUE INDEX "ux_user_roles_user_role" ON "public"."user_roles" USING "btree" ("user_id", "role_id");



CREATE UNIQUE INDEX "ux_vehicle_events_one_open_per_event" ON "public"."vehicle_events" USING "btree" ("transportation_event_id") WHERE ("is_open" = true);



CREATE OR REPLACE TRIGGER "trg_app_user_reset_tokens_set_updated_at" BEFORE UPDATE ON "public"."app_user_reset_tokens" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_app_user_security_set_updated_at" BEFORE UPDATE ON "public"."app_user_security" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_app_users_create_security_row" AFTER INSERT ON "public"."app_users" FOR EACH ROW EXECUTE FUNCTION "public"."ensure_app_user_security_row"();



CREATE OR REPLACE TRIGGER "trg_approved_networks_set_updated_at" BEFORE UPDATE ON "public"."approved_networks" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_billing_lines_set_updated_at" BEFORE UPDATE ON "public"."billing_lines" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_contract_periods_set_updated_at" BEFORE UPDATE ON "public"."contract_periods" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_late_fee_rules_set_updated_at" BEFORE UPDATE ON "public"."late_fee_rules" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_lost_rentals_set_updated_at" BEFORE UPDATE ON "public"."lost_rentals" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_pay_type_rules_set_updated_at" BEFORE UPDATE ON "public"."pay_type_rules" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_reservation_vehicle_dependencies_set_updated_at" BEFORE UPDATE ON "public"."reservation_vehicle_dependencies" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_transportation_events_set_updated_at" BEFORE UPDATE ON "public"."transportation_events" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_vehicle_events_set_updated_at" BEFORE UPDATE ON "public"."vehicle_events" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_vehicle_stock_history_set_updated_at" BEFORE UPDATE ON "public"."vehicle_stock_history" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_vehicle_tags_set_updated_at" BEFORE UPDATE ON "public"."vehicle_tags" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



ALTER TABLE ONLY "public"."app_user_reset_tokens"
    ADD CONSTRAINT "app_user_reset_tokens_issued_by_user_id_fkey" FOREIGN KEY ("issued_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."app_user_reset_tokens"
    ADD CONSTRAINT "app_user_reset_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."app_users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."app_user_security"
    ADD CONSTRAINT "app_user_security_temporary_password_issued_by_fkey" FOREIGN KEY ("temporary_password_issued_by") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."app_user_security"
    ADD CONSTRAINT "app_user_security_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."app_users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."approval_actions"
    ADD CONSTRAINT "approval_actions_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."app_users"("id");



ALTER TABLE ONLY "public"."approval_actions"
    ADD CONSTRAINT "approval_actions_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "public"."app_users"("id");



ALTER TABLE ONLY "public"."approved_networks"
    ADD CONSTRAINT "approved_networks_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."approved_networks"
    ADD CONSTRAINT "approved_networks_updated_by_user_id_fkey" FOREIGN KEY ("updated_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."billing_event_totals"
    ADD CONSTRAINT "billing_event_totals_transportation_event_id_fkey" FOREIGN KEY ("transportation_event_id") REFERENCES "public"."transportation_events"("id");



ALTER TABLE ONLY "public"."billing_lines"
    ADD CONSTRAINT "billing_lines_contract_period_id_fkey" FOREIGN KEY ("contract_period_id") REFERENCES "public"."contract_periods"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."billing_lines"
    ADD CONSTRAINT "billing_lines_parent_billing_line_id_fkey" FOREIGN KEY ("parent_billing_line_id") REFERENCES "public"."billing_lines"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."billing_lines"
    ADD CONSTRAINT "billing_lines_pay_type_rule_id_fkey" FOREIGN KEY ("pay_type_rule_id") REFERENCES "public"."pay_type_rules"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."billing_lines"
    ADD CONSTRAINT "billing_lines_reservation_id_fkey" FOREIGN KEY ("reservation_id") REFERENCES "public"."reservations"("id");



ALTER TABLE ONLY "public"."billing_lines"
    ADD CONSTRAINT "billing_lines_transportation_event_id_fkey" FOREIGN KEY ("transportation_event_id") REFERENCES "public"."transportation_events"("id");



ALTER TABLE ONLY "public"."billing_lines"
    ADD CONSTRAINT "billing_lines_vehicle_event_id_fkey" FOREIGN KEY ("vehicle_event_id") REFERENCES "public"."vehicle_events"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."billing_lines"
    ADD CONSTRAINT "billing_lines_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicles"("id");



ALTER TABLE ONLY "public"."billing_lines"
    ADD CONSTRAINT "billing_lines_warranty_provider_id_fkey" FOREIGN KEY ("warranty_provider_id") REFERENCES "public"."warranty_providers"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."contract_periods"
    ADD CONSTRAINT "contract_periods_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."contract_periods"
    ADD CONSTRAINT "contract_periods_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."contract_periods"
    ADD CONSTRAINT "contract_periods_vehicle_event_id_fkey" FOREIGN KEY ("vehicle_event_id") REFERENCES "public"."vehicle_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_preferences"
    ADD CONSTRAINT "customer_preferences_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."email_outbound_messages"
    ADD CONSTRAINT "email_outbound_messages_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."email_outbound_messages"
    ADD CONSTRAINT "email_outbound_messages_related_customer_id_fkey" FOREIGN KEY ("related_customer_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."email_outbound_messages"
    ADD CONSTRAINT "email_outbound_messages_related_reservation_id_fkey" FOREIGN KEY ("related_reservation_id") REFERENCES "public"."reservations"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."email_outbound_messages"
    ADD CONSTRAINT "email_outbound_messages_related_transportation_event_id_fkey" FOREIGN KEY ("related_transportation_event_id") REFERENCES "public"."transportation_events"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."email_outbound_messages"
    ADD CONSTRAINT "email_outbound_messages_related_user_id_fkey" FOREIGN KEY ("related_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."email_provider_webhook_events"
    ADD CONSTRAINT "email_provider_webhook_events_email_outbound_message_id_fkey" FOREIGN KEY ("email_outbound_message_id") REFERENCES "public"."email_outbound_messages"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."extended_warranty_rules"
    ADD CONSTRAINT "extended_warranty_rules_provider_id_fkey" FOREIGN KEY ("provider_id") REFERENCES "public"."warranty_providers"("id");



ALTER TABLE ONLY "public"."reservations"
    ADD CONSTRAINT "fk_reservations_transportation_event" FOREIGN KEY ("transportation_event_id") REFERENCES "public"."transportation_events"("id");



ALTER TABLE ONLY "public"."late_fee_rules"
    ADD CONSTRAINT "late_fee_rules_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."late_fee_rules"
    ADD CONSTRAINT "late_fee_rules_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."lost_rentals"
    ADD CONSTRAINT "lost_rentals_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."lost_rentals"
    ADD CONSTRAINT "lost_rentals_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."lost_rentals"
    ADD CONSTRAINT "lost_rentals_reservation_id_fkey" FOREIGN KEY ("reservation_id") REFERENCES "public"."reservations"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."lost_rentals"
    ADD CONSTRAINT "lost_rentals_transportation_event_id_fkey" FOREIGN KEY ("transportation_event_id") REFERENCES "public"."transportation_events"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."lost_rentals"
    ADD CONSTRAINT "lost_rentals_updated_by_user_id_fkey" FOREIGN KEY ("updated_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notification_delivery_queue"
    ADD CONSTRAINT "notification_delivery_queue_target_user_id_fkey" FOREIGN KEY ("target_user_id") REFERENCES "public"."app_users"("id");



ALTER TABLE ONLY "public"."notification_recipients"
    ADD CONSTRAINT "notification_recipients_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."app_users"("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_related_event_id_fkey" FOREIGN KEY ("related_event_id") REFERENCES "public"."transportation_events"("id");



ALTER TABLE ONLY "public"."quotes"
    ADD CONSTRAINT "quotes_converted_to_reservation_id_fkey" FOREIGN KEY ("converted_to_reservation_id") REFERENCES "public"."reservations"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."quotes"
    ADD CONSTRAINT "quotes_customer_fk" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id");



ALTER TABLE ONLY "public"."reservation_conflicts"
    ADD CONSTRAINT "reservation_conflicts_reservation_id_fkey" FOREIGN KEY ("reservation_id") REFERENCES "public"."reservations"("id") ON UPDATE CASCADE ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reservation_vehicle_dependencies"
    ADD CONSTRAINT "reservation_vehicle_dependenc_source_transportation_event__fkey" FOREIGN KEY ("source_transportation_event_id") REFERENCES "public"."transportation_events"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reservation_vehicle_dependencies"
    ADD CONSTRAINT "reservation_vehicle_dependencies_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reservation_vehicle_dependencies"
    ADD CONSTRAINT "reservation_vehicle_dependencies_reservation_id_fkey" FOREIGN KEY ("reservation_id") REFERENCES "public"."reservations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."reservation_vehicle_dependencies"
    ADD CONSTRAINT "reservation_vehicle_dependencies_resolved_by_user_id_fkey" FOREIGN KEY ("resolved_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reservation_vehicle_dependencies"
    ADD CONSTRAINT "reservation_vehicle_dependencies_updated_by_user_id_fkey" FOREIGN KEY ("updated_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."reservation_vehicle_dependencies"
    ADD CONSTRAINT "reservation_vehicle_dependencies_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."reservations"
    ADD CONSTRAINT "reservations_customer_fk" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id");



ALTER TABLE ONLY "public"."reservations"
    ADD CONSTRAINT "reservations_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicles"("id") ON UPDATE CASCADE ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."role_permissions"
    ADD CONSTRAINT "role_permissions_permission_id_fkey" FOREIGN KEY ("permission_id") REFERENCES "public"."permissions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."role_permissions"
    ADD CONSTRAINT "role_permissions_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "public"."roles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."transportation_event_notes"
    ADD CONSTRAINT "transportation_event_notes_entered_by_user_id_fkey" FOREIGN KEY ("entered_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."transportation_event_notes"
    ADD CONSTRAINT "transportation_event_notes_transportation_event_id_fkey" FOREIGN KEY ("transportation_event_id") REFERENCES "public"."transportation_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."transportation_events"
    ADD CONSTRAINT "transportation_events_closed_by_fkey" FOREIGN KEY ("closed_by") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."transportation_events"
    ADD CONSTRAINT "transportation_events_customer_fk" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id");



ALTER TABLE ONLY "public"."user_auth_security_events"
    ADD CONSTRAINT "user_auth_security_events_recorded_by_user_id_fkey" FOREIGN KEY ("recorded_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_auth_security_events"
    ADD CONSTRAINT "user_auth_security_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."app_users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_role_id_fkey" FOREIGN KEY ("role_id") REFERENCES "public"."roles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."app_users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vehicle_events"
    ADD CONSTRAINT "vehicle_events_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vehicle_events"
    ADD CONSTRAINT "vehicle_events_transportation_event_id_fkey" FOREIGN KEY ("transportation_event_id") REFERENCES "public"."transportation_events"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vehicle_events"
    ADD CONSTRAINT "vehicle_events_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vehicle_events"
    ADD CONSTRAINT "vehicle_events_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicles"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."vehicle_qr_codes"
    ADD CONSTRAINT "vehicle_qr_codes_issued_by_user_id_fkey" FOREIGN KEY ("issued_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vehicle_qr_codes"
    ADD CONSTRAINT "vehicle_qr_codes_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vehicle_scan_events"
    ADD CONSTRAINT "vehicle_scan_events_related_reservation_id_fkey" FOREIGN KEY ("related_reservation_id") REFERENCES "public"."reservations"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vehicle_scan_events"
    ADD CONSTRAINT "vehicle_scan_events_related_transportation_event_id_fkey" FOREIGN KEY ("related_transportation_event_id") REFERENCES "public"."transportation_events"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vehicle_scan_events"
    ADD CONSTRAINT "vehicle_scan_events_scan_session_id_fkey" FOREIGN KEY ("scan_session_id") REFERENCES "public"."vehicle_scan_sessions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vehicle_scan_events"
    ADD CONSTRAINT "vehicle_scan_events_scanned_by_user_id_fkey" FOREIGN KEY ("scanned_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."vehicle_scan_events"
    ADD CONSTRAINT "vehicle_scan_events_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vehicle_scan_events"
    ADD CONSTRAINT "vehicle_scan_events_vehicle_qr_code_id_fkey" FOREIGN KEY ("vehicle_qr_code_id") REFERENCES "public"."vehicle_qr_codes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vehicle_scan_sessions"
    ADD CONSTRAINT "vehicle_scan_sessions_started_by_user_id_fkey" FOREIGN KEY ("started_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."vehicle_stock_history"
    ADD CONSTRAINT "vehicle_stock_history_changed_by_user_id_fkey" FOREIGN KEY ("changed_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vehicle_stock_history"
    ADD CONSTRAINT "vehicle_stock_history_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vehicle_swaps"
    ADD CONSTRAINT "vehicle_swaps_new_vehicle_id_fkey" FOREIGN KEY ("new_vehicle_id") REFERENCES "public"."vehicles"("id");



ALTER TABLE ONLY "public"."vehicle_swaps"
    ADD CONSTRAINT "vehicle_swaps_old_vehicle_id_fkey" FOREIGN KEY ("old_vehicle_id") REFERENCES "public"."vehicles"("id");



ALTER TABLE ONLY "public"."vehicle_swaps"
    ADD CONSTRAINT "vehicle_swaps_transportation_event_id_fkey" FOREIGN KEY ("transportation_event_id") REFERENCES "public"."transportation_events"("id");



ALTER TABLE ONLY "public"."vehicle_tags"
    ADD CONSTRAINT "vehicle_tags_applied_by_user_id_fkey" FOREIGN KEY ("applied_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vehicle_tags"
    ADD CONSTRAINT "vehicle_tags_removed_by_user_id_fkey" FOREIGN KEY ("removed_by_user_id") REFERENCES "public"."app_users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."vehicle_tags"
    ADD CONSTRAINT "vehicle_tags_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "public"."tags"("id") ON UPDATE CASCADE ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."vehicle_tags"
    ADD CONSTRAINT "vehicle_tags_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicles"("id") ON UPDATE CASCADE ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."warranty_alerts"
    ADD CONSTRAINT "warranty_alerts_transportation_event_id_fkey" FOREIGN KEY ("transportation_event_id") REFERENCES "public"."transportation_events"("id");



ALTER TABLE "public"."active_vehicle_assignments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."admin_setting_permissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."admin_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."app_user_reset_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."app_user_security" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."app_users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."approval_actions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."approved_networks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."audit_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_event_totals" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."billing_lines" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."contract_periods" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "contract_periods_delete_authenticated" ON "public"."contract_periods" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "contract_periods_insert_authenticated" ON "public"."contract_periods" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "contract_periods_select_authenticated" ON "public"."contract_periods" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "contract_periods_update_authenticated" ON "public"."contract_periods" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



ALTER TABLE "public"."customer_preferences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."email_outbound_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."email_provider_webhook_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."engine_runs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."extended_warranty_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."fleet_policies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gm_warranty_rates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."late_fee_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."lost_rentals" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "lost_rentals_delete_authenticated" ON "public"."lost_rentals" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "lost_rentals_insert_authenticated" ON "public"."lost_rentals" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "lost_rentals_select_authenticated" ON "public"."lost_rentals" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "lost_rentals_update_authenticated" ON "public"."lost_rentals" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



ALTER TABLE "public"."notification_delivery_queue" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification_recipients" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pay_type_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."permissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."quotes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rental_model_limits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."reservation_conflicts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."reservation_vehicle_dependencies" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reservation_vehicle_dependencies_delete_authenticated" ON "public"."reservation_vehicle_dependencies" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "reservation_vehicle_dependencies_insert_authenticated" ON "public"."reservation_vehicle_dependencies" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "reservation_vehicle_dependencies_select_authenticated" ON "public"."reservation_vehicle_dependencies" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "reservation_vehicle_dependencies_update_authenticated" ON "public"."reservation_vehicle_dependencies" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



ALTER TABLE "public"."reservations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."role_permissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."roles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."service_action_contracts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tags" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."transportation_event_notes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."transportation_event_state_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."transportation_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_auth_security_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_roles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vehicle_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "vehicle_events_delete_authenticated" ON "public"."vehicle_events" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "vehicle_events_insert_authenticated" ON "public"."vehicle_events" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "vehicle_events_select_authenticated" ON "public"."vehicle_events" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "vehicle_events_update_authenticated" ON "public"."vehicle_events" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



ALTER TABLE "public"."vehicle_qr_codes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vehicle_scan_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vehicle_scan_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vehicle_stock_history" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "vehicle_stock_history_delete_authenticated" ON "public"."vehicle_stock_history" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "vehicle_stock_history_insert_authenticated" ON "public"."vehicle_stock_history" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "vehicle_stock_history_select_authenticated" ON "public"."vehicle_stock_history" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "vehicle_stock_history_update_authenticated" ON "public"."vehicle_stock_history" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



ALTER TABLE "public"."vehicle_swaps" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vehicle_tags" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vehicles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."warranty_alerts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."warranty_cases" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."warranty_day_ledger" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."warranty_providers" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































GRANT ALL ON FUNCTION "public"."accept_case_extension_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_escalate_current_dependency" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."accept_case_extension_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_escalate_current_dependency" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_case_extension_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_escalate_current_dependency" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."accept_extension_commit_state"("p_transportation_event_id" "uuid", "p_current_billing_line_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_dependency_id_to_escalate" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."accept_extension_commit_state"("p_transportation_event_id" "uuid", "p_current_billing_line_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_dependency_id_to_escalate" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_extension_commit_state"("p_transportation_event_id" "uuid", "p_current_billing_line_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_dependency_id_to_escalate" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."accept_reservation_extension_state"("p_reservation_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_escalate_current_dependency" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."accept_reservation_extension_state"("p_reservation_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_escalate_current_dependency" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_reservation_extension_state"("p_reservation_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_escalate_current_dependency" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."accept_transportation_event_extension_state"("p_transportation_event_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_escalate_current_dependency" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."accept_transportation_event_extension_state"("p_transportation_event_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_escalate_current_dependency" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_transportation_event_extension_state"("p_transportation_event_id" "uuid", "p_new_expected_return_at" timestamp with time zone, "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid", "p_escalate_current_dependency" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."activate_case_billing_state"("p_reservation_id" "uuid", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_paid_through_at" timestamp with time zone, "p_line_type" "text", "p_source_rule" "text", "p_pay_type_override" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."activate_case_billing_state"("p_reservation_id" "uuid", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_paid_through_at" timestamp with time zone, "p_line_type" "text", "p_source_rule" "text", "p_pay_type_override" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."activate_case_billing_state"("p_reservation_id" "uuid", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_paid_through_at" timestamp with time zone, "p_line_type" "text", "p_source_rule" "text", "p_pay_type_override" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."add_billing_context_note_state"("p_transportation_event_id" "uuid", "p_note_text" "text", "p_entered_by_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."add_billing_context_note_state"("p_transportation_event_id" "uuid", "p_note_text" "text", "p_entered_by_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_billing_context_note_state"("p_transportation_event_id" "uuid", "p_note_text" "text", "p_entered_by_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."add_estimated_return_change_note_state"("p_transportation_event_id" "uuid", "p_old_expected_return_at" timestamp with time zone, "p_new_expected_return_at" timestamp with time zone, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."add_estimated_return_change_note_state"("p_transportation_event_id" "uuid", "p_old_expected_return_at" timestamp with time zone, "p_new_expected_return_at" timestamp with time zone, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_estimated_return_change_note_state"("p_transportation_event_id" "uuid", "p_old_expected_return_at" timestamp with time zone, "p_new_expected_return_at" timestamp with time zone, "p_reason_code" "text", "p_optional_note" "text", "p_entered_by_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."add_transportation_event_general_note_state"("p_transportation_event_id" "uuid", "p_note_text" "text", "p_entered_by_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."add_transportation_event_general_note_state"("p_transportation_event_id" "uuid", "p_note_text" "text", "p_entered_by_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_transportation_event_general_note_state"("p_transportation_event_id" "uuid", "p_note_text" "text", "p_entered_by_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."add_user_role_state"("p_user_id" "uuid", "p_role_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."add_user_role_state"("p_user_id" "uuid", "p_role_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_user_role_state"("p_user_id" "uuid", "p_role_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."assign_reservation_vehicle_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_reference_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."assign_reservation_vehicle_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_reference_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_reservation_vehicle_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_reference_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."assign_reservation_vehicle_with_hard_lock_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_vehicle_available_now" boolean, "p_reference_at" timestamp with time zone, "p_actor_user_id" "uuid", "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."assign_reservation_vehicle_with_hard_lock_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_vehicle_available_now" boolean, "p_reference_at" timestamp with time zone, "p_actor_user_id" "uuid", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_reservation_vehicle_with_hard_lock_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_vehicle_available_now" boolean, "p_reference_at" timestamp with time zone, "p_actor_user_id" "uuid", "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."assign_user_role_by_name_state"("p_user_id" "uuid", "p_role_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."assign_user_role_by_name_state"("p_user_id" "uuid", "p_role_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_user_role_by_name_state"("p_user_id" "uuid", "p_role_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."begin_admin_password_reset_state"("p_target_user_id" "uuid", "p_admin_user_id" "uuid", "p_issued_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."begin_admin_password_reset_state"("p_target_user_id" "uuid", "p_admin_user_id" "uuid", "p_issued_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."begin_admin_password_reset_state"("p_target_user_id" "uuid", "p_admin_user_id" "uuid", "p_issued_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."business_contract_days"("p_out" timestamp with time zone, "p_in" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."business_contract_days"("p_out" timestamp with time zone, "p_in" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."business_contract_days"("p_out" timestamp with time zone, "p_in" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."cancel_case_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_cancellation_reason" "text", "p_closed_by" "uuid", "p_closed_at" timestamp with time zone, "p_note" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."cancel_case_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_cancellation_reason" "text", "p_closed_by" "uuid", "p_closed_at" timestamp with time zone, "p_note" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_case_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_cancellation_reason" "text", "p_closed_by" "uuid", "p_closed_at" timestamp with time zone, "p_note" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."cancel_reservation_with_transportation_event_state"("p_reservation_id" "uuid", "p_cancellation_reason" "text", "p_closed_by" "uuid", "p_closed_at" timestamp with time zone, "p_note" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."cancel_reservation_with_transportation_event_state"("p_reservation_id" "uuid", "p_cancellation_reason" "text", "p_closed_by" "uuid", "p_closed_at" timestamp with time zone, "p_note" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_reservation_with_transportation_event_state"("p_reservation_id" "uuid", "p_cancellation_reason" "text", "p_closed_by" "uuid", "p_closed_at" timestamp with time zone, "p_note" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."clear_password_reset_pending_state"("p_user_id" "uuid", "p_completed_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."clear_reservation_vehicle_assignment_state"("p_reservation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."clear_reservation_vehicle_assignment_state"("p_reservation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."clear_reservation_vehicle_assignment_state"("p_reservation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."clear_reservation_vehicle_assignment_with_dependency_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."clear_reservation_vehicle_assignment_with_dependency_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."clear_reservation_vehicle_assignment_with_dependency_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."close_billing_line_at_paid_through_state"("p_billing_line_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."close_billing_line_at_paid_through_state"("p_billing_line_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."close_billing_line_at_paid_through_state"("p_billing_line_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."close_billing_line_state"("p_billing_line_id" "uuid", "p_effective_end_time" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."close_billing_line_state"("p_billing_line_id" "uuid", "p_effective_end_time" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."close_billing_line_state"("p_billing_line_id" "uuid", "p_effective_end_time" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."close_current_reservation_billing_line_state"("p_reservation_id" "uuid", "p_effective_end_time" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."close_current_reservation_billing_line_state"("p_reservation_id" "uuid", "p_effective_end_time" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."close_current_reservation_billing_line_state"("p_reservation_id" "uuid", "p_effective_end_time" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."close_current_transportation_event_billing_line_state"("p_transportation_event_id" "uuid", "p_effective_end_time" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."close_current_transportation_event_billing_line_state"("p_transportation_event_id" "uuid", "p_effective_end_time" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."close_current_transportation_event_billing_line_state"("p_transportation_event_id" "uuid", "p_effective_end_time" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."close_transportation_event_state"("p_transportation_event_id" "uuid", "p_closed_by" "uuid", "p_closed_at" timestamp with time zone, "p_close_note" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."close_transportation_event_state"("p_transportation_event_id" "uuid", "p_closed_by" "uuid", "p_closed_at" timestamp with time zone, "p_close_note" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."close_transportation_event_state"("p_transportation_event_id" "uuid", "p_closed_by" "uuid", "p_closed_at" timestamp with time zone, "p_close_note" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."close_vehicle_scan_session_state"("p_vehicle_scan_session_id" "uuid", "p_notes" "text", "p_closed_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."complete_case_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer, "p_close_billing" boolean, "p_close_note" "text", "p_closed_by" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."complete_case_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer, "p_close_billing" boolean, "p_close_note" "text", "p_closed_by" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_case_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer, "p_close_billing" boolean, "p_close_note" "text", "p_closed_by" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."complete_case_return_and_close_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer, "p_close_billing" boolean, "p_close_note" "text", "p_closed_by" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."complete_case_return_and_close_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer, "p_close_billing" boolean, "p_close_note" "text", "p_closed_by" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_case_return_and_close_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer, "p_close_billing" boolean, "p_close_note" "text", "p_closed_by" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."complete_password_reset_db_state"("p_user_id" "uuid", "p_token_hash" "text", "p_completed_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."consume_reset_token_state"("p_token_hash" "text", "p_used_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."consume_reset_token_state"("p_token_hash" "text", "p_used_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."consume_reset_token_state"("p_token_hash" "text", "p_used_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."continue_case_same_vehicle_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_time" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."continue_case_same_vehicle_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_time" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."continue_case_same_vehicle_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_time" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."continue_case_same_vehicle_state"("p_reservation_id" "uuid", "p_new_time" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."continue_case_same_vehicle_state"("p_reservation_id" "uuid", "p_new_time" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."continue_case_same_vehicle_state"("p_reservation_id" "uuid", "p_new_time" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_and_start_case_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_and_start_case_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_and_start_case_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_app_user_state"("p_auth_user_id" "uuid", "p_email" "text", "p_full_name" "text", "p_phone" "text", "p_is_active" boolean, "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_app_user_state"("p_auth_user_id" "uuid", "p_email" "text", "p_full_name" "text", "p_phone" "text", "p_is_active" boolean, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_app_user_state"("p_auth_user_id" "uuid", "p_email" "text", "p_full_name" "text", "p_phone" "text", "p_is_active" boolean, "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_app_user_with_role_state"("p_auth_user_id" "uuid", "p_email" "text", "p_role_name" "text", "p_full_name" "text", "p_phone" "text", "p_is_active" boolean, "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_app_user_with_role_state"("p_auth_user_id" "uuid", "p_email" "text", "p_role_name" "text", "p_full_name" "text", "p_phone" "text", "p_is_active" boolean, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_app_user_with_role_state"("p_auth_user_id" "uuid", "p_email" "text", "p_role_name" "text", "p_full_name" "text", "p_phone" "text", "p_is_active" boolean, "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_approved_network_state"("p_label" "text", "p_network_value" "text", "p_network_type" "text", "p_notes" "text", "p_created_by_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_billing_parent_line_state"("p_transportation_event_id" "uuid", "p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_source_rule" "text", "p_vehicle_event_id" "uuid", "p_contract_period_id" "uuid", "p_line_type" "text", "p_warranty_provider_id" "uuid", "p_default_covered_days_snapshot" integer, "p_covered_days_override" integer, "p_is_open" boolean, "p_paid_through_at" timestamp with time zone, "p_extended_from_billing_line_id" "uuid", "p_default_daily_rate_snapshot" numeric, "p_daily_rate_override" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."create_billing_parent_line_state"("p_transportation_event_id" "uuid", "p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_source_rule" "text", "p_vehicle_event_id" "uuid", "p_contract_period_id" "uuid", "p_line_type" "text", "p_warranty_provider_id" "uuid", "p_default_covered_days_snapshot" integer, "p_covered_days_override" integer, "p_is_open" boolean, "p_paid_through_at" timestamp with time zone, "p_extended_from_billing_line_id" "uuid", "p_default_daily_rate_snapshot" numeric, "p_daily_rate_override" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_billing_parent_line_state"("p_transportation_event_id" "uuid", "p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_source_rule" "text", "p_vehicle_event_id" "uuid", "p_contract_period_id" "uuid", "p_line_type" "text", "p_warranty_provider_id" "uuid", "p_default_covered_days_snapshot" integer, "p_covered_days_override" integer, "p_is_open" boolean, "p_paid_through_at" timestamp with time zone, "p_extended_from_billing_line_id" "uuid", "p_default_daily_rate_snapshot" numeric, "p_daily_rate_override" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_case_bootstrap_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_status" "text", "p_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_case_bootstrap_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_status" "text", "p_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_case_bootstrap_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_status" "text", "p_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_case_bootstrap_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_case_bootstrap_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_case_bootstrap_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_customer_state"("p_tekion_customer_number" "text", "p_name" "text", "p_phone" "text", "p_email" "text", "p_flags" "jsonb", "p_internal_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_customer_state"("p_tekion_customer_number" "text", "p_name" "text", "p_phone" "text", "p_email" "text", "p_flags" "jsonb", "p_internal_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_customer_state"("p_tekion_customer_number" "text", "p_name" "text", "p_phone" "text", "p_email" "text", "p_flags" "jsonb", "p_internal_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_extended_warranty_rule_state"("p_provider_id" "uuid", "p_covered_days" integer, "p_requires_approval" boolean, "p_daily_rate" numeric, "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_extended_warranty_rule_state"("p_provider_id" "uuid", "p_covered_days" integer, "p_requires_approval" boolean, "p_daily_rate" numeric, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_extended_warranty_rule_state"("p_provider_id" "uuid", "p_covered_days" integer, "p_requires_approval" boolean, "p_daily_rate" numeric, "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_extension_billing_line_state"("p_parent_billing_line_id" "uuid", "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_new_expected_return_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."create_extension_billing_line_state"("p_parent_billing_line_id" "uuid", "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_new_expected_return_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_extension_billing_line_state"("p_parent_billing_line_id" "uuid", "p_extension_amount" numeric, "p_extension_tax_amount" numeric, "p_new_expected_return_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."create_hard_lock_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_vehicle_available_now" boolean, "p_source_transportation_event_id" "uuid", "p_expected_return_snapshot" timestamp with time zone, "p_notes" "text", "p_actor_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_hard_lock_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_vehicle_available_now" boolean, "p_source_transportation_event_id" "uuid", "p_expected_return_snapshot" timestamp with time zone, "p_notes" "text", "p_actor_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_hard_lock_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_vehicle_available_now" boolean, "p_source_transportation_event_id" "uuid", "p_expected_return_snapshot" timestamp with time zone, "p_notes" "text", "p_actor_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_late_fee_rule_state"("p_rule_kind" "text", "p_threshold_unit" "text", "p_threshold_value" integer, "p_fee_amount" numeric, "p_sort_order" integer, "p_description" "text", "p_created_by" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_late_fee_rule_state"("p_rule_kind" "text", "p_threshold_unit" "text", "p_threshold_value" integer, "p_fee_amount" numeric, "p_sort_order" integer, "p_description" "text", "p_created_by" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_late_fee_rule_state"("p_rule_kind" "text", "p_threshold_unit" "text", "p_threshold_value" integer, "p_fee_amount" numeric, "p_sort_order" integer, "p_description" "text", "p_created_by" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_or_update_reservation_conflict_state"("p_reservation_id" "uuid", "p_dependency_id" "uuid", "p_conflict_type" "text", "p_severity" "text", "p_message" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_or_update_reservation_conflict_state"("p_reservation_id" "uuid", "p_dependency_id" "uuid", "p_conflict_type" "text", "p_severity" "text", "p_message" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_or_update_reservation_conflict_state"("p_reservation_id" "uuid", "p_dependency_id" "uuid", "p_conflict_type" "text", "p_severity" "text", "p_message" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_reservation_billing_line_state"("p_reservation_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_line_type" "text", "p_paid_through_at" timestamp with time zone, "p_source_rule" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_reservation_billing_line_state"("p_reservation_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_line_type" "text", "p_paid_through_at" timestamp with time zone, "p_source_rule" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_reservation_billing_line_state"("p_reservation_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_line_type" "text", "p_paid_through_at" timestamp with time zone, "p_source_rule" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_reservation_for_tekion_customer_state"("p_tekion_customer_number" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_reservation_type" "text", "p_status" "text", "p_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_reservation_for_tekion_customer_state"("p_tekion_customer_number" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_reservation_type" "text", "p_status" "text", "p_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_reservation_for_tekion_customer_state"("p_tekion_customer_number" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_reservation_type" "text", "p_status" "text", "p_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_reservation_with_transportation_event_state"("p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_reservation_type" "text", "p_status" "text", "p_notes" "text", "p_customer_id" "uuid", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_reservation_with_transportation_event_state"("p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_reservation_type" "text", "p_status" "text", "p_notes" "text", "p_customer_id" "uuid", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_reservation_with_transportation_event_state"("p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_reservation_type" "text", "p_status" "text", "p_notes" "text", "p_customer_id" "uuid", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_reset_token_state"("p_user_id" "uuid", "p_token_hash" "text", "p_reset_mode" "text", "p_issued_by_user_id" "uuid", "p_issued_at" timestamp with time zone, "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_reset_token_state"("p_user_id" "uuid", "p_token_hash" "text", "p_reset_mode" "text", "p_issued_by_user_id" "uuid", "p_issued_at" timestamp with time zone, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_reset_token_state"("p_user_id" "uuid", "p_token_hash" "text", "p_reset_mode" "text", "p_issued_by_user_id" "uuid", "p_issued_at" timestamp with time zone, "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_billing_amount" numeric, "p_billing_tax_amount" numeric, "p_billing_start_time" timestamp with time zone, "p_billing_paid_through_at" timestamp with time zone, "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text", "p_billing_line_type" "text", "p_billing_source_rule" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_billing_amount" numeric, "p_billing_tax_amount" numeric, "p_billing_start_time" timestamp with time zone, "p_billing_paid_through_at" timestamp with time zone, "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text", "p_billing_line_type" "text", "p_billing_source_rule" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_start_and_bill_case_with_vehicle_by_vin_and_get_payload_"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_billing_amount" numeric, "p_billing_tax_amount" numeric, "p_billing_start_time" timestamp with time zone, "p_billing_paid_through_at" timestamp with time zone, "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text", "p_billing_line_type" "text", "p_billing_source_rule" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_start_and_bill_case_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_billing_amount" numeric, "p_billing_tax_amount" numeric, "p_billing_start_time" timestamp with time zone, "p_billing_paid_through_at" timestamp with time zone, "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text", "p_billing_line_type" "text", "p_billing_source_rule" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_start_and_bill_case_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_billing_amount" numeric, "p_billing_tax_amount" numeric, "p_billing_start_time" timestamp with time zone, "p_billing_paid_through_at" timestamp with time zone, "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text", "p_billing_line_type" "text", "p_billing_source_rule" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_start_and_bill_case_with_vehicle_by_vin_state"("p_tekion_customer_number" "text", "p_customer_name" "text", "p_start_date" timestamp with time zone, "p_expected_return_datetime" timestamp with time zone, "p_requested_model" "text", "p_vehicle_vin" "text", "p_vehicle_stock_number" "text", "p_vehicle_model" "text", "p_vehicle_fleet_type" "text", "p_vehicle_mileage" integer, "p_vehicle_current_tag" "text", "p_vehicle_fleet_conversion_type" "text", "p_actual_out_at" timestamp with time zone, "p_billing_amount" numeric, "p_billing_tax_amount" numeric, "p_billing_start_time" timestamp with time zone, "p_billing_paid_through_at" timestamp with time zone, "p_customer_phone" "text", "p_customer_email" "text", "p_customer_flags" "jsonb", "p_customer_internal_notes" "text", "p_reservation_type" "text", "p_reservation_status" "text", "p_reservation_notes" "text", "p_service_advisor" "text", "p_ro_number" "text", "p_pay_type" "text", "p_vehicle_location" "text", "p_vehicle_notes" "text", "p_vehicle_status" "text", "p_vehicle_recon_status" "text", "p_billing_line_type" "text", "p_billing_source_rule" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_transportation_event_billing_line_state"("p_transportation_event_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_line_type" "text", "p_paid_through_at" timestamp with time zone, "p_source_rule" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_transportation_event_billing_line_state"("p_transportation_event_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_line_type" "text", "p_paid_through_at" timestamp with time zone, "p_source_rule" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_transportation_event_billing_line_state"("p_transportation_event_id" "uuid", "p_pay_type" "text", "p_amount" numeric, "p_tax_amount" numeric, "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_line_type" "text", "p_paid_through_at" timestamp with time zone, "p_source_rule" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_transportation_event_state"("p_source_type" "text", "p_source_id" "uuid", "p_customer_id" "uuid", "p_expected_return_at" timestamp with time zone, "p_notes" "text", "p_status" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_transportation_event_state"("p_source_type" "text", "p_source_id" "uuid", "p_customer_id" "uuid", "p_expected_return_at" timestamp with time zone, "p_notes" "text", "p_status" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_transportation_event_state"("p_source_type" "text", "p_source_id" "uuid", "p_customer_id" "uuid", "p_expected_return_at" timestamp with time zone, "p_notes" "text", "p_status" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_vehicle_state"("p_vin" "text", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text", "p_notes" "text", "p_status" "text", "p_recon_status" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_vehicle_state"("p_vin" "text", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text", "p_notes" "text", "p_status" "text", "p_recon_status" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_vehicle_state"("p_vin" "text", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text", "p_notes" "text", "p_status" "text", "p_recon_status" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_warranty_provider_state"("p_name" "text", "p_provider_type" "text", "p_default_daily_rate" numeric, "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_warranty_provider_state"("p_name" "text", "p_provider_type" "text", "p_default_daily_rate" numeric, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_warranty_provider_state"("p_name" "text", "p_provider_type" "text", "p_default_daily_rate" numeric, "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_app_user_security_row"() TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_app_user_security_row"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_app_user_security_row"() TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_tax_child_line_state"("p_parent_billing_line_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_tax_child_line_state"("p_parent_billing_line_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_tax_child_line_state"("p_parent_billing_line_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_user_security_state"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_user_security_state"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_user_security_state"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."escalate_dependency_to_critical_state"("p_dependency_id" "uuid", "p_actor_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."escalate_dependency_to_critical_state"("p_dependency_id" "uuid", "p_actor_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."escalate_dependency_to_critical_state"("p_dependency_id" "uuid", "p_actor_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."escalate_reservation_dependency_to_critical_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."escalate_reservation_dependency_to_critical_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."escalate_reservation_dependency_to_critical_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."escalate_transportation_event_dependency_to_critical_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."escalate_transportation_event_dependency_to_critical_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."escalate_transportation_event_dependency_to_critical_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_active_late_fee_rules_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_active_late_fee_rules_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_active_late_fee_rules_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_admin_setting_permission_requirement_state"("p_setting_key" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_admin_settings_catalog_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_approved_network_match_state"("p_request_ip" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_approved_network_match_state"("p_request_ip" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_approved_network_match_state"("p_request_ip" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_approved_networks_state"("p_active_only" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_auth_security_policy_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_billing_dependency_banner_state"("p_transportation_event_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_billing_dependency_banner_state"("p_transportation_event_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_billing_dependency_banner_state"("p_transportation_event_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_billing_rule_catalog_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_billing_rule_catalog_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_billing_rule_catalog_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_calendar_dependency_badges_state"("p_range_start" timestamp with time zone, "p_range_end" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_calendar_dependency_badges_state"("p_range_start" timestamp with time zone, "p_range_end" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_calendar_dependency_badges_state"("p_range_start" timestamp with time zone, "p_range_end" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_case_activation_list_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_case_activation_list_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_case_activation_list_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_case_candidate_dashboard_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_case_candidate_dashboard_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_case_candidate_dashboard_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_case_completion_candidate_state"("p_reservation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_case_completion_candidate_state"("p_reservation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_case_completion_candidate_state"("p_reservation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_case_completion_list_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_case_completion_list_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_case_completion_list_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_case_continuation_candidate_state"("p_reservation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_case_continuation_candidate_state"("p_reservation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_case_continuation_candidate_state"("p_reservation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_case_continuation_list_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_case_continuation_list_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_case_continuation_list_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_case_reassignment_candidate_state"("p_reservation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_case_reassignment_candidate_state"("p_reservation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_case_reassignment_candidate_state"("p_reservation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_case_reassignment_list_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_case_reassignment_list_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_case_reassignment_list_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_ctp_monitoring_policy_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_current_reservation_dependency_state"("p_reservation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_current_reservation_dependency_state"("p_reservation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_current_reservation_dependency_state"("p_reservation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_customer_by_tekion_customer_number_state"("p_tekion_customer_number" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_customer_by_tekion_customer_number_state"("p_tekion_customer_number" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_customer_by_tekion_customer_number_state"("p_tekion_customer_number" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_customer_operational_aggregate_list_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_customer_operational_aggregate_list_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_customer_operational_aggregate_list_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_customer_operational_list_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_customer_operational_list_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_customer_operational_list_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_customer_operational_payload_state"("p_customer_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_customer_operational_payload_state"("p_customer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_customer_operational_payload_state"("p_customer_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_customer_operational_state"("p_customer_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_customer_operational_state"("p_customer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_customer_operational_state"("p_customer_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dashboard_payload_state"("p_user_id" "uuid", "p_lost_rentals_start_at" timestamp with time zone, "p_lost_rentals_end_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dashboard_section_access_state"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_dashboard_section_access_state"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dashboard_section_access_state"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_email_outbound_message_state"("p_email_outbound_message_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_frontend_safe_service_action_contracts_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_live_active_case_list_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_live_active_case_list_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_live_active_case_list_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_login_network_gate_state_by_email"("p_email" "text", "p_request_ip" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_lost_rentals_summary_state"("p_start_at" timestamp with time zone, "p_end_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_lost_rentals_summary_state"("p_start_at" timestamp with time zone, "p_end_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_lost_rentals_summary_state"("p_start_at" timestamp with time zone, "p_end_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_master_operational_dashboard_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_master_operational_dashboard_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_master_operational_dashboard_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_network_gate_state"("p_user_id" "uuid", "p_request_ip" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_network_gate_state"("p_user_id" "uuid", "p_request_ip" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_network_gate_state"("p_user_id" "uuid", "p_request_ip" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_operational_domain_counts_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_operational_domain_counts_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_operational_domain_counts_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_or_create_customer_state_by_tekion"("p_tekion_customer_number" "text", "p_name" "text", "p_phone" "text", "p_email" "text", "p_flags" "jsonb", "p_internal_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_or_create_customer_state_by_tekion"("p_tekion_customer_number" "text", "p_name" "text", "p_phone" "text", "p_email" "text", "p_flags" "jsonb", "p_internal_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_or_create_customer_state_by_tekion"("p_tekion_customer_number" "text", "p_name" "text", "p_phone" "text", "p_email" "text", "p_flags" "jsonb", "p_internal_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_or_create_vehicle_state_by_vin"("p_vin" "text", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text", "p_notes" "text", "p_status" "text", "p_recon_status" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_or_create_vehicle_state_by_vin"("p_vin" "text", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text", "p_notes" "text", "p_status" "text", "p_recon_status" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_or_create_vehicle_state_by_vin"("p_vin" "text", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text", "p_notes" "text", "p_status" "text", "p_recon_status" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_permissions_catalog_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_reservation_assignment_state"("p_reservation_id" "uuid", "p_reference_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_reservation_assignment_state"("p_reservation_id" "uuid", "p_reference_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_reservation_assignment_state"("p_reservation_id" "uuid", "p_reference_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_reservation_current_billing_state"("p_reservation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_reservation_current_billing_state"("p_reservation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_reservation_current_billing_state"("p_reservation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_reservation_extension_candidate_state"("p_reservation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_reservation_extension_candidate_state"("p_reservation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_reservation_extension_candidate_state"("p_reservation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_reservation_lifecycle_list_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_reservation_lifecycle_list_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_reservation_lifecycle_list_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_reservation_lifecycle_state"("p_reservation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_reservation_lifecycle_state"("p_reservation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_reservation_lifecycle_state"("p_reservation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_reservation_operational_list_payload_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_reservation_operational_list_payload_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_reservation_operational_list_payload_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_reservation_operational_payload_state"("p_reservation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_reservation_operational_payload_state"("p_reservation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_reservation_operational_payload_state"("p_reservation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_reservation_transportation_link_payload_state"("p_reservation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_reservation_transportation_link_payload_state"("p_reservation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_reservation_transportation_link_payload_state"("p_reservation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_reservation_vehicle_candidates_state"("p_reservation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_reservation_vehicle_candidates_state"("p_reservation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_reservation_vehicle_candidates_state"("p_reservation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_reservation_vin_lock_lead_days_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_reservation_vin_lock_lead_days_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_reservation_vin_lock_lead_days_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_reservation_vin_lock_window_state"("p_reservation_id" "uuid", "p_reference_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_reservation_vin_lock_window_state"("p_reservation_id" "uuid", "p_reference_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_reservation_vin_lock_window_state"("p_reservation_id" "uuid", "p_reference_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_reservations_needing_vin_assignment_state"("p_reference_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_reservations_needing_vin_assignment_state"("p_reference_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_reservations_needing_vin_assignment_state"("p_reference_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_reset_link_network_gate_state"("p_token_hash" "text", "p_request_ip" "text", "p_reference_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_reset_token_validity_state"("p_token_hash" "text", "p_reference_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_roles_with_permissions_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_security_admin_settings_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_service_action_contract_catalog_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_service_action_contract_state"("p_action_key" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_transportation_event_current_billing_state"("p_transportation_event_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_transportation_event_current_billing_state"("p_transportation_event_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_transportation_event_current_billing_state"("p_transportation_event_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_transportation_event_current_dependency_state"("p_transportation_event_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_transportation_event_current_dependency_state"("p_transportation_event_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_transportation_event_current_dependency_state"("p_transportation_event_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_transportation_event_extension_candidate_state"("p_transportation_event_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_transportation_event_extension_candidate_state"("p_transportation_event_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_transportation_event_extension_candidate_state"("p_transportation_event_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_transportation_event_note_history_state"("p_transportation_event_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_transportation_event_note_history_state"("p_transportation_event_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_transportation_event_note_history_state"("p_transportation_event_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_transportation_event_operational_list_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_transportation_event_operational_list_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_transportation_event_operational_list_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_transportation_event_operational_payload_state"("p_transportation_event_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_transportation_event_operational_payload_state"("p_transportation_event_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_transportation_event_operational_payload_state"("p_transportation_event_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_transportation_event_state"("p_transportation_event_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_transportation_event_state"("p_transportation_event_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_transportation_event_state"("p_transportation_event_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_transportation_event_unified_operational_list_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_transportation_event_unified_operational_list_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_transportation_event_unified_operational_list_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_transportation_event_unified_operational_payload_state"("p_transportation_event_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_transportation_event_unified_operational_payload_state"("p_transportation_event_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_transportation_event_unified_operational_payload_state"("p_transportation_event_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_unified_case_payload_state"("p_reservation_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_unified_case_payload_state"("p_reservation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_unified_case_payload_state"("p_reservation_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_upcoming_rental_dependency_feed_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_upcoming_rental_dependency_feed_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_upcoming_rental_dependency_feed_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_admin_detail_payload_state"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_admin_list_payload_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_admin_setting_access_state"("p_user_id" "uuid", "p_setting_key" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_admin_settings_access_matrix_state"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_auth_access_gate_state"("p_user_id" "uuid", "p_current_aal" "text", "p_checked_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_auth_access_gate_state_by_email"("p_email" "text", "p_current_aal" "text", "p_checked_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_auth_security_event_history_state"("p_user_id" "uuid", "p_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_email_outbound_history_state"("p_user_id" "uuid", "p_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_login_precheck_state_by_email"("p_email" "text", "p_reference_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_outside_network_access_state"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_reset_artifact_state"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_reset_entry_state_by_email"("p_email" "text", "p_reference_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_role_names_state"("p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_role_names_state"("p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_role_names_state"("p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_security_detail_state"("p_user_id" "uuid", "p_reference_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_utilization_snapshot_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_utilization_snapshot_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_utilization_snapshot_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_vehicle_by_vin_state"("p_vin" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_vehicle_by_vin_state"("p_vin" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_vehicle_by_vin_state"("p_vin" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_vehicle_ctp_monitoring_list_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_vehicle_ctp_monitoring_state"("p_vehicle_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_vehicle_operational_aggregate_list_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_vehicle_operational_aggregate_list_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_vehicle_operational_aggregate_list_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_vehicle_operational_payload_state"("p_vehicle_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_vehicle_operational_payload_state"("p_vehicle_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_vehicle_operational_payload_state"("p_vehicle_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_vehicle_operational_state"("p_vehicle_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_vehicle_operational_state"("p_vehicle_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_vehicle_operational_state"("p_vehicle_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_vehicle_qr_action_entry_state"("p_vehicle_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_vehicle_scan_session_state"("p_vehicle_scan_session_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_warning_center_counts_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_warning_center_counts_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_warning_center_counts_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_warning_center_detail_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_warning_center_detail_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_warning_center_detail_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."invalidate_reset_tokens_for_user_state"("p_user_id" "uuid", "p_invalidated_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."issue_admin_password_reset_package_state"("p_target_user_id" "uuid", "p_admin_user_id" "uuid", "p_issue_email_link" boolean, "p_token_hash" "text", "p_notes" "text", "p_issued_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."issue_new_user_password_setup_package_state"("p_user_id" "uuid", "p_admin_user_id" "uuid", "p_issue_email_link" boolean, "p_token_hash" "text", "p_notes" "text", "p_issued_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."issue_vehicle_qr_code_state"("p_vehicle_id" "uuid", "p_issued_by_user_id" "uuid", "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_email_outbound_message_failed_state"("p_email_outbound_message_id" "uuid", "p_provider_response" "jsonb", "p_failed_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_email_outbound_message_sent_state"("p_email_outbound_message_id" "uuid", "p_provider_message_id" "text", "p_provider_response" "jsonb", "p_sent_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."queue_email_outbound_message_state"("p_message_type" "text", "p_to_email" "text", "p_from_email" "text", "p_subject" "text", "p_template_key" "text", "p_related_user_id" "uuid", "p_related_customer_id" "uuid", "p_related_reservation_id" "uuid", "p_related_transportation_event_id" "uuid", "p_created_by_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."reassign_active_case_to_vehicle_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone, "p_actor_user_id" "uuid", "p_resolve_current_dependency" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."reassign_active_case_to_vehicle_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone, "p_actor_user_id" "uuid", "p_resolve_current_dependency" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."reassign_active_case_to_vehicle_and_get_unified_payload_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone, "p_actor_user_id" "uuid", "p_resolve_current_dependency" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."reassign_active_case_to_vehicle_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone, "p_actor_user_id" "uuid", "p_resolve_current_dependency" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."reassign_active_case_to_vehicle_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone, "p_actor_user_id" "uuid", "p_resolve_current_dependency" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."reassign_active_case_to_vehicle_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone, "p_actor_user_id" "uuid", "p_resolve_current_dependency" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."record_email_provider_webhook_event_state"("p_provider_name" "text", "p_event_type" "text", "p_provider_message_id" "text", "p_email_outbound_message_id" "uuid", "p_provider_event_id" "text", "p_event_payload" "jsonb", "p_occurred_at" timestamp with time zone, "p_received_at" timestamp with time zone, "p_processed_status" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."record_failed_login_attempt"("p_user_id" "uuid", "p_attempted_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."record_failed_login_attempt"("p_user_id" "uuid", "p_attempted_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_failed_login_attempt"("p_user_id" "uuid", "p_attempted_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."record_successful_login"("p_user_id" "uuid", "p_logged_in_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."record_successful_login"("p_user_id" "uuid", "p_logged_in_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."record_successful_login"("p_user_id" "uuid", "p_logged_in_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."record_user_auth_security_event_state"("p_user_id" "uuid", "p_event_type" "text", "p_factor_type" "text", "p_event_status" "text", "p_details" "jsonb", "p_recorded_by_user_id" "uuid", "p_recorded_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."record_user_mfa_event_state"("p_user_id" "uuid", "p_event_type" "text", "p_event_status" "text", "p_details" "jsonb", "p_recorded_by_user_id" "uuid", "p_recorded_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."record_vehicle_scan_event_state"("p_vehicle_id" "uuid", "p_action_type" "text", "p_scanned_by_user_id" "uuid", "p_scan_session_id" "uuid", "p_vehicle_qr_token" "text", "p_related_reservation_id" "uuid", "p_related_transportation_event_id" "uuid", "p_metadata" "jsonb", "p_scanned_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."remove_user_role_state"("p_user_id" "uuid", "p_role_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."remove_user_role_state"("p_user_id" "uuid", "p_role_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_user_role_state"("p_user_id" "uuid", "p_role_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."renew_reservation_same_vehicle_state"("p_reservation_id" "uuid", "p_new_contract_out_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."renew_reservation_same_vehicle_state"("p_reservation_id" "uuid", "p_new_contract_out_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."renew_reservation_same_vehicle_state"("p_reservation_id" "uuid", "p_new_contract_out_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."renew_same_vehicle_state"("p_vehicle_event_id" "uuid", "p_new_contract_out_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."renew_same_vehicle_state"("p_vehicle_event_id" "uuid", "p_new_contract_out_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."renew_same_vehicle_state"("p_vehicle_event_id" "uuid", "p_new_contract_out_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."reopen_transportation_event_state"("p_transportation_event_id" "uuid", "p_reopen_note" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."reopen_transportation_event_state"("p_transportation_event_id" "uuid", "p_reopen_note" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reopen_transportation_event_state"("p_transportation_event_id" "uuid", "p_reopen_note" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_dependencies_for_vehicle_return_state"("p_vehicle_id" "uuid", "p_actor_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_dependencies_for_vehicle_return_state"("p_vehicle_id" "uuid", "p_actor_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_dependencies_for_vehicle_return_state"("p_vehicle_id" "uuid", "p_actor_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_extended_warranty_provider_default_state"("p_provider_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_extended_warranty_provider_default_state"("p_provider_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_extended_warranty_provider_default_state"("p_provider_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_linked_conflicts_for_dependency_state"("p_dependency_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_linked_conflicts_for_dependency_state"("p_dependency_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_linked_conflicts_for_dependency_state"("p_dependency_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_over_due_pay_type_default_state"() TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_over_due_pay_type_default_state"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_over_due_pay_type_default_state"() TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_pay_type_rule_state"("p_pay_type" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_pay_type_rule_state"("p_pay_type" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_pay_type_rule_state"("p_pay_type" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_reservation_conflict_state"("p_conflict_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_reservation_conflict_state"("p_conflict_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_reservation_conflict_state"("p_conflict_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_reservation_dependency_as_reassigned_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_reservation_dependency_as_reassigned_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_reservation_dependency_as_reassigned_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_reservation_dependency_as_removed_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_reservation_dependency_as_removed_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_reservation_dependency_as_removed_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_reservation_dependency_state"("p_dependency_id" "uuid", "p_resolution_type" "text", "p_actor_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_reservation_dependency_state"("p_dependency_id" "uuid", "p_resolution_type" "text", "p_actor_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_reservation_dependency_state"("p_dependency_id" "uuid", "p_resolution_type" "text", "p_actor_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_transportation_event_dependency_as_reassigned_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_transportation_event_dependency_as_reassigned_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_transportation_event_dependency_as_reassigned_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_transportation_event_dependency_as_removed_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_transportation_event_dependency_as_removed_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_transportation_event_dependency_as_removed_state"("p_transportation_event_id" "uuid", "p_actor_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."restart_reservation_same_vehicle_after_gap_state"("p_reservation_id" "uuid", "p_new_actual_out_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."restart_reservation_same_vehicle_after_gap_state"("p_reservation_id" "uuid", "p_new_actual_out_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."restart_reservation_same_vehicle_after_gap_state"("p_reservation_id" "uuid", "p_new_actual_out_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."return_reservation_vehicle_use_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer, "p_note" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."return_reservation_vehicle_use_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer, "p_note" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."return_reservation_vehicle_use_state"("p_reservation_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_end_mileage" integer, "p_note" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."return_vehicle_state"("p_vehicle_event_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_ended_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."return_vehicle_state"("p_vehicle_event_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_ended_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."return_vehicle_state"("p_vehicle_event_id" "uuid", "p_actual_in_at" timestamp with time zone, "p_ended_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";



GRANT ALL ON FUNCTION "public"."select_soft_lock_candidate_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid", "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."select_soft_lock_candidate_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."select_soft_lock_candidate_state"("p_reservation_id" "uuid", "p_actor_user_id" "uuid", "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_approved_network_active_state"("p_network_id" "uuid", "p_is_active" boolean, "p_updated_by_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_email_password_reset_link_enabled_state"("p_enabled" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_expected_return_state"("p_transportation_event_id" "uuid", "p_new_expected_return_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."set_expected_return_state"("p_transportation_event_id" "uuid", "p_new_expected_return_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_expected_return_state"("p_transportation_event_id" "uuid", "p_new_expected_return_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_extended_warranty_rule_active_state"("p_rule_id" "uuid", "p_is_active" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."set_extended_warranty_rule_active_state"("p_rule_id" "uuid", "p_is_active" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_extended_warranty_rule_active_state"("p_rule_id" "uuid", "p_is_active" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_late_fee_rule_active_state"("p_rule_id" "uuid", "p_is_active" boolean, "p_updated_by" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."set_late_fee_rule_active_state"("p_rule_id" "uuid", "p_is_active" boolean, "p_updated_by" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_late_fee_rule_active_state"("p_rule_id" "uuid", "p_is_active" boolean, "p_updated_by" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_late_fees_enabled_state"("p_enabled" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_mfa_required_for_all_users_state"("p_required" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_network_restriction_enabled_state"("p_enabled" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_preferred_max_ctp_days_state"("p_preferred_max_ctp_days" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_preferred_max_ctp_qualified_miles_state"("p_preferred_max_ctp_qualified_miles" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_reservation_actual_return_state"("p_reservation_id" "uuid", "p_actual_return_datetime" timestamp with time zone, "p_end_mileage" integer, "p_note" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_reservation_actual_return_state"("p_reservation_id" "uuid", "p_actual_return_datetime" timestamp with time zone, "p_end_mileage" integer, "p_note" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_reservation_actual_return_state"("p_reservation_id" "uuid", "p_actual_return_datetime" timestamp with time zone, "p_end_mileage" integer, "p_note" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_reservation_billed_through_state"("p_reservation_id" "uuid", "p_billed_through_datetime" timestamp with time zone, "p_note" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_reservation_billed_through_state"("p_reservation_id" "uuid", "p_billed_through_datetime" timestamp with time zone, "p_note" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_reservation_billed_through_state"("p_reservation_id" "uuid", "p_billed_through_datetime" timestamp with time zone, "p_note" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_reservation_vin_lock_lead_days_state"("p_days" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_user_active_state"("p_user_id" "uuid", "p_is_active" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."set_user_active_state"("p_user_id" "uuid", "p_is_active" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_user_active_state"("p_user_id" "uuid", "p_is_active" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_user_outside_network_access_state"("p_user_id" "uuid", "p_allowed" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."set_user_outside_network_access_state"("p_user_id" "uuid", "p_allowed" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_user_outside_network_access_state"("p_user_id" "uuid", "p_allowed" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_vehicle_ctp_entry_state"("p_vehicle_id" "uuid", "p_ctp_program_entered_at" timestamp with time zone, "p_ctp_entry_mileage" integer, "p_ctp_program_active" boolean, "p_ctp_monitoring_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_vehicle_status_state"("p_vehicle_id" "uuid", "p_status" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."set_vehicle_status_state"("p_vehicle_id" "uuid", "p_status" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_vehicle_status_state"("p_vehicle_id" "uuid", "p_status" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_warranty_provider_active_state"("p_provider_id" "uuid", "p_is_active" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."set_warranty_provider_active_state"("p_provider_id" "uuid", "p_is_active" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_warranty_provider_active_state"("p_provider_id" "uuid", "p_is_active" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."start_reservation_vehicle_use_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_actual_out_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."start_reservation_vehicle_use_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_actual_out_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."start_reservation_vehicle_use_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_actual_out_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."start_vehicle_scan_session_state"("p_session_type" "text", "p_started_by_user_id" "uuid", "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."start_vehicle_use_state"("p_transportation_event_id" "uuid", "p_vehicle_id" "uuid", "p_actual_out_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."start_vehicle_use_state"("p_transportation_event_id" "uuid", "p_vehicle_id" "uuid", "p_actual_out_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."start_vehicle_use_state"("p_transportation_event_id" "uuid", "p_vehicle_id" "uuid", "p_actual_out_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."swap_reservation_vehicle_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."swap_reservation_vehicle_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."swap_reservation_vehicle_state"("p_reservation_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."swap_vehicle_state"("p_old_vehicle_event_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."swap_vehicle_state"("p_old_vehicle_event_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."swap_vehicle_state"("p_old_vehicle_event_id" "uuid", "p_new_vehicle_id" "uuid", "p_swap_time" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_approved_network_state"("p_network_id" "uuid", "p_label" "text", "p_network_value" "text", "p_network_type" "text", "p_notes" "text", "p_updated_by_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_customer_state"("p_customer_id" "uuid", "p_name" "text", "p_phone" "text", "p_email" "text", "p_flags" "jsonb", "p_internal_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."update_customer_state"("p_customer_id" "uuid", "p_name" "text", "p_phone" "text", "p_email" "text", "p_flags" "jsonb", "p_internal_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_customer_state"("p_customer_id" "uuid", "p_name" "text", "p_phone" "text", "p_email" "text", "p_flags" "jsonb", "p_internal_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_extended_warranty_rule_state"("p_rule_id" "uuid", "p_covered_days" integer, "p_requires_approval" boolean, "p_daily_rate" numeric, "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."update_extended_warranty_rule_state"("p_rule_id" "uuid", "p_covered_days" integer, "p_requires_approval" boolean, "p_daily_rate" numeric, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_extended_warranty_rule_state"("p_rule_id" "uuid", "p_covered_days" integer, "p_requires_approval" boolean, "p_daily_rate" numeric, "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_late_fee_rule_state"("p_rule_id" "uuid", "p_rule_kind" "text", "p_threshold_unit" "text", "p_threshold_value" integer, "p_fee_amount" numeric, "p_sort_order" integer, "p_description" "text", "p_updated_by" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."update_late_fee_rule_state"("p_rule_id" "uuid", "p_rule_kind" "text", "p_threshold_unit" "text", "p_threshold_value" integer, "p_fee_amount" numeric, "p_sort_order" integer, "p_description" "text", "p_updated_by" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_late_fee_rule_state"("p_rule_id" "uuid", "p_rule_kind" "text", "p_threshold_unit" "text", "p_threshold_value" integer, "p_fee_amount" numeric, "p_sort_order" integer, "p_description" "text", "p_updated_by" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_vehicle_core_state"("p_vehicle_id" "uuid", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text", "p_notes" "text", "p_recon_status" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."update_vehicle_core_state"("p_vehicle_id" "uuid", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text", "p_notes" "text", "p_recon_status" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_vehicle_core_state"("p_vehicle_id" "uuid", "p_stock_number" "text", "p_model" "text", "p_fleet_type" "text", "p_mileage" integer, "p_current_tag" "text", "p_fleet_conversion_type" "text", "p_location" "text", "p_notes" "text", "p_recon_status" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_warranty_provider_state"("p_provider_id" "uuid", "p_name" "text", "p_provider_type" "text", "p_default_daily_rate" numeric, "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."update_warranty_provider_state"("p_provider_id" "uuid", "p_name" "text", "p_provider_type" "text", "p_default_daily_rate" numeric, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_warranty_provider_state"("p_provider_id" "uuid", "p_name" "text", "p_provider_type" "text", "p_default_daily_rate" numeric, "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."upsert_reservation_dependency_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_source_transportation_event_id" "uuid", "p_dependency_type" "text", "p_status" "text", "p_risk_level" "text", "p_expected_return_snapshot" timestamp with time zone, "p_notes" "text", "p_actor_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."upsert_reservation_dependency_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_source_transportation_event_id" "uuid", "p_dependency_type" "text", "p_status" "text", "p_risk_level" "text", "p_expected_return_snapshot" timestamp with time zone, "p_notes" "text", "p_actor_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."upsert_reservation_dependency_state"("p_reservation_id" "uuid", "p_vehicle_id" "uuid", "p_source_transportation_event_id" "uuid", "p_dependency_type" "text", "p_status" "text", "p_risk_level" "text", "p_expected_return_snapshot" timestamp with time zone, "p_notes" "text", "p_actor_user_id" "uuid") TO "service_role";


















GRANT ALL ON TABLE "public"."active_vehicle_assignments" TO "anon";
GRANT ALL ON TABLE "public"."active_vehicle_assignments" TO "authenticated";
GRANT ALL ON TABLE "public"."active_vehicle_assignments" TO "service_role";



GRANT ALL ON TABLE "public"."admin_setting_permissions" TO "anon";
GRANT ALL ON TABLE "public"."admin_setting_permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."admin_setting_permissions" TO "service_role";



GRANT ALL ON TABLE "public"."admin_settings" TO "anon";
GRANT ALL ON TABLE "public"."admin_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."admin_settings" TO "service_role";



GRANT ALL ON TABLE "public"."app_user_reset_tokens" TO "anon";
GRANT ALL ON TABLE "public"."app_user_reset_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."app_user_reset_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."app_user_security" TO "anon";
GRANT ALL ON TABLE "public"."app_user_security" TO "authenticated";
GRANT ALL ON TABLE "public"."app_user_security" TO "service_role";



GRANT ALL ON TABLE "public"."app_users" TO "anon";
GRANT ALL ON TABLE "public"."app_users" TO "authenticated";
GRANT ALL ON TABLE "public"."app_users" TO "service_role";



GRANT ALL ON TABLE "public"."approval_actions" TO "anon";
GRANT ALL ON TABLE "public"."approval_actions" TO "authenticated";
GRANT ALL ON TABLE "public"."approval_actions" TO "service_role";



GRANT ALL ON TABLE "public"."approved_networks" TO "anon";
GRANT ALL ON TABLE "public"."approved_networks" TO "authenticated";
GRANT ALL ON TABLE "public"."approved_networks" TO "service_role";



GRANT ALL ON TABLE "public"."audit_log" TO "anon";
GRANT ALL ON TABLE "public"."audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."audit_log" TO "service_role";



GRANT ALL ON TABLE "public"."billing_event_totals" TO "anon";
GRANT ALL ON TABLE "public"."billing_event_totals" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_event_totals" TO "service_role";



GRANT ALL ON TABLE "public"."billing_lines" TO "anon";
GRANT ALL ON TABLE "public"."billing_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."billing_lines" TO "service_role";



GRANT ALL ON TABLE "public"."contract_periods" TO "anon";
GRANT ALL ON TABLE "public"."contract_periods" TO "authenticated";
GRANT ALL ON TABLE "public"."contract_periods" TO "service_role";



GRANT ALL ON TABLE "public"."customer_preferences" TO "anon";
GRANT ALL ON TABLE "public"."customer_preferences" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_preferences" TO "service_role";



GRANT ALL ON TABLE "public"."customers" TO "anon";
GRANT ALL ON TABLE "public"."customers" TO "authenticated";
GRANT ALL ON TABLE "public"."customers" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."email_outbound_messages" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."email_outbound_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."email_outbound_messages" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."email_provider_webhook_events" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."email_provider_webhook_events" TO "authenticated";
GRANT ALL ON TABLE "public"."email_provider_webhook_events" TO "service_role";



GRANT ALL ON TABLE "public"."engine_runs" TO "anon";
GRANT ALL ON TABLE "public"."engine_runs" TO "authenticated";
GRANT ALL ON TABLE "public"."engine_runs" TO "service_role";



GRANT ALL ON TABLE "public"."extended_warranty_rules" TO "anon";
GRANT ALL ON TABLE "public"."extended_warranty_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."extended_warranty_rules" TO "service_role";



GRANT ALL ON TABLE "public"."fleet_policies" TO "anon";
GRANT ALL ON TABLE "public"."fleet_policies" TO "authenticated";
GRANT ALL ON TABLE "public"."fleet_policies" TO "service_role";



GRANT ALL ON TABLE "public"."gm_warranty_rates" TO "anon";
GRANT ALL ON TABLE "public"."gm_warranty_rates" TO "authenticated";
GRANT ALL ON TABLE "public"."gm_warranty_rates" TO "service_role";



GRANT ALL ON TABLE "public"."late_fee_rules" TO "anon";
GRANT ALL ON TABLE "public"."late_fee_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."late_fee_rules" TO "service_role";



GRANT ALL ON TABLE "public"."lost_rentals" TO "anon";
GRANT ALL ON TABLE "public"."lost_rentals" TO "authenticated";
GRANT ALL ON TABLE "public"."lost_rentals" TO "service_role";



GRANT ALL ON TABLE "public"."notification_delivery_queue" TO "anon";
GRANT ALL ON TABLE "public"."notification_delivery_queue" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_delivery_queue" TO "service_role";



GRANT ALL ON TABLE "public"."notification_log" TO "anon";
GRANT ALL ON TABLE "public"."notification_log" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_log" TO "service_role";



GRANT ALL ON TABLE "public"."notification_recipients" TO "anon";
GRANT ALL ON TABLE "public"."notification_recipients" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_recipients" TO "service_role";



GRANT ALL ON TABLE "public"."notification_rules" TO "anon";
GRANT ALL ON TABLE "public"."notification_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_rules" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."pay_type_rules" TO "anon";
GRANT ALL ON TABLE "public"."pay_type_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."pay_type_rules" TO "service_role";



GRANT ALL ON TABLE "public"."permissions" TO "anon";
GRANT ALL ON TABLE "public"."permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."permissions" TO "service_role";



GRANT ALL ON TABLE "public"."quotes" TO "anon";
GRANT ALL ON TABLE "public"."quotes" TO "authenticated";
GRANT ALL ON TABLE "public"."quotes" TO "service_role";



GRANT ALL ON TABLE "public"."rental_model_limits" TO "anon";
GRANT ALL ON TABLE "public"."rental_model_limits" TO "authenticated";
GRANT ALL ON TABLE "public"."rental_model_limits" TO "service_role";



GRANT ALL ON TABLE "public"."reservation_conflicts" TO "anon";
GRANT ALL ON TABLE "public"."reservation_conflicts" TO "authenticated";
GRANT ALL ON TABLE "public"."reservation_conflicts" TO "service_role";



GRANT ALL ON TABLE "public"."reservation_vehicle_dependencies" TO "anon";
GRANT ALL ON TABLE "public"."reservation_vehicle_dependencies" TO "authenticated";
GRANT ALL ON TABLE "public"."reservation_vehicle_dependencies" TO "service_role";



GRANT ALL ON TABLE "public"."reservations" TO "anon";
GRANT ALL ON TABLE "public"."reservations" TO "authenticated";
GRANT ALL ON TABLE "public"."reservations" TO "service_role";



GRANT ALL ON TABLE "public"."role_permissions" TO "anon";
GRANT ALL ON TABLE "public"."role_permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."role_permissions" TO "service_role";



GRANT ALL ON TABLE "public"."roles" TO "anon";
GRANT ALL ON TABLE "public"."roles" TO "authenticated";
GRANT ALL ON TABLE "public"."roles" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."service_action_contracts" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."service_action_contracts" TO "authenticated";
GRANT ALL ON TABLE "public"."service_action_contracts" TO "service_role";



GRANT ALL ON TABLE "public"."tags" TO "anon";
GRANT ALL ON TABLE "public"."tags" TO "authenticated";
GRANT ALL ON TABLE "public"."tags" TO "service_role";



GRANT ALL ON TABLE "public"."transportation_event_notes" TO "anon";
GRANT ALL ON TABLE "public"."transportation_event_notes" TO "authenticated";
GRANT ALL ON TABLE "public"."transportation_event_notes" TO "service_role";



GRANT ALL ON TABLE "public"."transportation_event_state_history" TO "anon";
GRANT ALL ON TABLE "public"."transportation_event_state_history" TO "authenticated";
GRANT ALL ON TABLE "public"."transportation_event_state_history" TO "service_role";



GRANT ALL ON TABLE "public"."transportation_events" TO "anon";
GRANT ALL ON TABLE "public"."transportation_events" TO "authenticated";
GRANT ALL ON TABLE "public"."transportation_events" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."user_auth_security_events" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."user_auth_security_events" TO "authenticated";
GRANT ALL ON TABLE "public"."user_auth_security_events" TO "service_role";



GRANT ALL ON TABLE "public"."user_roles" TO "anon";
GRANT ALL ON TABLE "public"."user_roles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_roles" TO "service_role";



GRANT ALL ON TABLE "public"."v_active_approved_networks" TO "service_role";



GRANT ALL ON TABLE "public"."warranty_providers" TO "anon";
GRANT ALL ON TABLE "public"."warranty_providers" TO "authenticated";
GRANT ALL ON TABLE "public"."warranty_providers" TO "service_role";



GRANT ALL ON TABLE "public"."v_active_extended_warranty_provider_rules" TO "anon";
GRANT ALL ON TABLE "public"."v_active_extended_warranty_provider_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."v_active_extended_warranty_provider_rules" TO "service_role";



GRANT ALL ON TABLE "public"."v_active_hard_lock_conflicts" TO "anon";
GRANT ALL ON TABLE "public"."v_active_hard_lock_conflicts" TO "authenticated";
GRANT ALL ON TABLE "public"."v_active_hard_lock_conflicts" TO "service_role";



GRANT ALL ON TABLE "public"."v_active_late_fee_rules" TO "anon";
GRANT ALL ON TABLE "public"."v_active_late_fee_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."v_active_late_fee_rules" TO "service_role";



GRANT ALL ON TABLE "public"."v_active_usable_reset_tokens" TO "service_role";



GRANT ALL ON TABLE "public"."v_admin_settings_catalog" TO "service_role";



GRANT ALL ON TABLE "public"."v_app_users_with_roles" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_auth_security_policy_state" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_auth_security_policy_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_auth_security_policy_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_current_open_billing_lines" TO "anon";
GRANT ALL ON TABLE "public"."v_current_open_billing_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."v_current_open_billing_lines" TO "service_role";



GRANT ALL ON TABLE "public"."vehicle_events" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_events" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_events" TO "service_role";



GRANT ALL ON TABLE "public"."v_current_vehicle_continuity" TO "anon";
GRANT ALL ON TABLE "public"."v_current_vehicle_continuity" TO "authenticated";
GRANT ALL ON TABLE "public"."v_current_vehicle_continuity" TO "service_role";



GRANT ALL ON TABLE "public"."v_reservation_transportation_link_state" TO "anon";
GRANT ALL ON TABLE "public"."v_reservation_transportation_link_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_reservation_transportation_link_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_reservation_current_billing_state" TO "anon";
GRANT ALL ON TABLE "public"."v_reservation_current_billing_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_reservation_current_billing_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_case_activation_state" TO "anon";
GRANT ALL ON TABLE "public"."v_case_activation_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_case_activation_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_case_completion_candidate_state" TO "anon";
GRANT ALL ON TABLE "public"."v_case_completion_candidate_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_case_completion_candidate_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_case_continuation_candidate_state" TO "anon";
GRANT ALL ON TABLE "public"."v_case_continuation_candidate_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_case_continuation_candidate_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_reservation_assignment_state" TO "anon";
GRANT ALL ON TABLE "public"."v_reservation_assignment_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_reservation_assignment_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_reservation_operational_state" TO "anon";
GRANT ALL ON TABLE "public"."v_reservation_operational_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_reservation_operational_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_case_reassignment_candidate_state" TO "anon";
GRANT ALL ON TABLE "public"."v_case_reassignment_candidate_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_case_reassignment_candidate_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_contract_period_monitoring" TO "anon";
GRANT ALL ON TABLE "public"."v_contract_period_monitoring" TO "authenticated";
GRANT ALL ON TABLE "public"."v_contract_period_monitoring" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_ctp_monitoring_policy_state" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_ctp_monitoring_policy_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_ctp_monitoring_policy_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_current_extendable_billing_lines" TO "anon";
GRANT ALL ON TABLE "public"."v_current_extendable_billing_lines" TO "authenticated";
GRANT ALL ON TABLE "public"."v_current_extendable_billing_lines" TO "service_role";



GRANT ALL ON TABLE "public"."v_current_pay_type_rules" TO "anon";
GRANT ALL ON TABLE "public"."v_current_pay_type_rules" TO "authenticated";
GRANT ALL ON TABLE "public"."v_current_pay_type_rules" TO "service_role";



GRANT ALL ON TABLE "public"."v_customer_operational_aggregate_state" TO "anon";
GRANT ALL ON TABLE "public"."v_customer_operational_aggregate_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_customer_operational_aggregate_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_customer_operational_state" TO "anon";
GRANT ALL ON TABLE "public"."v_customer_operational_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_customer_operational_state" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_email_outbound_message_state" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_email_outbound_message_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_email_outbound_message_state" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_email_webhook_event_history" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_email_webhook_event_history" TO "authenticated";
GRANT ALL ON TABLE "public"."v_email_webhook_event_history" TO "service_role";



GRANT ALL ON TABLE "public"."v_extended_warranty_rule_catalog" TO "anon";
GRANT ALL ON TABLE "public"."v_extended_warranty_rule_catalog" TO "authenticated";
GRANT ALL ON TABLE "public"."v_extended_warranty_rule_catalog" TO "service_role";



GRANT ALL ON TABLE "public"."v_extension_commit_candidates" TO "anon";
GRANT ALL ON TABLE "public"."v_extension_commit_candidates" TO "authenticated";
GRANT ALL ON TABLE "public"."v_extension_commit_candidates" TO "service_role";



GRANT ALL ON TABLE "public"."v_late_fee_rule_catalog" TO "anon";
GRANT ALL ON TABLE "public"."v_late_fee_rule_catalog" TO "authenticated";
GRANT ALL ON TABLE "public"."v_late_fee_rule_catalog" TO "service_role";



GRANT ALL ON TABLE "public"."vehicles" TO "anon";
GRANT ALL ON TABLE "public"."vehicles" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicles" TO "service_role";



GRANT ALL ON TABLE "public"."v_live_active_case_state" TO "anon";
GRANT ALL ON TABLE "public"."v_live_active_case_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_live_active_case_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_operational_domain_counts" TO "anon";
GRANT ALL ON TABLE "public"."v_operational_domain_counts" TO "authenticated";
GRANT ALL ON TABLE "public"."v_operational_domain_counts" TO "service_role";



GRANT ALL ON TABLE "public"."v_reservation_extension_candidate_state" TO "anon";
GRANT ALL ON TABLE "public"."v_reservation_extension_candidate_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_reservation_extension_candidate_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_reservation_vehicle_candidates" TO "anon";
GRANT ALL ON TABLE "public"."v_reservation_vehicle_candidates" TO "authenticated";
GRANT ALL ON TABLE "public"."v_reservation_vehicle_candidates" TO "service_role";



GRANT ALL ON TABLE "public"."v_reservations_needing_vin_assignment" TO "anon";
GRANT ALL ON TABLE "public"."v_reservations_needing_vin_assignment" TO "authenticated";
GRANT ALL ON TABLE "public"."v_reservations_needing_vin_assignment" TO "service_role";



GRANT ALL ON TABLE "public"."v_roles_with_permissions" TO "service_role";



GRANT ALL ON TABLE "public"."v_security_admin_settings_state" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_service_action_contract_state" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_service_action_contract_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_service_action_contract_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_transportation_event_state" TO "anon";
GRANT ALL ON TABLE "public"."v_transportation_event_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_transportation_event_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_transportation_event_current_billing_state" TO "anon";
GRANT ALL ON TABLE "public"."v_transportation_event_current_billing_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_transportation_event_current_billing_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_transportation_event_current_dependency_state" TO "anon";
GRANT ALL ON TABLE "public"."v_transportation_event_current_dependency_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_transportation_event_current_dependency_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_transportation_event_extension_candidate_state" TO "anon";
GRANT ALL ON TABLE "public"."v_transportation_event_extension_candidate_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_transportation_event_extension_candidate_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_transportation_event_note_history" TO "anon";
GRANT ALL ON TABLE "public"."v_transportation_event_note_history" TO "authenticated";
GRANT ALL ON TABLE "public"."v_transportation_event_note_history" TO "service_role";



GRANT ALL ON TABLE "public"."v_transportation_event_operational_state" TO "anon";
GRANT ALL ON TABLE "public"."v_transportation_event_operational_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_transportation_event_operational_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_transportation_event_unified_operational_state" TO "anon";
GRANT ALL ON TABLE "public"."v_transportation_event_unified_operational_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_transportation_event_unified_operational_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_unresolved_reservation_conflicts" TO "anon";
GRANT ALL ON TABLE "public"."v_unresolved_reservation_conflicts" TO "authenticated";
GRANT ALL ON TABLE "public"."v_unresolved_reservation_conflicts" TO "service_role";



GRANT ALL ON TABLE "public"."v_unresolved_reservation_dependencies" TO "anon";
GRANT ALL ON TABLE "public"."v_unresolved_reservation_dependencies" TO "authenticated";
GRANT ALL ON TABLE "public"."v_unresolved_reservation_dependencies" TO "service_role";



GRANT ALL ON TABLE "public"."v_upcoming_rental_dependency_feed" TO "anon";
GRANT ALL ON TABLE "public"."v_upcoming_rental_dependency_feed" TO "authenticated";
GRANT ALL ON TABLE "public"."v_upcoming_rental_dependency_feed" TO "service_role";



GRANT ALL ON TABLE "public"."v_user_account_admin_status" TO "service_role";



GRANT ALL ON TABLE "public"."v_user_admin_list_summary" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_user_auth_security_event_history" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_user_auth_security_event_history" TO "authenticated";
GRANT ALL ON TABLE "public"."v_user_auth_security_event_history" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_user_auth_entry_orchestration_state" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_user_auth_entry_orchestration_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_user_auth_entry_orchestration_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_user_auth_entry_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_user_effective_permissions" TO "service_role";



GRANT ALL ON TABLE "public"."v_user_reset_artifact_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_users_requiring_password_reset" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_vehicle_ctp_monitoring_state" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_vehicle_ctp_monitoring_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_vehicle_ctp_monitoring_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_vehicle_operational_state" TO "anon";
GRANT ALL ON TABLE "public"."v_vehicle_operational_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_vehicle_operational_state" TO "service_role";



GRANT ALL ON TABLE "public"."v_vehicle_operational_aggregate_state" TO "anon";
GRANT ALL ON TABLE "public"."v_vehicle_operational_aggregate_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_vehicle_operational_aggregate_state" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."vehicle_qr_codes" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."vehicle_qr_codes" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_qr_codes" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_vehicle_qr_action_entry_state" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_vehicle_qr_action_entry_state" TO "authenticated";
GRANT ALL ON TABLE "public"."v_vehicle_qr_action_entry_state" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."vehicle_scan_events" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."vehicle_scan_events" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_scan_events" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."vehicle_scan_sessions" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."vehicle_scan_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_scan_sessions" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_vehicle_scan_event_history" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_vehicle_scan_event_history" TO "authenticated";
GRANT ALL ON TABLE "public"."v_vehicle_scan_event_history" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_vehicle_scan_session_history" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."v_vehicle_scan_session_history" TO "authenticated";
GRANT ALL ON TABLE "public"."v_vehicle_scan_session_history" TO "service_role";



GRANT ALL ON TABLE "public"."v_warning_center_critical_items" TO "anon";
GRANT ALL ON TABLE "public"."v_warning_center_critical_items" TO "authenticated";
GRANT ALL ON TABLE "public"."v_warning_center_critical_items" TO "service_role";



GRANT ALL ON TABLE "public"."v_warning_center_review_items" TO "anon";
GRANT ALL ON TABLE "public"."v_warning_center_review_items" TO "authenticated";
GRANT ALL ON TABLE "public"."v_warning_center_review_items" TO "service_role";



GRANT ALL ON TABLE "public"."v_warning_center_warning_items" TO "anon";
GRANT ALL ON TABLE "public"."v_warning_center_warning_items" TO "authenticated";
GRANT ALL ON TABLE "public"."v_warning_center_warning_items" TO "service_role";



GRANT ALL ON TABLE "public"."v_warranty_provider_catalog" TO "anon";
GRANT ALL ON TABLE "public"."v_warranty_provider_catalog" TO "authenticated";
GRANT ALL ON TABLE "public"."v_warranty_provider_catalog" TO "service_role";



GRANT ALL ON TABLE "public"."vehicle_stock_history" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_stock_history" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_stock_history" TO "service_role";



GRANT ALL ON TABLE "public"."vehicle_swaps" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_swaps" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_swaps" TO "service_role";



GRANT ALL ON TABLE "public"."vehicle_tags" TO "anon";
GRANT ALL ON TABLE "public"."vehicle_tags" TO "authenticated";
GRANT ALL ON TABLE "public"."vehicle_tags" TO "service_role";



GRANT ALL ON TABLE "public"."warranty_alerts" TO "anon";
GRANT ALL ON TABLE "public"."warranty_alerts" TO "authenticated";
GRANT ALL ON TABLE "public"."warranty_alerts" TO "service_role";



GRANT ALL ON TABLE "public"."warranty_cases" TO "anon";
GRANT ALL ON TABLE "public"."warranty_cases" TO "authenticated";
GRANT ALL ON TABLE "public"."warranty_cases" TO "service_role";



GRANT ALL ON TABLE "public"."warranty_day_ledger" TO "anon";
GRANT ALL ON TABLE "public"."warranty_day_ledger" TO "authenticated";
GRANT ALL ON TABLE "public"."warranty_day_ledger" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";



































drop extension if exists "pg_net";


