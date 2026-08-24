from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / 'supabase/migrations/20260821193000_reconcile_rental_loaner_pickup_workflows.sql').read_text()
LOWER = SQL.lower()
PICKUP = LOWER.split('create or replace function public.activate_pricing_agreement_pickup_state', 1)[1]
UI = (ROOT / 'frontend/src/reservations/PickupWorkspace.tsx').read_text()


def test_one_way_candidate_and_assignment_contracts():
    assert "v_reservation_type is null or v_vehicle_type is null" in LOWER
    assert "v_reservation_type='rental' and v_vehicle_type<>'rental'" in LOWER
    assert "v_reservation_type not in ('rental','loaner')" in LOWER
    assert "lower(btrim(r.reservation_type))='rental' and lower(btrim(v.fleet_type))='rental'" in LOWER
    assert "lower(btrim(r.reservation_type))='loaner' and lower(btrim(v.fleet_type)) in ('loaner','rental')" in LOWER
    assert 'v.model = r.requested_model' in LOWER and 'v.is_retired = false' in LOWER
    assert 'with (security_invoker=true)' in LOWER
    assert "lower(btrim(vc.fleet_type))='loaner' then 1 else 2" in LOWER


def test_loaner_ro_fails_before_continuity():
    ro = LOWER.index("v_reservation_type='loaner' and nullif(btrim(v_reservation.ro_number),'') is null")
    continuity = LOWER.index('public.start_vehicle_use_state')
    assert ro < continuity
    assert 'loaner pickup requires a repair-order number before vehicle assignment' in LOWER
    assert "using errcode='22023'" in LOWER[ro:continuity]
    assert "v_reservation_type='rental'" not in LOWER[ro:continuity]


def test_activation_branches_rental_and_loaner_authoritatively():
    assert PICKUP.count("if v_reservation_type='rental' then") == 2
    assert PICKUP.count('get_billing_preview_state(v_reservation.transportation_event_id,clock_timestamp())') == 2
    assert PICKUP.count('get_billing_preview_state(v_reservation.transportation_event_id,v_reservation.expected_return_datetime)') == 3
    rental = PICKUP[PICKUP.index("if v_reservation_type='rental' then", PICKUP.index('update public.rental_pricing_agreements')):]
    loaner = rental[rental.index('else'):rental.index('end if;', rental.index('else'))]
    assert 'update public.billing_lines set amount=' in rental
    assert 'ensure_tax_child_line_state' in rental
    assert 'get_rental_payment_state' in rental
    assert 'get_rental_payment_state' not in loaner
    assert 'expected_return_datetime' not in loaner
    assert 'clock_timestamp()' in loaner
    assert "'reservation_type',v_reservation_type" in PICKUP


def test_security_boundaries_are_preserved():
    assert 'security definer set search_path to \'\'' in PICKUP
    assert 'revoke all on function public.start_reservation_vehicle_use_state(uuid,uuid,timestamptz) from public,anon,authenticated' in LOWER
    assert 'grant execute on function public.start_reservation_vehicle_use_state(uuid,uuid,timestamptz) to postgres,service_role' in LOWER
    assert 'revoke all on function public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) from public,anon' in LOWER
    assert 'grant execute on function public.activate_pricing_agreement_pickup_state(uuid,uuid,timestamptz,integer) to authenticated,service_role' in LOWER


def test_frontend_separates_authoritative_rental_and_loaner_results():
    assert "text(activation.reservation_type).trim().toLowerCase()" in UI
    assert "reservationType==='loaner'" in UI and "reservationType!=='rental'" in UI
    assert 'LOANER PICKUP COMPLETE' in UI and 'RENTAL PICKUP COMPLETE' in UI
    loaner = UI[UI.index("if(reservationType==='loaner')"):UI.index("if(reservationType!=='rental')")]
    assert 'parsePayment' not in loaner
    assert 'Mark Paid in Full' not in loaner
    assert 'Not Paid' not in loaner and 'Paid in Full' not in loaner
    assert 'Mark billed through' in loaner and 'RO number' in loaner
    assert 'Rental-fleet fallback' in UI
    assert 'Loaner pickup requires an RO number' in UI
    for forbidden in ('parseFloat', 'toFixed', ".from('billing_lines')"):
        assert forbidden not in UI


def test_loaner_contract_days_accepts_authoritative_numeric_value():
    loaner = UI[UI.index("if(reservationType==='loaner')"):UI.index("if(reservationType!=='rental')")]
    assert "contractDaysText(preview.contract_days)||'Unavailable'" in loaner
    assert "text(preview.contract_days)" not in loaner
    assert "typeof v==='number'&&Number.isFinite(v)?String(v)" in UI
    assert "typeof v==='string'&&/^\\d+$/.test(v.trim())?v.trim():''" in UI
