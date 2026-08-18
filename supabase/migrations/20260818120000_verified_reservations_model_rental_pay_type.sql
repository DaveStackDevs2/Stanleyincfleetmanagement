-- Record the already-verified live Reservations vehicle helper repair and the
-- transportation/pay-type pricing-agreement invariant. This migration is data-free.

create or replace function public.create_vehicle_state(
    p_vin text,
    p_stock_number text,
    p_model text,
    p_fleet_type text,
    p_mileage integer,
    p_current_tag text,
    p_fleet_conversion_type text,
    p_location text default null,
    p_notes text default null,
    p_status text default 'available',
    p_recon_status text default 'clean'
) returns jsonb
language plpgsql
security invoker
set search_path to ''
as $function$
declare
    v_id uuid;
begin
    if p_vin is null or btrim(p_vin) = '' then raise exception 'vin cannot be blank'; end if;
    if char_length(btrim(p_vin)) < 8 then raise exception 'vin must be at least 8 characters'; end if;
    if p_stock_number is null or btrim(p_stock_number) = '' then raise exception 'stock_number cannot be blank'; end if;
    if p_model is null or btrim(p_model) = '' then raise exception 'model cannot be blank'; end if;
    if p_fleet_type is null or btrim(p_fleet_type) = '' then raise exception 'fleet_type cannot be blank'; end if;
    if p_current_tag is null or btrim(p_current_tag) = '' then raise exception 'current_tag cannot be blank'; end if;
    if p_fleet_conversion_type is null or btrim(p_fleet_conversion_type) = '' then raise exception 'fleet_conversion_type cannot be blank'; end if;
    if p_status is null or btrim(p_status) = '' then raise exception 'status cannot be blank'; end if;
    if p_recon_status is null or btrim(p_recon_status) = '' then raise exception 'recon_status cannot be blank'; end if;
    if p_mileage is null or p_mileage < 0 then raise exception 'mileage must be non-negative'; end if;
    if exists (select 1 from public.vehicles where vin = p_vin) then raise exception 'vin % already exists', p_vin; end if;

    insert into public.vehicles (
        vin, vin_last8, stock_number, model, fleet_type, status, mileage,
        recon_status, current_tag, fleet_conversion_type, location, notes
    ) values (
        p_vin, right(btrim(p_vin), 8), p_stock_number, p_model, p_fleet_type,
        p_status, p_mileage, p_recon_status, p_current_tag,
        p_fleet_conversion_type, p_location, p_notes
    ) returning id into v_id;

    return jsonb_build_object(
        'status', 'vehicle_created', 'vehicle_id', v_id,
        'vin', p_vin, 'stock_number', p_stock_number
    );
end;
$function$;

alter function public.create_vehicle_state(text,text,text,text,integer,text,text,text,text,text,text) owner to postgres;
revoke all on function public.create_vehicle_state(text,text,text,text,integer,text,text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.create_vehicle_state(text,text,text,text,integer,text,text,text,text,text,text) to service_role;

create or replace function public.enforce_pricing_agreement_transportation_pay_type_state()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
    v_transportation_type text;
    v_pay_type text;
begin
    if new.reservation_id is not null then
        select r.reservation_type into v_transportation_type
        from public.reservations r where r.id = new.reservation_id;
    elsif new.quote_id is not null then
        select q.reservation_type into v_transportation_type
        from public.quotes q where q.id = new.quote_id;
    else
        select r.reservation_type into v_transportation_type
        from public.reservations r
        where r.transportation_event_id = new.transportation_event_id;
    end if;

    select p.pay_type into v_pay_type
    from public.pay_type_rules p where p.id = new.pay_type_rule_id;

    if nullif(btrim(v_transportation_type), '') is null then
        raise exception 'Transportation type could not be resolved' using errcode = '22023';
    end if;
    if nullif(btrim(v_pay_type), '') is null then
        raise exception 'Pay type could not be resolved' using errcode = '22023';
    end if;
    if lower(btrim(v_transportation_type)) = 'rental' and lower(btrim(v_pay_type)) <> 'rental' then
        raise exception 'Rental workflow requires the Rental pay type' using errcode = '22023';
    end if;
    if lower(btrim(v_transportation_type)) <> 'rental' and lower(btrim(v_pay_type)) = 'rental' then
        raise exception 'Rental pay type requires a Rental workflow' using errcode = '22023';
    end if;
    return new;
end;
$function$;

alter function public.enforce_pricing_agreement_transportation_pay_type_state() owner to postgres;
revoke all on function public.enforce_pricing_agreement_transportation_pay_type_state() from public, anon, authenticated, service_role;

drop trigger if exists trg_rental_pricing_agreements_transportation_pay_type on public.rental_pricing_agreements;
create trigger trg_rental_pricing_agreements_transportation_pay_type
before insert or update of pay_type_rule_id, reservation_id, quote_id, transportation_event_id
on public.rental_pricing_agreements
for each row execute function public.enforce_pricing_agreement_transportation_pay_type_state();
