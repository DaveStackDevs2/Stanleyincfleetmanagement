import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import './ReservationsWorkspace.css'
import { AuthoritativeFields, PickupWorkspace } from './PickupWorkspace'
import { EditReservationWorkspace } from './EditReservationWorkspace'

export type ReservationsNavigationContext =
  | { workflow: 'edit' | 'pickup'; reservationId: string }
  | { workflow: 'quote' | 'reservation' | 'walk_in'; reservationType: 'rental' | 'loaner'; vehicleModel: string; startAt: string }
type Workflow = ReservationsNavigationContext['workflow']
type Plan = 'daily' | 'weekly' | 'monthly'
type Json = Record<string, unknown>
type Customer = { id: string; name: string; number: string | null }
type PayType = { id: string; name: string }
type RateCard = { id: string; vehicleModel: string; daily: string | null; weekly: string | null; monthly: string | null }
type Quote = { id: string; eventId: string; customerId: string; customerName: string; start: string; expectedReturn: string; reservationType: string; vehicleModel: string; payType: string; initialPlan: string; currentPlan: string; daily: string | null; weekly: string | null; monthly: string | null }
type Intake = { customers: Customer[]; payTypes: PayType[]; rateCards: RateCard[]; quotes: Quote[] }
type CapacityAlternative = { vehicleModel: string; minimumRemaining: number }
type CapacityState = { status: 'available' | 'not_configured' | 'full'; available: boolean; alternatives: CapacityAlternative[] }

const record = (value: unknown): Json | null => typeof value === 'object' && value !== null && !Array.isArray(value) ? value as Json : null
const string = (value: unknown): string => typeof value === 'string' ? value : ''
const nullableString = (value: unknown): string | null => value === null || value === undefined ? null : typeof value === 'string' ? value : typeof value === 'number' ? String(value) : null
const array = (value: unknown): unknown[] => Array.isArray(value) ? value : []
const pick = (row: Json, ...keys: string[]): unknown => keys.map(key => row[key]).find(value => value !== undefined)

function parseIntake(value: unknown): Intake {
  const root = record(value)
  if (!root || root.status !== 'pricing_agreement_intake_ready') throw new Error('invalid-response')
  const customers = array(root.customers).map(record).filter(Boolean).map(row => ({
    id: string(pick(row!, 'customer_id', 'id')), name: string(pick(row!, 'customer_name', 'name')), number: nullableString(pick(row!, 'tekion_customer_number', 'customer_number')),
  })).filter(item => item.id && item.name)
  const payTypes = array(pick(root, 'active_pay_types', 'pay_types')).map(record).filter(Boolean).map(row => ({
    id: string(pick(row!, 'pay_type_rule_id', 'id')), name: string(pick(row!, 'pay_type', 'name')),
  })).filter(item => item.id && item.name)
  const rateCards = array(root.rate_cards).map(record).filter(Boolean).map(row => ({
    id: string(pick(row!, 'rental_rate_rule_id', 'rate_card_id', 'id')), vehicleModel: string(row!.vehicle_class), daily: nullableString(pick(row!, 'daily_rate', 'daily_rate_snapshot')), weekly: nullableString(pick(row!, 'weekly_rate', 'weekly_rate_snapshot')), monthly: nullableString(pick(row!, 'monthly_rate', 'monthly_rate_snapshot')),
  })).filter(item => item.id && item.vehicleModel)
  const quotes = array(pick(root, 'active_quotes', 'quotes')).map(record).filter(Boolean).map(row => {
    const pricing = record(row!.pricing_agreement) ?? row!
    const customer = record(row!.customer)
    return { id:string(pick(row!, 'quote_id', 'id')), eventId:string(pick(row!, 'transportation_event_id', 'event_id')), customerId:string(pick(row!, 'customer_id')) || string(pick(customer ?? {}, 'customer_id', 'id')), customerName:string(pick(row!, 'customer_name')) || string(pick(customer ?? {}, 'customer_name', 'name')), start:string(pick(row!, 'start_date', 'start_at')), expectedReturn:string(pick(row!, 'expected_return_datetime', 'expected_return_at')), reservationType:string(row!.reservation_type), vehicleModel:string(pricing.vehicle_class), payType:string(pick(pricing, 'pay_type', 'pay_type_name')), initialPlan:string(pricing.initial_rate_plan), currentPlan:string(pricing.current_rate_plan), daily:nullableString(pick(pricing, 'daily_rate', 'daily_rate_snapshot')), weekly:nullableString(pick(pricing, 'weekly_rate', 'weekly_rate_snapshot')), monthly:nullableString(pick(pricing, 'monthly_rate', 'monthly_rate_snapshot')) }
  }).filter(item => item.id && item.eventId)
  return { customers, payTypes, rateCards, quotes }
}

