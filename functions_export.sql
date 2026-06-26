schema,function_name,function_definition
auth,email,"CREATE OR REPLACE FUNCTION auth.email()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$function$
"
auth,jwt,"CREATE OR REPLACE FUNCTION auth.jwt()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$function$
"
auth,role,"CREATE OR REPLACE FUNCTION auth.role()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$function$
"
auth,uid,"CREATE OR REPLACE FUNCTION auth.uid()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$function$
"
extensions,armor,"CREATE OR REPLACE FUNCTION extensions.armor(bytea)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_armor$function$
"
extensions,armor,"CREATE OR REPLACE FUNCTION extensions.armor(bytea, text[], text[])
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_armor$function$
"
extensions,crypt,"CREATE OR REPLACE FUNCTION extensions.crypt(text, text)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_crypt$function$
"
extensions,dearmor,"CREATE OR REPLACE FUNCTION extensions.dearmor(text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_dearmor$function$
"
extensions,decrypt,"CREATE OR REPLACE FUNCTION extensions.decrypt(bytea, bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_decrypt$function$
"
extensions,decrypt_iv,"CREATE OR REPLACE FUNCTION extensions.decrypt_iv(bytea, bytea, bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_decrypt_iv$function$
"
extensions,digest,"CREATE OR REPLACE FUNCTION extensions.digest(bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_digest$function$
"
extensions,digest,"CREATE OR REPLACE FUNCTION extensions.digest(text, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_digest$function$
"
extensions,encrypt,"CREATE OR REPLACE FUNCTION extensions.encrypt(bytea, bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_encrypt$function$
"
extensions,encrypt_iv,"CREATE OR REPLACE FUNCTION extensions.encrypt_iv(bytea, bytea, bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_encrypt_iv$function$
"
extensions,gen_random_bytes,"CREATE OR REPLACE FUNCTION extensions.gen_random_bytes(integer)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_random_bytes$function$
"
extensions,gen_random_uuid,"CREATE OR REPLACE FUNCTION extensions.gen_random_uuid()
 RETURNS uuid
 LANGUAGE c
 PARALLEL SAFE
AS '$libdir/pgcrypto', $function$pg_random_uuid$function$
"
extensions,gen_salt,"CREATE OR REPLACE FUNCTION extensions.gen_salt(text)
 RETURNS text
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_gen_salt$function$
"
extensions,gen_salt,"CREATE OR REPLACE FUNCTION extensions.gen_salt(text, integer)
 RETURNS text
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_gen_salt_rounds$function$
"
extensions,grant_pg_cron_access,"CREATE OR REPLACE FUNCTION extensions.grant_pg_cron_access()
 RETURNS event_trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF EXISTS (
    SELECT
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_cron'
  )
  THEN
    grant usage on schema cron to postgres with grant option;

    alter default privileges in schema cron grant all on tables to postgres with grant option;
    alter default privileges in schema cron grant all on functions to postgres with grant option;
    alter default privileges in schema cron grant all on sequences to postgres with grant option;

    alter default privileges for user supabase_admin in schema cron grant all
        on sequences to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on tables to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on functions to postgres with grant option;

    grant all privileges on all tables in schema cron to postgres with grant option;
    revoke all on table cron.job from postgres;
    grant select on table cron.job to postgres with grant option;
  END IF;
END;
$function$
"
extensions,grant_pg_graphql_access,"CREATE OR REPLACE FUNCTION extensions.grant_pg_graphql_access()
 RETURNS event_trigger
 LANGUAGE plpgsql
AS $function$
begin
    if not exists (
        select 1
        from pg_event_trigger_ddl_commands() ev
        join pg_catalog.pg_extension e on ev.objid = e.oid
        where e.extname = 'pg_graphql'
    ) then
        return;
    end if;

    drop function if exists graphql_public.graphql;
    create or replace function graphql_public.graphql(
        ""operationName"" text default null,
        query text default null,
        variables jsonb default null,
        extensions jsonb default null
    )
        returns jsonb
        language sql
    as $$
        select graphql.resolve(
            query := query,
            variables := coalesce(variables, '{}'),
            ""operationName"" := ""operationName"",
            extensions := extensions
        );
    $$;

    -- Attach the wrapper to the extension so DROP EXTENSION cascades to it,
    -- which in turn triggers set_graphql_placeholder to reinstall the ""not enabled"" stub.
    alter extension pg_graphql add function graphql_public.graphql(text, text, jsonb, jsonb);

    grant usage on schema graphql to postgres, anon, authenticated, service_role;
    grant execute on function graphql.resolve to postgres, anon, authenticated, service_role;
    grant usage on schema graphql to postgres with grant option;
    grant usage on schema graphql_public to postgres with grant option;
