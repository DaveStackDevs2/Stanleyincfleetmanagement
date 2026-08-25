from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / 'frontend/src/App.tsx').read_text()
ADMIN = (ROOT / 'frontend/src/admin/PayTypeManagement.tsx').read_text()


def test_standalone_capacity_destination_is_removed():
    assert "ReservationCapacityManagement" not in APP
    assert "reservation-capacity" not in APP
    assert "title: 'Reservation Capacity'" not in APP
    assert not (ROOT / 'frontend/src/admin/ReservationCapacityManagement.tsx').exists()


def test_combined_surface_loads_existing_authoritative_states():
    assert "Rental Models &amp; Rates" in ADMIN
    assert "supabase.rpc('get_admin_rental_rate_cards_state')" in ADMIN
    assert "supabase.rpc('get_admin_rental_reservation_capacity_state')" in ADMIN
    assert "currentModels.set" in ADMIN and "capacityModels?.forEach" in ADMIN
    assert "No active Rental rate" in ADMIN
    assert "Not configured (unavailable)" in ADMIN


def test_model_actions_keep_engines_separate_and_history_manageable():
    for rpc in ('create_admin_rental_rate_card_state', 'update_admin_rental_rate_card_state', 'set_admin_rental_rate_card_enabled_state'):
        assert f"supabase.rpc('{rpc}'" in ADMIN
    for rpc in ('upsert_admin_rental_reservation_capacity_state', 'remove_admin_rental_reservation_capacity_state'):
        assert f"supabase.rpc('{rpc}'" in ADMIN
    assert "Inactive / Previous Rental Rate Cards" in ADMIN
    assert "vehicleClass:model.vehicleClass" in ADMIN
    assert "Pricing was saved, but Reservation Capacity was not" in ADMIN
    assert ADMIN.index("create_admin_rental_rate_card_state") < ADMIN.index("if (!edit && rateForm.saveCapacity)")
    assert "/^\\d+$/.test" in ADMIN  # includes zero and rejects capacity arithmetic/fractions


def test_backend_impact_is_rendered_without_recalculation():
    for field in ('impact.days', 'hard_reservation_conflicts', 'at_risk_quotes', 'reservation_count', 'reservation_overage', 'active_quote_count', 'combined_count', 'quote_pressure_overage'):
        assert field in ADMIN
    assert "Hard Reservation conflicts" in ADMIN
    assert "At-risk Quote pressure" in ADMIN
    assert "Quotes are non-binding" in ADMIN
    assert "reservationCount+" not in ADMIN and "activeQuoteCount+" not in ADMIN
