import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'

type PayType = {
  id: string
  payType: string
  description: string | null
  taxable: boolean
  defaultDailyAmount: number | null
  sortOrder: number
  enabled: boolean
}

type ColorPair = { background_color: string; text_color: string }
type RentalRateRule = { id: string; vehicleClass: string; dailyRate: number; weeklyRate: number | null; monthlyRate: number | null; sortOrder: number; enabled: boolean; current: boolean }
type RentalRateState = { rateRules: RentalRateRule[] }
type PayTypeState = { payTypes: PayType[]; colors: Record<string, ColorPair> }
type ColorState = { payTypes: string[]; colors: Record<string, ColorPair> }
type EditForm = { id: string; payType: string; taxable: boolean; amount: string; sortOrder: string; description: string }
type TaxState = { taxRate: number; percentage: number }
type RentalRateForm = { id: string | null; vehicleClass: string; dailyRate: string; weeklyRate: string; monthlyRate: string; sortOrder: string; capacity: string; saveCapacity: boolean }
type ImpactItem = { id: string; customerName: string; vehicleClass: string; start: string; end: string; status: string; dates: string[]; kind: 'Reservation' | 'Quote' }
type ImpactDay = { date: string; capacity: number; capacityConfigured: boolean; reservationCount: number; reservationOverage: number; activeQuoteCount: number; combinedCount: number; quotePressureOverage: number }
type CapacityModel = { vehicleClass: string; dailyLimit: number | null; configured: boolean; hasActiveRateCard: boolean; impact: { days: ImpactDay[]; hardReservations: ImpactItem[]; atRiskQuotes: ImpactItem[] } }
type ExtendedWarrantyProviderRule = { id: string; providerId: string; providerName: string; enabled: boolean; defaultDailyAmount: number | null; coveredDays: number; notes: string }
type ExtendedWarrantyState = { providerRules: ExtendedWarrantyProviderRule[] }
type ExtendedWarrantyForm = { id: string | null; providerId: string | null; providerName: string; defaultDailyAmount: string; coveredDays: string; notes: string }
type ExtendedWarrantyFocusMode = 'list' | 'form' | 'success'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const HEX = /^#[0-9a-f]{6}$/i
const FALLBACK_COLORS: ColorPair = { background_color: '#e5e7eb', text_color: '#374151' }
const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value)
const hasExactKeys = (value: Record<string, unknown>, keys: string[]): boolean =>
  Object.keys(value).sort().join('|') === [...keys].sort().join('|')

function percentageToDecimalFraction(value: string): string | null {
  const normalized = value.trim()
  if (!/^(?:\d+\.?\d*|\.\d+)$/.test(normalized)) return null
  const [whole, fraction = ''] = normalized.startsWith('.') ? ['0', normalized.slice(1)] : normalized.split('.')
  const digits = `${whole}${fraction}`.replace(/^0+(?=\d)/, '')
  const position = digits.length - fraction.length - 2
  const decimal = position > 0 ? `${digits.slice(0, position)}.${digits.slice(position)}` : `0.${'0'.repeat(-position)}${digits}`
  return decimal.replace(/\.?0+$/, '') || '0'
}

function parseTaxState(value: unknown): TaxState {
  if (!isRecord(value) || !hasExactKeys(value, ['status', 'can_manage', 'setting_key', 'tax_rate', 'tax_percentage', 'calculation_mode', 'tax_line_mode', 'exempt_pay_types']) ||
    value.status !== 'admin_loaner_rental_tax_ready' || value.can_manage !== true ||
    value.setting_key !== 'billing.loaner_rental_tax_rate' || typeof value.tax_rate !== 'number' ||
    typeof value.tax_percentage !== 'number' || value.calculation_mode !== 'exact_no_rounding' ||
    value.tax_line_mode !== 'separate_child_line' || !Array.isArray(value.exempt_pay_types) ||
    value.exempt_pay_types.length !== 2 || value.exempt_pay_types[0] !== 'GM Warranty' || value.exempt_pay_types[1] !== 'Extended Warranty') throw new Error('invalid-tax-state')
  return { taxRate: value.tax_rate, percentage: value.tax_percentage }
}

function parseTaxMutation(value: unknown, expectedRate: number, expectedPercentage: number): void {
  if (!isRecord(value) || !hasExactKeys(value, ['status', 'setting_key', 'previous_tax_rate', 'tax_rate', 'tax_percentage', 'calculation_mode', 'tax_line_mode']) ||
    value.status !== 'admin_loaner_rental_tax_updated' ||
    value.setting_key !== 'billing.loaner_rental_tax_rate' ||
    typeof value.previous_tax_rate !== 'number' || !Number.isFinite(value.previous_tax_rate) ||
    typeof value.tax_rate !== 'number' || value.tax_rate !== expectedRate ||
    typeof value.tax_percentage !== 'number' || value.tax_percentage !== expectedPercentage ||
    value.calculation_mode !== 'exact_no_rounding' || value.tax_line_mode !== 'separate_child_line') {
    throw new Error('invalid-tax-mutation')
  }
}

function parsePayTypeState(value: unknown): PayTypeState {
  if (!isRecord(value) || value.status !== 'admin_pay_type_rules_ready' || value.can_manage !== true ||
    !Array.isArray(value.pay_types) || !isRecord(value.colors)) {
    throw new Error('invalid-pay-type-state')
  }
  const payTypes = value.pay_types.map((item) => {
    if (!isRecord(item) || typeof item.pay_type_rule_id !== 'string' || !UUID.test(item.pay_type_rule_id) ||
      typeof item.pay_type !== 'string' || !item.pay_type.trim() ||
      !(item.description === null || typeof item.description === 'string') ||
      typeof item.is_taxable !== 'boolean' ||
      !(item.default_daily_amount === null || (typeof item.default_daily_amount === 'number' && Number.isFinite(item.default_daily_amount))) ||
      typeof item.sort_order !== 'number' || !Number.isInteger(item.sort_order) ||
      typeof item.is_enabled !== 'boolean') {
      throw new Error('invalid-pay-type')
    }
    return {
      id: item.pay_type_rule_id, payType: item.pay_type, description: item.description,
      taxable: item.is_taxable, defaultDailyAmount: item.default_daily_amount,
      sortOrder: item.sort_order, enabled: item.is_enabled,
    }
  })
  return { payTypes, colors: parseColorMap(value.colors) }
}

function parseColorMap(value: Record<string, unknown>): Record<string, ColorPair> {
  const colors: Record<string, ColorPair> = {}
  for (const [key, pair] of Object.entries(value)) {
    if (!isRecord(pair) || Object.keys(pair).length !== 2 ||
      typeof pair.background_color !== 'string' || !HEX.test(pair.background_color) ||
      typeof pair.text_color !== 'string' || !HEX.test(pair.text_color)) {
      throw new Error('invalid-color')
    }
    colors[key] = { background_color: pair.background_color, text_color: pair.text_color }
  }
  return colors
}