end;
$function$
"
extensions,grant_pg_net_access,"CREATE OR REPLACE FUNCTION extensions.grant_pg_net_access()
 RETURNS event_trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_net'
  )
  THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = 'supabase_functions_admin'
    )
    THEN
      CREATE USER supabase_functions_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION;
    END IF;

    GRANT USAGE ON SCHEMA net TO supabase_functions_admin, postgres, anon, authenticated, service_role;

    IF EXISTS (
      SELECT FROM pg_extension
      WHERE extname = 'pg_net'
      -- all versions in use on existing projects as of 2025-02-20
      -- version 0.12.0 onwards don't need these applied
      AND extversion IN ('0.2', '0.6', '0.7', '0.7.1', '0.8', '0.10.0', '0.11.0')
    ) THEN
      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;

      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;

      REVOKE ALL ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
      REVOKE ALL ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;

      GRANT EXECUTE ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
      GRANT EXECUTE ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
    END IF;
  END IF;
END;
$function$
"
extensions,hmac,"CREATE OR REPLACE FUNCTION extensions.hmac(bytea, bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_hmac$function$
"
extensions,hmac,"CREATE OR REPLACE FUNCTION extensions.hmac(text, text, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_hmac$function$
"
extensions,pg_stat_statements,"CREATE OR REPLACE FUNCTION extensions.pg_stat_statements(showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamp with time zone, OUT minmax_stats_since timestamp with time zone)
 RETURNS SETOF record
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pg_stat_statements', $function$pg_stat_statements_1_11$function$
"
extensions,pg_stat_statements_info,"CREATE OR REPLACE FUNCTION extensions.pg_stat_statements_info(OUT dealloc bigint, OUT stats_reset timestamp with time zone)
 RETURNS record
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pg_stat_statements', $function$pg_stat_statements_info$function$
"
extensions,pg_stat_statements_reset,"CREATE OR REPLACE FUNCTION extensions.pg_stat_statements_reset(userid oid DEFAULT 0, dbid oid DEFAULT 0, queryid bigint DEFAULT 0, minmax_only boolean DEFAULT false)
 RETURNS timestamp with time zone
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pg_stat_statements', $function$pg_stat_statements_reset_1_11$function$
"
extensions,pgp_armor_headers,"CREATE OR REPLACE FUNCTION extensions.pgp_armor_headers(text, OUT key text, OUT value text)
 RETURNS SETOF record
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_armor_headers$function$
"
extensions,pgp_key_id,"CREATE OR REPLACE FUNCTION extensions.pgp_key_id(bytea)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_key_id_w$function$
"
extensions,pgp_pub_decrypt,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_decrypt(bytea, bytea)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_decrypt_text$function$
"
extensions,pgp_pub_decrypt,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_decrypt_text$function$
"
extensions,pgp_pub_decrypt,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text, text)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_decrypt_text$function$
"
extensions,pgp_pub_decrypt_bytea,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_decrypt_bytea$function$
"
extensions,pgp_pub_decrypt_bytea,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_decrypt_bytea$function$
"
extensions,pgp_pub_decrypt_bytea,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_decrypt_bytea$function$
"
extensions,pgp_pub_encrypt,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_encrypt(text, bytea)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_encrypt_text$function$
"
extensions,pgp_pub_encrypt,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_encrypt(text, bytea, text)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_encrypt_text$function$
"
extensions,pgp_pub_encrypt_bytea,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_encrypt_bytea$function$
"
extensions,pgp_pub_encrypt_bytea,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea, text)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_encrypt_bytea$function$
"
extensions,pgp_sym_decrypt,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_decrypt(bytea, text)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_decrypt_text$function$
"
extensions,pgp_sym_decrypt,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_decrypt(bytea, text, text)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_decrypt_text$function$
"
extensions,pgp_sym_decrypt_bytea,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_decrypt_bytea$function$
"
extensions,pgp_sym_decrypt_bytea,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_decrypt_bytea$function$
"
extensions,pgp_sym_encrypt,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_encrypt(text, text)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_encrypt_text$function$
"
extensions,pgp_sym_encrypt,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_encrypt(text, text, text)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_encrypt_text$function$
"
extensions,pgp_sym_encrypt_bytea,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_encrypt_bytea$function$
"
extensions,pgp_sym_encrypt_bytea,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text, text)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_encrypt_bytea$function$
"
extensions,pgrst_ddl_watch,"CREATE OR REPLACE FUNCTION extensions.pgrst_ddl_watch()
 RETURNS event_trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    IF cmd.command_tag IN (
      'CREATE SCHEMA', 'ALTER SCHEMA'
    , 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE'
    , 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE'
    , 'CREATE VIEW', 'ALTER VIEW'
    , 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW'
    , 'CREATE FUNCTION', 'ALTER FUNCTION'
    , 'CREATE TRIGGER'
    , 'CREATE TYPE', 'ALTER TYPE'
    , 'CREATE RULE'
    , 'COMMENT'
    )
    -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
    AND cmd.schema_name is distinct from 'pg_temp'
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $function$
"
extensions,pgrst_drop_watch,"CREATE OR REPLACE FUNCTION extensions.pgrst_drop_watch()
 RETURNS event_trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  obj record;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    IF obj.object_type IN (
      'schema'
    , 'table'
    , 'foreign table'
    , 'view'
    , 'materialized view'
    , 'function'
    , 'trigger'
    , 'type'
    , 'rule'
    )
    AND obj.is_temporary IS false -- no pg_temp objects
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $function$
"
extensions,set_graphql_placeholder,"CREATE OR REPLACE FUNCTION extensions.set_graphql_placeholder()
 RETURNS event_trigger
 LANGUAGE plpgsql
