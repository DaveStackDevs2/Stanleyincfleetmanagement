from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260826223000_fleet_board_model_sort_order.sql"
BOARD = (ROOT / "frontend/src/fleet-board/FleetBoard.tsx").read_text()
SQL = MIGRATION.read_text()


def test_fleet_board_capacity_uses_current_rate_card_sort_order():
    capacity = SQL.split("create or replace function public.get_fleet_board_capacity_state", 1)[1].split(
        "alter function public.get_fleet_board_capacity_state", 1
    )[0]
    assert "from public.rental_rate_rules r" in capacity
    assert "r.is_active = true" in capacity
    assert "r.effective_from <= clock_timestamp()" in capacity
    assert "coalesce(r.sort_order, 2147483647)" in capacity
    assert "order by coalesce(r.sort_order, 2147483647), lower(l.vehicle_class), l.vehicle_class" in capacity
    assert "order by l.vehicle_class" not in capacity


def test_vehicle_groups_follow_same_model_sort_order_before_model_name():
    board_state = SQL.split("create or replace function public.get_fleet_board_state", 1)[1]
    vehicles = board_state.split("'vehicles',", 1)[1].split("'reservations',", 1)[0]
    assert "from public.rental_rate_rules r" in vehicles
    assert "coalesce(r.sort_order, 2147483647)" in vehicles
    assert vehicles.index("coalesce(r.sort_order, 2147483647)") < vehicles.index("lower(coalesce(v.model, ''))")


def test_fleet_board_security_boundary_is_preserved():
    lowered = SQL.lower()
    for name in ("get_fleet_board_capacity_state", "get_fleet_board_state"):
        assert f"alter function public.{name}(timestamptz, timestamptz) owner to postgres" in lowered
        assert f"revoke all on function public.{name}(timestamptz, timestamptz) from public, anon" in lowered
        assert f"grant execute on function public.{name}(timestamptz, timestamptz) to postgres, authenticated, service_role" in lowered
    assert lowered.count("security definer") == 2
    assert lowered.count("set search_path to ''") == 2


def test_zero_capacity_visibility_is_display_only_and_user_controlled():
    assert "const [hideZeroCapacity, setHideZeroCapacity] = useState(false)" in BOARD
    assert "capacity.dailyLimit > 0" in BOARD
    assert "Hide 0 capacity" in BOARD
    assert "aria-pressed={hideZeroCapacity}" in BOARD
    assert "visibleCapacities.map" in BOARD
    assert "visibleCapacities.length === 0" in BOARD
    assert "upsert_admin_rental_reservation_capacity_state" not in BOARD
    assert "rental_model_limits" not in BOARD


def test_no_capacity_or_pricing_business_rules_change_in_frontend():
    assert "get_fleet_board_capacity_state" in BOARD
    assert "get_rental_reservation_capacity_state" not in BOARD
    assert ".insert(" not in BOARD
    assert ".update(" not in BOARD
    assert ".delete(" not in BOARD
