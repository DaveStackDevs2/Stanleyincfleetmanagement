import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESERVATIONS = (ROOT / "frontend/src/reservations/ReservationsWorkspace.tsx").read_text()
PICKUP = (ROOT / "frontend/src/reservations/PickupWorkspace.tsx").read_text()


def test_walk_in_uses_existing_rpc_and_authoritative_identifier_handoff():
    assert "create_walk_in_with_pricing_agreement_state" in RESERVATIONS
    walk_in_success = RESERVATIONS.split("else if (workflow === 'walk_in')", 1)[1].split(
        "setBusy(false)", 1
    )[0]
    assert "record(data)?.reservation_id" in walk_in_success
    assert "authoritativeUuid" in walk_in_success
    assert "await load()" in walk_in_success
    assert "setPickupReservationId(reservationId)" in walk_in_success
    assert "setWorkflow('pickup')" in walk_in_success
    assert "initialReservationId={pickupReservationId}" in RESERVATIONS


def test_pickup_handoff_only_selects_authoritative_loaded_item():
    assert "initialReservationId?:string|null" in PICKUP
    assert "get_pricing_agreement_pickup_state" in PICKUP
    handoff = PICKUP.split("useEffect(()=>{if(loading||!initialReservationId", 1)[1].split(
        "const activate=", 1
    )[0]
    assert "items.find(item=>item.reservationId===initialReservationId)" in handoff
    assert "setReservationId(authoritativeItem.reservationId)" in handoff
    assert "setReservationId('')" in handoff
    assert "not present in Pickup" in handoff
    assert "setVehicleId('')" in handoff
    assert "setVehicleId(authoritativeItem" not in handoff


def test_activation_remains_pickup_owned_and_never_automatic():
    assert "activate_pricing_agreement_pickup_state" not in RESERVATIONS
    assert PICKUP.count("activate_pricing_agreement_pickup_state") == 1
    assert "onSubmit={activate}" in PICKUP
    assert "select an authoritative ready vehicle" in PICKUP


def test_walk_in_preflights_loaner_ro_and_daily_only_before_rpc():
    validation = RESERVATIONS.split("const validate = () =>", 1)[1].split(
        "const submit =", 1
    )[0]
    assert "workflow === 'walk_in' && plan !== 'daily'" in validation
    assert "Weekly and monthly pickup billing is not implemented yet." in validation
    assert "workflow === 'walk_in' && reservationType === 'loaner' && !roNumber.trim()" in validation
    assert "Loaner Walk-in requires an RO number" in validation
    assert "reservationType === 'rental' && !roNumber.trim()" not in validation
    assert RESERVATIONS.index("const validation = validate()") < RESERVATIONS.index(
        "create_walk_in_with_pricing_agreement_state"
    )


def test_quote_and_reservation_paths_keep_generic_result_behavior():
    assert "workflow === 'quote'" in RESERVATIONS
    assert "workflow === 'reservation' ? 'create_reservation_with_pricing_agreement_state'" in RESERVATIONS
    assert "else if (await load()) setResult(record(data))" in RESERVATIONS
    assert "Reservations update complete" in RESERVATIONS


def test_no_frontend_business_arithmetic_or_new_backend_checkpoint():
    combined = RESERVATIONS + PICKUP
    assert ".from(" not in combined
    assert not re.search(r"(?:daily_rate|subtotal|tax_rate|tax_amount|total)\s*[*/]", combined)
    migrations = sorted((ROOT / "supabase/migrations").glob("*.sql"))
    assert migrations[-1].name == "20260821193000_reconcile_rental_loaner_pickup_workflows.sql"
