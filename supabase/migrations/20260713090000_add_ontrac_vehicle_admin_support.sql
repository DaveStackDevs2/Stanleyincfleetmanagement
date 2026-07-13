-- Add vehicle administration fields required for manual entry and GM OnTrac synchronization.
alter table public.vehicles
    alter column vin drop not null,
    add column if not exists vin_last8 text,
    add column if not exists model_year integer,
    add column if not exists trim text,
    add column if not exists qualified_miles integer,
    add column if not exists ontrac_days_in_service integer,
    add column if not exists record_source text not null default 'manual',
    add column if not exists ontrac_first_seen_at timestamp with time zone,
    add column if not exists ontrac_last_seen_at timestamp with time zone,
    add column if not exists plate_sync_required boolean not null default false;

update public.vehicles
set vin_last8 = upper(right(vin, 8))
where vin is not null
  and vin_last8 is null;

alter table public.vehicles
    alter column vin_last8 set not null;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'vehicles_vin_last8_length_check'
          and conrelid = 'public.vehicles'::regclass
    ) then
        alter table public.vehicles
            add constraint vehicles_vin_last8_length_check
            check (char_length(vin_last8) = 8);
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conname = 'vehicles_model_year_check'
          and conrelid = 'public.vehicles'::regclass
    ) then
        alter table public.vehicles
            add constraint vehicles_model_year_check
            check (
                model_year is null
                or model_year between 1980 and 2100
            );
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conname = 'vehicles_qualified_miles_check'
          and conrelid = 'public.vehicles'::regclass
    ) then
        alter table public.vehicles
            add constraint vehicles_qualified_miles_check
            check (
                qualified_miles is null
                or qualified_miles >= 0
            );
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conname = 'vehicles_ontrac_days_in_service_check'
          and conrelid = 'public.vehicles'::regclass
    ) then
        alter table public.vehicles
            add constraint vehicles_ontrac_days_in_service_check
            check (
                ontrac_days_in_service is null
                or ontrac_days_in_service >= 0
            );
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conname = 'vehicles_record_source_check'
          and conrelid = 'public.vehicles'::regclass
    ) then
        alter table public.vehicles
            add constraint vehicles_record_source_check
            check (
                record_source in ('manual', 'ontrac')
            );
    end if;
end;
$$;

-- Record each uploaded GM OnTrac report and its processing outcome.
create table if not exists public.ontrac_import_batches (
    id uuid primary key default gen_random_uuid(),
    created_at timestamp with time zone not null default now(),
    completed_at timestamp with time zone,
    report_type text not null,
    original_file_name text not null,
    import_status text not null default 'uploaded',
    uploaded_by_user_id uuid,
    total_row_count integer not null default 0,
    inserted_vehicle_count integer not null default 0,
    updated_vehicle_count integer not null default 0,
    unmatched_row_count integer not null default 0,
    error_row_count integer not null default 0,
    notes text,

    constraint ontrac_import_batches_report_type_check
        check (
            report_type in (
                'in_service_list',
                'expiring_plates'
            )
        ),

    constraint ontrac_import_batches_status_check
        check (
            import_status in (
                'uploaded',
                'processing',
                'completed',
                'completed_with_errors',
                'failed'
            )
        ),

    constraint ontrac_import_batches_counts_check
        check (
            total_row_count >= 0
            and inserted_vehicle_count >= 0
            and updated_vehicle_count >= 0
            and unmatched_row_count >= 0
            and error_row_count >= 0
        ),

    constraint ontrac_import_batches_uploaded_by_user_id_fkey
        foreign key (uploaded_by_user_id)
        references public.app_users(id)
);

