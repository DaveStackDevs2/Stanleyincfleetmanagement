import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'
import './ReservationsWorkspace.css'

type Workflow = 'quote' | 'reservation' | 'walk_in'
type Plan = 'daily' | 'weekly' | 'monthly'
type Json = Record<string, unknown>
type Customer = { id: string; name: string; number: string | null }
type PayType = { id: string; name: string }
type RateCard = { id: string; vehicleClass: string; daily: string | null; weekly: string | null; monthly: string | null }
type Quote = { id: string; eventId: string; customerId: string; customerName: string; start: string; expectedReturn: string; reservationType: string; vehicleClass: string; payType: string; initialPlan: string; currentPlan: string; daily: string | null; weekly: string | null; monthly: string | null }
type Intake = { customers: Customer[]; payTypes: PayType[]; rateCards: RateCard[]; quotes: Quote[] }

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
    id: string(pick(row!, 'rental_rate_rule_id', 'rate_card_id', 'id')), vehicleClass: string(row!.vehicle_class), daily: nullableString(pick(row!, 'daily_rate', 'daily_rate_snapshot')), weekly: nullableString(pick(row!, 'weekly_rate', 'weekly_rate_snapshot')), monthly: nullableString(pick(row!, 'monthly_rate', 'monthly_rate_snapshot')),
  })).filter(item => item.id && item.vehicleClass)
  const quotes = array(pick(root, 'active_quotes', 'quotes')).map(record).filter(Boolean).map(row => {
    const pricing = record(row!.pricing_agreement) ?? row!
    const customer = record(row!.customer)
    return { id:string(pick(row!, 'quote_id', 'id')), eventId:string(pick(row!, 'transportation_event_id', 'event_id')), customerId:string(pick(row!, 'customer_id')) || string(pick(customer ?? {}, 'customer_id', 'id')), customerName:string(pick(row!, 'customer_name')) || string(pick(customer ?? {}, 'customer_name', 'name')), start:string(pick(row!, 'start_date', 'start_at')), expectedReturn:string(pick(row!, 'expected_return_datetime', 'expected_return_at')), reservationType:string(row!.reservation_type), vehicleClass:string(pricing.vehicle_class), payType:string(pick(pricing, 'pay_type', 'pay_type_name')), initialPlan:string(pricing.initial_rate_plan), currentPlan:string(pricing.current_rate_plan), daily:nullableString(pick(pricing, 'daily_rate', 'daily_rate_snapshot')), weekly:nullableString(pick(pricing, 'weekly_rate', 'weekly_rate_snapshot')), monthly:nullableString(pick(pricing, 'monthly_rate', 'monthly_rate_snapshot')) }
  }).filter(item => item.id && item.eventId)
  return { customers, payTypes, rateCards, quotes }
}

const money = (value: string | null) => value === null ? 'Not configured' : `$${value}`
const dateTime = (value: string) => value ? new Date(value).toLocaleString() : '—'
const optional = (value: string) => value.trim() || null
function friendlyError(message: string): string {
  const text = message.toLowerCase()
  if (text.includes('aal2') || text.includes('permission') || text.includes('access denied') || text.includes('application user')) return 'Authorization/security: an active authorized user with AAL2 is required.'
  if (text.includes('not configured') || text.includes('configuration') || text.includes('rate card')) return 'Missing configuration: the selected pricing option is not configured.'
  if (text.includes('not found')) return 'Not found: the selected operational record is no longer available.'
  if (text.includes('active') || text.includes('conflict') || text.includes('already') || text.includes('inconsistent')) return 'Workflow conflict: authoritative state changed. Refresh Reservations and try again.'
  if (text.includes('required') || text.includes('invalid') || text.includes('after start')) return 'Validation: review the required fields and date range.'
  return 'Unexpected failure: Reservations could not complete the request. Please try again.'
}

