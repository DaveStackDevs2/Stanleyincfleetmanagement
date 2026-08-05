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
type RentalRateRule = { id: string; vehicleClass: string; payTypeRuleId: string; payType: string; dailyRate: number; sortOrder: number; enabled: boolean; current: boolean }
type RentalRatePayType = { id: string; payType: string; enabled: boolean; sortOrder: number }
type RentalRateState = { rateRules: RentalRateRule[]; payTypes: RentalRatePayType[] }
type PayTypeState = { payTypes: PayType[]; colors: Record<string, ColorPair> }
type ColorState = { payTypes: string[]; colors: Record<string, ColorPair> }
type EditForm = { id: string; payType: string; taxable: boolean; amount: string; sortOrder: string; description: string }
type RentalRateForm = { id: string | null; vehicleClass: string; payTypeRuleId: string; dailyRate: string; sortOrder: string }
type ExtendedWarrantyProviderRule = { id: string; providerId: string; providerName: string; enabled: boolean; defaultDailyAmount: number | null; coveredDays: number | null; requiresApproval: boolean; notes: string }
type ExtendedWarrantyState = { providerRules: ExtendedWarrantyProviderRule[] }
type ExtendedWarrantyForm = { id: string | null; providerId: string | null; providerName: string; defaultDailyAmount: string; coveredDays: string; requiresApproval: boolean; notes: string }
type ExtendedWarrantyFocusMode = 'list' | 'form' | 'success'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const HEX = /^#[0-9a-f]{6}$/i
const FALLBACK_COLORS: ColorPair = { background_color: '#e5e7eb', text_color: '#374151' }
const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value)

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
  if (!isRecord(item) || typeof item.rental_rate_rule_id !== 'string' || !UUID.test(item.rental_rate_rule_id) ||
    typeof item.vehicle_class !== 'string' || !item.vehicle_class.trim() ||
    typeof item.pay_type_rule_id !== 'string' || !UUID.test(item.pay_type_rule_id) ||
    typeof item.pay_type !== 'string' || !item.pay_type.trim() ||
    typeof item.daily_rate !== 'number' || !Number.isFinite(item.daily_rate) || item.daily_rate < 0 ||
    typeof item.sort_order !== 'number' || !Number.isInteger(item.sort_order) || item.sort_order < 0 ||
    typeof item.is_active !== 'boolean' || typeof item.is_current !== 'boolean' ||
    typeof item.effective_from !== 'string' || !(item.effective_to === null || typeof item.effective_to === 'string') ||
    typeof item.created_at !== 'string' || typeof item.updated_at !== 'string') {
    throw new Error('invalid-rental-rate-rule')
  }
  return { id: item.rental_rate_rule_id, vehicleClass: item.vehicle_class, payTypeRuleId: item.pay_type_rule_id,
    payType: item.pay_type, dailyRate: item.daily_rate, sortOrder: item.sort_order, enabled: item.is_active, current: item.is_current }
}

function parseRentalRateState(value: unknown): RentalRateState {
  if (!isRecord(value) || value.status !== 'admin_rental_rate_rules_ready' || value.can_manage !== true ||
    !Array.isArray(value.rate_rules) || !Array.isArray(value.pay_types)) throw new Error('invalid-rental-rate-state')
  const rateRules = value.rate_rules.map(parseRentalRateRule)
  const payTypes = value.pay_types.map((item) => {
    if (!isRecord(item) || typeof item.pay_type_rule_id !== 'string' || !UUID.test(item.pay_type_rule_id) ||
      typeof item.pay_type !== 'string' || !item.pay_type.trim() || typeof item.is_enabled !== 'boolean' ||
      typeof item.sort_order !== 'number' || !Number.isInteger(item.sort_order)) throw new Error('invalid-rental-rate-pay-type')
    return { id: item.pay_type_rule_id, payType: item.pay_type, enabled: item.is_enabled, sortOrder: item.sort_order }
  })
  return { rateRules, payTypes }
}