function parseColors(value: unknown): ColorState {
  if (!isRecord(value) || value.status !== 'fleet_board_pay_type_colors_ready' ||
    value.can_manage !== true || !Array.isArray(value.pay_types) || !isRecord(value.colors)) {
    throw new Error('invalid-color-state')
  }
  const payTypes: string[] = []
  for (const item of value.pay_types) {
    if (!isRecord(item) || typeof item.pay_type !== 'string' ||
      !(item.description === null || typeof item.description === 'string') ||
      typeof item.sort_order !== 'number' || !Number.isInteger(item.sort_order)) {
      throw new Error('invalid-color-pay-type')
    }
    payTypes.push(item.pay_type)
  }
  return { payTypes, colors: parseColorMap(value.colors) }
}


function parseRentalRateRule(item: unknown): RentalRateRule {
  const money = (value: unknown) => value === null || (typeof value === 'number' && Number.isFinite(value) && value >= 0)
  if (!isRecord(item) || !hasExactKeys(item, ['rental_rate_rule_id','vehicle_class','daily_rate','weekly_rate','monthly_rate','sort_order','is_active','is_current','effective_from','effective_to','created_at','updated_at']) ||
    typeof item.rental_rate_rule_id !== 'string' || !UUID.test(item.rental_rate_rule_id) || typeof item.vehicle_class !== 'string' || !item.vehicle_class.trim() ||
    typeof item.daily_rate !== 'number' || !money(item.daily_rate) || !money(item.weekly_rate) || !money(item.monthly_rate) || typeof item.sort_order !== 'number' || !Number.isInteger(item.sort_order) || item.sort_order < 0 ||
    typeof item.is_active !== 'boolean' || typeof item.is_current !== 'boolean' || typeof item.effective_from !== 'string' || !(item.effective_to === null || typeof item.effective_to === 'string') || typeof item.created_at !== 'string' || typeof item.updated_at !== 'string') throw new Error('invalid-rental-rate-card')
  return { id:item.rental_rate_rule_id, vehicleClass:item.vehicle_class, dailyRate:item.daily_rate, weeklyRate:item.weekly_rate as number|null, monthlyRate:item.monthly_rate as number|null, sortOrder:item.sort_order, enabled:item.is_active, current:item.is_current }
}
function parseRentalRateState(value: unknown): RentalRateState {
  if (!isRecord(value) || !hasExactKeys(value,['status','can_manage','rate_cards']) || value.status !== 'admin_rental_rate_cards_ready' || value.can_manage !== true || !Array.isArray(value.rate_cards)) throw new Error('invalid-rental-rate-state')
  return { rateRules:value.rate_cards.map(parseRentalRateRule) }
}

const strings = (value: unknown) => Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : []
const numeric = (value: unknown) => typeof value === 'number' ? value : 0
function parseCapacityState(value: unknown): CapacityModel[] {
  if (!isRecord(value) || value.status !== 'admin_rental_reservation_capacity_ready' || !Array.isArray(value.models)) throw new Error('invalid-capacity-state')
  return value.models.map((raw) => {
    if (!isRecord(raw) || typeof raw.vehicle_class !== 'string' || !raw.vehicle_class.trim()) throw new Error('invalid-capacity-model')
    const impact = isRecord(raw.impact) ? raw.impact : {}
    const days: ImpactDay[] = Array.isArray(impact.days) ? impact.days.map((rawDay) => {
      const day = isRecord(rawDay) ? rawDay : {}
      return { date: String(day.date ?? ''), capacity: numeric(day.capacity), capacityConfigured: day.capacity_configured === true, reservationCount: numeric(day.reservation_count), reservationOverage: numeric(day.reservation_overage), activeQuoteCount: numeric(day.active_quote_count), combinedCount: numeric(day.combined_count), quotePressureOverage: numeric(day.quote_pressure_overage) }
    }).filter((day) => day.date) : []
    const items = (rawItems: unknown, kind: ImpactItem['kind']): ImpactItem[] => Array.isArray(rawItems) ? rawItems.map((rawItem) => {
      const item = isRecord(rawItem) ? rawItem : {}
      return { id: String(item[kind === 'Reservation' ? 'reservation_id' : 'quote_id'] ?? ''), customerName: typeof item.customer_name === 'string' ? item.customer_name : 'Customer unavailable', vehicleClass: String(item.vehicle_class ?? ''), start: String(item.start_date ?? ''), end: String(item.expected_return_datetime ?? ''), status: String(item.status ?? ''), dates: strings(item[kind === 'Reservation' ? 'conflict_dates' : 'risk_dates']), kind }
    }).filter((item) => item.id) : []
    return { vehicleClass: raw.vehicle_class, dailyLimit: typeof raw.daily_limit === 'number' ? raw.daily_limit : null, configured: raw.configured === true, hasActiveRateCard: raw.has_active_rate_card === true, impact: { days, hardReservations: items(impact.hard_reservation_conflicts, 'Reservation'), atRiskQuotes: items(impact.at_risk_quotes, 'Quote') } }
  })
}

function parseExtendedWarrantyProviderRule(item: unknown): ExtendedWarrantyProviderRule {
  if (!isRecord(item) || typeof item.rule_id !== 'string' || !UUID.test(item.rule_id) ||
    typeof item.provider_id !== 'string' || !UUID.test(item.provider_id) ||
    typeof item.provider_name !== 'string' || !item.provider_name.trim() ||
    !(typeof item.is_enabled === 'boolean' || typeof item.provider_is_active === 'boolean' || typeof item.is_active === 'boolean') ||
    !(item.resolved_daily_rate === null || (typeof item.resolved_daily_rate === 'number' && Number.isFinite(item.resolved_daily_rate) && item.resolved_daily_rate >= 0)) ||
    !(typeof item.covered_days === 'number' && Number.isInteger(item.covered_days) && item.covered_days > 0) ||
    typeof item.requires_approval !== 'boolean' || item.requires_approval !== false ||
    !(item.notes === null || typeof item.notes === 'string')) throw new Error('invalid-extended-warranty-provider-rule')
  return { id: item.rule_id, providerId: item.provider_id, providerName: item.provider_name, enabled: Boolean(item.is_enabled ?? item.provider_is_active ?? item.is_active),
    defaultDailyAmount: (item.default_daily_rate as number | null | undefined) ?? item.resolved_daily_rate, coveredDays: item.covered_days, notes: item.notes ?? '' }
}

function parseExtendedWarrantyState(value: unknown): ExtendedWarrantyState {
  if (!isRecord(value) || value.status !== 'admin_billing_configuration_ready' || value.can_manage !== true || !(Array.isArray(value.extended_warranty_rules) || Array.isArray(value.extended_warranty_provider_rules))) {
    throw new Error('invalid-extended-warranty-state')
  }
  return { providerRules: ((value.extended_warranty_rules ?? value.extended_warranty_provider_rules) as unknown[]).map(parseExtendedWarrantyProviderRule) }
}

function parseExtendedWarrantyMutation(value: unknown, expectedStatus: string, expectedId?: string): ExtendedWarrantyProviderRule {
  if (!isRecord(value) || value.status !== expectedStatus || !isRecord(value.provider_rule)) throw new Error('invalid-extended-warranty-mutation')
  const rule = parseExtendedWarrantyProviderRule(value.provider_rule)
  if (expectedId && rule.id !== expectedId && rule.providerId !== expectedId) throw new Error('unexpected-extended-warranty-rule')
  return rule
}

