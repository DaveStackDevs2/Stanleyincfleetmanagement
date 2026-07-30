import { useEffect, useMemo, useState, type CSSProperties, type PointerEvent } from 'react'
import { supabase } from '../lib/supabase'
import './FleetBoard.css'

type ViewMode = 'day' | 'week'
type FleetFilter = 'all' | 'rental' | 'loaner'

type Vehicle = {
  id: string
  stockNumber: string
  model: string
  modelYear: number | null
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
  reservationType: string
}

type Capacity = { model: string; dailyLimit: number }
type PayTypeColors = Record<string, { backgroundColor: string; textColor: string }>
type AssignmentLane = Assignment & { lane: number; left: number; width: number }
type TimelineHover = { target: string; quarter: number }

const NEUTRAL_PAY_TYPE_COLORS = { backgroundColor: '#E4E7ED', textColor: '#29313D' }
const DAY_TIMELINE_START_HOUR = 7
const DAY_TIMELINE_END_HOUR = 19
const isHexColor = (value: unknown): value is string => typeof value === 'string' && /^#[0-9a-fA-F]{6}$/.test(value)

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
const sameInstant = (value: unknown, expected: string) => {
  const parsed = dateValue(value)
  return parsed !== null && Date.parse(parsed) === Date.parse(expected)
}
const recordValue = (value: unknown): Record<string, unknown> | null => value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null
const formatAssignmentTime = (value: string) => new Date(value).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
const formatTimelineQuarter = (quarter: number) => new Date(2000, 0, 1, DAY_TIMELINE_START_HOUR, quarter * 15).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })

function assignmentLanes(items: Assignment[], dayStart: Date, dayEnd: Date): { items: AssignmentLane[]; laneCount: number } {
  const start = dayStart.getTime()
  const end = dayEnd.getTime()
  const duration = end - start
  const laneEnds: number[] = []
  const positioned = items
    .map(item => ({ item, visibleStart: Math.max(Date.parse(item.startsAt), start), visibleEnd: Math.min(Date.parse(item.endsAt), end) }))
    .filter(item => item.visibleEnd > item.visibleStart)
    .sort((a, b) => a.visibleStart - b.visibleStart || a.visibleEnd - b.visibleEnd || a.item.id.localeCompare(b.item.id))
    .map(({ item, visibleStart, visibleEnd }) => {
      let lane = laneEnds.findIndex(laneEnd => laneEnd <= visibleStart)
      if (lane === -1) lane = laneEnds.length
      laneEnds[lane] = visibleEnd
      return {
        ...item,
        lane,
        left: ((visibleStart - start) / duration) * 100,
        width: ((visibleEnd - visibleStart) / duration) * 100,
      }
    })
  return { items: positioned, laneCount: Math.max(laneEnds.length, 1) }
}

function vehicleFrom(value: unknown): Vehicle | null {
  const row = recordValue(value)
  if (!row) return null
  const id = textValue(row.id)
  if (!id) return null
  return {
    id,
    stockNumber: textValue(row.stock_number, 'Unnumbered'),
    model: textValue(row.model, 'Unknown model'),
    modelYear: typeof row.model_year === 'number' ? row.model_year : null,
    fleetType: textValue(row.fleet_type, 'Unassigned'),
    status: textValue(row.status, 'Unknown'),
    location: textValue(row.location),
  }
}

function assignmentFrom(value: unknown, rangeEnd: string): Assignment | null {
  const row = recordValue(value)
  if (!row) return null
  const id = textValue(row.transportation_event_id)
  const vehicleId = textValue(row.vehicle_id)
  const startsAt = dateValue(row.actual_out_at) ?? dateValue(row.current_billing_start_time)
  const endsAt = dateValue(row.actual_in_at) ?? dateValue(row.expected_return_at) ?? dateValue(row.current_billing_end_time) ?? rangeEnd
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
  const reservationType = textValue(row.reservation_type)
  if (reservationType.toLowerCase() !== 'rental') return null
  return { id, startsAt, endsAt, requestedModel: textValue(row.requested_model, 'Model not set'), status: textValue(row.status, 'Unknown'), reservationType }
}

function capacityFrom(value: unknown): Capacity | null {
  const row = recordValue(value)
  if (!row || typeof row.daily_limit !== 'number') return null
  const model = textValue(row.vehicle_class)
  return model ? { model, dailyLimit: row.daily_limit } : null
}

function arrayFrom<T>(value: unknown, parse: (item: unknown) => T | null): T[] | null {
  if (!Array.isArray(value)) return null
  const parsed = value.map(parse)
  return parsed.every((item): item is T => item !== null) ? parsed : null
}