export function ReservationsWorkspace() {
  const [intake, setIntake] = useState<Intake | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [workflow, setWorkflow] = useState<Workflow>('quote')
  const [customerId, setCustomerId] = useState('')
  const [customerSearch, setCustomerSearch] = useState('')
  const [vehicleClass, setVehicleClass] = useState('')
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

  const load = useCallback(async (): Promise<boolean> => {
    setLoading(true); setError(null); setIntake(null)
    const { data, error: rpcError } = await supabase.rpc('get_pricing_agreement_intake_state')
    if (rpcError) { setError(friendlyError(rpcError.message)); setLoading(false); return false }
    try { setIntake(parseIntake(data)); setLoading(false); return true }
    catch { setError('Unexpected failure: Supabase returned an unrecognized Reservations response.'); setLoading(false); return false }
  }, [])
  useEffect(() => { void load() }, [load])
  const selectedRate = intake?.rateCards.find(card => card.vehicleClass === vehicleClass) ?? null
  const selectedPlanValue = selectedRate?.[plan] ?? null
  const shownCustomers = useMemo(() => intake?.customers.filter(customer => `${customer.name} ${customer.number ?? ''}`.toLowerCase().includes(customerSearch.trim().toLowerCase())) ?? [], [intake, customerSearch])

  const reset = () => { setResult(null); setConversion(null); setError(null); void load() }
  const validate = () => {
    if (!customerId) return 'Validation: customer is required.'
    if (!vehicleClass || !selectedRate) return 'Validation: vehicle class is required.'
    if (!start) return 'Validation: start date and time are required.'
    if (!expectedReturn || new Date(expectedReturn).getTime() <= new Date(start).getTime()) return 'Validation: expected return must be after start.'
    if (!reservationType) return 'Validation: Loaner or Rental is required.'
    if (!payTypeId) return 'Validation: pay type is required.'
    if (!plan) return 'Validation: rate plan is required.'
    if (selectedPlanValue === null) return `Missing configuration: ${plan} pricing is not configured for ${vehicleClass}.`
    return null
  }
  const submit = async (event: FormEvent) => {
    event.preventDefault(); const validation = validate(); if (validation) { setError(validation); return }
    setBusy(true); setError(null)
    const common = { p_customer_id:customerId, p_vehicle_class:vehicleClass.trim(), p_start_date:new Date(start).toISOString(), p_expected_return_datetime:new Date(expectedReturn).toISOString(), p_reservation_type:reservationType, p_pay_type_rule_id:payTypeId, p_initial_rate_plan:plan }
    const call = workflow === 'quote'
      ? supabase.rpc('create_quote_with_pricing_agreement_state', { ...common, p_notes:optional(notes) })
      : supabase.rpc(workflow === 'reservation' ? 'create_reservation_with_pricing_agreement_state' : 'create_walk_in_with_pricing_agreement_state', { ...common, p_service_advisor:optional(advisor), p_ro_number:optional(roNumber), p_notes:optional(notes) })
    const { data, error: rpcError } = await call
    if (rpcError) setError(friendlyError(rpcError.message));
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

  if (result) return <main className="content reservations-page"><section className="reservation-success"><p className="eyebrow">AUTHORITATIVE RESULT</p><h1>Reservations update complete</h1><p>Supabase completed the workflow. No VIN, vehicle use, contract period, pricing timer, or billing was started.</p><div className="snapshot-grid">{Object.entries(result).filter(([, value]) => ['string','number'].includes(typeof value) || value === null).map(([key,value]) => <div key={key}><span>{key.replaceAll('_',' ')}</span><strong>{value === null ? 'Not configured' : String(value)}</strong></div>)}</div><button className="primary-action" type="button" onClick={reset}>Return to Reservations</button></section></main>
  if (conversion) return <main className="content reservations-page"><section className="reservation-success"><p className="eyebrow">QUOTE CONVERSION</p><h1>Convert Quote to Reservation</h1><p>The existing Transportation Event <code>{conversion.eventId}</code> and pricing agreement will be preserved.</p>{error && <div className="data-message error-message">{error}</div>}<form className="reservation-form" onSubmit={convert}><label>Service advisor<input value={advisor} onChange={e=>setAdvisor(e.target.value)} /></label><label>Repair-order number<input value={roNumber} onChange={e=>setRoNumber(e.target.value)} /></label><label className="wide">Notes<textarea value={notes} onChange={e=>setNotes(e.target.value)} /></label><div className="form-actions wide"><button type="button" onClick={()=>setConversion(null)}>Cancel</button><button className="primary-action" disabled={busy}>{busy?'Converting…':'Convert to Reservation'}</button></div></form></section></main>
  return <main className="content reservations-page">
    <section className="page-heading"><div><p className="eyebrow">OPERATIONS / RESERVATIONS</p><h1>Reservations</h1><p>Create pre-pickup Quotes, Reservations, and Walk-ins from authoritative pricing configuration.</p></div><button type="button" onClick={()=>void load()} disabled={loading}>Refresh</button></section>
    {error && <div className="data-message error-message"><strong>Reservations needs attention</strong><span>{error}</span></div>}
    {loading ? <div className="reservation-card">Loading authoritative intake…</div> : intake && <>
      <div className="reservation-tabs" role="tablist">{(['quote','reservation','walk_in'] as Workflow[]).map(item=><button type="button" className={workflow===item?'active':''} onClick={()=>setWorkflow(item)} key={item}>{item==='walk_in'?'Walk-in':item[0].toUpperCase()+item.slice(1)}</button>)}</div>
      <form className="reservation-card reservation-form" onSubmit={submit}>
        <label className="wide">Find existing customer<input type="search" value={customerSearch} onChange={e=>setCustomerSearch(e.target.value)} placeholder="Search name or Tekion customer number" /></label>
        <label className="wide">Customer<select required value={customerId} onChange={e=>setCustomerId(e.target.value)}><option value="">Select an existing customer</option>{shownCustomers.map(c=><option value={c.id} key={c.id}>{c.name}{c.number?` · ${c.number}`:''}</option>)}</select></label>
        <label>Workflow type<select required value={reservationType} onChange={e=>setReservationType(e.target.value)}><option value="">Select Loaner or Rental</option><option value="loaner">Loaner</option><option value="rental">Rental</option></select></label>
        <label>Vehicle class<select required value={vehicleClass} onChange={e=>setVehicleClass(e.target.value)}><option value="">Select configured class</option>{intake.rateCards.map(card=><option value={card.vehicleClass} key={card.id}>{card.vehicleClass}</option>)}</select></label>
        <label>Pay type<select required value={payTypeId} onChange={e=>setPayTypeId(e.target.value)}><option value="">Select active pay type</option>{intake.payTypes.map(item=><option value={item.id} key={item.id}>{item.name}</option>)}</select></label>
        <label>Initial rate plan<select required value={plan} onChange={e=>setPlan(e.target.value as Plan)}><option value="daily" disabled={selectedRate?.daily==null}>Daily</option><option value="weekly" disabled={selectedRate?.weekly==null}>Weekly</option><option value="monthly" disabled={selectedRate?.monthly==null}>Monthly</option></select></label>
        <label>Start date/time<input type="datetime-local" required value={start} onChange={e=>setStart(e.target.value)} /></label><label>Expected return date/time<input type="datetime-local" required value={expectedReturn} onChange={e=>setExpectedReturn(e.target.value)} /></label>
        {workflow!=='quote' && <><label>Service advisor<input value={advisor} onChange={e=>setAdvisor(e.target.value)} /></label><label>Repair-order number<input value={roNumber} onChange={e=>setRoNumber(e.target.value)} /></label></>}
        <label className="wide">Notes<textarea value={notes} onChange={e=>setNotes(e.target.value)} /></label>
        <div className="rate-preview wide"><strong>Configured pricing — exact Supabase values</strong><span>Daily: {money(selectedRate?.daily??null)}</span><span>Weekly: {money(selectedRate?.weekly??null)}</span><span>Monthly: {money(selectedRate?.monthly??null)}</span>{selectedRate && selectedPlanValue===null && <em>{plan} is not configured. Choose another plan.</em>}</div>
        <div className="form-actions wide"><button className="primary-action" disabled={busy}>{busy?'Submitting…':`Create ${workflow==='walk_in'?'Walk-in':workflow[0].toUpperCase()+workflow.slice(1)}`}</button></div>
      </form>
      <section className="reservation-card quote-list"><div className="section-heading"><div><h2>Active Quotes</h2><p>Authoritative Quotes available for same-event conversion.</p></div><strong>{intake.quotes.length}</strong></div>{intake.quotes.length===0?<p className="empty-state">No active Quotes.</p>:intake.quotes.map(q=><article key={q.id}><div><h3>{q.customerName||'Customer'}</h3><small>Quote ID {q.id}</small><small>Transportation Event ID {q.eventId}</small></div><dl><div><dt>Schedule</dt><dd>{dateTime(q.start)} — {dateTime(q.expectedReturn)}</dd></div><div><dt>Type / class</dt><dd>{q.reservationType} · {q.vehicleClass}</dd></div><div><dt>Pay type / plan</dt><dd>{q.payType} · {q.initialPlan} / {q.currentPlan}</dd></div><div><dt>Pricing snapshots</dt><dd>Daily {money(q.daily)} · Weekly {money(q.weekly)} · Monthly {money(q.monthly)}</dd></div></dl><button className="primary-action" type="button" onClick={()=>{setAdvisor('');setRoNumber('');setNotes('');setConversion(q)}}>Convert to Reservation</button></article>)}</section>
    </>}
  </main>
}