function parseRentalRateMutation(value: unknown, expectedStatus: string, expectedId?: string): RentalRateRule {
  if (!isRecord(value) || value.status !== expectedStatus || !isRecord(value.rental_rate_card)) throw new Error('invalid-rental-rate-mutation')
  const rule = parseRentalRateRule(value.rental_rate_card)
  if (expectedId && rule.id !== expectedId) throw new Error('unexpected-rental-rate-rule')
  return rule
}

function parsePayTypeMutation(value: unknown, expectedStatus: 'admin_pay_type_rule_created' | 'admin_pay_type_rule_updated', expectedId?: string): void {
  if (!isRecord(value) || value.status !== expectedStatus || !isRecord(value.pay_type_rule)) {
    throw new Error('invalid-update')
  }
  const rule = value.pay_type_rule
  if (typeof rule.pay_type_rule_id !== 'string' || !UUID.test(rule.pay_type_rule_id) ||
    (expectedId !== undefined && rule.pay_type_rule_id !== expectedId) || typeof rule.pay_type !== 'string' || !rule.pay_type.trim() ||
    typeof rule.is_enabled !== 'boolean' || typeof rule.is_active !== 'boolean' || typeof rule.active !== 'boolean' ||
    typeof rule.is_taxable !== 'boolean' || typeof rule.tax_applicable !== 'boolean' ||
    rule.is_taxable !== rule.tax_applicable ||
    !(rule.default_daily_amount === null || (typeof rule.default_daily_amount === 'number' && Number.isFinite(rule.default_daily_amount) && rule.default_daily_amount >= 0)) ||
    typeof rule.sort_order !== 'number' || !Number.isInteger(rule.sort_order) || rule.sort_order < 0 ||
    !(rule.description === null || typeof rule.description === 'string')) {
    throw new Error('invalid-updated-pay-type')
  }
}

