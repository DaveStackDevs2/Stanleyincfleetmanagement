import { useEffect, useMemo, useState, type CSSProperties } from 'react'
import { supabase } from '../lib/supabase'

type ViewMode = 'day' | 'week'
type FleetFilter = 'all' | 'rental' | 'loaner'

type Vehicle = {
  id: string
  stockNumber: string
  vin: string
  year: number | null
  make: string
  model: string
  fleetType: string
  status: string
  location: string
}

type OperationalEvent = {
  id: string
  vehicleId: string | null
  sourceType: string
  sourceId: string | null
  status: string
  startsAt: string
  endsAt: string
  payType: string
  hasConflict: boolean
  isOpen: boolean
}

type CreateTarget = { vehicle: Vehicle | null; startsAt: Date } | null

const DAY_MS = 86_400_000
const startOfDay = (date: Date) => new Date(date.getFullYear(), date.getMonth(), date.getDate())
const addDays = (date: Date, days: number) => new Date(date.getTime() + days * DAY_MS)
const isoDay = (date: Date) => date.toISOString().slice(0, 10)
const asText = (value: unknown, fallback = '') => typeof value === 'string' ? value : fallback
const asDate = (value: unknown) => typeof value === 'string' && !Number.isNaN(Date.parse(value)) ? value : null

const normalizeVehicle = (row: Record<string, unknown>): Vehicle => ({
  id: asText(row.id),
  stockNumber: asText(row.stock_number, asText(row.unit_number, 'Unnumbered')),
  vin: asText(row.vin),
  year: typeof row.year === 'number' ? row.year : typeof row.model_year === 'number' ? row.model_year : null,
  make: asText(row.make),
  model: asText(row.model, 'Unknown model'),
  fleetType: asText(row.fleet_type, 'Unassigned'),
  status: asText(row.status, 'Unknown'),
  location: asText(row.location),
})

const normalizeEvent = (row: Record<string, unknown>): OperationalEvent | null => {
  const startsAt = asDate(row.actual_out_at) ?? asDate(row.current_billing_start_time) ?? asDate(row.updated_at)
  const endsAt = asDate(row.actual_in_at) ?? asDate(row.expected_return_at) ?? asDate(row.current_billing_end_time)
  const id = asText(row.transportation_event_id)
  if (!id || !startsAt || !endsAt) return null

  return {
    id,
    vehicleId: asText(row.vehicle_id) || null,
    sourceType: asText(row.source_type, 'transportation'),
    sourceId: asText(row.source_id) || null,
    status: asText(row.transportation_event_status, 'open'),
    startsAt,
    endsAt,
    payType: asText(row.current_billing_pay_type, 'Unassigned pay type'),
    hasConflict: Boolean(row.current_conflict_id) && row.current_conflict_is_resolved !== true,
    isOpen: row.vehicle_event_is_open === true || !row.actual_in_at,
  }
}

const eventColor = (event: OperationalEvent) => {
  if (event.hasConflict) return { background: '#b42318', color: '#fff' }
  const key = event.payType.toLowerCase()
  if (key.includes('warranty')) return { background: '#f4df3b', color: '#171717' }
  if (key.includes('internal')) return { background: '#6f4e89', color: '#fff' }
  if (key.includes('shop')) return { background: '#2f80c9', color: '#fff' }
  if (key.includes('rental') || key.includes('customer')) return { background: '#f5a623', color: '#171717' }
  return { background: '#19a974', color: '#fff' }
}

