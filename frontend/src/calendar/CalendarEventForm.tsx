import { useState, type FormEvent } from 'react'
import './CalendarEventForm.css'

export type CalendarFormVehicle = {
  id: string
  stockNumber: string
  modelYear: number | null
  model: string
}

export type CalendarFormEventType = {
  eventType: string
  label: string
}

export type CalendarEventFormValue = {
  id: string | null
  vehicleId: string
  eventType: string
  customerName: string
  startsAt: string
  endsAt: string
  payType: string
  status: string
  referenceNumber: string
  vehicleYear: string
  vehicleMake: string
  vehicleModel: string
}

type Props = {
  title: string
  vehicles: CalendarFormVehicle[]
  eventTypes: CalendarFormEventType[]
  initialValue: CalendarEventFormValue
  onCancel: () => void
  onSubmit: (value: CalendarEventFormValue) => Promise<string | null>
}

export function CalendarEventForm({ title, vehicles, eventTypes, initialValue, onCancel, onSubmit }: Props) {
  const [value, setValue] = useState(initialValue)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const submit = async (formEvent: FormEvent<HTMLFormElement>) => {
    formEvent.preventDefault()
    setError(null)

    if (!value.vehicleId || !value.eventType || !value.customerName.trim() || !value.startsAt || !value.endsAt || !value.status.trim()) {
      setError('Complete all required fields.')
      return
    }

    const startsAt = new Date(value.startsAt)
    const endsAt = new Date(value.endsAt)
    if (Number.isNaN(startsAt.getTime()) || Number.isNaN(endsAt.getTime()) || startsAt >= endsAt) {
      setError('End date and time must be after the start date and time.')
      return
    }

    setSaving(true)
    const submitError = await onSubmit(value)
    if (submitError) setError(submitError)
    setSaving(false)
  }

  const update = (field: keyof CalendarEventFormValue, nextValue: string) =>
    setValue(current => ({ ...current, [field]: nextValue }))

  return (
    <div className="calendar-modal" role="dialog" aria-modal="true" aria-labelledby="calendar-event-form-title">
      <form className="calendar-event-form" onSubmit={event => void submit(event)}>
        <h2 id="calendar-event-form-title">{title}</h2>
        <label>Vehicle *<select required value={value.vehicleId} onChange={event => update('vehicleId', event.target.value)}><option value="">Select a vehicle</option>{vehicles.map(vehicle => <option value={vehicle.id} key={vehicle.id}>{vehicle.stockNumber} · {vehicle.model}</option>)}</select></label>
        <label>Event type *<select required value={value.eventType} onChange={event => update('eventType', event.target.value)}><option value="">Select an event type</option>{eventTypes.map(type => <option value={type.eventType} key={type.eventType}>{type.label}</option>)}</select></label>
        <label>Customer name *<input required value={value.customerName} onChange={event => update('customerName', event.target.value)} /></label>
        <div className="form-columns"><label>Start *<input required type="datetime-local" step="900" value={value.startsAt} onChange={event => update('startsAt', event.target.value)} /></label><label>End *<input required type="datetime-local" step="900" value={value.endsAt} onChange={event => update('endsAt', event.target.value)} /></label></div>
        <div className="form-columns"><label>Pay type<input value={value.payType} onChange={event => update('payType', event.target.value)} /></label><label>Status *<input required value={value.status} onChange={event => update('status', event.target.value)} /></label></div>
        <label>Reference number<input value={value.referenceNumber} onChange={event => update('referenceNumber', event.target.value)} /></label>
        <div className="form-columns vehicle-description"><label>Vehicle year<input type="number" min="1980" max="2100" value={value.vehicleYear} onChange={event => update('vehicleYear', event.target.value)} /></label><label>Vehicle make<input value={value.vehicleMake} onChange={event => update('vehicleMake', event.target.value)} /></label><label>Vehicle model<input value={value.vehicleModel} onChange={event => update('vehicleModel', event.target.value)} /></label></div>
        {error && <div className="calendar-error" role="alert">{error}</div>}
        <div className="form-actions"><button type="button" disabled={saving} onClick={onCancel}>Cancel</button><button type="submit" className="primary-action" disabled={saving}>{saving ? 'Saving…' : 'Save event'}</button></div>
      </form>
    </div>
  )
}