AS $function$
    DECLARE
    graphql_is_dropped bool;
    BEGIN
    graphql_is_dropped = (
        SELECT ev.schema_name = 'graphql_public'
        FROM pg_event_trigger_dropped_objects() AS ev
        WHERE ev.schema_name = 'graphql_public'
    );

    IF graphql_is_dropped
    THEN
        create or replace function graphql_public.graphql(
            ""operationName"" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language plpgsql
        as $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;
    END IF;

    END;
$function$
"
extensions,uuid_generate_v1,"CREATE OR REPLACE FUNCTION extensions.uuid_generate_v1()
 RETURNS uuid
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_generate_v1$function$
"
extensions,uuid_generate_v1mc,"CREATE OR REPLACE FUNCTION extensions.uuid_generate_v1mc()
 RETURNS uuid
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_generate_v1mc$function$
"
extensions,uuid_generate_v3,"CREATE OR REPLACE FUNCTION extensions.uuid_generate_v3(namespace uuid, name text)
 RETURNS uuid
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_generate_v3$function$
"
extensions,uuid_generate_v4,"CREATE OR REPLACE FUNCTION extensions.uuid_generate_v4()
 RETURNS uuid
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_generate_v4$function$
"
extensions,uuid_generate_v5,"CREATE OR REPLACE FUNCTION extensions.uuid_generate_v5(namespace uuid, name text)
 RETURNS uuid
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_generate_v5$function$
"
extensions,uuid_nil,"CREATE OR REPLACE FUNCTION extensions.uuid_nil()
 RETURNS uuid
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_nil$function$
"
extensions,uuid_ns_dns,"CREATE OR REPLACE FUNCTION extensions.uuid_ns_dns()
 RETURNS uuid
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_ns_dns$function$
"
extensions,uuid_ns_oid,"CREATE OR REPLACE FUNCTION extensions.uuid_ns_oid()
 RETURNS uuid
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_ns_oid$function$
"
extensions,uuid_ns_url,"CREATE OR REPLACE FUNCTION extensions.uuid_ns_url()
 RETURNS uuid
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_ns_url$function$
"
extensions,uuid_ns_x500,"CREATE OR REPLACE FUNCTION extensions.uuid_ns_x500()
 RETURNS uuid
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_ns_x500$function$
"
graphql_public,graphql,"CREATE OR REPLACE FUNCTION graphql_public.graphql(""operationName"" text DEFAULT NULL::text, query text DEFAULT NULL::text, variables jsonb DEFAULT NULL::jsonb, extensions jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $function$
"
pgbouncer,get_auth,"CREATE OR REPLACE FUNCTION pgbouncer.get_auth(p_usename text)
 RETURNS TABLE(username text, password text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  BEGIN
      RAISE DEBUG 'PgBouncer auth request: %', p_usename;

      RETURN QUERY
      SELECT
          rolname::text,
          CASE WHEN rolvaliduntil < now()
              THEN null
              ELSE rolpassword::text
          END
      FROM pg_authid
      WHERE rolname=$1 and rolcanlogin;
  END;
  $function$
"
public,accept_case_extension_and_get_unified_payload_state,"CREATE OR REPLACE FUNCTION public.accept_case_extension_and_get_unified_payload_state(p_reservation_id uuid, p_new_expected_return_at timestamp with time zone, p_extension_amount numeric, p_extension_tax_amount numeric DEFAULT 0, p_reason_code text DEFAULT NULL::text, p_optional_note text DEFAULT NULL::text, p_entered_by_user_id uuid DEFAULT NULL::uuid, p_escalate_current_dependency boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,accept_extension_commit_state,"CREATE OR REPLACE FUNCTION public.accept_extension_commit_state(p_transportation_event_id uuid, p_current_billing_line_id uuid, p_new_expected_return_at timestamp with time zone, p_extension_amount numeric, p_extension_tax_amount numeric DEFAULT 0, p_reason_code text DEFAULT NULL::text, p_optional_note text DEFAULT NULL::text, p_entered_by_user_id uuid DEFAULT NULL::uuid, p_dependency_id_to_escalate uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,accept_reservation_extension_state,"CREATE OR REPLACE FUNCTION public.accept_reservation_extension_state(p_reservation_id uuid, p_new_expected_return_at timestamp with time zone, p_extension_amount numeric, p_extension_tax_amount numeric DEFAULT 0, p_reason_code text DEFAULT NULL::text, p_optional_note text DEFAULT NULL::text, p_entered_by_user_id uuid DEFAULT NULL::uuid, p_escalate_current_dependency boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,accept_transportation_event_extension_state,"CREATE OR REPLACE FUNCTION public.accept_transportation_event_extension_state(p_transportation_event_id uuid, p_new_expected_return_at timestamp with time zone, p_extension_amount numeric, p_extension_tax_amount numeric DEFAULT 0, p_reason_code text DEFAULT NULL::text, p_optional_note text DEFAULT NULL::text, p_entered_by_user_id uuid DEFAULT NULL::uuid, p_escalate_current_dependency boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,activate_case_billing_state,"CREATE OR REPLACE FUNCTION public.activate_case_billing_state(p_reservation_id uuid, p_amount numeric, p_tax_amount numeric DEFAULT 0, p_start_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_paid_through_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_line_type text DEFAULT 'initial_assignment'::text, p_source_rule text DEFAULT NULL::text, p_pay_type_override text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,add_billing_context_note_state,"CREATE OR REPLACE FUNCTION public.add_billing_context_note_state(p_transportation_event_id uuid, p_note_text text, p_entered_by_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,add_estimated_return_change_note_state,"CREATE OR REPLACE FUNCTION public.add_estimated_return_change_note_state(p_transportation_event_id uuid, p_old_expected_return_at timestamp with time zone, p_new_expected_return_at timestamp with time zone, p_reason_code text, p_optional_note text DEFAULT NULL::text, p_entered_by_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,add_transportation_event_general_note_state,"CREATE OR REPLACE FUNCTION public.add_transportation_event_general_note_state(p_transportation_event_id uuid, p_note_text text, p_entered_by_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,add_user_role_state,"CREATE OR REPLACE FUNCTION public.add_user_role_state(p_user_id uuid, p_role_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,assign_reservation_vehicle_state,"CREATE OR REPLACE FUNCTION public.assign_reservation_vehicle_state(p_reservation_id uuid, p_vehicle_id uuid, p_reference_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,assign_reservation_vehicle_with_hard_lock_state,"CREATE OR REPLACE FUNCTION public.assign_reservation_vehicle_with_hard_lock_state(p_reservation_id uuid, p_vehicle_id uuid, p_vehicle_available_now boolean, p_reference_at timestamp with time zone DEFAULT now(), p_actor_user_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,assign_user_role_by_name_state,"CREATE OR REPLACE FUNCTION public.assign_user_role_by_name_state(p_user_id uuid, p_role_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,begin_admin_password_reset_state,"CREATE OR REPLACE FUNCTION public.begin_admin_password_reset_state(p_target_user_id uuid, p_admin_user_id uuid, p_issued_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,business_contract_days,"CREATE OR REPLACE FUNCTION public.business_contract_days(p_out timestamp with time zone, p_in timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    select
        case
            when p_out is null then null
            else greatest(
                1,
                floor(extract(epoch from (coalesce(p_in, now()) - p_out)) / 86400.0)::int + 1
            )
        end
$function$
"
public,cancel_case_and_get_unified_payload_state,"CREATE OR REPLACE FUNCTION public.cancel_case_and_get_unified_payload_state(p_reservation_id uuid, p_cancellation_reason text, p_closed_by uuid DEFAULT NULL::uuid, p_closed_at timestamp with time zone DEFAULT now(), p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,cancel_reservation_with_transportation_event_state,"CREATE OR REPLACE FUNCTION public.cancel_reservation_with_transportation_event_state(p_reservation_id uuid, p_cancellation_reason text, p_closed_by uuid DEFAULT NULL::uuid, p_closed_at timestamp with time zone DEFAULT now(), p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,clear_password_reset_pending_state,"CREATE OR REPLACE FUNCTION public.clear_password_reset_pending_state(p_user_id uuid, p_completed_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,clear_reservation_vehicle_assignment_state,"CREATE OR REPLACE FUNCTION public.clear_reservation_vehicle_assignment_state(p_reservation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,clear_reservation_vehicle_assignment_with_dependency_state,"CREATE OR REPLACE FUNCTION public.clear_reservation_vehicle_assignment_with_dependency_state(p_reservation_id uuid, p_actor_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,close_billing_line_at_paid_through_state,"CREATE OR REPLACE FUNCTION public.close_billing_line_at_paid_through_state(p_billing_line_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,close_billing_line_state,"CREATE OR REPLACE FUNCTION public.close_billing_line_state(p_billing_line_id uuid, p_effective_end_time timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,close_current_reservation_billing_line_state,"CREATE OR REPLACE FUNCTION public.close_current_reservation_billing_line_state(p_reservation_id uuid, p_effective_end_time timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,close_current_transportation_event_billing_line_state,"CREATE OR REPLACE FUNCTION public.close_current_transportation_event_billing_line_state(p_transportation_event_id uuid, p_effective_end_time timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,close_transportation_event_state,"CREATE OR REPLACE FUNCTION public.close_transportation_event_state(p_transportation_event_id uuid, p_closed_by uuid DEFAULT NULL::uuid, p_closed_at timestamp with time zone DEFAULT now(), p_close_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,close_vehicle_scan_session_state,"CREATE OR REPLACE FUNCTION public.close_vehicle_scan_session_state(p_vehicle_scan_session_id uuid, p_notes text DEFAULT NULL::text, p_closed_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,complete_case_and_get_unified_payload_state,"CREATE OR REPLACE FUNCTION public.complete_case_and_get_unified_payload_state(p_reservation_id uuid, p_actual_in_at timestamp with time zone, p_end_mileage integer DEFAULT NULL::integer, p_close_billing boolean DEFAULT true, p_close_note text DEFAULT NULL::text, p_closed_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,complete_case_return_and_close_state,"CREATE OR REPLACE FUNCTION public.complete_case_return_and_close_state(p_reservation_id uuid, p_actual_in_at timestamp with time zone, p_end_mileage integer DEFAULT NULL::integer, p_close_billing boolean DEFAULT true, p_close_note text DEFAULT NULL::text, p_closed_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,complete_password_reset_db_state,"CREATE OR REPLACE FUNCTION public.complete_password_reset_db_state(p_user_id uuid, p_token_hash text DEFAULT NULL::text, p_completed_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,consume_reset_token_state,"CREATE OR REPLACE FUNCTION public.consume_reset_token_state(p_token_hash text, p_used_at timestamp with time zone DEFAULT now())
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,continue_case_same_vehicle_and_get_unified_payload_state,"CREATE OR REPLACE FUNCTION public.continue_case_same_vehicle_and_get_unified_payload_state(p_reservation_id uuid, p_new_time timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,continue_case_same_vehicle_state,"CREATE OR REPLACE FUNCTION public.continue_case_same_vehicle_state(p_reservation_id uuid, p_new_time timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,create_and_start_case_with_vehicle_by_vin_state,"CREATE OR REPLACE FUNCTION public.create_and_start_case_with_vehicle_by_vin_state(p_tekion_customer_number text, p_customer_name text, p_start_date timestamp with time zone, p_expected_return_datetime timestamp with time zone, p_requested_model text, p_vehicle_vin text, p_vehicle_stock_number text, p_vehicle_model text, p_vehicle_fleet_type text, p_vehicle_mileage integer, p_vehicle_current_tag text, p_vehicle_fleet_conversion_type text, p_actual_out_at timestamp with time zone, p_customer_phone text DEFAULT NULL::text, p_customer_email text DEFAULT NULL::text, p_customer_flags jsonb DEFAULT NULL::jsonb, p_customer_internal_notes text DEFAULT NULL::text, p_reservation_type text DEFAULT 'rental'::text, p_reservation_status text DEFAULT 'quote'::text, p_reservation_notes text DEFAULT NULL::text, p_service_advisor text DEFAULT NULL::text, p_ro_number text DEFAULT NULL::text, p_pay_type text DEFAULT 'customer'::text, p_vehicle_location text DEFAULT NULL::text, p_vehicle_notes text DEFAULT NULL::text, p_vehicle_status text DEFAULT 'available'::text, p_vehicle_recon_status text DEFAULT 'clean'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,create_app_user_state,"CREATE OR REPLACE FUNCTION public.create_app_user_state(p_auth_user_id uuid, p_email text, p_full_name text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_is_active boolean DEFAULT true, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,create_app_user_with_role_state,"CREATE OR REPLACE FUNCTION public.create_app_user_with_role_state(p_auth_user_id uuid, p_email text, p_role_name text, p_full_name text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_is_active boolean DEFAULT true, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,create_approved_network_state,"CREATE OR REPLACE FUNCTION public.create_approved_network_state(p_label text, p_network_value text, p_network_type text, p_notes text DEFAULT NULL::text, p_created_by_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,create_billing_parent_line_state,"CREATE OR REPLACE FUNCTION public.create_billing_parent_line_state(p_transportation_event_id uuid, p_reservation_id uuid, p_vehicle_id uuid, p_pay_type text, p_amount numeric, p_tax_amount numeric, p_start_time timestamp with time zone, p_end_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_source_rule text DEFAULT NULL::text, p_vehicle_event_id uuid DEFAULT NULL::uuid, p_contract_period_id uuid DEFAULT NULL::uuid, p_line_type text DEFAULT 'initial_assignment'::text, p_warranty_provider_id uuid DEFAULT NULL::uuid, p_default_covered_days_snapshot integer DEFAULT NULL::integer, p_covered_days_override integer DEFAULT NULL::integer, p_is_open boolean DEFAULT true, p_paid_through_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_extended_from_billing_line_id uuid DEFAULT NULL::uuid, p_default_daily_rate_snapshot numeric DEFAULT NULL::numeric, p_daily_rate_override numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,create_case_bootstrap_state,"CREATE OR REPLACE FUNCTION public.create_case_bootstrap_state(p_tekion_customer_number text, p_customer_name text, p_start_date timestamp with time zone, p_expected_return_datetime timestamp with time zone, p_requested_model text, p_customer_phone text DEFAULT NULL::text, p_customer_email text DEFAULT NULL::text, p_customer_flags jsonb DEFAULT NULL::jsonb, p_customer_internal_notes text DEFAULT NULL::text, p_reservation_type text DEFAULT 'rental'::text, p_status text DEFAULT 'quote'::text, p_notes text DEFAULT NULL::text, p_service_advisor text DEFAULT NULL::text, p_ro_number text DEFAULT NULL::text, p_pay_type text DEFAULT 'customer'::text, p_vehicle_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,create_case_bootstrap_with_vehicle_by_vin_state,"CREATE OR REPLACE FUNCTION public.create_case_bootstrap_with_vehicle_by_vin_state(p_tekion_customer_number text, p_customer_name text, p_start_date timestamp with time zone, p_expected_return_datetime timestamp with time zone, p_requested_model text, p_vehicle_vin text, p_vehicle_stock_number text, p_vehicle_model text, p_vehicle_fleet_type text, p_vehicle_mileage integer, p_vehicle_current_tag text, p_vehicle_fleet_conversion_type text, p_customer_phone text DEFAULT NULL::text, p_customer_email text DEFAULT NULL::text, p_customer_flags jsonb DEFAULT NULL::jsonb, p_customer_internal_notes text DEFAULT NULL::text, p_reservation_type text DEFAULT 'rental'::text, p_reservation_status text DEFAULT 'quote'::text, p_reservation_notes text DEFAULT NULL::text, p_service_advisor text DEFAULT NULL::text, p_ro_number text DEFAULT NULL::text, p_pay_type text DEFAULT 'customer'::text, p_vehicle_location text DEFAULT NULL::text, p_vehicle_notes text DEFAULT NULL::text, p_vehicle_status text DEFAULT 'available'::text, p_vehicle_recon_status text DEFAULT 'clean'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
public,create_customer_state,"CREATE OR REPLACE FUNCTION public.create_customer_state(p_tekion_customer_number text, p_name text, p_phone text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_flags jsonb DEFAULT NULL::jsonb, p_internal_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
$function$
"
