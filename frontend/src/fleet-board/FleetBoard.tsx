import { useEffect, useMemo, useState, type CSSProperties } from 'react'
import { supabase } from '../lib/supabase'
import './FleetBoard.css'

type ViewMode = 'day' | 'week'
type FleetFilter = 'all' | 'rental' | 'loaner'

type Vehicle = {
  id: string
  stockNumber: string
  model: string
  fleetType: string
  status: string
  location: string
}

type Assignment = {
  id: string
  vehicleId: string
  sourceType: string
  status: string
  startsAt: string
  endsAt: string
  payType: string
  hasConflict: boolean
}

type Reservation = {
  id: string
  requestedModel: string
  startsAt: string
  endsAt: string
  status: string
}

type Capacity = { model: string; dailyLimit: number }

const startOfDay = (date: Date) => new Date(date.getFullYear(), date.getMonth(), date.getDate())
const addDays = (date: Date, days: number) => {
  const result = new Date(date)
  result.setDate(result.getDate() + days)
  return result
}
const dayKey = (date: Date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
const dateFromInput = (value: string): Date | null => {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
  if (!match) return null
  const year = Number(match[1])
  const month = Number(match[2]) - 1
  const day = Number(match[3])
  const result = new Date(year, month, day)
  return result.getFullYear() === year && result.getMonth() === month && result.getDate() === day
    ? result
    : null
}
const textValue = (value: unknown, fallback = '') => typeof value === 'string' ? value : fallback
const dateValue = (value: unknown) => typeof value === 'string' && !Number.isNaN(Date.parse(value)) ? value : null
const recordValue = (value: unknown): Record<string, unknown> | null => value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null

function vehicleFrom(value: unknown): Vehicle | null {
  const row = recordValue(value)
  if (!row) return null
  const id = textValue(row.id)
  if (!id) return null
  return {
    id,
    stockNumber: textValue(row.stock_number, 'Unnumbered'),
    model: textValue(row.model, 'Unknown model'),
    fleetType: textValue(row.fleet_type, 'Unassigned'),
    status: textValue(row.status, 'Unknown'),
    location: textValue(row.location),
  }
}

function assignmentFrom(value: unknown): Assignment | null {
  const row = recordValue(value)
  if (!row) return null
  const id = textValue(row.transportation_event_id)
  const vehicleId = textValue(row.vehicle_id)
  const startsAt = dateValue(row.actual_out_at) ?? dateValue(row.current_billing_start_time)
  const endsAt = dateValue(row.actual_in_at) ?? dateValue(row.expected_return_at) ?? dateValue(row.current_billing_end_time)
  if (!id || !vehicleId || !startsAt || !endsAt) return null
  return {
    id,
    vehicleId,
    sourceType: textValue(row.source_type, 'Transportation event'),
    status: textValue(row.transportation_event_status, 'Unknown'),
    startsAt,
    endsAt,
    payType: textValue(row.current_billing_pay_type, 'Pay type not set'),
    hasConflict: Boolean(row.current_conflict_id) && row.current_conflict_is_resolved === false,
  }
}

function reservationFrom(value: unknown): Reservation | null {
  const row = recordValue(value)
  if (!row) return null
  const id = textValue(row.id)
  const startsAt = dateValue(row.start_date)
  const endsAt = dateValue(row.expected_return_datetime)
  if (!id || !startsAt || !endsAt || textValue(row.vehicle_id)) return null
  return { id, startsAt, endsAt, requestedModel: textValue(row.requested_model, 'Model not set'), status: textValue(row.status, 'Unknown') }
}

function capacityFrom(value: unknown): Capacity | null {
  const row = recordValue(value)
  if (!row || typeof row.daily_limit !== 'number') return null
  const model = textValue(row.vehicle_class)
  return model ? { model, dailyLimit: row.daily_limit } : null
}

export function FleetBoard({ onBack }: { onBack: () => void }) {
  const [view, setView] = useState<ViewMode>('day')
  const [date, setDate] = useState(() => startOfDay(new Date()))
  const [filter, setFilter] = useState<FleetFilter>('all')
  const [vehicles, setVehicles] = useState<Vehicle[]>([])
  const [assignments, setAssignments] = useState<Assignment[]>([])
  const [reservations, setReservations] = useState<Reservation[]>([])
  const [capacities, setCapacities] = useState<Capacity[]>([])
  const [loading, setLoading] = useState(true)
  const [loadFailed, setLoadFailed] = useState(false)

  const rangeStart = view === 'day' ? date : addDays(date, -date.getDay())
  const rangeEnd = addDays(rangeStart, view === 'day' ? 1 : 7)
  const rangeStartIso = rangeStart.toISOString()
  const rangeEndIso = rangeEnd.toISOString()
  const days = Array.from({ length: view === 'day' ? 1 : 7 }, (_, index) => addDays(rangeStart, index))

  useEffect(() => {
    let current = true
    async function loadBoard() {
      setLoading(true)
      setLoadFailed(false)
      const [vehicleResult, assignmentResult, reservationResult, capacityResult] = await Promise.all([
        supabase.from('vehicles').select('id,stock_number,model,fleet_type,status,location').order('fleet_type').order('model').order('stock_number'),
        supabase.from('v_transportation_event_unified_operational_state').select('transportation_event_id,vehicle_id,source_type,transportation_event_status,actual_out_at,actual_in_at,expected_return_at,current_billing_start_time,current_billing_end_time,current_billing_pay_type,current_conflict_id,current_conflict_is_resolved'),
        supabase.from('reservations').select('id,vehicle_id,start_date,expected_return_datetime,status,requested_model').lt('start_date', rangeEndIso).gt('expected_return_datetime', rangeStartIso),
        supabase.from('rental_model_limits').select('vehicle_class,daily_limit').order('vehicle_class'),
      ])
      if (!current) return
      if (vehicleResult.error || assignmentResult.error || reservationResult.error || capacityResult.error) {
        setLoadFailed(true)
        setVehicles([])
        setAssignments([])
        setReservations([])
        setCapacities([])
      } else {
        setVehicles((vehicleResult.data ?? []).map(vehicleFrom).filter((item): item is Vehicle => item !== null))
        setAssignments((assignmentResult.data ?? []).map(assignmentFrom).filter((item): item is Assignment => item !== null))
        setReservations((reservationResult.data ?? []).map(reservationFrom).filter((item): item is Reservation => item !== null))
        setCapacities((capacityResult.data ?? []).map(capacityFrom).filter((item): item is Capacity => item !== null))
      }
      setLoading(false)
    }
    void loadBoard()
    return () => { current = false }
  }, [rangeStartIso, rangeEndIso])

  const visibleVehicles = useMemo(() => vehicles.filter(vehicle => filter === 'all' || vehicle.fleetType.toLowerCase().includes(filter)), [filter, vehicles])
  const vehicleGroups = useMemo(() => {
    const groups = new Map<string, Vehicle[]>()
    visibleVehicles.forEach(vehicle => {
      const label = `${vehicle.fleetType} · ${vehicle.model}`
      groups.set(label, [...(groups.get(label) ?? []), vehicle])
    })
    return [...groups.entries()]
  }, [visibleVehicles])
  const overlaps = (startsAt: string, endsAt: string, day: Date) => new Date(startsAt) < addDays(day, 1) && new Date(endsAt) > day

  return <main className="fleet-board">
    <header className="fleet-board-title">
      <div><p className="eyebrow">PRIMARY WORKSPACE</p><h1>Fleet Board</h1><p>Existing model-level reservations and VIN-level transportation assignments.</p></div>
      <button type="button" onClick={onBack}>Admin Console</button>
    </header>
    <section className="fleet-board-toolbar" aria-label="Fleet Board controls">
      <div className="board-segmented">{(['all', 'rental', 'loaner'] as FleetFilter[]).map(item => <button type="button" className={filter === item ? 'active' : ''} onClick={() => setFilter(item)} key={item}>{item === 'all' ? 'All vehicles' : `${item[0].toUpperCase()}${item.slice(1)}s`}</button>)}</div>
      <div className="board-segmented"><button type="button" className={view === 'day' ? 'active' : ''} onClick={() => setView('day')}>Day</button><button type="button" className={view === 'week' ? 'active' : ''} onClick={() => setView('week')}>Week</button></div>
      <button type="button" aria-label="Previous period" onClick={() => setDate(addDays(date, view === 'day' ? -1 : -7))}>‹</button>
      <input aria-label="Jump to date" type="date" value={dayKey(date)} onChange={event => { const selectedDate = dateFromInput(event.target.value); if (selectedDate) setDate(selectedDate) }} />
      <button type="button" aria-label="Next period" onClick={() => setDate(addDays(date, view === 'day' ? 1 : 7))}>›</button>
      <button type="button" className="primary-action" onClick={() => setDate(startOfDay(new Date()))}>Today</button>
    </section>
    {loadFailed && <div className="board-message error-message" role="alert">Fleet Board data could not be loaded. Access to one or more existing operational sources may need review.</div>}
    {loading ? <div className="board-message" role="status">Loading Fleet Board…</div> : !loadFailed && <div className="fleet-board-scroll">
      <div className="fleet-board-grid" style={{ '--board-days': days.length } as CSSProperties}>
        <div className="board-corner">Resource</div>
        <div className="board-day-head">{days.map(day => <button type="button" key={dayKey(day)} onClick={() => { setDate(day); setView('day') }}>{day.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' })}</button>)}</div>
        <div className="board-group-title">Reservation Capacity</div>
        {capacities.map(capacity => <div className="board-row capacity-row" key={capacity.model}>
          <div className="board-resource"><strong>{capacity.model}</strong><small>Daily limit {capacity.dailyLimit}</small></div>
          <div className="board-days">{days.map(day => { const booked = reservations.filter(item => item.status !== 'cancelled' && item.requestedModel === capacity.model && overlaps(item.startsAt, item.endsAt, day)); return <div className="board-day" key={dayKey(day)}><strong>{booked.length} / {capacity.dailyLimit}</strong>{booked.map(item => <span className="reservation-block" title={`Reservation · ${item.status}`} key={item.id}>{item.status}</span>)}</div> })}</div>
        </div>)}
        {capacities.length === 0 && <div className="board-empty">No reservation capacity records are available.</div>}
        {vehicleGroups.map(([label, groupVehicles]) => <section className="board-group" key={label}>
          <h2 className="board-group-title">{label}</h2>
          {groupVehicles.map(vehicle => <div className="board-row" key={vehicle.id}>
            <div className="board-resource"><strong>{vehicle.stockNumber}</strong><span>{vehicle.model}</span><small>{vehicle.status}{vehicle.location ? ` · ${vehicle.location}` : ''}</small></div>
            <div className="board-days">{days.map(day => <div className="board-day" key={dayKey(day)}>{assignments.filter(item => item.vehicleId === vehicle.id && overlaps(item.startsAt, item.endsAt, day)).map(item => <article className={`assignment-block${item.hasConflict ? ' conflict' : ''}`} title={`${item.sourceType} · ${item.status}`} key={item.id}><strong>{item.payType}</strong><span>{new Date(item.startsAt).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}–{new Date(item.endsAt).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}</span></article>)}</div>)}</div>
          </div>)}
        </section>)}
      </div>
    </div>}
    <p className="fleet-board-note">Read-only foundation: operational changes continue through existing reservation, transportation-event, assignment, billing, and conflict workflows.</p>
  </main>
}