function parseExtendedWarrantyProviderRule(item: unknown): ExtendedWarrantyProviderRule {
  if (!isRecord(item) || typeof item.rule_id !== 'string' || !UUID.test(item.rule_id) ||
    typeof item.provider_id !== 'string' || !UUID.test(item.provider_id) ||
    typeof item.provider_name !== 'string' || !item.provider_name.trim() ||
    !(typeof item.is_enabled === 'boolean' || typeof item.provider_is_active === 'boolean' || typeof item.is_active === 'boolean') ||
    !(item.resolved_daily_rate === null || (typeof item.resolved_daily_rate === 'number' && Number.isFinite(item.resolved_daily_rate) && item.resolved_daily_rate >= 0)) ||
    !(item.covered_days === null || (typeof item.covered_days === 'number' && Number.isInteger(item.covered_days) && item.covered_days > 0)) ||
    typeof item.requires_approval !== 'boolean' ||
    !(item.notes === null || typeof item.notes === 'string')) throw new Error('invalid-extended-warranty-provider-rule')
  return { id: item.rule_id, providerId: item.provider_id, providerName: item.provider_name, enabled: Boolean(item.is_enabled ?? item.provider_is_active ?? item.is_active),
    defaultDailyAmount: (item.default_daily_rate as number | null | undefined) ?? item.resolved_daily_rate, coveredDays: item.covered_days, requiresApproval: item.requires_approval, notes: item.notes ?? '' }
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
  if (!isRecord(value) || value.status !== expectedStatus || !isRecord(value.rental_rate_rule)) throw new Error('invalid-rental-rate-mutation')
  const rule = parseRentalRateRule(value.rental_rate_rule)
  if (expectedId && rule.id !== expectedId) throw new Error('unexpected-rental-rate-rule')
  return rule
}