function colorsFrom(value: unknown): PayTypeColors | null {
  const colors = recordValue(value)
  if (!colors) return null
  const parsed: PayTypeColors = {}
  for (const [payType, value] of Object.entries(colors)) {
    const color = recordValue(value)
    parsed[payType] = color && isHexColor(color.background_color) && isHexColor(color.text_color)
      ? { backgroundColor: color.background_color, textColor: color.text_color }
      : NEUTRAL_PAY_TYPE_COLORS
  }
  return parsed
}

function boardPayloadFrom(value: unknown, requestedStart: string, requestedEnd: string) {
  const payload = recordValue(value)
  if (!payload) return null
  if (payload.status !== 'fleet_board_ready' || !sameInstant(payload.range_start, requestedStart) || !sameInstant(payload.range_end, requestedEnd)) return null
  const vehicles = arrayFrom(payload.vehicles, vehicleFrom)
  const assignments = arrayFrom(payload.assignments, item => assignmentFrom(item, requestedEnd))
  const reservations = arrayFrom(payload.reservations, reservationFrom)
  const capacities = arrayFrom(payload.capacities, capacityFrom)
  const payTypeColors = colorsFrom(payload.pay_type_colors)
  return vehicles && assignments && reservations && capacities && payTypeColors
    ? { vehicles, assignments, reservations, capacities, payTypeColors }
    : null
}