-- Preserve each source row for preview, matching, review, and audit.
create table if not exists public.ontrac_import_rows (
    id uuid primary key default gen_random_uuid(),

    batch_id uuid not null
        references public.ontrac_import_batches(id)
        on delete cascade,

    row_number integer not null,

    vin text,
    vin_last8 text,

    stock_number text,
    model_year integer,
    make text,
    model text,
    trim text,

    license_plate text,
    plate_expiration_date date,

    odometer integer,
    qualified_miles integer,
    days_in_service integer,

    program text,
    vehicle_status text,

    matched_vehicle_id uuid
        references public.vehicles(id),

    action_required text not null default 'review',
    proposed_action text,
    import_error text,
    row_processed boolean not null default false,

    constraint ontrac_import_rows_action_required_check
        check (
            action_required in (
                'review',
                'insert',
                'update',
                'retire_candidate',
                'plate_required',
                'error',
                'ignore'
            )
        ),

    constraint ontrac_import_rows_proposed_action_check
        check (
            proposed_action is null
            or proposed_action in (
                'insert',
                'update',
                'retire',
                'assign_plate',
                'none'
            )
        )
);

create index if not exists idx_ontrac_import_rows_batch
    on public.ontrac_import_rows(batch_id);

create index if not exists idx_ontrac_import_rows_vin
    on public.ontrac_import_rows(vin);

create index if not exists idx_ontrac_import_rows_last8
    on public.ontrac_import_rows(vin_last8);

-- Combined vehicle state for Fleet Administration and OnTrac Sync Center.
create or replace view public.v_admin_vehicle_master_state
with (security_invoker = true)
as
select
    v.id as vehicle_id,
    v.vin,
    v.vin_last8,
    v.stock_number,
    v.model_year,
    v.model,
    v.trim,
    v.fleet_type,
    v.status as vehicle_status,
    v.mileage as odometer,
    v.qualified_miles,
    v.ontrac_days_in_service,
    v.current_tag as license_plate,
    t.expires_at as plate_expiration_date,
    v.record_source,
    v.ontrac_first_seen_at,
    v.ontrac_last_seen_at,
    v.plate_sync_required,
    v.ctp_program_active,
    v.ctp_program_entered_at,
    v.ctp_entry_mileage,
    v.is_retired,
    v.retired_at,
    v.retirement_reason,
    v.location,
    v.notes
from public.vehicles v
left join public.tags t
    on t.tag_name = v.current_tag
   and t.status = 'active';

-- Configurable preferred and absolute CTP thresholds.
insert into public.admin_settings (
    setting_key,
    setting_value,
    description
)
values
    (
        'ctp_preferred_max_days',
        '0'::jsonb,
        'Preferred maximum number of days a vehicle should remain in CTP before review or replacement.'
    ),
    (
        'ctp_absolute_max_days',
        '0'::jsonb,
        'Absolute maximum number of days a vehicle may remain in CTP.'
    ),
    (
        'ctp_preferred_max_odometer',
        '0'::jsonb,
        'Preferred maximum actual vehicle odometer mileage before review or removal from CTP.'
    ),
    (
        'ctp_absolute_max_odometer',
        '0'::jsonb,
        'Absolute maximum actual vehicle odometer mileage permitted in CTP.'
    )
on conflict (setting_key) do nothing;

-- Single frontend-readable payload for the four CTP threshold values.
create or replace function public.get_ctp_threshold_settings_state()
returns jsonb
language sql
stable
as $$
    select jsonb_build_object(
        'ctp_preferred_max_days',
            coalesce((
                select (setting_value #>> '{}')::integer
                from public.admin_settings
                where setting_key = 'ctp_preferred_max_days'
            ), 0),

        'ctp_absolute_max_days',
            coalesce((
                select (setting_value #>> '{}')::integer
                from public.admin_settings
                where setting_key = 'ctp_absolute_max_days'
            ), 0),

        'ctp_preferred_max_odometer',
            coalesce((
                select (setting_value #>> '{}')::integer
                from public.admin_settings
                where setting_key = 'ctp_preferred_max_odometer'
            ), 0),

        'ctp_absolute_max_odometer',
            coalesce((
                select (setting_value #>> '{}')::integer
                from public.admin_settings
                where setting_key = 'ctp_absolute_max_odometer'
            ), 0)
    );
$$;
