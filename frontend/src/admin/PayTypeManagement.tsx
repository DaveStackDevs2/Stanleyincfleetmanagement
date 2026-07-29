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
type PayTypeState = { payTypes: PayType[]; colors: Record<string, ColorPair> }
type ColorState = { payTypes: string[]; colors: Record<string, ColorPair> }

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

export function PayTypeManagement({ onBack }: { onBack: () => void }) {
  const [state, setState] = useState<PayTypeState | null>(null)
  const [draftColors, setDraftColors] = useState<Record<string, ColorPair>>({})
  const [dirtyColorKeys, setDirtyColorKeys] = useState<Set<string>>(() => new Set())
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [successMessage, setSuccessMessage] = useState<string | null>(null)
  const [form, setForm] = useState({ payType: '', taxable: false, amount: '', sortOrder: '0', description: '' })

  const load = useCallback(async () => {
    setBusy(true); setMessage(null); setSuccessMessage(null)
    const [rules, palette] = await Promise.all([
      supabase.rpc('get_admin_pay_type_rules_state'),
      supabase.rpc('get_fleet_board_pay_type_colors_state'),
    ])
    try {
      if (rules.error || palette.error) throw new Error('request-failed')
      const { payTypes, colors } = parsePayTypeState(rules.data)
      parseColors(palette.data)
      setState({ payTypes, colors })
      setDraftColors(Object.fromEntries(payTypes.filter((item) => item.enabled).map((item) => [
        item.payType, colors[item.payType] ?? FALLBACK_COLORS,
      ])))
      setDirtyColorKeys(new Set())
      return true
    } catch {
      setState(null)
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
      p_default_daily_amount: amount, p_sort_order: sortOrder,
      p_description: form.description.trim() || null,
    }), 'The pay type could not be added. Review the values and try again.').then((saved) => {
      if (saved) setForm({ payType: '', taxable: false, amount: '', sortOrder: '0', description: '' })
    })
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

  return <main className="content management-page pay-type-page">
    <section className="fleet-header"><div><p className="eyebrow">ADMINISTRATION / BILLING</p>
      <h1>Rates, Fees &amp; Billing Rules</h1><p>Manage pay types and the colors used to identify active billing on the Fleet Board.</p></div>
      <div className="page-actions"><button className="secondary-action" type="button" onClick={onBack}>Back to Admin Console</button></div>
    </section>
    {message && <div className="data-message error-message" role="alert">{message}</div>}
    {successMessage && <div className="data-message success-message" role="status" aria-live="polite">{successMessage}</div>}
    {busy && !state && <p role="status">Loading pay types…</p>}
    {state && <>
      <section className="vehicle-table-card"><div className="section-heading"><div><h2>Pay Types</h2><p>Disabled pay types remain available to historical billing records.</p></div><button type="button" onClick={() => void load()} disabled={busy}>Refresh</button></div>
        <div className="table-wrap"><table><thead><tr><th>Pay type</th><th>Description</th><th>Taxable</th><th>Daily amount</th><th>Sort order</th><th>Status</th><th>Action</th></tr></thead><tbody>
          {state.payTypes.map((item) => <tr key={item.id}><td><strong>{item.payType}</strong></td><td>{item.description || '—'}</td><td>{item.taxable ? 'Yes' : 'No'}</td>
            <td>{item.defaultDailyAmount == null ? '—' : item.defaultDailyAmount.toLocaleString(undefined, { style: 'currency', currency: 'USD' })}</td><td>{item.sortOrder}</td><td>{item.enabled ? 'Enabled' : 'Disabled'}</td><td>
              <button type="button" disabled={busy} onClick={() => void mutate(supabase.rpc('set_admin_pay_type_rule_enabled_state', { p_pay_type_rule_id: item.id, p_is_enabled: !item.enabled }),
                `The pay type could not be ${item.enabled ? 'disabled' : 'reactivated'}. No changes were applied.`)}>{item.enabled ? 'Disable' : 'Reactivate'}</button>
            </td></tr>)}
        </tbody></table></div></section>
      <div className="pay-type-grid">
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
      </div>
    </>}
  </main>
}