export function FleetBoard() {
  const [view, setView] = useState<ViewMode>('day')
  const [date, setDate] = useState(() => startOfDay(new Date()))
  const [filter, setFilter] = useState<FleetFilter>('all')
  const [vehicles, setVehicles] = useState<Vehicle[]>([])
  const [assignments, setAssignments] = useState<Assignment[]>([])
  const [reservations, setReservations] = useState<Reservation[]>([])
  const [capacities, setCapacities] = useState<Capacity[]>([])
  const [payTypeColors, setPayTypeColors] = useState<PayTypeColors>({})
  const [loading, setLoading] = useState(true)
  const [loadFailed, setLoadFailed] = useState(false)
  const [currentTime, setCurrentTime] = useState(() => new Date())
  const [timelineHover, setTimelineHover] = useState<TimelineHover | null>(null)

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
      const boardResult = await supabase.rpc('get_fleet_board_state', { p_range_start: rangeStartIso, p_range_end: rangeEndIso })
      if (!current) return
      const board = boardPayloadFrom(boardResult.data, rangeStartIso, rangeEndIso)
      if (boardResult.error || !board) {
        setLoadFailed(true)
        setVehicles([])
        setAssignments([])
        setReservations([])
        setCapacities([])
        setPayTypeColors({})
      } else {
        setVehicles(board.vehicles)
        setAssignments(board.assignments)
        setReservations(board.reservations)
        setCapacities(board.capacities)
        setPayTypeColors(board.payTypeColors)
      }
      setLoading(false)
    }
    void loadBoard()
    return () => { current = false }
  }, [rangeStartIso, rangeEndIso])

  useEffect(() => {
    const timer = window.setInterval(() => setCurrentTime(new Date()), 60_000)
    return () => window.clearInterval(timer)
  }, [])

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
  const isDayView = view === 'day'
  const timelineStart = new Date(date.getFullYear(), date.getMonth(), date.getDate(), DAY_TIMELINE_START_HOUR)
  const timelineEnd = new Date(date.getFullYear(), date.getMonth(), date.getDate(), DAY_TIMELINE_END_HOUR)
  const showCurrentTime = isDayView
    && dayKey(date) === dayKey(currentTime)
    && currentTime >= timelineStart
    && currentTime <= timelineEnd
  const currentTimePosition = ((currentTime.getTime() - timelineStart.getTime()) / (timelineEnd.getTime() - timelineStart.getTime())) * 100
  const updateTimelineHover = (event: PointerEvent<HTMLElement>, target: string) => {
    if ((event.target as HTMLElement).closest('.assignment-block')) {
      setTimelineHover(null)
      return
    }
    const bounds = event.currentTarget.getBoundingClientRect()
    const quarter = Math.max(0, Math.min(48, Math.round(((event.clientX - bounds.left) / bounds.width) * 48)))
    setTimelineHover({ target, quarter })
  }
  const timelineHoverIndicator = (target: string) => timelineHover?.target === target
    ? <div className={`timeline-hover-indicator${timelineHover.quarter === 0 ? ' at-start' : timelineHover.quarter === 48 ? ' at-end' : ''}`} style={{ left: `${(timelineHover.quarter / 48) * 100}%` }} aria-hidden="true"><span>{formatTimelineQuarter(timelineHover.quarter)}</span></div>
    : null

  return <main className="fleet-board">
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
      <div className={`fleet-board-grid ${isDayView ? 'day-timeline-grid' : ''}`} style={{ '--board-days': days.length } as CSSProperties}>
        <div className="board-corner">Resource</div>
        {isDayView ? <div className="day-timeline-head" aria-label={`${date.toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' })}, 7 AM to 7 PM timeline`} onPointerMove={event => updateTimelineHover(event, 'header')} onPointerLeave={() => setTimelineHover(null)}>
          {Array.from({ length: 12 }, (_, index) => { const hour = DAY_TIMELINE_START_HOUR + index; return <div key={hour}><span>{new Date(2000, 0, 1, hour).toLocaleTimeString([], { hour: 'numeric' })}</span></div> })}
          <span className="day-timeline-final-boundary">{new Date(2000, 0, 1, DAY_TIMELINE_END_HOUR).toLocaleTimeString([], { hour: 'numeric' })}</span>
          {timelineHoverIndicator('header')}
        </div> : <div className="board-day-head">{days.map(day => <button type="button" key={dayKey(day)} onClick={() => { setDate(day); setView('day') }}>{day.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' })}</button>)}</div>}
        <div className="board-group-title">Reservation Capacity</div>
        {capacities.map(capacity => <div className="board-row capacity-row" key={capacity.model}>
          <div className="board-resource"><strong>{capacity.model}</strong><small>Daily limit {capacity.dailyLimit}</small></div>
          <div className={isDayView ? 'day-capacity' : 'board-days'}>{days.map(day => { const booked = reservations.filter(item => item.status !== 'cancelled' && item.requestedModel === capacity.model && overlaps(item.startsAt, item.endsAt, day)); return <div className="board-day" key={dayKey(day)}><strong>{booked.length} / {capacity.dailyLimit}</strong>{booked.map(item => <span className="reservation-block" title={`Reservation · ${item.status}`} key={item.id}>{item.status}</span>)}</div> })}</div>
        </div>)}
        {capacities.length === 0 && <div className="board-empty">No reservation capacity records are available.</div>}
        {vehicleGroups.map(([label, groupVehicles]) => <section className="board-group" key={label}>
          <h2 className="board-group-title">{label}</h2>
          {groupVehicles.map(vehicle => {
            const vehicleAssignments = assignments.filter(item => item.vehicleId === vehicle.id)
            const laneLayout = isDayView ? assignmentLanes(vehicleAssignments, timelineStart, timelineEnd) : null
            return <div className="board-row" style={isDayView ? { '--assignment-lanes': laneLayout?.laneCount } as CSSProperties : undefined} key={vehicle.id}>
              <div className="board-resource"><strong>{vehicle.stockNumber}</strong><span>{vehicle.model}</span><small>{vehicle.status}{vehicle.location ? ` · ${vehicle.location}` : ''}</small></div>
              {isDayView && laneLayout ? <div className="day-timeline-row" onPointerMove={event => updateTimelineHover(event, vehicle.id)} onPointerLeave={() => setTimelineHover(null)}>
                {showCurrentTime && <div className="current-time-marker" style={{ left: `${currentTimePosition}%` }} aria-label="Current time" />}
                {timelineHoverIndicator(vehicle.id)}
                {laneLayout.items.map(item => { const colors = payTypeColors[item.payType] ?? NEUTRAL_PAY_TYPE_COLORS; return <article className={`assignment-block day-assignment${item.hasConflict ? ' conflict' : ''}`} style={{ backgroundColor: colors.backgroundColor, color: colors.textColor, left: `${item.left}%`, width: `${item.width}%`, top: `calc(5px + ${item.lane} * 46px)` }} title={`${item.payType} · ${item.status} · ${item.sourceType} · ${formatAssignmentTime(item.startsAt)}–${formatAssignmentTime(item.endsAt)}`} key={item.id}><strong>{item.payType}</strong><span className="assignment-status">{item.status}</span><span className="assignment-source">{item.sourceType}</span><span className="assignment-times">{formatAssignmentTime(item.startsAt)}–{formatAssignmentTime(item.endsAt)}</span></article> })}
              </div> : <div className="board-days">{days.map(day => <div className="board-day" key={dayKey(day)}>{vehicleAssignments.filter(item => overlaps(item.startsAt, item.endsAt, day)).map(item => { const colors = payTypeColors[item.payType] ?? NEUTRAL_PAY_TYPE_COLORS; return <article className={`assignment-block${item.hasConflict ? ' conflict' : ''}`} style={{ backgroundColor: colors.backgroundColor, color: colors.textColor }} title={`${item.sourceType} · ${item.status}`} key={item.id}><strong>{item.payType}</strong><span>{formatAssignmentTime(item.startsAt)}–{formatAssignmentTime(item.endsAt)}</span></article> })}</div>)}</div>}
            </div>
          })}
        </section>)}
      </div>
    </div>}
  </main>
}
