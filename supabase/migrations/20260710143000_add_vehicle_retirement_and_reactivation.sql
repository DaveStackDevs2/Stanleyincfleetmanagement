alter table public.vehicles
    add column if not exists is_retired boolean not null default false,
    add column if not exists retired_at timestamp with time zone,
    add column if not exists retired_by_user_id uuid,
    add column if not exists retirement_reason text;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'vehicles_retired_by_user_id_fkey'
          and conrelid = 'public.vehicles'::regclass
    ) then
        alter table public.vehicles
            add constraint vehicles_retired_by_user_id_fkey
            foreign key (retired_by_user_id)
            references public.app_users(id);
    end if;
end;
$$;

create or replace function public.retire_vehicle_state(
    p_vehicle_id uuid,
    p_actor_user_id uuid default null,
    p_retirement_reason text default null
)
returns jsonb
language plpgsql
as $$
declare
    v_vehicle public.vehicles%rowtype;
begin
    select *
    into v_vehicle
    from public.vehicles
    where id = p_vehicle_id
    for update;

    if not found then
        raise exception 'Vehicle % not found.', p_vehicle_id;
    end if;

    if v_vehicle.is_retired then
        raise exception 'Vehicle % is already retired.', p_vehicle_id;
    end if;

    if p_retirement_reason is null
       or btrim(p_retirement_reason) = '' then
        raise exception 'Retirement reason is required.';
    end if;

    if p_actor_user_id is not null
       and not exists (
           select 1
           from public.app_users
           where id = p_actor_user_id
       ) then
        raise exception 'User % does not exist.', p_actor_user_id;
    end if;

    if exists (
        select 1
        from public.active_vehicle_assignments
        where vehicle_id = p_vehicle_id
          and is_active = true
    ) then
        raise exception 'Vehicle % has an active vehicle assignment.', p_vehicle_id;
    end if;

    if exists (
        select 1
        from public.vehicle_events
        where vehicle_id = p_vehicle_id
          and is_open = true
    ) then
        raise exception 'Vehicle % has an open vehicle event.', p_vehicle_id;
    end if;

    if exists (
        select 1
        from public.reservations
        where vehicle_id = p_vehicle_id
          and status is distinct from 'cancelled'
          and actual_return_datetime is null
    ) then
        raise exception 'Vehicle % has an open or upcoming reservation.', p_vehicle_id;
    end if;

    update public.vehicles
    set is_retired = true,
        retired_at = now(),
        retired_by_user_id = p_actor_user_id,
        retirement_reason = btrim(p_retirement_reason),
        status = 'retired',
        ctp_program_active = false
    where id = p_vehicle_id;

    return jsonb_build_object(
        'status', 'vehicle_retired',
        'vehicle_id', p_vehicle_id,
        'vin', v_vehicle.vin,
        'stock_number', v_vehicle.stock_number,
        'retirement_reason', btrim(p_retirement_reason),
        'retired_by_user_id', p_actor_user_id,
        'retired_at', now()
    );
end;
$$;

create or replace function public.reactivate_vehicle_state(
    p_vehicle_id uuid,
    p_actor_user_id uuid default null,
    p_reactivation_reason text default null
)
returns jsonb
language plpgsql
as $$
declare
    v_vehicle public.vehicles%rowtype;
begin
    select *
    into v_vehicle
    from public.vehicles
    where id = p_vehicle_id
    for update;

    if not found then
        raise exception 'Vehicle % not found.', p_vehicle_id;
    end if;

    if not v_vehicle.is_retired then
        raise exception 'Vehicle % is not retired.', p_vehicle_id;
    end if;

    if p_reactivation_reason is null
       or btrim(p_reactivation_reason) = '' then
        raise exception 'Reactivation reason is required.';
    end if;

    if p_actor_user_id is not null
       and not exists (
           select 1
           from public.app_users
           where id = p_actor_user_id
       ) then
        raise exception 'User % does not exist.', p_actor_user_id;
    end if;

    update public.vehicles
    set is_retired = false,
        retired_at = null,
        retired_by_user_id = null,
        retirement_reason = null,
        status = 'available'
    where id = p_vehicle_id;

    return jsonb_build_object(
        'status', 'vehicle_reactivated',
        'vehicle_id', p_vehicle_id,
        'vin', v_vehicle.vin,
        'stock_number', v_vehicle.stock_number,
        'reactivation_reason', btrim(p_reactivation_reason),
        'reactivated_by_user_id', p_actor_user_id,
        'reactivated_at', now()
    );
end;
$$;