function parseUpdatedPayType(value: unknown, expectedId: string): void {
  if (!isRecord(value) || value.status !== 'admin_pay_type_rule_updated' || !isRecord(value.pay_type_rule)) {
    throw new Error('invalid-update')
  }
  const rule = value.pay_type_rule
  if (rule.pay_type_rule_id !== expectedId || typeof rule.pay_type !== 'string' || !rule.pay_type.trim() ||
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
  const [extendedWarrantyState, setExtendedWarrantyState] = useState<ExtendedWarrantyState | null>(null)
  const [extendedWarrantyForm, setExtendedWarrantyForm] = useState<ExtendedWarrantyForm>({ id: null, providerId: null, providerName: '', defaultDailyAmount: '', coveredDays: '', requiresApproval: false, notes: '' })
  const [extendedWarrantyFocusMode, setExtendedWarrantyFocusMode] = useState<ExtendedWarrantyFocusMode>('list')
  const [rateForm, setRateForm] = useState<RentalRateForm>({ id: null, vehicleClass: '', payTypeRuleId: '', dailyRate: '', sortOrder: '0' })
  const [draftColors, setDraftColors] = useState<Record<string, ColorPair>>({})
  const [dirtyColorKeys, setDirtyColorKeys] = useState<Set<string>>(() => new Set())
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [successMessage, setSuccessMessage] = useState<string | null>(null)
  const [form, setForm] = useState({ payType: '', taxable: false, amount: '', sortOrder: '0', description: '' })
  const [editForm, setEditForm] = useState<EditForm | null>(null)

  const load = useCallback(async () => {
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const [rules, palette, rentalRates, extendedWarranty] = await Promise.all([
      supabase.rpc('get_admin_pay_type_rules_state'),
      supabase.rpc('get_fleet_board_pay_type_colors_state'),
      supabase.rpc('get_admin_rental_rate_rules_state'),
      supabase.rpc('get_admin_billing_configuration_state'),
    ])
    try {
      if (rules.error || palette.error) throw new Error('request-failed')
      const { payTypes, colors } = parsePayTypeState(rules.data)
      parseColors(palette.data)
      if (!rentalRates.error) setRateState(parseRentalRateState(rentalRates.data))
      else setRateState(null)
      if (!extendedWarranty.error) setExtendedWarrantyState(parseExtendedWarrantyState(extendedWarranty.data))
      else setExtendedWarrantyState(null)
      setState({ payTypes, colors })
      setDraftColors(Object.fromEntries(payTypes.filter((item) => item.enabled).map((item) => [
        item.payType, colors[item.payType] ?? FALLBACK_COLORS,
      ])))
      setDirtyColorKeys(new Set())
      return true
    } catch {
      setState(null)
      setRateState(null)
      setExtendedWarrantyState(null)
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

  const addPayType = (event: FormEvent) => {
    event.preventDefault()
    const amount = form.amount.trim() === '' ? null : Number(form.amount)
    const sortOrder = Number(form.sortOrder)
    if (!form.payType.trim() || (amount !== null && (!Number.isFinite(amount) || amount < 0)) ||
      !Number.isInteger(sortOrder) || sortOrder < 0) {
      setMessage('Enter a pay-type name, an optional non-negative daily amount, and a non-negative whole-number sort order.')
      return
    }
    void mutate(supabase.rpc('create_admin_pay_type_rule_state', {
      p_pay_type: form.payType.trim(), p_is_taxable: form.taxable,
      p_default_daily_rate: amount, p_sort_order: sortOrder,
      p_description: form.description.trim() || null,
    }), 'The pay type could not be added. Review the values and try again.').then((saved) => {
      if (saved) setForm({ payType: '', taxable: false, amount: '', sortOrder: '0', description: '' })
    })
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
      p_default_daily_rate: amount, p_sort_order: sortOrder,
      p_description: editForm.description.trim() || null,
    })
    if (result.error) {
      setMessage('The pay type could not be updated. Review the values and try again. No update was confirmed.')
      setBusy(false)
      return
    }
    try {
      parseUpdatedPayType(result.data, editForm.id)
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



  const validateRateForm = (draft: RentalRateForm) => {
    const dailyRate = Number(draft.dailyRate)
    const sortOrder = Number(draft.sortOrder)
    if (!draft.vehicleClass.trim() || !draft.payTypeRuleId || !Number.isFinite(dailyRate) || dailyRate < 0 || !Number.isInteger(sortOrder) || sortOrder < 0) {
      setMessage('Enter a vehicle class, enabled pay type, finite non-negative daily rate, and non-negative whole-number sort order.')
      return null
    }
    return { dailyRate, sortOrder }
  }

  const editRentalRate = (item: RentalRateRule) => {
    setMessage(null); setSuccessMessage(null)
    setRateForm({ id: item.id, vehicleClass: item.vehicleClass, payTypeRuleId: item.payTypeRuleId, dailyRate: String(item.dailyRate), sortOrder: String(item.sortOrder) })
  }

  const saveRentalRate = async (event: FormEvent) => {
    event.preventDefault()
    if (busy) return
    const validated = validateRateForm(rateForm)
    if (!validated) return
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const isEdit = rateForm.id !== null
    const result = isEdit
      ? await supabase.rpc('update_admin_rental_rate_rule_state', { p_rental_rate_rule_id: rateForm.id, p_vehicle_class: rateForm.vehicleClass.trim(), p_pay_type_rule_id: rateForm.payTypeRuleId, p_daily_rate: validated.dailyRate, p_sort_order: validated.sortOrder })
      : await supabase.rpc('create_admin_rental_rate_rule_state', { p_vehicle_class: rateForm.vehicleClass.trim(), p_pay_type_rule_id: rateForm.payTypeRuleId, p_daily_rate: validated.dailyRate, p_sort_order: validated.sortOrder })
    if (result.error) { setMessage(`The rental rate could not be ${isEdit ? 'updated' : 'added'}. Review the values and try again. No change was confirmed.`); setBusy(false); return }
    try { parseRentalRateMutation(result.data, isEdit ? 'admin_rental_rate_rule_updated' : 'admin_rental_rate_rule_created', rateForm.id ?? undefined) }
    catch { setMessage('The rental rate request completed, but its result could not be verified. Refresh before trying again.'); setBusy(false); return }
    const reloaded = await load()
    if (reloaded) { setRateForm({ id: null, vehicleClass: '', payTypeRuleId: '', dailyRate: '', sortOrder: '0' }); setSuccessMessage(`Rental rate ${isEdit ? 'updated' : 'added'} successfully.`) }
    else setMessage('The rental rate changed, but authoritative settings could not be reloaded. Refresh before making another change.')
  }

  const setRentalRateEnabled = async (item: RentalRateRule) => {
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const enabled = !item.enabled
    const result = await supabase.rpc('set_admin_rental_rate_rule_enabled_state', { p_rental_rate_rule_id: item.id, p_is_enabled: enabled })
    if (result.error) { setMessage(`The rental rate could not be ${enabled ? 'reactivated' : 'disabled'}. No changes were applied.`); setBusy(false); return }
    try { parseRentalRateMutation(result.data, enabled ? 'admin_rental_rate_rule_enabled' : 'admin_rental_rate_rule_disabled', item.id) }
    catch { setMessage('The rental rate status changed, but its result could not be verified. Refresh before trying again.'); setBusy(false); return }
    if (await load()) setSuccessMessage(`Rental rate ${enabled ? 'reactivated' : 'disabled'} successfully.`)
    else setMessage(`The rental rate changed, but authoritative settings could not be reloaded after ${enabled ? 'reactivating' : 'disabling'}. Refresh before making another change.`)
  }



  const editExtendedWarrantyProvider = (item: ExtendedWarrantyProviderRule) => {
    setMessage(null); setSuccessMessage(null)
    setExtendedWarrantyForm({ id: item.id, providerId: item.providerId, providerName: item.providerName, defaultDailyAmount: item.defaultDailyAmount === null ? '' : String(item.defaultDailyAmount), coveredDays: item.coveredDays === null ? '' : String(item.coveredDays), requiresApproval: item.requiresApproval, notes: item.notes })
    setExtendedWarrantyFocusMode('form')
  }

  const saveExtendedWarrantyProvider = async (event: FormEvent) => {
    event.preventDefault()
    if (busy) return
    const amount = extendedWarrantyForm.defaultDailyAmount.trim() === '' ? null : Number(extendedWarrantyForm.defaultDailyAmount)
    const coveredDays = extendedWarrantyForm.coveredDays.trim() === '' ? null : Number(extendedWarrantyForm.coveredDays)
    if (!extendedWarrantyForm.providerName.trim() || (amount !== null && (!Number.isFinite(amount) || amount < 0)) ||
      (coveredDays !== null && (!Number.isInteger(coveredDays) || coveredDays <= 0))) {
      setMessage('Enter a provider name, optional finite non-negative daily amount, and optional positive whole-number covered-day cap.')
      return
    }
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const isEdit = extendedWarrantyForm.id !== null
    const payload = { p_provider_name: extendedWarrantyForm.providerName.trim(), p_default_daily_rate: amount, p_covered_days: coveredDays, p_requires_approval: extendedWarrantyForm.requiresApproval, p_notes: extendedWarrantyForm.notes.trim() || null }
    const result = isEdit
      ? await supabase.rpc('update_admin_extended_warranty_provider_rule_state', { p_provider_id: extendedWarrantyForm.providerId, ...payload })
      : await supabase.rpc('create_admin_extended_warranty_provider_rule_state', payload)
    if (result.error) { setMessage(`The Extended Warranty provider could not be ${isEdit ? 'updated' : 'added'}. Review the values and try again. No change was confirmed.`); setBusy(false); return }
    try { parseExtendedWarrantyMutation(result.data, isEdit ? 'admin_extended_warranty_provider_rule_updated' : 'admin_extended_warranty_provider_rule_created', (extendedWarrantyForm.providerId ?? extendedWarrantyForm.id) ?? undefined) }
    catch { setMessage('The Extended Warranty provider request completed, but its result could not be verified. Refresh before trying again.'); setBusy(false); return }
    const reloaded = await load()
    if (reloaded) { setExtendedWarrantyForm({ id: null, providerId: null, providerName: '', defaultDailyAmount: '', coveredDays: '', requiresApproval: false, notes: '' }); setSuccessMessage(`Extended Warranty provider ${isEdit ? 'updated' : 'added'} successfully.`); setExtendedWarrantyFocusMode('success') }
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

  const extendedWarrantyFocused = extendedWarrantyFocusMode !== 'list'

  return <main className="content management-page pay-type-page">
    <section className="fleet-header"><div><p className="eyebrow">ADMINISTRATION / BILLING</p>
      <h1>Rates, Fees &amp; Billing Rules</h1><p>Manage pay types and the colors used to identify active billing on the Fleet Board.</p></div>
      <div className="page-actions"><button className="secondary-action" type="button" onClick={onBack}>Back to Admin Console</button></div>
    </section>
    {message && <div className="data-message error-message" role="alert">{message}</div>}
    {successMessage && <div className="data-message success-message" role="status" aria-live="polite">{successMessage}</div>}
    {busy && !state && <p role="status">Loading pay types…</p>}
    {state && <>
      {!extendedWarrantyFocused && <section className="vehicle-table-card"><div className="section-heading"><div><h2>Pay Types</h2><p>Disabled pay types remain available to historical billing records.</p></div><button type="button" onClick={() => void load()} disabled={busy}>Refresh</button></div>
        <div className="table-wrap"><table><thead><tr><th>Pay type</th><th>Description</th><th>Taxable</th><th>Daily amount</th><th>Sort order</th><th>Status</th><th>Action</th></tr></thead><tbody>
          {state.payTypes.map((item) => <tr key={item.id}><td><strong>{item.payType}</strong></td><td>{item.description || '—'}</td><td>{item.taxable ? 'Yes' : 'No'}</td>
            <td>{item.defaultDailyAmount == null ? '—' : item.defaultDailyAmount.toLocaleString(undefined, { style: 'currency', currency: 'USD' })}</td><td>{item.sortOrder}</td><td>{item.enabled ? 'Enabled' : 'Disabled'}</td><td>
              <button type="button" disabled={busy} onClick={() => editPayType(item)}>Edit</button>{' '}
              <button type="button" disabled={busy} onClick={() => void mutate(supabase.rpc('set_admin_pay_type_rule_enabled_state', { p_pay_type_rule_id: item.id, p_is_enabled: !item.enabled }),
                `The pay type could not be ${item.enabled ? 'disabled' : 'reactivated'}. No changes were applied.`)}>{item.enabled ? 'Disable' : 'Reactivate'}</button>
            </td></tr>)}
        </tbody></table></div></section>}

      {!extendedWarrantyFocused && <section className="vehicle-table-card"><div className="section-heading"><div><h2>Rental Rates</h2><p>Configure normal daily rates by Admin-entered vehicle class/model identifier and pay type. No rates are preloaded.</p></div></div>
        {!rateState && <p className="data-message">Rental rate settings could not be loaded. Pay Type management remains available.</p>}
        {rateState && <>
          {rateState.rateRules.length === 0 ? <p className="empty-state">No rental rates are configured yet. Add rates only after the business provides approved values.</p> :
            <div className="table-wrap"><table><thead><tr><th>Vehicle class</th><th>Pay type</th><th>Daily rate</th><th>Sort order</th><th>Status</th><th>Action</th></tr></thead><tbody>{rateState.rateRules.map((item) => <tr key={item.id}><td><strong>{item.vehicleClass}</strong></td><td>{item.payType}</td><td>{item.dailyRate.toLocaleString(undefined, { style: 'currency', currency: 'USD' })}</td><td>{item.sortOrder}</td><td>{item.enabled ? 'Enabled' : 'Disabled'}</td><td><button type="button" disabled={busy} onClick={() => editRentalRate(item)}>Edit</button>{' '}<button type="button" disabled={busy} onClick={() => void setRentalRateEnabled(item)}>{item.enabled ? 'Disable' : 'Reactivate'}</button></td></tr>)}</tbody></table></div>}
          <form className="details-panel editor-body" onSubmit={saveRentalRate}><div><h2>{rateForm.id ? 'Edit Rental Rate' : 'Add Rental Rate'}</h2><p>Vehicle class is free text. Pay types come from the authoritative Admin RPC.</p></div>
            <label>Vehicle class / model identifier<input required value={rateForm.vehicleClass} disabled={busy} onChange={(event) => setRateForm({ ...rateForm, vehicleClass: event.target.value })}/></label>
            <label>Pay type<select required value={rateForm.payTypeRuleId} disabled={busy} onChange={(event) => setRateForm({ ...rateForm, payTypeRuleId: event.target.value })}><option value="">Select an enabled pay type</option>{rateState.payTypes.filter((item) => item.enabled || item.id === rateForm.payTypeRuleId).map((item) => <option disabled={!item.enabled} key={item.id} value={item.id}>{item.payType}{item.enabled ? '' : ' (disabled)'}</option>)}</select></label>
            <label>Daily rate<input required min="0" step="0.01" type="number" value={rateForm.dailyRate} disabled={busy} onChange={(event) => setRateForm({ ...rateForm, dailyRate: event.target.value })}/></label>
            <label>Sort order<input required min="0" step="1" type="number" value={rateForm.sortOrder} disabled={busy} onChange={(event) => setRateForm({ ...rateForm, sortOrder: event.target.value })}/></label>
            <div className="page-actions"><button className="primary-action" disabled={busy} type="submit">{rateForm.id ? 'Save Rental Rate' : 'Add Rental Rate'}</button>{rateForm.id && <button type="button" disabled={busy} onClick={() => setRateForm({ id: null, vehicleClass: '', payTypeRuleId: '', dailyRate: '', sortOrder: '0' })}>Cancel</button>}</div>
          </form>
        </>}
      </section>}


      <section className="vehicle-table-card extended-warranty-providers"><div className="section-heading"><div><h2>Extended Warranty Providers</h2><p>Configure outside Extended Warranty providers separately from GM Warranty and the single Extended Warranty pay type. Leave the covered-day cap blank unless that provider has a maximum number of covered days.</p></div>{extendedWarrantyFocusMode === 'list' && <button className="primary-action" type="button" disabled={busy} onClick={() => { setMessage(null); setSuccessMessage(null); setExtendedWarrantyForm({ id: null, providerId: null, providerName: '', defaultDailyAmount: '', coveredDays: '', requiresApproval: false, notes: '' }); setExtendedWarrantyFocusMode('form') }}>Add Extended Warranty Provider</button>}</div>
        {!extendedWarrantyState && <p className="data-message">Extended Warranty provider settings could not be loaded. Pay Type management remains available.</p>}
        {extendedWarrantyState && extendedWarrantyFocusMode === 'list' && <>
          {extendedWarrantyState.providerRules.length === 0 ? <p className="empty-state">No Extended Warranty providers are configured yet. Add providers only after approved business values are available.</p> :
            <div className="table-wrap"><table><thead><tr><th>Provider</th><th>Default daily amount</th><th>Covered-day cap</th><th>Requires approval</th><th>Notes</th><th>Status</th><th>Action</th></tr></thead><tbody>{extendedWarrantyState.providerRules.map((item) => <tr key={item.id}><td><strong>{item.providerName}</strong></td><td>{item.defaultDailyAmount == null ? '—' : item.defaultDailyAmount.toLocaleString(undefined, { style: 'currency', currency: 'USD' })}</td><td>{item.coveredDays ?? 'No automatic cap'}</td><td>{item.requiresApproval ? 'Yes' : 'No'}</td><td>{item.notes || '—'}</td><td>{item.enabled ? 'Enabled' : 'Disabled'}</td><td><button type="button" disabled={busy} onClick={() => editExtendedWarrantyProvider(item)}>Edit</button>{' '}<button type="button" disabled={busy} onClick={() => void setExtendedWarrantyProviderEnabled(item)}>{item.enabled ? 'Disable' : 'Reactivate'}</button></td></tr>)}</tbody></table></div>}
        </>}
        {extendedWarrantyState && extendedWarrantyFocusMode === 'success' && <div className="details-panel editor-body" role="status" aria-live="polite"><div><h2>Extended Warranty provider saved</h2><p>The provider was saved and authoritative billing-rule data was reloaded. Return to Rates, Fees &amp; Billing Rules to review the current list.</p></div><button className="primary-action" type="button" disabled={busy} onClick={async () => { setSuccessMessage(null); await load(); setExtendedWarrantyFocusMode('list') }}>Return to Rates, Fees &amp; Billing Rules</button></div>}
        {extendedWarrantyState && extendedWarrantyFocusMode === 'form' && <form className="details-panel editor-body" onSubmit={saveExtendedWarrantyProvider}><div><h2>{extendedWarrantyForm.id ? 'Edit Extended Warranty Provider' : 'Add Extended Warranty Provider'}</h2><p>This focused form updates provider/rule defaults through Admin RPCs only; historical cases keep their snapshots.</p></div>
            <label>Provider name<input required value={extendedWarrantyForm.providerName} disabled={busy} onChange={(event) => setExtendedWarrantyForm({ ...extendedWarrantyForm, providerName: event.target.value })}/></label>
            <label>Default daily amount<input min="0" step="0.01" type="number" value={extendedWarrantyForm.defaultDailyAmount} disabled={busy} onChange={(event) => setExtendedWarrantyForm({ ...extendedWarrantyForm, defaultDailyAmount: event.target.value })}/></label>
            <label>Optional covered-day cap<input min="1" step="1" type="number" aria-describedby="extended-warranty-cap-help" value={extendedWarrantyForm.coveredDays} disabled={busy} onChange={(event) => setExtendedWarrantyForm({ ...extendedWarrantyForm, coveredDays: event.target.value })}/><span id="extended-warranty-cap-help">Only enter a number when that provider has a maximum number of covered days. Blank means no automatic cap.</span></label>
            <label className="checkbox-field"><input type="checkbox" checked={extendedWarrantyForm.requiresApproval} disabled={busy} onChange={(event) => setExtendedWarrantyForm({ ...extendedWarrantyForm, requiresApproval: event.target.checked })}/> Requires approval</label>
            <label>Notes<textarea value={extendedWarrantyForm.notes} disabled={busy} onChange={(event) => setExtendedWarrantyForm({ ...extendedWarrantyForm, notes: event.target.value })}/></label>
            <div className="page-actions"><button className="primary-action" disabled={busy} type="submit">{extendedWarrantyForm.id ? 'Save Extended Warranty Provider' : 'Add Extended Warranty Provider'}</button><button type="button" disabled={busy} onClick={async () => { setMessage(null); setExtendedWarrantyForm({ id: null, providerId: null, providerName: '', defaultDailyAmount: '', coveredDays: '', requiresApproval: false, notes: '' }); await load(); setExtendedWarrantyFocusMode('list') }}>Cancel / Return to Rates, Fees &amp; Billing Rules</button></div>
          </form>}
      </section>

      {!extendedWarrantyFocused && <div className="pay-type-grid">
        {editForm && <form className="details-panel editor-body" onSubmit={savePayType}><div><h2>Edit Pay Type</h2><p>Update billing defaults without changing this pay type's identity.</p></div>
          <label>Pay-type name<input value={editForm.payType} readOnly aria-readonly="true" /></label>
          <label>Description<textarea value={editForm.description} disabled={busy} onChange={(event) => setEditForm({ ...editForm, description: event.target.value })}/></label>
          <label>Default daily amount<input min="0" step="0.01" type="number" value={editForm.amount} disabled={busy} onChange={(event) => setEditForm({ ...editForm, amount: event.target.value })}/></label>
          <label>Sort order<input required min="0" step="1" type="number" value={editForm.sortOrder} disabled={busy} onChange={(event) => setEditForm({ ...editForm, sortOrder: event.target.value })}/></label>
          <label className="checkbox-field"><input type="checkbox" checked={editForm.taxable} disabled={busy} onChange={(event) => setEditForm({ ...editForm, taxable: event.target.checked })}/> Taxable</label>
          <div className="page-actions"><button className="primary-action" disabled={busy} type="submit">Save Pay Type</button><button type="button" disabled={busy} onClick={() => setEditForm(null)}>Cancel</button></div>
        </form>}
        <form className="details-panel editor-body" onSubmit={addPayType}><div><h2>Add Pay Type</h2><p>New pay types are enabled immediately. Existing pay types are never deleted.</p></div>
          <label>Pay-type name<input required value={form.payType} onChange={(event) => setForm({ ...form, payType: event.target.value })}/></label>
          <label>Description<textarea value={form.description} onChange={(event) => setForm({ ...form, description: event.target.value })}/></label>
          <label>Default daily amount<input min="0" step="0.01" type="number" value={form.amount} onChange={(event) => setForm({ ...form, amount: event.target.value })}/></label>
          <label>Sort order<input required min="0" step="1" type="number" value={form.sortOrder} onChange={(event) => setForm({ ...form, sortOrder: event.target.value })}/></label>
          <label className="checkbox-field"><input type="checkbox" checked={form.taxable} onChange={(event) => setForm({ ...form, taxable: event.target.checked })}/> Taxable</label>
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