export function VehicleCalendar({ onBack }: { onBack: () => void }) {
  const [view, setView] = useState<ViewMode>('day')
  const [date, setDate] = useState(() => startOfDay(new Date()))
  const [fleetFilter, setFleetFilter] = useState<FleetFilter>('all')
  const [availableOnly, setAvailableOnly] = useState(false)
  const [vehicles, setVehicles] = useState<Vehicle[]>([])
  const [events, setEvents] = useState<OperationalEvent[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [createTarget, setCreateTarget] = useState<CreateTarget>(null)
  const [vehicleTarget, setVehicleTarget] = useState<Vehicle | null>(null)

  const rangeStart = view === 'day' ? date : addDays(date, -date.getDay())
  const rangeEnd = addDays(rangeStart, view === 'day' ? 1 : 7)
  const days = Array.from({ length: view === 'day' ? 1 : 7 }, (_, index) => addDays(rangeStart, index))

  useEffect(() => {
    let active = true
    const load = async () => {
      setLoading(true)
      setError(null)

      const [vehicleResult, eventResult] = await Promise.all([
        supabase.from('vehicles').select('*').order('fleet_type').order('model').order('stock_number'),
        supabase
          .from('v_transportation_event_unified_operational_state')
          .select('*')
          .or(`expected_return_at.gte.${rangeStart.toISOString()},actual_in_at.gte.${rangeStart.toISOString()}`)
          .lt('updated_at', rangeEnd.toISOString()),
      ])

      if (!active) return
      if (vehicleResult.error || eventResult.error) {
        setError(vehicleResult.error?.message ?? eventResult.error?.message ?? 'The availability board could not be loaded.')
        setVehicles([])
        setEvents([])
      } else {
        setVehicles((vehicleResult.data ?? []).map(row => normalizeVehicle(row as Record<string, unknown>)))
        setEvents((eventResult.data ?? []).map(row => normalizeEvent(row as Record<string, unknown>)).filter((event): event is OperationalEvent => Boolean(event)))
      }
      setLoading(false)
    }

    void load()
    return () => { active = false }
  }, [rangeStart.getTime(), rangeEnd.getTime()])

  const visibleVehicles = useMemo(() => vehicles.filter(vehicle => {
    const fleet = vehicle.fleetType.toLowerCase()
    if (fleetFilter !== 'all' && !fleet.includes(fleetFilter)) return false
    if (!availableOnly) return true
    return !events.some(event => event.vehicleId === vehicle.id && event.isOpen && new Date(event.startsAt) <= new Date() && new Date(event.endsAt) > new Date())
  }), [vehicles, events, fleetFilter, availableOnly])

  const groupedVehicles = useMemo(() => {
    const groups = new Map<string, Vehicle[]>()
    visibleVehicles.forEach(vehicle => {
      const key = `${vehicle.fleetType || 'Unassigned'} · ${vehicle.model}`
      groups.set(key, [...(groups.get(key) ?? []), vehicle])
    })
    return [...groups.entries()]
  }, [visibleVehicles])

  const reservations = events.filter(event => event.sourceType.toLowerCase().includes('reservation') && !event.vehicleId)
  const currentTime = new Date()
  const currentTimePercent = Math.max(0, Math.min(100, ((currentTime.getHours() * 60 + currentTime.getMinutes() - 420) / 720) * 100))

  const openSlot = (vehicle: Vehicle | null, day: Date, clientX?: number, element?: HTMLElement) => {
    let hour = 8
    let minute = 0
    if (view === 'day' && typeof clientX === 'number' && element) {
      const bounds = element.getBoundingClientRect()
      const elapsed = Math.max(0, Math.min(720, ((clientX - bounds.left) / bounds.width) * 720))
      const rounded = Math.round(elapsed / 15) * 15
      hour = 7 + Math.floor(rounded / 60)
      minute = rounded % 60
    }
    setCreateTarget({ vehicle, startsAt: new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, minute) })
  }

  const renderEvent = (event: OperationalEvent) => {
    const start = new Date(event.startsAt)
    const end = new Date(event.endsAt)
    const style: CSSProperties = eventColor(event)
    if (view === 'day') {
      const startMinutes = start.getHours() * 60 + start.getMinutes() - 420
      const endMinutes = end.getHours() * 60 + end.getMinutes() - 420
      style.left = `${Math.max(0, startMinutes) / 720 * 100}%`
      style.width = `${Math.max(1.5, (Math.min(720, endMinutes) - Math.max(0, startMinutes)) / 720 * 100)}%`
    }

    return <button className={`availability-event ${view === 'day' ? 'day' : ''}`} style={style} key={event.id} title={`${event.sourceType} · ${event.payType} · ${event.status}`}>
      <strong>{event.payType}</strong>
      <span>{event.sourceType} {event.sourceId ? `#${event.sourceId.slice(0, 8)}` : ''}</span>
      <small>{start.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}–{end.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })} {event.hasConflict ? '⚠ Conflict' : ''}</small>
    </button>
  }

  return <main className="availability-board">
    <header className="availability-title">
      <div>
        <p className="eyebrow">PRIMARY WORKSPACE</p>
        <h1>Vehicle Availability</h1>
        <p>Model-level reservations above; VIN-level rentals and loaners below.</p>
      </div>
      <button onClick={onBack}>Admin Console</button>
    </header>

    <section className="availability-toolbar">
      <div className="segmented">
        {(['all', 'rental', 'loaner'] as FleetFilter[]).map(item => <button className={fleetFilter === item ? 'active' : ''} onClick={() => setFleetFilter(item)} key={item}>{item === 'all' ? 'All' : `${item[0].toUpperCase()}${item.slice(1)}s`}</button>)}
      </div>
      <label className="availability-toggle"><input type="checkbox" checked={availableOnly} onChange={event => setAvailableOnly(event.target.checked)} /> Available now</label>
      <div className="segmented"><button className={view === 'day' ? 'active' : ''} onClick={() => setView('day')}>Day</button><button className={view === 'week' ? 'active' : ''} onClick={() => setView('week')}>Week</button></div>
      <button onClick={() => setDate(addDays(date, view === 'day' ? -1 : -7))}>‹</button>
      <input aria-label="Jump to date" type="date" value={isoDay(date)} onChange={event => setDate(startOfDay(new Date(`${event.target.value}T12:00:00`)))} />
      <button onClick={() => setDate(addDays(date, view === 'day' ? 1 : 7))}>›</button>
      <button className="primary-action" onClick={() => setDate(startOfDay(new Date()))}>Today</button>
    </section>

    {error && <div className="calendar-error" role="alert">{error}</div>}
    {loading ? <div className="calendar-loading">Loading vehicles and transportation events…</div> : <div className="availability-scroll">
      <div className="availability-grid" style={{ '--day-count': days.length } as CSSProperties}>
        <div className="availability-corner">Vehicle / capacity</div>
        <div className="availability-head">{view === 'day' ? <div className="availability-hours">{Array.from({ length: 13 }, (_, index) => <span key={index}>{new Date(2026, 0, 1, index + 7).toLocaleTimeString([], { hour: 'numeric' })}</span>)}</div> : days.map(day => <button onClick={() => { setDate(day); setView('day') }} key={isoDay(day)}>{day.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' })}</button>)}</div>

        <div className="availability-section-title">Reservations</div>
        <div className="reservation-capacity-row" onDoubleClick={event => openSlot(null, date, event.clientX, event.currentTarget)}>
          <strong>{reservations.length} unassigned reservation{reservations.length === 1 ? '' : 's'}</strong>
          <span>Model capacity limits and conflict generation will be connected through Admin next.</span>
        </div>

        {groupedVehicles.map(([group, rows]) => <section className="availability-group" key={group}>
          <div className="availability-section-title">{group}</div>
          {rows.map(vehicle => <div className="availability-row" key={vehicle.id}>
            <button className="availability-resource" onClick={() => setVehicleTarget(vehicle)}>
              <strong>{vehicle.stockNumber}</strong>
              <span>{[vehicle.year, vehicle.make, vehicle.model].filter(Boolean).join(' ')}</span>
              <small>{vehicle.status}{vehicle.location ? ` · ${vehicle.location}` : ''}</small>
            </button>
            <div className="availability-timeline">
              {days.map(day => <div className="availability-day" key={isoDay(day)} onDoubleClick={event => openSlot(vehicle, day, event.clientX, event.currentTarget)}>
                {events.filter(item => item.vehicleId === vehicle.id && new Date(item.startsAt) < addDays(day, 1) && new Date(item.endsAt) > day).map(renderEvent)}
              </div>)}
              {view === 'day' && isoDay(date) === isoDay(new Date()) && <i className="current-time" style={{ left: `${currentTimePercent}%` }} />}
            </div>
          </div>)}
        </section>)}
      </div>
    </div>}

    {createTarget && <div className="calendar-modal" role="dialog" aria-modal="true"><div><button className="modal-close" onClick={() => setCreateTarget(null)}>×</button><p className="eyebrow">CREATE</p><h2>{createTarget.vehicle ? `${createTarget.vehicle.stockNumber} · ${createTarget.vehicle.model}` : 'Model-level booking'}</h2><p>{createTarget.startsAt.toLocaleString()}</p><div className="vehicle-actions"><button className="primary-action">Quote</button><button className="primary-action">Reservation</button></div><p className="availability-note">These buttons are the handoff point to the existing quote and reservation workflows. Reservations remain model-based and do not assign a VIN.</p></div></div>}

    {vehicleTarget && <div className="calendar-modal" role="dialog" aria-modal="true"><div><button className="modal-close" onClick={() => setVehicleTarget(null)}>×</button><p className="eyebrow">VEHICLE ACTION</p><h2>{vehicleTarget.stockNumber}</h2><p>{[vehicleTarget.year, vehicleTarget.make, vehicleTarget.model].filter(Boolean).join(' ')}</p><div className="vehicle-actions"><button className="primary-action">Rent now</button><button className="primary-action">Loan now</button><button>Vehicle details</button></div><p className="availability-note">Rent now and Loan now will enter the existing billing workflow to establish pay type and duration.</p></div></div>}
  </main>
}
