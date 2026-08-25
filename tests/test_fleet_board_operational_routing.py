from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260824185322_fleet_board_operational_routing.sql"
BOARD = (ROOT / "frontend/src/fleet-board/FleetBoard.tsx").read_text()
APP = (ROOT / "frontend/src/App.tsx").read_text()
RESERVATIONS = (ROOT / "frontend/src/reservations/ReservationsWorkspace.tsx").read_text()
EDIT = (ROOT / "frontend/src/reservations/EditReservationWorkspace.tsx").read_text()
PICKUP = (ROOT / "frontend/src/reservations/PickupWorkspace.tsx").read_text()
BILLING = (ROOT / "frontend/src/billing/BillingWorkspace.tsx").read_text()
SQL = MIGRATION.read_text()


def test_existing_board_rpc_is_extended_with_preserved_boundary():
    assert SQL.lower().count("create or replace function public.get_fleet_board_state") == 1
    assert "security definer" in SQL.lower()
    assert "set search_path to ''" in SQL.lower()
    assert "interval '32 days'" in SQL
    assert "au.is_active = true" in SQL
    assert "owner to postgres" in SQL.lower()
    assert "to postgres, authenticated, service_role" in SQL.lower()
    assert " to anon" not in SQL.lower()


def test_board_reservations_are_actionable_rental_or_loaner_only():
    assert "in ('rental', 'loaner')" in SQL
    assert "r.vehicle_id is null" in SQL
    assert "<> 'cancelled'" in SQL
    assert "r.start_date < p_range_end" in SQL
    assert "r.expected_return_datetime > p_range_start" in SQL
    assert "te.status = 'active'" in SQL
    assert "a.is_active = true" in SQL
    assert "a.pricing_started_at is null" in SQL


def test_existing_payloads_and_rental_capacity_source_are_preserved():
    for payload in ("'vehicles'", "'reservations'", "'capacities'", "'assignments'", "'pay_type_colors'"):
        assert payload in SQL
    assert "from public.rental_model_limits" in SQL
    assert "item.reservationType === 'rental'" in BOARD
    assert "loaner_model_limits" not in SQL + BOARD


def test_board_displays_both_model_level_types_and_routes_actions_only():
    assert "reservationType !== 'rental' && reservationType !== 'loaner'" in BOARD
    assert "Pre-pickup Reservations" in BOARD
    assert "Rental' : 'Loaner'" in BOARD
    assert "No VIN assigned" in BOARD
    assert "onOpenReservation('edit', item.id)" in BOARD
    assert "onOpenReservation('pickup', item.id)" in BOARD
    reads_only = BOARD.replace("supabase.rpc('get_fleet_board_state'", "").replace("supabase.rpc('get_fleet_board_capacity_state'", "")
    assert ".rpc(" not in reads_only


def test_authoritative_one_time_edit_and_pickup_handoffs():
    assert "initialReservationId={editReservationId}" in RESERVATIONS
    assert "initialReservationId={pickupReservationId}" in RESERVATIONS
    assert "items.find(item=>item.reservationId===initialReservationId)" in EDIT
    assert "authoritativeLoadVersion" in EDIT
    assert "onInitialReservationHandled()" in EDIT
    assert "if(error)" in EDIT and "return null" in EDIT
    assert "handledInitialReservationId" in EDIT
    assert "items.find(item=>item.reservationId===initialReservationId)" in PICKUP


def test_assignment_uses_existing_billing_handoff_without_mutation():
    assert "export const ACTIVE_CASE_STORAGE_KEY='billing.activeTransportationEventId'" in BILLING
    assert "ACTIVE_CASE_STORAGE_KEY" in APP
    assert "window.sessionStorage.setItem(ACTIVE_CASE_STORAGE_KEY" in APP
    assert "setPage('dashboard')" in APP
    assert "onOpenBilling(item.id)" in BOARD


def test_day_reservations_use_timeline_lanes_and_week_stays_day_bucketed():
    assert "function reservationLanes" in BOARD
    assert "Math.max(Date.parse(item.startsAt), start)" in BOARD
    assert "Math.min(Date.parse(item.endsAt), end)" in BOARD
    assert "laneEnds.findIndex(laneEnd => laneEnd <= visibleStart)" in BOARD
    assert "left: ((visibleStart - start) / duration) * 100" in BOARD
    assert "width: ((visibleEnd - visibleStart) / duration) * 100" in BOARD
    assert "reservationLanes(reservations, timelineStart, timelineEnd)" in BOARD
    assert "className={`reservation-block day-reservation" in BOARD
    assert "top: `calc(5px + ${item.lane} * 76px)`" in BOARD
    week_branch = BOARD.split(": <div className=\"board-days\">{days.map(day", 1)[1]
    assert "reservations.filter(item => overlaps(item.startsAt, item.endsAt, day))" in week_branch


def test_empty_slot_context_fails_closed_by_exact_fleet_type_and_uses_safe_fields():
    assert "timelineHover.quarter * 15" in BOARD
    assert "closest('.assignment-block')" in BOARD
    assert "fleetType.trim().toLowerCase()" in BOARD
    assert "slotFleetType === 'rental'" in BOARD
    assert "? ['rental', 'loaner']" in BOARD
    assert "slotFleetType === 'loaner' ? ['loaner'] : []" in BOARD
    assert "slotReservationTypes.length === 0" in BOARD
    assert "This fleet type is not eligible for intake routing." in BOARD
    assert "includes('rental')" not in BOARD
    assert "vehicleModel: slotChoice.vehicle.model" in BOARD
    assert "startAt: slotChoice.startsAt" in BOARD
    assert "stock {slotChoice.vehicle.stockNumber}" in BOARD
    assert "VIN {slotChoice.vehicle.stockNumber}" not in BOARD
    assert "no VIN will be assigned" in BOARD
    create_context = BOARD.split("onCreateIntake({", 1)[1].split("})", 1)[0]
    assert "vehicleId" not in create_context and "vehicle_id" not in create_context
    assert "expectedReturn" not in create_context


def test_create_context_waits_for_authoritative_intake_and_keeps_existing_engines():
    assert "if (!intake || loading || !navigationContext) return" in RESERVATIONS
    assert "intake.rateCards.some" in RESERVATIONS
    assert "setExpectedReturn('')" in RESERVATIONS
    assert "onNavigationContextHandled?.()" in RESERVATIONS
    for rpc in ("create_quote_with_pricing_agreement_state", "create_reservation_with_pricing_agreement_state", "create_walk_in_with_pricing_agreement_state"):
        assert rpc in RESERVATIONS
    assert "setPickupReservationId(reservationId)" in RESERVATIONS


def test_no_calendar_resurrection_or_frontend_mutation_arithmetic():
    changed = SQL + BOARD + APP
    for artifact in ("vehicle_calendar", "calendar_events", "create_calendar"):
        assert artifact not in changed.lower()
    for mutation in (".insert(", ".update(", ".delete(", "activate_pricing_agreement_pickup_state"):
        assert mutation not in BOARD