const money = (value: string | null) => value === null ? 'Not configured' : `$${value}`
const dateTime = (value: string) => value ? new Date(value).toLocaleString() : '—'
const optional = (value: string) => value.trim() || null
const authoritativeUuid = (value: unknown): string | null => {
  const candidate = string(value).trim()
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(candidate) ? candidate : null
}
function friendlyError(message: string): string {
  const text = message.toLowerCase()
  if (text.includes('reservation capacity unavailable')) return 'No Rental reservation capacity is available for the selected model and dates. Refresh availability and choose an available alternative.'
  if (text.includes('rental workflow requires the rental pay type') || text.includes('rental pay type requires a rental workflow')) return 'Pay type mismatch: Rental workflows require the active Rental pay type, and Rental cannot be used for Loaner workflows.'
  if (text.includes('aal2') || text.includes('permission') || text.includes('access denied') || text.includes('application user')) return 'Authorization/security: an active authorized user with AAL2 is required.'
  if (text.includes('not configured') || text.includes('configuration') || text.includes('rate card')) return 'Missing configuration: the selected pricing option is not configured.'
  if (text.includes('not found')) return 'Not found: the selected operational record is no longer available.'
  if (text.includes('active') || text.includes('conflict') || text.includes('already') || text.includes('inconsistent')) return 'Workflow conflict: authoritative state changed. Refresh Reservations and try again.'
  if (text.includes('required') || text.includes('invalid') || text.includes('after start')) return 'Validation: review the required fields and date range.'
  return 'Unexpected failure: Reservations could not complete the request. Please try again.'
}

function parseCapacity(value: unknown): CapacityState {
  const root=record(value); const status=root?.status
  if (!root || (status!=='available'&&status!=='not_configured'&&status!=='full') || typeof root.available!=='boolean') throw new Error('invalid-capacity')
  const alternatives=array(root.alternatives).map(record).filter(Boolean).map(item=>({vehicleModel:string(item!.vehicle_class),minimumRemaining:Number(item!.minimum_remaining)})).filter(item=>item.vehicleModel&&Number.isInteger(item.minimumRemaining)&&item.minimumRemaining>0)
  return {status,available:root.available,alternatives}
}

const localDateTime = (value: string) => {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000)
  return local.toISOString().slice(0, 16)
}