export function PayTypeManagement({ onBack }: { onBack: () => void }) {
  const [state, setState] = useState<PayTypeState | null>(null)
  const [rateState, setRateState] = useState<RentalRateState | null>(null)
  const [capacityModels, setCapacityModels] = useState<CapacityModel[] | null>(null)
  const [capacityDrafts, setCapacityDrafts] = useState<Record<string, string>>({})
  const [extendedWarrantyState, setExtendedWarrantyState] = useState<ExtendedWarrantyState | null>(null)
  const [extendedWarrantyForm, setExtendedWarrantyForm] = useState<ExtendedWarrantyForm>({ id: null, providerId: null, providerName: '', defaultDailyAmount: '', coveredDays: '', notes: '' })
  const [extendedWarrantyFocusMode, setExtendedWarrantyFocusMode] = useState<ExtendedWarrantyFocusMode>('list')
  const [rateForm, setRateForm] = useState<RentalRateForm>({ id: null, vehicleClass: '', dailyRate: '', weeklyRate: '', monthlyRate: '', sortOrder: '0', capacity: '', saveCapacity: false })
  const [draftColors, setDraftColors] = useState<Record<string, ColorPair>>({})
  const [dirtyColorKeys, setDirtyColorKeys] = useState<Set<string>>(() => new Set())
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [successMessage, setSuccessMessage] = useState<string | null>(null)
  const [form, setForm] = useState({ payType: '', taxable: true, amount: '', sortOrder: '0', description: '' })
  const [editForm, setEditForm] = useState<EditForm | null>(null)
  const [taxState, setTaxState] = useState<TaxState | null>(null)
  const [taxEditing, setTaxEditing] = useState(false)
  const [taxPercentage, setTaxPercentage] = useState('')

  const load = useCallback(async () => {
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const [rules, palette, rentalRates, rentalCapacity, extendedWarranty, tax] = await Promise.all([
      supabase.rpc('get_admin_pay_type_rules_state'),
      supabase.rpc('get_fleet_board_pay_type_colors_state'),
      supabase.rpc('get_admin_rental_rate_cards_state'),
      supabase.rpc('get_admin_rental_reservation_capacity_state'),
      supabase.rpc('get_admin_billing_configuration_state'),
      supabase.rpc('get_admin_loaner_rental_tax_state'),
    ])
    try {
      if (rules.error || palette.error) throw new Error('request-failed')
      const { payTypes, colors } = parsePayTypeState(rules.data)
      parseColors(palette.data)
      if (!rentalRates.error) setRateState(parseRentalRateState(rentalRates.data))
      else setRateState(null)
      if (!rentalCapacity.error) {
        const parsedCapacity = parseCapacityState(rentalCapacity.data)
        setCapacityModels(parsedCapacity)
        setCapacityDrafts(Object.fromEntries(parsedCapacity.map((item) => [item.vehicleClass.trim().toLocaleLowerCase(), item.dailyLimit === null ? '' : String(item.dailyLimit)])))
      } else setCapacityModels(null)
      if (!extendedWarranty.error) setExtendedWarrantyState(parseExtendedWarrantyState(extendedWarranty.data))
      else setExtendedWarrantyState(null)
      if (tax.error) throw new Error('tax-request-failed')
      setTaxState(parseTaxState(tax.data))
      setState({ payTypes, colors })
      setDraftColors(Object.fromEntries(payTypes.filter((item) => item.enabled).map((item) => [
        item.payType, colors[item.payType] ?? FALLBACK_COLORS,
      ])))
      setDirtyColorKeys(new Set())
      return true
    } catch {
      setState(null)
      setRateState(null)
      setCapacityModels(null)
      setExtendedWarrantyState(null)
      setTaxState(null)
      setMessage('Pay-type settings could not be loaded. Confirm your access and try again.')
      return false
    } finally { setBusy(false) }
  }, [])

  useEffect(() => { void load() }, [load])

  const mutate = async (request: PromiseLike<{ error: unknown }>, failure: string) => {
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const { error } = await request
    if (error) { setMessage(failure); setBusy(false); return false }
    await load()
    return true
  }

  const addPayType = async (event: FormEvent) => {
    event.preventDefault()
    const amount = form.amount.trim() === '' ? null : Number(form.amount)
    const sortOrder = Number(form.sortOrder)
    if (!form.payType.trim() || (amount !== null && (!Number.isFinite(amount) || amount < 0)) ||
      !Number.isInteger(sortOrder) || sortOrder < 0) {
      setMessage('Enter a pay-type name, an optional non-negative daily amount, and a non-negative whole-number sort order.')
      return
    }
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const result = await supabase.rpc('create_admin_pay_type_rule_state', {
      p_pay_type: form.payType.trim(), p_is_taxable: form.taxable,
      p_default_daily_amount: amount, p_sort_order: sortOrder,
      p_description: form.description.trim() || null,
    })
    if (result.error) {
      setMessage('The pay type could not be added. Review the values and try again. No addition was confirmed.')
      setBusy(false)
      return
    }
    try { parsePayTypeMutation(result.data, 'admin_pay_type_rule_created') } catch {
      setMessage('The add request completed, but its result could not be verified. Refresh before trying again.')
      setBusy(false)
      return
    }
    const name = form.payType.trim()
    if (await load()) {
      setForm({ payType: '', taxable: true, amount: '', sortOrder: '0', description: '' })
      setSuccessMessage(`${name} was added successfully.`)
    } else setMessage('The pay type was added, but the authoritative settings could not be reloaded. Refresh before making another change.')
  }

  const editPayType = (item: PayType) => {
    setMessage(null); setSuccessMessage(null)
    setEditForm({ id: item.id, payType: item.payType, taxable: item.taxable,
      amount: item.defaultDailyAmount === null ? '' : String(item.defaultDailyAmount),
      sortOrder: String(item.sortOrder), description: item.description ?? '' })
  }

  const savePayType = async (event: FormEvent) => {
    event.preventDefault()
    if (!editForm || busy) return
    const amount = editForm.amount.trim() === '' ? null : Number(editForm.amount)
    const sortOrder = Number(editForm.sortOrder)
    if ((amount !== null && (!Number.isFinite(amount) || amount < 0)) || !Number.isInteger(sortOrder) || sortOrder < 0) {
      setMessage('Enter an optional non-negative daily amount and a non-negative whole-number sort order.')
      return
    }
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const result = await supabase.rpc('update_admin_pay_type_rule_state', {
      p_pay_type_rule_id: editForm.id, p_is_taxable: editForm.taxable,
      p_default_daily_amount: amount, p_sort_order: sortOrder,
      p_description: editForm.description.trim() || null,
    })
    if (result.error) {
      setMessage('The pay type could not be updated. Review the values and try again. No update was confirmed.')
      setBusy(false)
      return
    }
    try {
      parsePayTypeMutation(result.data, 'admin_pay_type_rule_updated', editForm.id)
    } catch {
      setMessage('The update request completed, but its result could not be verified. The pay type may have changed; refresh before trying again.')
      setBusy(false)
      return
    }
    const name = editForm.payType
    const reloaded = await load()
    if (reloaded) {
      setEditForm(null)
      setSuccessMessage(`${name} was updated successfully.`)
    } else {
      setMessage('The pay type was updated, but the authoritative settings could not be reloaded. Refresh before making another change.')
    }
  }



  const emptyRateForm = (): RentalRateForm => ({ id:null, vehicleClass:'', dailyRate:'', weeklyRate:'', monthlyRate:'', sortOrder:'0', capacity:'', saveCapacity:false })
  const validateRateForm = (draft: RentalRateForm) => {
    const dailyRate=Number(draft.dailyRate), weeklyRate=draft.weeklyRate.trim()===''?null:Number(draft.weeklyRate), monthlyRate=draft.monthlyRate.trim()===''?null:Number(draft.monthlyRate), sortOrder=Number(draft.sortOrder)
    if (!draft.vehicleClass.trim() || draft.dailyRate.trim()==='' || !Number.isFinite(dailyRate) || dailyRate<0 || (weeklyRate!==null&&(!Number.isFinite(weeklyRate)||weeklyRate<0)) || (monthlyRate!==null&&(!Number.isFinite(monthlyRate)||monthlyRate<0)) || !Number.isInteger(sortOrder) || sortOrder<0) { setMessage('Enter a vehicle class, required finite non-negative daily rate, optional finite non-negative weekly and monthly rates, and non-negative whole-number sort order.'); return null }
    if (monthlyRate !== null && weeklyRate === null) { setMessage('Weekly rate is required when a monthly rate is configured'); return null }
    return {dailyRate,weeklyRate,monthlyRate,sortOrder}
  }
  const editRentalRate = (item: RentalRateRule) => { setMessage(null); setSuccessMessage(null); setRateForm({id:item.id,vehicleClass:item.vehicleClass,dailyRate:String(item.dailyRate),weeklyRate:item.weeklyRate===null?'':String(item.weeklyRate),monthlyRate:item.monthlyRate===null?'':String(item.monthlyRate),sortOrder:String(item.sortOrder),capacity:'',saveCapacity:false}) }
  const saveRentalRate = async (event: FormEvent) => {
    event.preventDefault(); if(busy)return; const values=validateRateForm(rateForm); if(!values)return; const edit=rateForm.id!==null
    if (!edit && rateForm.saveCapacity && !/^\d+$/.test(rateForm.capacity)) { setMessage('Reservation Capacity must be a whole number zero or greater. No changes were saved.'); return }
    setBusy(true);setMessage(null);setSuccessMessage(null)
    const payload={p_vehicle_class:rateForm.vehicleClass.trim(),p_daily_rate:values.dailyRate,p_weekly_rate:values.weeklyRate,p_monthly_rate:values.monthlyRate,p_sort_order:values.sortOrder}
    const result=edit?await supabase.rpc('update_admin_rental_rate_card_state',{p_rental_rate_rule_id:rateForm.id,...payload}):await supabase.rpc('create_admin_rental_rate_card_state',payload)
    if(result.error){setMessage(`The rental rate could not be ${edit?'updated':'added'}. Review the values and try again. No change was confirmed.`);setBusy(false);return}
    try{parseRentalRateMutation(result.data,edit?'admin_rental_rate_card_updated':'admin_rental_rate_card_created',rateForm.id??undefined)}catch{setMessage('The rental rate request completed, but its complete result could not be verified. Refresh before trying again.');setBusy(false);return}
    if (!edit && rateForm.saveCapacity) {
      const capacityResult = await supabase.rpc('upsert_admin_rental_reservation_capacity_state', { p_vehicle_class: rateForm.vehicleClass.trim(), p_daily_limit: Number(rateForm.capacity) })
      if (capacityResult.error) {
        await load()
        setRateForm(emptyRateForm())
        setMessage('Pricing WAS saved, but Reservation Capacity WAS NOT. The model is unavailable for new Rental Reservations until capacity is configured.')
        return
      }
    }
    if(await load()){setRateForm(emptyRateForm());setSuccessMessage(edit?'Rental rate updated successfully.':'Rental model and authoritative settings saved successfully.')}else setMessage('The rental rate changed, but authoritative settings could not be reloaded. Refresh before making another change.')
  }
  const setRentalRateEnabled=async(item:RentalRateRule)=>{setBusy(true);setMessage(null);setSuccessMessage(null);const enabled=!item.enabled;const result=await supabase.rpc('set_admin_rental_rate_card_enabled_state',{p_rental_rate_rule_id:item.id,p_is_enabled:enabled});if(result.error){setMessage(`The rental rate could not be ${enabled?'reactivated':'disabled'}. No change was confirmed.`);setBusy(false);return}try{parseRentalRateMutation(result.data,enabled?'admin_rental_rate_card_enabled':'admin_rental_rate_card_disabled',item.id)}catch{setMessage('The rental rate status result could not be verified. Refresh before trying again.');setBusy(false);return}if(await load())setSuccessMessage(`Rental rate ${enabled?'reactivated':'disabled'} successfully.`);else setMessage('The rental rate changed, but authoritative settings could not be reloaded.')}
  const saveCapacity = async (vehicleClass: string, value: string) => {
    if (!/^\d+$/.test(value)) { setMessage('Reservation Capacity must be a whole number zero or greater.'); return }
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const result = await supabase.rpc('upsert_admin_rental_reservation_capacity_state', { p_vehicle_class: vehicleClass.trim(), p_daily_limit: Number(value) })
    if (result.error) { setMessage('Reservation Capacity could not be saved.'); setBusy(false); return }
    if (await load()) setSuccessMessage(`Reservation Capacity saved for ${vehicleClass}.`)
  }
  const removeCapacity = async (item: CapacityModel) => {
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const result = await supabase.rpc('remove_admin_rental_reservation_capacity_state', { p_vehicle_class: item.vehicleClass })
    if (result.error) { setMessage('Reservation Capacity configuration could not be removed.'); setBusy(false); return }
    if (await load()) setSuccessMessage(`Reservation Capacity removed for ${item.vehicleClass}; the model is unavailable for new Rental Reservations.`)
  }


  const editExtendedWarrantyProvider = (item: ExtendedWarrantyProviderRule) => {
    setMessage(null); setSuccessMessage(null)
    setExtendedWarrantyForm({ id: item.id, providerId: item.providerId, providerName: item.providerName, defaultDailyAmount: item.defaultDailyAmount === null ? '' : String(item.defaultDailyAmount), coveredDays: String(item.coveredDays), notes: item.notes })
    setExtendedWarrantyFocusMode('form')
  }

  const saveExtendedWarrantyProvider = async (event: FormEvent) => {
    event.preventDefault()
    if (busy) return
    const amount = extendedWarrantyForm.defaultDailyAmount.trim() === '' ? null : Number(extendedWarrantyForm.defaultDailyAmount)
    const coveredDays = Number(extendedWarrantyForm.coveredDays)
    if (!extendedWarrantyForm.providerName.trim() || (amount !== null && (!Number.isFinite(amount) || amount < 0)) ||
      (!Number.isInteger(coveredDays) || coveredDays <= 0)) {
      setMessage('Enter a provider name, optional finite non-negative daily amount, and a positive whole-number covered-day cap.')
      return
    }
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const isEdit = extendedWarrantyForm.id !== null
    const payload = { p_provider_name: extendedWarrantyForm.providerName.trim(), p_default_daily_rate: amount, p_covered_days: coveredDays, p_requires_approval: false, p_notes: extendedWarrantyForm.notes.trim() || null }
    const result = isEdit
      ? await supabase.rpc('update_admin_extended_warranty_provider_rule_state', { p_provider_id: extendedWarrantyForm.providerId, ...payload })
      : await supabase.rpc('create_admin_extended_warranty_provider_rule_state', payload)
    if (result.error) { setMessage(`The Extended Warranty provider could not be ${isEdit ? 'updated' : 'added'}. Review the values and try again. No change was confirmed.`); setBusy(false); return }
    try { parseExtendedWarrantyMutation(result.data, isEdit ? 'admin_extended_warranty_provider_rule_updated' : 'admin_extended_warranty_provider_rule_created', (extendedWarrantyForm.providerId ?? extendedWarrantyForm.id) ?? undefined) }
    catch { setMessage('The Extended Warranty provider request completed, but its result could not be verified. Refresh before trying again.'); setBusy(false); return }
    const reloaded = await load()
    if (reloaded) { setExtendedWarrantyForm({ id: null, providerId: null, providerName: '', defaultDailyAmount: '', coveredDays: '', notes: '' }); setSuccessMessage(`Extended Warranty provider ${isEdit ? 'updated' : 'added'} successfully.`); setExtendedWarrantyFocusMode('success') }
    else setMessage('The Extended Warranty provider changed, but authoritative settings could not be reloaded. Refresh before making another change.')
  }

  const setExtendedWarrantyProviderEnabled = async (item: ExtendedWarrantyProviderRule) => {
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const enabled = !item.enabled
    const result = await supabase.rpc('set_admin_extended_warranty_provider_enabled_state', { p_provider_id: item.providerId, p_is_enabled: enabled })
    if (result.error) { setMessage(`The Extended Warranty provider could not be ${enabled ? 'reactivated' : 'disabled'}. No changes were applied.`); setBusy(false); return }
    try { parseExtendedWarrantyMutation(result.data, enabled ? 'admin_extended_warranty_provider_enabled' : 'admin_extended_warranty_provider_disabled', item.id) }
    catch { setMessage('The Extended Warranty provider status changed, but its result could not be verified. Refresh before trying again.'); setBusy(false); return }
    if (await load()) setSuccessMessage(`Extended Warranty provider ${enabled ? 'reactivated' : 'disabled'} successfully.`)
    else setMessage(`The Extended Warranty provider changed, but authoritative settings could not be reloaded after ${enabled ? 'reactivating' : 'disabling'}. Refresh before making another change.`)
  }

  const saveColors = async () => {
    if (!state) return
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const authoritative = await supabase.rpc('get_fleet_board_pay_type_colors_state')
    try {
      if (authoritative.error) throw new Error('request-failed')
      const fresh = parseColors(authoritative.data)
      const merged = Object.fromEntries(fresh.payTypes.map((payType) => {
        const pair = dirtyColorKeys.has(payType) ? draftColors[payType] : fresh.colors[payType]
        const selected = pair ?? FALLBACK_COLORS
        if (!HEX.test(selected.background_color) || !HEX.test(selected.text_color)) throw new Error('invalid-color')
        return [payType, selected]
      }))
      const saved = await supabase.rpc('set_fleet_board_pay_type_colors_state', { p_colors: merged })
      if (saved.error) throw new Error('request-failed')
      if (await load()) setSuccessMessage('Fleet Board colors saved successfully.')
    } catch {
      setMessage('The Fleet Board colors could not be saved. No color changes were applied.')
      setBusy(false)
    }
  }

  const saveTaxRate = async (event: FormEvent) => {
    event.preventDefault()
    const percentage = Number(taxPercentage)
    const decimal = percentageToDecimalFraction(taxPercentage)
    if (decimal === null || !Number.isFinite(percentage) || percentage <= 0 || percentage > 100) {
      setMessage('Enter a tax percentage greater than 0 and no greater than 100.'); return
    }
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const result = await supabase.rpc('set_admin_loaner_rental_tax_rate_state', { p_tax_rate: decimal })
    if (result.error) { setMessage('The loaner and rental tax rate could not be saved. No change was confirmed.'); setBusy(false); return }
    try { parseTaxMutation(result.data, Number(decimal), percentage) }
    catch { setMessage('The tax update request completed, but its result could not be verified. The rate may have changed; refresh before trying again.'); setBusy(false); return }
    if (await load()) { setTaxEditing(false); setSuccessMessage('Loaner and rental tax rate saved successfully.') }
    else setMessage('The tax rate changed, but the authoritative state could not be reloaded. Refresh before making another change.')
  }

  const extendedWarrantyFocused = extendedWarrantyFocusMode !== 'list'
  const rateFocused = rateForm.id !== null || rateForm.vehicleClass !== ''
  const focused = extendedWarrantyFocused || taxEditing || rateFocused
  const modelKey = (value: string) => value.trim().toLocaleLowerCase()
  const activeRates = rateState?.rateRules.filter((item) => item.enabled && item.current) ?? []
  const inactiveRates = rateState?.rateRules.filter((item) => !item.enabled || !item.current) ?? []
  const currentModels = new Map<string, { vehicleClass: string; rate: RentalRateRule | null; capacity: CapacityModel | null }>()
  activeRates.forEach((rate) => currentModels.set(modelKey(rate.vehicleClass), { vehicleClass: rate.vehicleClass, rate, capacity: null }))
  capacityModels?.forEach((capacity) => { const key = modelKey(capacity.vehicleClass); const existing = currentModels.get(key); currentModels.set(key, { vehicleClass: existing?.vehicleClass ?? capacity.vehicleClass, rate: existing?.rate ?? null, capacity }) })
  const money = (value: number | null) => value === null ? 'Not configured' : value.toLocaleString(undefined, { style: 'currency', currency: 'USD' })
  const warningList = (items: ImpactItem[]) => <ul>{items.map((item) => <li key={`${item.kind}-${item.id}`}><strong>{item.customerName}</strong> — {item.kind} <code>{item.id}</code>, {item.vehicleClass}, {item.start} to {item.end}, status {item.status}. Affected local dates: {item.dates.join(', ')}</li>)}</ul>

  return <main className="content management-page pay-type-page">
    <section className="fleet-header"><div><p className="eyebrow">ADMINISTRATION / BILLING</p>
      <h1>Rates, Fees &amp; Billing Rules</h1><p>Manage pay types and the colors used to identify active billing on the Fleet Board.</p></div>
      <div className="page-actions"><button className="secondary-action" type="button" onClick={onBack}>Back to Admin Console</button></div>
    </section>
    {message && <div className="data-message error-message" role="alert">{message}</div>}
    {successMessage && <div className="data-message success-message" role="status" aria-live="polite">{successMessage}</div>}
    {busy && !state && <p role="status">Loading pay types…</p>}
    {state && <>
      {taxEditing && taxState && <section className="vehicle-table-card"><form className="details-panel editor-body" onSubmit={saveTaxRate}><div><h2>Edit Loaner &amp; Rental Tax</h2><p>Enter the percentage transferred to Tekion as a separate tax line. Calculations use exact PostgreSQL numeric multiplication without rounding.</p></div><label>Tax percentage<input required inputMode="decimal" value={taxPercentage} disabled={busy} onChange={(event) => setTaxPercentage(event.target.value)} /><span>Greater than 0 through 100.</span></label><p>GM Warranty and Extended Warranty are currently the only exempt pay types; stored Admin taxability is authoritative.</p><div className="page-actions"><button className="primary-action" disabled={busy} type="submit">Save Tax Rate</button><button type="button" disabled={busy} onClick={async () => { setMessage(null); await load(); setTaxEditing(false) }}>Cancel / Return to Rates, Fees &amp; Billing Rules</button></div></form></section>}
      {!focused && taxState && <section className="vehicle-table-card loaner-rental-tax"><div className="section-heading"><div><h2>Loaner &amp; Rental Tax</h2><p>Tax is calculated exactly without rounding and appears as a separate line for transfer into Tekion.</p></div><button className="primary-action" type="button" disabled={busy} onClick={() => { setMessage(null); setSuccessMessage(null); setTaxPercentage(String(taxState.percentage)); setTaxEditing(true) }}>Edit</button></div><p><strong>{taxState.percentage}%</strong></p><p>GM Warranty and Extended Warranty are currently the only exempt pay types; stored Admin taxability is authoritative.</p></section>}
      {!focused && <section className="vehicle-table-card"><div className="section-heading"><div><h2>Pay Types</h2><p>Disabled pay types remain available to historical billing records.</p></div><button type="button" onClick={() => void load()} disabled={busy}>Refresh</button></div>
        <div className="table-wrap"><table><thead><tr><th>Pay type</th><th>Description</th><th>Taxable</th><th>Daily amount (Customer Pay: Standard RO daily rate)</th><th>Sort order</th><th>Status</th><th>Action</th></tr></thead><tbody>
          {state.payTypes.map((item) => <tr key={item.id}><td><strong>{item.payType}</strong></td><td>{item.description || '—'}</td><td>{item.taxable ? 'Yes' : 'No'}</td>
            <td>{item.defaultDailyAmount == null ? '—' : item.defaultDailyAmount.toLocaleString(undefined, { style: 'currency', currency: 'USD' })}</td><td>{item.sortOrder}</td><td>{item.enabled ? 'Enabled' : 'Disabled'}</td><td>
              <button type="button" disabled={busy} onClick={() => editPayType(item)}>Edit</button>{' '}
              <button type="button" disabled={busy} onClick={() => void mutate(supabase.rpc('set_admin_pay_type_rule_enabled_state', { p_pay_type_rule_id: item.id, p_is_enabled: !item.enabled }),
                `The pay type could not be ${item.enabled ? 'disabled' : 'reactivated'}. No changes were applied.`)}>{item.enabled ? 'Disable' : 'Reactivate'}</button>
            </td></tr>)}
        </tbody></table></div></section>}

      {rateFocused && <section className="vehicle-table-card"><form className="details-panel editor-body" onSubmit={saveRentalRate}><div><h2>{rateForm.id?'Edit Rental Rate':'Add Rental Model'}</h2><p>Blank weekly or monthly rates mean not configured, never free. A monthly rate requires a weekly rate. Pricing and capacity remain separate authoritative writes.</p></div><label>Vehicle class / model identifier<input required value={rateForm.vehicleClass} disabled={busy || (!rateForm.saveCapacity && rateForm.id === null)} onChange={e=>setRateForm({...rateForm,vehicleClass:e.target.value})}/></label><label>Daily rate<input required min="0" step="0.01" type="number" value={rateForm.dailyRate} disabled={busy} onChange={e=>setRateForm({...rateForm,dailyRate:e.target.value})}/></label><label>Weekly rate (optional)<input min="0" step="0.01" type="number" value={rateForm.weeklyRate} disabled={busy} onChange={e=>setRateForm({...rateForm,weeklyRate:e.target.value})}/></label><label>Monthly rate (optional)<input min="0" step="0.01" type="number" value={rateForm.monthlyRate} disabled={busy} onChange={e=>setRateForm({...rateForm,monthlyRate:e.target.value})}/></label><label>Sort order<input required min="0" step="1" type="number" value={rateForm.sortOrder} disabled={busy} onChange={e=>setRateForm({...rateForm,sortOrder:e.target.value})}/></label>{rateForm.saveCapacity&&<label>Reservation Capacity<input required min="0" step="1" type="number" value={rateForm.capacity} disabled={busy} onChange={e=>setRateForm({...rateForm,capacity:e.target.value})}/><span>Whole number zero or greater. Pricing is created first, then capacity is saved.</span></label>}<div className="page-actions"><button className="primary-action" disabled={busy} type="submit">{rateForm.id?'Save Rental Rate':'Add Rate'}</button><button type="button" disabled={busy} onClick={async()=>{setMessage(null);await load();setRateForm(emptyRateForm())}}>Cancel / Return to Rates, Fees &amp; Billing Rules</button></div></form></section>}
      {!focused && <section className="vehicle-table-card"><div className="section-heading"><div><h2>Rental Models &amp; Rates</h2><p>Manage each model's current Rental pricing and fixed Reservation Capacity together. Missing capacity remains unavailable; Quotes are non-binding.</p></div><button className="primary-action" type="button" disabled={busy} onClick={()=>setRateForm({...emptyRateForm(),vehicleClass:' ',saveCapacity:true})}>Add Rental Model</button></div>{(!rateState||!capacityModels)&&<p className="data-message">Rental model pricing or capacity settings could not be loaded. Other billing management remains available.</p>}{rateState&&capacityModels&&(currentModels.size===0?<p className="empty-state">No current Rental models are configured or referenced.</p>:<div className="table-wrap"><table><thead><tr><th>Model / class</th><th>Daily / Weekly / Monthly</th><th>Reservation Capacity</th><th>Pricing status</th><th>Capacity status</th><th>Actions</th></tr></thead><tbody>{[...currentModels.values()].map((model)=>{const capacity=model.capacity;const draftKey=modelKey(model.vehicleClass);return <tr key={draftKey}><td><strong>{model.vehicleClass}</strong></td><td>{model.rate?<>{money(model.rate.dailyRate)} / {money(model.rate.weeklyRate)} / {money(model.rate.monthlyRate)}</>:'Not configured'}</td><td><input aria-label={`${model.vehicleClass} Reservation Capacity`} min="0" step="1" type="number" placeholder="Not configured" value={capacityDrafts[draftKey]??''} onChange={(event)=>setCapacityDrafts((current)=>({...current,[draftKey]:event.target.value}))}/></td><td>{model.rate?'Active current Rental rate':'No active Rental rate'}</td><td>{capacity?.configured?`Configured: ${capacity.dailyLimit}`:'Not configured (unavailable)'}</td><td>{model.rate?<button type="button" disabled={busy} onClick={()=>editRentalRate(model.rate!)}>Edit Rate</button>:<button type="button" disabled={busy} onClick={()=>setRateForm({...emptyRateForm(),vehicleClass:model.vehicleClass})}>Add Rate</button>}{' '}<button type="button" disabled={busy} onClick={()=>void saveCapacity(model.vehicleClass,capacityDrafts[draftKey]??'')}>Save Capacity</button>{capacity?.configured&&<><span> </span><button type="button" disabled={busy} onClick={()=>void removeCapacity(capacity)}>Remove Capacity</button></>}</td></tr>})}</tbody></table></div>)}</section>}
      {!focused&&inactiveRates.length>0&&<section className="vehicle-table-card"><h2>Inactive / Previous Rental Rate Cards</h2><p>Historical pricing remains separate from the current model configuration and fully manageable.</p><div className="table-wrap"><table><thead><tr><th>Vehicle class</th><th>Daily / Weekly / Monthly</th><th>Sort order</th><th>Status</th><th>Actions</th></tr></thead><tbody>{inactiveRates.map((item)=><tr key={item.id}><td><strong>{item.vehicleClass}</strong></td><td>{money(item.dailyRate)} / {money(item.weeklyRate)} / {money(item.monthlyRate)}</td><td>{item.sortOrder}</td><td>{item.enabled?'Previous':'Disabled'}</td><td><button type="button" disabled={busy} onClick={()=>editRentalRate(item)}>Edit</button>{' '}<button type="button" disabled={busy} onClick={()=>void setRentalRateEnabled(item)}>{item.enabled?'Disable':'Reactivate'}</button></td></tr>)}</tbody></table></div></section>}
      {!focused&&capacityModels?.some((item)=>item.impact.hardReservations.length||item.impact.atRiskQuotes.length)&&<section className="vehicle-table-card" aria-live="polite"><h2>Future capacity impact</h2>{capacityModels.map((item)=>(item.impact.hardReservations.length>0||item.impact.atRiskQuotes.length>0)&&<div key={`impact-${item.vehicleClass}`}><h3>Authoritative daily impact — {item.vehicleClass}</h3><div className="table-wrap"><table><thead><tr><th>Affected local date</th><th>Saved/effective capacity</th><th>Reservation count + hard overage</th><th>Active Quote count</th><th>Combined pressure + Quote-pressure overage</th></tr></thead><tbody>{item.impact.days.map((day)=><tr key={day.date}><td>{day.date}</td><td>{day.capacityConfigured?`Saved capacity: ${day.capacity}`:`Unavailable (effective capacity: ${day.capacity})`}</td><td>{day.reservationCount}{day.reservationOverage>0&&<strong> — Hard Reservation overage: {day.reservationOverage}</strong>}</td><td>{day.activeQuoteCount}</td><td>{day.combinedCount}{day.quotePressureOverage>0&&<strong> — Quote-pressure overage: {day.quotePressureOverage}</strong>}</td></tr>)}</tbody></table></div>{item.impact.hardReservations.length>0&&<div><h4>Hard Reservation conflicts</h4><p>Committed Reservations exceed saved/effective capacity. No Reservation has been selected for displacement.</p>{warningList(item.impact.hardReservations)}</div>}{item.impact.atRiskQuotes.length>0&&<div><h4>At-risk Quote pressure</h4><p>Quotes are non-binding and do not consume committed capacity, but these active Quotes create pressure if converted.</p>{warningList(item.impact.atRiskQuotes)}</div>}</div>)}</section>}

      {!rateFocused && <section className="vehicle-table-card extended-warranty-providers"><div className="section-heading"><div><h2>Extended Warranty Providers</h2><p>Configure outside Extended Warranty providers separately from GM Warranty and the single Extended Warranty pay type. Each provider must have a normal covered-day limit. Exceptional shorter or longer coverage uses an authorized case override.</p></div>{extendedWarrantyFocusMode === 'list' && <button className="primary-action" type="button" disabled={busy} onClick={() => { setMessage(null); setSuccessMessage(null); setExtendedWarrantyForm({ id: null, providerId: null, providerName: '', defaultDailyAmount: '', coveredDays: '', notes: '' }); setExtendedWarrantyFocusMode('form') }}>Add Extended Warranty Provider</button>}</div>
        {!extendedWarrantyState && <p className="data-message">Extended Warranty provider settings could not be loaded. Pay Type management remains available.</p>}
        {extendedWarrantyState && extendedWarrantyFocusMode === 'list' && <>
          {extendedWarrantyState.providerRules.length === 0 ? <p className="empty-state">No Extended Warranty providers are configured yet. Add providers only after approved business values are available.</p> :
            <div className="table-wrap"><table><thead><tr><th>Provider</th><th>Default daily amount</th><th>Covered-day cap</th><th>Notes</th><th>Status</th><th>Action</th></tr></thead><tbody>{extendedWarrantyState.providerRules.map((item) => <tr key={item.id}><td><strong>{item.providerName}</strong></td><td>{item.defaultDailyAmount == null ? '—' : item.defaultDailyAmount.toLocaleString(undefined, { style: 'currency', currency: 'USD' })}</td><td>{item.coveredDays}</td><td>{item.notes || '—'}</td><td>{item.enabled ? 'Enabled' : 'Disabled'}</td><td><button type="button" disabled={busy} onClick={() => editExtendedWarrantyProvider(item)}>Edit</button>{' '}<button type="button" disabled={busy} onClick={() => void setExtendedWarrantyProviderEnabled(item)}>{item.enabled ? 'Disable' : 'Reactivate'}</button></td></tr>)}</tbody></table></div>}
        </>}
        {extendedWarrantyState && extendedWarrantyFocusMode === 'success' && <div className="details-panel editor-body" role="status" aria-live="polite"><div><h2>Extended Warranty provider saved</h2><p>The provider was saved and authoritative billing-rule data was reloaded. Return to Rates, Fees &amp; Billing Rules to review the current list.</p></div><button className="primary-action" type="button" disabled={busy} onClick={async () => { setSuccessMessage(null); await load(); setExtendedWarrantyFocusMode('list') }}>Return to Rates, Fees &amp; Billing Rules</button></div>}
        {extendedWarrantyState && extendedWarrantyFocusMode === 'form' && <form className="details-panel editor-body" onSubmit={saveExtendedWarrantyProvider}><div><h2>{extendedWarrantyForm.id ? 'Edit Extended Warranty Provider' : 'Add Extended Warranty Provider'}</h2><p>This focused form updates provider/rule defaults through Admin RPCs only; historical cases keep their snapshots.</p></div>
            <label>Provider name<input required value={extendedWarrantyForm.providerName} disabled={busy} onChange={(event) => setExtendedWarrantyForm({ ...extendedWarrantyForm, providerName: event.target.value })}/></label>
            <label>Default daily amount<input min="0" step="0.01" type="number" value={extendedWarrantyForm.defaultDailyAmount} disabled={busy} onChange={(event) => setExtendedWarrantyForm({ ...extendedWarrantyForm, defaultDailyAmount: event.target.value })}/></label>
            <label>Covered-day cap<input required min="1" step="1" type="number" aria-describedby="extended-warranty-cap-help" value={extendedWarrantyForm.coveredDays} disabled={busy} onChange={(event) => setExtendedWarrantyForm({ ...extendedWarrantyForm, coveredDays: event.target.value })}/><span id="extended-warranty-cap-help">Enter the provider's normal covered-day limit. Exceptional extensions use an authorized case override.</span></label>
            <label>Notes<textarea value={extendedWarrantyForm.notes} disabled={busy} onChange={(event) => setExtendedWarrantyForm({ ...extendedWarrantyForm, notes: event.target.value })}/></label>
            <div className="page-actions"><button className="primary-action" disabled={busy} type="submit">{extendedWarrantyForm.id ? 'Save Extended Warranty Provider' : 'Add Extended Warranty Provider'}</button><button type="button" disabled={busy} onClick={async () => { setMessage(null); setExtendedWarrantyForm({ id: null, providerId: null, providerName: '', defaultDailyAmount: '', coveredDays: '', notes: '' }); await load(); setExtendedWarrantyFocusMode('list') }}>Cancel / Return to Rates, Fees &amp; Billing Rules</button></div>
          </form>}
      </section>}

      {!focused && <div className="pay-type-grid">
        {editForm && <form className="details-panel editor-body" onSubmit={savePayType}><div><h2>Edit Pay Type</h2><p>Update billing defaults without changing this pay type's identity.</p></div>
          <label>Pay-type name<input value={editForm.payType} readOnly aria-readonly="true" /></label>
          <label>Description<textarea value={editForm.description} disabled={busy} onChange={(event) => setEditForm({ ...editForm, description: event.target.value })}/></label>
          <label>{editForm.payType.trim().toLowerCase()==='customer pay'?'Standard RO daily rate':'Default daily amount'}<input min="0" step="0.01" type="number" value={editForm.amount} disabled={busy} onChange={(event) => setEditForm({ ...editForm, amount: event.target.value })}/></label>
          <label>Sort order<input required min="0" step="1" type="number" value={editForm.sortOrder} disabled={busy} onChange={(event) => setEditForm({ ...editForm, sortOrder: event.target.value })}/></label>
          <label><input type="checkbox" checked={editForm.taxable} disabled={busy} onChange={(event) => setEditForm({ ...editForm, taxable: event.target.checked })}/> Taxable</label>
          <div className="page-actions"><button className="primary-action" disabled={busy} type="submit">Save Pay Type</button><button type="button" disabled={busy} onClick={() => setEditForm(null)}>Cancel</button></div>
        </form>}
        <form className="details-panel editor-body" onSubmit={addPayType}><div><h2>Add Pay Type</h2><p>New pay types are enabled immediately. Taxability is selected by an authorized Admin; existing pay types are never deleted.</p></div>
          <label>Pay-type name<input required value={form.payType} onChange={(event) => setForm({ ...form, payType: event.target.value })}/></label>
          <label>Description<textarea value={form.description} onChange={(event) => setForm({ ...form, description: event.target.value })}/></label>
          <label>{form.payType.trim().toLowerCase()==='customer pay'?'Standard RO daily rate':'Default daily amount'}<input min="0" step="0.01" type="number" value={form.amount} onChange={(event) => setForm({ ...form, amount: event.target.value })}/></label>
          <label>Sort order<input required min="0" step="1" type="number" value={form.sortOrder} onChange={(event) => setForm({ ...form, sortOrder: event.target.value })}/></label>
          <label><input type="checkbox" checked={form.taxable} disabled={busy} onChange={(event) => setForm({ ...form, taxable: event.target.checked })}/> Taxable</label>
          <button className="primary-action" disabled={busy} type="submit">Add Pay Type</button>
        </form>
        <section className="details-panel editor-body"><div><h2>Fleet Board Colors</h2><p>Colors apply only to currently active pay types.</p></div>
          {state.payTypes.filter((item) => item.enabled).map((item) => { const pair = draftColors[item.payType] ?? FALLBACK_COLORS; return <div className="color-row" key={item.id}><strong>{item.payType}</strong>
            <label>Background<input type="color" value={pair.background_color} disabled={busy} onChange={(event) => { setDraftColors((current) => ({ ...current, [item.payType]: { ...pair, background_color: event.target.value } })); setDirtyColorKeys((current) => new Set(current).add(item.payType)) }}/></label>
            <label>Text<input type="color" value={pair.text_color} disabled={busy} onChange={(event) => { setDraftColors((current) => ({ ...current, [item.payType]: { ...pair, text_color: event.target.value } })); setDirtyColorKeys((current) => new Set(current).add(item.payType)) }}/></label>
            <span className="color-preview" style={{ background: pair.background_color, color: pair.text_color }}>Preview</span></div> })}
          <button className="primary-action" type="button" disabled={busy} onClick={saveColors}>Save Colors</button>
        </section>
      </div>}
    </>}
  </main>
}