export function ReservationsWorkspace({ navigationContext = null, onNavigationContextHandled }: { navigationContext?: ReservationsNavigationContext | null; onNavigationContextHandled?: () => void }) {
  const [intake, setIntake] = useState<Intake | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [workflow, setWorkflow] = useState<Workflow>('quote')
  const [customerId, setCustomerId] = useState('')
  const [customerSearch, setCustomerSearch] = useState('')
  const [vehicleModel, setVehicleModel] = useState('')
  const [reservationType, setReservationType] = useState('')
  const [payTypeId, setPayTypeId] = useState('')
  const [plan, setPlan] = useState<Plan>('daily')
  const [start, setStart] = useState('')
  const [expectedReturn, setExpectedReturn] = useState('')
  const [advisor, setAdvisor] = useState('')
  const [roNumber, setRoNumber] = useState('')
  const [notes, setNotes] = useState('')
  const [result, setResult] = useState<Json | null>(null)
  const [conversion, setConversion] = useState<Quote | null>(null)
  const [pickupReservationId, setPickupReservationId] = useState<string | null>(null)
  const [editReservationId, setEditReservationId] = useState<string | null>(null)
  const [capacity, setCapacity] = useState<CapacityState | null>(null)
  const [capacityLoading, setCapacityLoading] = useState(false)
  const handleInitialPickupReservation = useCallback(() => { setPickupReservationId(null); onNavigationContextHandled?.() }, [onNavigationContextHandled])

  const load = useCallback(async (): Promise<boolean> => {
    setLoading(true); setError(null); setIntake(null)
    const { data, error: rpcError } = await supabase.rpc('get_pricing_agreement_intake_state')
    if (rpcError) { setError(friendlyError(rpcError.message)); setLoading(false); return false }
    try { setIntake(parseIntake(data)); setLoading(false); return true }
    catch { setError('Unexpected failure: Supabase returned an unrecognized Reservations response.'); setLoading(false); return false }
  }, [])
  useEffect(() => { void load() }, [load])
  const rentalPayType = useMemo(() => intake?.payTypes.find(item => item.name.trim().toLowerCase() === 'rental') ?? null, [intake])
  const allowedPayTypes = useMemo(() => reservationType === 'rental'
    ? (rentalPayType ? [rentalPayType] : [])
    : reservationType === 'loaner'
      ? (intake?.payTypes.filter(item => item.name.trim().toLowerCase() !== 'rental') ?? [])
      : [], [intake, rentalPayType, reservationType])
  const selectedRate = intake?.rateCards.find(card => card.vehicleModel === vehicleModel) ?? null
  const selectedPlanValue = selectedRate?.[plan] ?? null
  const shownCustomers = useMemo(() => intake?.customers.filter(customer => `${customer.name} ${customer.number ?? ''}`.toLowerCase().includes(customerSearch.trim().toLowerCase())) ?? [], [intake, customerSearch])

  useEffect(()=>{
    setCapacity(null)
    if (reservationType!=='rental'||workflow==='walk_in'||!vehicleModel||!start||!expectedReturn||new Date(expectedReturn)<=new Date(start)) return
    let current=true; setCapacityLoading(true)
    const timer=window.setTimeout(async()=>{
      const result=await supabase.rpc('get_rental_reservation_capacity_state',{p_vehicle_class:vehicleModel,p_start_date:new Date(start).toISOString(),p_expected_return_datetime:new Date(expectedReturn).toISOString(),p_exclude_reservation_id:null})
      if(!current)return
      try{if(result.error)throw result.error;setCapacity(parseCapacity(result.data))}catch{setError('Reservation capacity could not be verified. Refresh and try again.')}finally{setCapacityLoading(false)}
    },250)
    return()=>{current=false;window.clearTimeout(timer)}
  },[reservationType,workflow,vehicleModel,start,expectedReturn])

  useEffect(() => {
    if (!intake || loading || !navigationContext) return
    setWorkflow(navigationContext.workflow)
    if ('reservationId' in navigationContext) {
      if (navigationContext.workflow === 'pickup') setPickupReservationId(navigationContext.reservationId)
      else setEditReservationId(navigationContext.reservationId)
    } else {
      const configuredModel = intake.rateCards.some(card => card.vehicleModel === navigationContext.vehicleModel)
      setReservationType(navigationContext.reservationType)
      setVehicleModel(configuredModel ? navigationContext.vehicleModel : '')
      setStart(localDateTime(navigationContext.startAt))
      setExpectedReturn('')
      if (navigationContext.reservationType === 'rental') {
        const rental = intake.payTypes.find(item => item.name.trim().toLowerCase() === 'rental')
        setPayTypeId(rental?.id ?? '')
      } else setPayTypeId('')
      setError(configuredModel ? null : `Missing configuration: ${navigationContext.vehicleModel} is not present in authoritative rate-card data.`)
      onNavigationContextHandled?.()
    }
  }, [intake, loading, navigationContext, onNavigationContextHandled])

  const reset = () => { setResult(null); setConversion(null); setError(null); void load() }
  const validate = () => {
    if (!customerId) return 'Validation: customer is required.'
    if (!vehicleModel || !selectedRate) return 'Validation: vehicle model is required.'
    if (!start) return 'Validation: start date and time are required.'
    if (!expectedReturn || new Date(expectedReturn).getTime() <= new Date(start).getTime()) return 'Validation: expected return must be after start.'
    if (!reservationType) return 'Validation: Loaner or Rental is required.'
    if (reservationType === 'rental' && !rentalPayType) return 'Missing configuration: the active Rental pay type is required for Rental workflows.'
    if (!payTypeId) return 'Validation: pay type is required.'
    if (reservationType === 'rental' && payTypeId !== rentalPayType?.id) return 'Validation: Rental workflows require the authoritative Rental pay type.'
    if (reservationType !== 'rental' && payTypeId === rentalPayType?.id) return 'Validation: Rental pay type cannot be used for a Loaner workflow.'
    if (!plan) return 'Validation: rate plan is required.'
    if (workflow === 'walk_in' && plan !== 'daily') return 'Weekly and monthly pickup billing is not implemented yet.'
    if (workflow === 'walk_in' && reservationType === 'loaner' && !roNumber.trim()) return 'Validation: Loaner Walk-in requires an RO number before continuing to Pickup.'
    if (selectedPlanValue === null) return `Missing configuration: ${plan} pricing is not configured for ${vehicleModel}.`
    if (reservationType==='rental'&&workflow==='reservation'&&(capacityLoading||!capacity?.available)) return 'No authoritative Rental reservation capacity is available for the selected model and dates.'
    return null
  }
  const submit = async (event: FormEvent) => {
    event.preventDefault(); const validation = validate(); if (validation) { setError(validation); return }
    setBusy(true); setError(null)
    const common = { p_customer_id:customerId, p_vehicle_class:vehicleModel.trim(), p_start_date:new Date(start).toISOString(), p_expected_return_datetime:new Date(expectedReturn).toISOString(), p_reservation_type:reservationType, p_pay_type_rule_id:payTypeId, p_initial_rate_plan:plan }
    const call = workflow === 'quote'
      ? supabase.rpc('create_quote_with_pricing_agreement_state', { ...common, p_notes:optional(notes) })
      : supabase.rpc(workflow === 'reservation' ? 'create_reservation_with_pricing_agreement_state' : 'create_walk_in_with_pricing_agreement_state', { ...common, p_service_advisor:optional(advisor), p_ro_number:optional(roNumber), p_notes:optional(notes) })
    const { data, error: rpcError } = await call
    if (rpcError) setError(friendlyError(rpcError.message));
    else if (workflow === 'walk_in') {
      const reservationId = authoritativeUuid(record(data)?.reservation_id)
      if (!reservationId) { await load(); setError('State sync failed: the Walk-in response did not include a valid authoritative reservation ID. Refresh before continuing.') }
      else if (await load()) { setPickupReservationId(reservationId); setWorkflow('pickup') }
      else setError('State sync failed: the write completed, but Reservations could not reload authoritative intake. Refresh before continuing.')
    }
    else if (await load()) setResult(record(data));
    else setError('State sync failed: the write completed, but Reservations could not reload authoritative intake. Refresh before continuing.')
    setBusy(false)
  }
  const convert = async (event: FormEvent) => {
    event.preventDefault(); if (!conversion) return
    setBusy(true); setError(null)
    const { data, error: rpcError } = await supabase.rpc('convert_quote_to_reservation_with_pricing_agreement_state', { p_quote_id:conversion.id, p_service_advisor:optional(advisor), p_ro_number:optional(roNumber), p_notes:optional(notes) })
    if (rpcError) setError(friendlyError(rpcError.message));
    else if (await load()) { setConversion(null); setResult(record(data)); }
    else { setConversion(null); setError('State sync failed: the conversion completed, but Reservations could not reload authoritative intake. Refresh before continuing.') }
    setBusy(false)
  }

  if (result) return <main className="content reservations-page"><section className="reservation-success"><p className="eyebrow">AUTHORITATIVE RESULT</p><h1>Reservations update complete</h1><p>Supabase completed the workflow. No VIN, vehicle use, contract period, pricing timer, or billing was started.</p><AuthoritativeFields value={result} /><button className="primary-action" type="button" onClick={reset}>Return to Reservations</button></section></main>
  if (conversion) return <main className="content reservations-page"><section className="reservation-success"><p className="eyebrow">QUOTE CONVERSION</p><h1>Convert Quote to Reservation</h1><p>The existing Transportation Event <code>{conversion.eventId}</code> and pricing agreement will be preserved.</p>{error && <div className="data-message error-message">{error}</div>}<form className="reservation-form" onSubmit={convert}><label>Service advisor<input value={advisor} onChange={e=>setAdvisor(e.target.value)} /></label><label>Repair-order number<input value={roNumber} onChange={e=>setRoNumber(e.target.value)} /></label><label className="wide">Notes<textarea value={notes} onChange={e=>setNotes(e.target.value)} /></label><div className="form-actions wide"><button type="button" onClick={()=>setConversion(null)}>Cancel</button><button className="primary-action" disabled={busy}>{busy?'Converting…':'Convert to Reservation'}</button></div></form></section></main>
  return <main className="content reservations-page">
    <section className="page-heading"><div><p className="eyebrow">OPERATIONS / RESERVATIONS</p><h1>Reservations</h1><p>Create pre-pickup Quotes, Reservations, and Walk-ins from authoritative pricing configuration.</p></div><button type="button" onClick={()=>void load()} disabled={loading}>Refresh</button></section>
    {error && <div className="data-message error-message"><strong>Reservations needs attention</strong><span>{error}</span></div>}
    {loading ? <div className="reservation-card">Loading authoritative intake…</div> : intake && <>
      <div className="reservation-tabs" role="tablist">{(['quote','reservation','walk_in','edit','pickup'] as Workflow[]).map(item=><button type="button" className={workflow===item?'active':''} onClick={()=>setWorkflow(item)} key={item}>{item==='walk_in'?'Walk-in':item==='edit'?'Edit Reservation':item==='pickup'?'Check-in / Pickup':item[0].toUpperCase()+item.slice(1)}</button>)}</div>
      {workflow==='pickup'?<PickupWorkspace onError={setError} initialReservationId={pickupReservationId} onInitialReservationHandled={handleInitialPickupReservation}/>:workflow==='edit'?<EditReservationWorkspace onError={setError} initialReservationId={editReservationId} onInitialReservationHandled={()=>{setEditReservationId(null);onNavigationContextHandled?.()}}/>:<>
      <form className="reservation-card reservation-form" onSubmit={submit}>
        <label className="wide">Find existing customer<input type="search" value={customerSearch} onChange={e=>setCustomerSearch(e.target.value)} placeholder="Search name or Tekion customer number" /></label>
        <label className="wide">Customer<select required value={customerId} onChange={e=>setCustomerId(e.target.value)}><option value="">Select an existing customer</option>{shownCustomers.map(c=><option value={c.id} key={c.id}>{c.name}{c.number?` · ${c.number}`:''}</option>)}</select></label>
        <label>Workflow type<select required value={reservationType} onChange={e=>{const next=e.target.value;setReservationType(next);if(next==='rental'){if(rentalPayType){setPayTypeId(rentalPayType.id);setError(null)}else{setPayTypeId('');setError('Missing configuration: the active Rental pay type is required for Rental workflows.')}}else{setPayTypeId('');setError(null)}}}><option value="">Select Loaner or Rental</option><option value="loaner">Loaner</option><option value="rental">Rental</option></select></label>
        <label>Vehicle model<select required value={vehicleModel} onChange={e=>setVehicleModel(e.target.value)}><option value="">Select vehicle model</option>{intake.rateCards.map(card=><option value={card.vehicleModel} key={card.id}>{card.vehicleModel}</option>)}</select></label>
        <label>Pay type<select required disabled={!reservationType || (reservationType==='rental' && !rentalPayType)} value={payTypeId} onChange={e=>setPayTypeId(e.target.value)}><option value="">{reservationType ? 'Select active pay type' : 'Select workflow type first'}</option>{allowedPayTypes.map(item=><option value={item.id} key={item.id}>{item.name}</option>)}</select></label>
        <label>Initial rate plan<select required value={plan} onChange={e=>setPlan(e.target.value as Plan)}><option value="daily" disabled={selectedRate?.daily==null}>Daily</option><option value="weekly" disabled={selectedRate?.weekly==null}>Weekly</option><option value="monthly" disabled={selectedRate?.monthly==null}>Monthly</option></select></label>
        <label>Start date/time<input type="datetime-local" required value={start} onChange={e=>setStart(e.target.value)} /></label><label>Expected return date/time<input type="datetime-local" required value={expectedReturn} onChange={e=>setExpectedReturn(e.target.value)} /></label>
        {workflow!=='quote' && <><label>Service advisor<input value={advisor} onChange={e=>setAdvisor(e.target.value)} /></label><label>Repair-order number<input value={roNumber} onChange={e=>setRoNumber(e.target.value)} /></label></>}
        <label className="wide">Notes<textarea value={notes} onChange={e=>setNotes(e.target.value)} /></label>
        {reservationType==='rental'&&workflow!=='walk_in'&&capacityLoading&&<div className="rate-preview wide" role="status">Checking authoritative Reservation Capacity…</div>}
        {reservationType==='rental'&&workflow!=='walk_in'&&capacity&&!capacity.available&&<div className="data-message error-message wide" role="alert"><strong>No reservation capacity is available for {vehicleModel} for the selected dates.</strong><span>{capacity.status==='not_configured'?'This model has no Reservation Capacity configuration.':'At least one dealership calendar day is full.'}</span>{capacity.alternatives.length>0&&<div><span>Available alternatives for the complete period:</span>{capacity.alternatives.map(item=><button type="button" key={item.vehicleModel} onClick={()=>setVehicleModel(item.vehicleModel)}>{item.vehicleModel} ({item.minimumRemaining} remaining)</button>)}</div>}</div>}
        {reservationType==='rental'&&workflow!=='walk_in'&&capacity?.available&&<div className="rate-preview wide"><strong>Reservation Capacity available</strong><span>Authoritative availability covers the complete selected period.</span></div>}
        <div className="rate-preview wide"><strong>Configured pricing — exact Supabase values</strong><span>Daily: {money(selectedRate?.daily??null)}</span><span>Weekly: {money(selectedRate?.weekly??null)}</span><span>Monthly: {money(selectedRate?.monthly??null)}</span>{selectedRate && selectedPlanValue===null && <em>{plan} is not configured. Choose another plan.</em>}</div>
        <div className="form-actions wide"><button className="primary-action" disabled={busy||(workflow==='reservation'&&reservationType==='rental'&&(capacityLoading||!capacity?.available))}>{busy?'Submitting…':`Create ${workflow==='walk_in'?'Walk-in':workflow[0].toUpperCase()+workflow.slice(1)}`}</button></div>
      </form>
      <section className="reservation-card quote-list"><div className="section-heading"><div><h2>Active Quotes</h2><p>Authoritative Quotes available for same-event conversion.</p></div><strong>{intake.quotes.length}</strong></div>{intake.quotes.length===0?<p className="empty-state">No active Quotes.</p>:intake.quotes.map(q=><article key={q.id}><div><h3>{q.customerName||'Customer'}</h3><small>Quote ID {q.id}</small><small>Transportation Event ID {q.eventId}</small></div><dl><div><dt>Schedule</dt><dd>{dateTime(q.start)} — {dateTime(q.expectedReturn)}</dd></div><div><dt>Type / model</dt><dd>{q.reservationType} · {q.vehicleModel}</dd></div><div><dt>Pay type / plan</dt><dd>{q.payType} · {q.initialPlan} / {q.currentPlan}</dd></div><div><dt>Pricing snapshots</dt><dd>Daily {money(q.daily)} · Weekly {money(q.weekly)} · Monthly {money(q.monthly)}</dd></div></dl><button className="primary-action" type="button" onClick={()=>{setAdvisor('');setRoNumber('');setNotes('');setConversion(q)}}>Convert to Reservation</button></article>)}</section>
      </>}
    </>}
  </main>
}
