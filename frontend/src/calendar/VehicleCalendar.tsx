import { useEffect, useMemo, useState, type CSSProperties, type DragEvent } from 'react'
import { useAuthorization } from '../authorization/useAuthorization'
import { supabase } from '../lib/supabase'
import {
  CalendarEventForm,
  type CalendarEventFormValue,
  type CalendarFormEventType,
} from './CalendarEventForm'

type Mode = 'rental' | 'loaner' | 'both'
type View = 'week' | 'day'
type Vehicle = { id:string; stock_number:string; model:string; fleet_type:string; status:string; location:string|null; is_active:boolean }
type CalendarEvent = { id:string; vehicle_id:string; event_type:string; customer_name:string; starts_at:string; ends_at:string; pay_type:string|null; status:string; reference_number:string|null; vehicle_year:number|null; vehicle_make:string|null; vehicle_model:string|null; stock_number:string; has_conflict:boolean; is_overdue:boolean; background_color:string; text_color:string }
type Color = { color_key:string; color_group:string; label:string; background_color:string; text_color:string }
type EventType = { event_type:string; label:string; sort_order:number; is_active:boolean }
type Payload = { status:string; vehicles:Vehicle[]; events:CalendarEvent[]; colors:Color[]; event_types:EventType[] }
type Filters = { location:string; status:string; vehicleType:string; payType:string; eventType:string; customer:string; stock:string; showInactive:boolean }

const defaults:Filters={location:'',status:'',vehicleType:'',payType:'',eventType:'',customer:'',stock:'',showInactive:false}
const DAY=86_400_000
const isoDay=(date:Date)=>date.toISOString().slice(0,10)
const addDays=(date:Date,days:number)=>new Date(date.getTime()+days*DAY)
const startDay=(date:Date)=>new Date(date.getFullYear(),date.getMonth(),date.getDate())
const readStored=<T,>(key:string,fallback:T):T=>{try{const value=localStorage.getItem(key);return value?JSON.parse(value) as T:fallback}catch{return fallback}}
const validPayload=(value:unknown):value is Payload=>{if(!value||typeof value!=='object')return false;const item=value as Partial<Payload>;return item.status==='vehicle_calendar_ready'&&Array.isArray(item.vehicles)&&Array.isArray(item.events)&&Array.isArray(item.colors)&&Array.isArray(item.event_types)}
const minutesSinceSeven=(value:string)=>{const date=new Date(value);return date.getHours()*60+date.getMinutes()-420}
const timelineStyle=(event:CalendarEvent):CSSProperties=>{const left=Math.max(0,minutesSinceSeven(event.starts_at))/720*100;const right=Math.min(720,minutesSinceSeven(event.ends_at));return{left:`${left}%`,width:`${Math.max(1,(right-Math.max(0,minutesSinceSeven(event.starts_at)))/720*100)}%`}}
const toLocalInput=(date:Date)=>{const local=new Date(date.getTime()-date.getTimezoneOffset()*60_000);return local.toISOString().slice(0,16)}

export function VehicleCalendar({onBack}:{onBack:()=>void}){
  const {permissionKeys}=useAuthorization()
  const [mode,setMode]=useState<Mode>(()=>readStored('calendar.mode','both'))
  const [view,setView]=useState<View>(()=>readStored('calendar.view','week'))
  const [date,setDate]=useState(()=>startDay(new Date(readStored('calendar.date',isoDay(new Date())))))
  const [filters,setFilters]=useState<Filters>(()=>readStored('calendar.filters',defaults))
  const [payload,setPayload]=useState<Payload|null>(null)
  const [error,setError]=useState<string|null>(null)
  const [loading,setLoading]=useState(true)
  const [reloadToken,setReloadToken]=useState(0)
  const [monthOpen,setMonthOpen]=useState(false)
  const [month,setMonth]=useState(()=>new Date(date.getFullYear(),date.getMonth(),1))
  const [collapsed,setCollapsed]=useState({loaner:false,rental:false})
  const [focusedVehicle,setFocusedVehicle]=useState<Vehicle|null>(null)
  const [focusedEvent,setFocusedEvent]=useState<CalendarEvent|null>(null)
  const [formValue,setFormValue]=useState<CalendarEventFormValue|null>(null)
  const [dark,setDark]=useState(()=>readStored('calendar.dark',false))
  const [colorsOpen,setColorsOpen]=useState(false)
  const canCreate=permissionKeys.includes('calendar.create')
  const canEdit=permissionKeys.includes('calendar.edit')
  const canDelete=permissionKeys.includes('calendar.delete')
  const canConfigureColors=permissionKeys.includes('calendar.configure_colors')
  const rangeStart=view==='day'?date:addDays(date,-date.getDay())
  const rangeEnd=addDays(rangeStart,view==='day'?1:7)
  const rangeStartIso=rangeStart.toISOString()
  const rangeEndIso=rangeEnd.toISOString()

  useEffect(()=>{localStorage.setItem('calendar.mode',JSON.stringify(mode));localStorage.setItem('calendar.view',JSON.stringify(view));localStorage.setItem('calendar.date',JSON.stringify(isoDay(date)));localStorage.setItem('calendar.filters',JSON.stringify(filters));localStorage.setItem('calendar.dark',JSON.stringify(dark))},[mode,view,date,filters,dark])
  useEffect(()=>{let current=true;const load=async()=>{setLoading(true);setError(null);const {data,error:loadError}=await supabase.rpc('get_vehicle_calendar_state',{p_range_start:rangeStartIso,p_range_end:rangeEndIso});if(!current)return;if(loadError||!validPayload(data)){setError('The vehicle calendar could not be loaded.');setPayload(null)}else setPayload(data);setLoading(false)};void load();return()=>{current=false}},[rangeStartIso,rangeEndIso,reloadToken])

  const vehicles=useMemo(()=>(payload?.vehicles??[]).filter(vehicle=>{const type=vehicle.fleet_type.toLowerCase();return(mode==='both'||type.includes(mode))&&(filters.showInactive||vehicle.is_active)&&(!filters.location||vehicle.location===filters.location)&&(!filters.status||vehicle.status===filters.status)&&(!filters.vehicleType||vehicle.fleet_type===filters.vehicleType)&&(!filters.stock||vehicle.stock_number.toLowerCase().includes(filters.stock.toLowerCase()))}),[payload,mode,filters])
  const events=useMemo(()=>(payload?.events??[]).filter(event=>(!filters.payType||event.pay_type===filters.payType)&&(!filters.eventType||event.event_type===filters.eventType)&&(!filters.customer||event.customer_name.toLowerCase().includes(filters.customer.toLowerCase()))),[payload,filters])
  const groups=[{key:'loaner' as const,label:'Loaner Vehicles',rows:vehicles.filter(v=>v.fleet_type.toLowerCase().includes('loaner'))},{key:'rental' as const,label:'Rental Vehicles',rows:vehicles.filter(v=>v.fleet_type.toLowerCase().includes('rental'))}].filter(group=>mode==='both'||mode===group.key)
  const days=Array.from({length:view==='day'?1:7},(_,index)=>addDays(rangeStart,index))
  const locations=[...new Set(payload?.vehicles.map(v=>v.location).filter((v):v is string=>!!v)??[])]
  const statuses=[...new Set(payload?.vehicles.map(v=>v.status)??[])]
  const types=[...new Set(payload?.vehicles.map(v=>v.fleet_type)??[])]
  const formVehicles=(payload?.vehicles??[]).map(vehicle=>({id:vehicle.id,stockNumber:vehicle.stock_number,modelYear:null,model:vehicle.model}))
  const formEventTypes:CalendarFormEventType[]=(payload?.event_types??[]).map(type=>({eventType:type.event_type,label:type.label}))

  const openCreate=(vehicle?:Vehicle,eventType='reservation')=>{
    if(!canCreate)return
    const start=new Date(date.getFullYear(),date.getMonth(),date.getDate(),8,0)
    const end=new Date(start.getTime()+60*60*1000)
    setFocusedVehicle(null)
    setFormValue({id:null,vehicleId:vehicle?.id??'',eventType,customerName:'',startsAt:toLocalInput(start),endsAt:toLocalInput(end),payType:'',status:'scheduled',referenceNumber:'',vehicleYear:'',vehicleMake:'',vehicleModel:vehicle?.model??''})
  }

  const openEdit=(event:CalendarEvent)=>{
    if(!canEdit)return
    setFocusedEvent(null)
    setFormValue({id:event.id,vehicleId:event.vehicle_id,eventType:event.event_type,customerName:event.customer_name,startsAt:toLocalInput(new Date(event.starts_at)),endsAt:toLocalInput(new Date(event.ends_at)),payType:event.pay_type??'',status:event.status,referenceNumber:event.reference_number??'',vehicleYear:event.vehicle_year?.toString()??'',vehicleMake:event.vehicle_make??'',vehicleModel:event.vehicle_model??''})
  }

  const submitForm=async(value:CalendarEventFormValue)=>{
    const {error:saveError}=await supabase.rpc('save_calendar_event_state',{p_event_id:value.id,p_vehicle_id:value.vehicleId,p_event_type:value.eventType,p_customer_name:value.customerName.trim(),p_starts_at:new Date(value.startsAt).toISOString(),p_ends_at:new Date(value.endsAt).toISOString(),p_pay_type:value.payType.trim()||null,p_status:value.status.trim(),p_reference_number:value.referenceNumber.trim()||null,p_vehicle_year:value.vehicleYear?Number(value.vehicleYear):null,p_vehicle_make:value.vehicleMake.trim()||null,p_vehicle_model:value.vehicleModel.trim()||null})
    if(saveError)return 'The event could not be saved because the vehicle is unavailable, the dates overlap, or permission was denied.'
    setFormValue(null)
    setReloadToken(value=>value+1)
    return null
  }

  const saveMove=async(event:CalendarEvent,vehicle:Vehicle,nextStart:Date,nextEnd:Date)=>{if(!canEdit)return;if(!window.confirm(`Save the change for ${event.customer_name} on ${vehicle.stock_number}?`))return;const {error:saveError}=await supabase.rpc('save_calendar_event_state',{p_event_id:event.id,p_vehicle_id:vehicle.id,p_event_type:event.event_type,p_customer_name:event.customer_name,p_starts_at:nextStart.toISOString(),p_ends_at:nextEnd.toISOString(),p_pay_type:event.pay_type,p_status:event.status,p_reference_number:event.reference_number,p_vehicle_year:event.vehicle_year,p_vehicle_make:event.vehicle_make,p_vehicle_model:event.vehicle_model});if(saveError){setError('The change was not saved because it conflicts or the vehicle is unavailable.');return}setReloadToken(value=>value+1)}
  const handleDrop=(drag:DragEvent<HTMLDivElement>,vehicle:Vehicle,day:Date)=>{const event=events.find(item=>item.id===drag.dataTransfer.getData('text/calendar-event'));if(!event||!canEdit)return;const bounds=drag.currentTarget.getBoundingClientRect();const oldStart=new Date(event.starts_at);const oldEnd=new Date(event.ends_at);if(view==='day'){const minutes=Math.max(0,Math.min(720,Math.round(((drag.clientX-bounds.left)/bounds.width*720)/15)*15));if(drag.dataTransfer.getData('text/calendar-resize')==='true'){const nextEnd=new Date(day.getFullYear(),day.getMonth(),day.getDate(),7,minutes);if(nextEnd>oldStart)void saveMove(event,vehicle,oldStart,nextEnd);return}const nextStart=new Date(day.getFullYear(),day.getMonth(),day.getDate(),7,minutes);void saveMove(event,vehicle,nextStart,new Date(nextStart.getTime()+oldEnd.getTime()-oldStart.getTime()));return}const nextStart=new Date(day.getFullYear(),day.getMonth(),day.getDate(),oldStart.getHours(),oldStart.getMinutes());void saveMove(event,vehicle,nextStart,new Date(nextStart.getTime()+oldEnd.getTime()-oldStart.getTime()))}
  const beginDrag=(drag:DragEvent<HTMLButtonElement>,event:CalendarEvent)=>{drag.dataTransfer.setData('text/calendar-event',event.id);const bounds=drag.currentTarget.getBoundingClientRect();drag.dataTransfer.setData('text/calendar-resize',view==='day'&&drag.clientX>bounds.right-14?'true':'false')}
  const deleteEvent=async(event:CalendarEvent)=>{if(!canDelete||!window.confirm(`Delete the ${event.event_type} for ${event.customer_name}?`))return;const {error:deleteError}=await supabase.rpc('delete_calendar_event_state',{p_event_id:event.id});if(deleteError){setError('The calendar event could not be deleted.');return}setFocusedEvent(null);setReloadToken(value=>value+1)}
  const monthDays=Array.from({length:42},(_,i)=>addDays(new Date(month.getFullYear(),month.getMonth(),1-month.getDay()),i))
  const timePosition=Math.max(0,Math.min(100,((new Date().getHours()*60+new Date().getMinutes()-420)/720)*100))
  const renderEvent=(event:CalendarEvent)=><button draggable={canEdit} onDragStart={drag=>beginDrag(drag,event)} onClick={()=>setFocusedEvent(event)} title={`${event.customer_name} • ${new Date(event.starts_at).toLocaleString()}–${new Date(event.ends_at).toLocaleString()} • ${event.event_type} • ${event.pay_type??'No pay type'} • ${event.status}`} className={`event-block ${view==='day'?'day-event':''}`} style={{background:event.background_color,color:event.text_color,...(view==='day'?timelineStyle(event):{})}} key={event.id}><strong>{event.customer_name}</strong><span>{new Date(event.starts_at).toLocaleTimeString([],{hour:'numeric',minute:'2-digit'})}–{new Date(event.ends_at).toLocaleTimeString([],{hour:'numeric',minute:'2-digit'})}</span><small>{event.stock_number} · {event.event_type} · {event.pay_type??'—'} · {event.status} · {event.reference_number??'—'} {event.has_conflict||event.is_overdue?'⚠':''}</small></button>

  return <main className={`calendar-page ${dark?'calendar-dark':''}`}>
    <header className="calendar-title"><div><p className="eyebrow">PRIMARY WORKSPACE</p><h1>Vehicle Calendar</h1><p>{date.toLocaleDateString(undefined,{month:'long',day:'numeric',year:'numeric'})}</p></div><div className="calendar-title-actions"><button onClick={onBack}>Admin Console</button>{canCreate&&<button className="primary-action" onClick={()=>openCreate()}>New event</button>}<button onClick={()=>setDark(value=>!value)}>{dark?'Light':'Dark'} mode</button></div></header>
    <section className="calendar-toolbar" aria-label="Calendar controls"><div className="segmented">{(['rental','loaner','both'] as Mode[]).map(item=><button className={mode===item?'active':''} onClick={()=>setMode(item)} key={item}>{item[0].toUpperCase()+item.slice(1)}</button>)}</div><div className="segmented"><button className={view==='day'?'active':''} onClick={()=>setView('day')}>Day</button><button className={view==='week'?'active':''} onClick={()=>setView('week')}>Week</button></div><button onClick={()=>setDate(startDay(new Date()))}>Today</button><button aria-label="Previous range" onClick={()=>setDate(addDays(date,view==='day'?-1:-7))}>‹</button><button aria-label="Next range" onClick={()=>setDate(addDays(date,view==='day'?1:7))}>›</button><div className="month-anchor"><button aria-label="Open monthly date picker" onClick={()=>setMonthOpen(value=>!value)}>▣</button>{monthOpen&&<div className="month-popover"><header><button onClick={()=>setMonth(new Date(month.getFullYear(),month.getMonth()-1,1))}>‹</button><strong>{month.toLocaleDateString(undefined,{month:'long',year:'numeric'})}</strong><button onClick={()=>setMonth(new Date(month.getFullYear(),month.getMonth()+1,1))}>›</button></header><div className="month-grid">{'SMTWTFS'.split('').map((d,i)=><b key={`${d}${i}`}>{d}</b>)}{monthDays.map(d=><button key={isoDay(d)} className={`${d.getMonth()!==month.getMonth()?'outside ':''}${isoDay(d)===isoDay(new Date())?'today ':''}${isoDay(d)===isoDay(date)?'selected':''}`} onClick={()=>{setDate(startDay(d));setMonthOpen(false)}}>{d.getDate()}</button>)}</div></div>}</div>{canConfigureColors&&<button onClick={()=>setColorsOpen(true)}>Colors</button>}</section>
    <section className="calendar-filters"><select value={filters.location} onChange={e=>setFilters({...filters,location:e.target.value})}><option value="">All locations</option>{locations.map(v=><option key={v}>{v}</option>)}</select><select value={filters.status} onChange={e=>setFilters({...filters,status:e.target.value})}><option value="">All statuses</option>{statuses.map(v=><option key={v}>{v}</option>)}</select><select value={filters.vehicleType} onChange={e=>setFilters({...filters,vehicleType:e.target.value})}><option value="">All vehicle types</option>{types.map(v=><option key={v}>{v}</option>)}</select><input aria-label="Pay type" placeholder="Pay type" value={filters.payType} onChange={e=>setFilters({...filters,payType:e.target.value})}/><select value={filters.eventType} onChange={e=>setFilters({...filters,eventType:e.target.value})}><option value="">All events</option>{formEventTypes.map(type=><option value={type.eventType} key={type.eventType}>{type.label}</option>)}</select><input aria-label="Customer search" placeholder="Customer" value={filters.customer} onChange={e=>setFilters({...filters,customer:e.target.value})}/><input aria-label="Stock-number search" placeholder="Stock #" value={filters.stock} onChange={e=>setFilters({...filters,stock:e.target.value})}/><label><input type="checkbox" checked={filters.showInactive} onChange={e=>setFilters({...filters,showInactive:e.target.checked})}/> Inactive</label></section>
    {error&&<div className="calendar-error" role="alert">{error}</div>}{loading?<div className="calendar-loading" role="status">Loading visible dates…</div>:error?null:vehicles.length===0?<div className="calendar-empty">No vehicles match the current calendar mode and filters.</div>:<div className="calendar-scroll"><div className="calendar-grid" style={{'--columns':days.length} as CSSProperties}><div className="resource-head">Stock #</div><div className="timeline-head">{view==='day'?<div className="time-header">{Array.from({length:13},(_,i)=><span key={i}>{i+7>12?i-5:i+7}:00 {i+7>=12?'PM':'AM'}</span>)}</div>:days.map(d=><button className={isoDay(d)===isoDay(date)?'selected-day':''} onClick={()=>setDate(d)} key={isoDay(d)}>{d.toLocaleDateString(undefined,{weekday:'short',month:'short',day:'numeric'})}</button>)}</div>{groups.map(group=><section className={`calendar-section ${group.key}`} key={group.key}><button className="section-bar" onClick={()=>setCollapsed({...collapsed,[group.key]:!collapsed[group.key]})}><span>{collapsed[group.key]?'▸':'▾'} {group.label}</span><small>{group.rows.length} vehicles</small></button>{!collapsed[group.key]&&group.rows.map(vehicle=><div className="calendar-row" key={vehicle.id}><button className="resource-cell" onClick={()=>setFocusedVehicle(vehicle)}><strong>{vehicle.stock_number}</strong><small>{vehicle.model}</small></button><div className={`row-timeline ${view==='day'?'day-timeline':''}`}>{days.map(day=><div className={`day-cell ${isoDay(day)===isoDay(date)?'selected-day':''}`} key={isoDay(day)} onDoubleClick={()=>openCreate(vehicle)} onDragOver={drag=>canEdit&&drag.preventDefault()} onDrop={drag=>handleDrop(drag,vehicle,day)}>{events.filter(event=>event.vehicle_id===vehicle.id&&new Date(event.starts_at)<addDays(day,1)&&new Date(event.ends_at)>day).map(renderEvent)}</div>)}{view==='day'&&<i className="current-time" style={{left:`${timePosition}%`}}/>}</div></div>)}</section>)}</div></div>}
    {colorsOpen&&<div className="calendar-modal" role="dialog" aria-modal="true"><div><button className="modal-close" onClick={()=>setColorsOpen(false)}>×</button><p className="eyebrow">ADMIN CONFIGURATION</p><h2>Calendar colors</h2>{payload?.colors.map(color=><div className="color-row" key={color.color_key}><label>{color.label}<input type="color" value={color.background_color} onChange={e=>setPayload(current=>current?{...current,colors:current.colors.map(item=>item.color_key===color.color_key?{...item,background_color:e.target.value}:item)}:current)}/></label><button onClick={async()=>{const {error:colorError}=await supabase.rpc('set_calendar_color_state',{p_color_key:color.color_key,p_background_color:color.background_color,p_text_color:color.text_color});setError(colorError?'The color could not be saved.':null);if(!colorError)setReloadToken(value=>value+1)}}>Save</button></div>)}</div></div>}
    {(focusedVehicle||focusedEvent)&&<div className="calendar-modal" role="dialog" aria-modal="true"><div><button className="modal-close" onClick={()=>{setFocusedVehicle(null);setFocusedEvent(null)}}>×</button>{focusedEvent?<><p className="eyebrow">{focusedEvent.event_type}</p><h2>{focusedEvent.customer_name}</h2><dl><dt>Time</dt><dd>{new Date(focusedEvent.starts_at).toLocaleString()} – {new Date(focusedEvent.ends_at).toLocaleString()}</dd><dt>Vehicle</dt><dd>{[focusedEvent.vehicle_year,focusedEvent.vehicle_make,focusedEvent.vehicle_model].filter(Boolean).join(' ')||focusedEvent.stock_number}</dd><dt>Status / Pay</dt><dd>{focusedEvent.status} / {focusedEvent.pay_type??'—'}</dd><dt>RO / Reservation</dt><dd>{focusedEvent.reference_number??'—'}</dd></dl><div className="vehicle-actions">{canEdit&&<button onClick={()=>openEdit(focusedEvent)}>Edit event</button>}{canDelete&&<button className="danger-action" onClick={()=>void deleteEvent(focusedEvent)}>Delete event</button>}</div></>:focusedVehicle&&<><p className="eyebrow">VEHICLE CALENDAR</p><h2>{focusedVehicle.stock_number}</h2><p>{focusedVehicle.model} · {focusedVehicle.status}</p>{canCreate&&<div className="vehicle-actions"><button onClick={()=>openCreate(focusedVehicle,'reservation')}>Reserve</button><button onClick={()=>openCreate(focusedVehicle,'quote')}>Quote</button><button onClick={()=>openCreate(focusedVehicle,'maintenance')}>Schedule Maintenance</button></div>}</>}</div></div>}
    {formValue&&<CalendarEventForm title={formValue.id?'Edit calendar event':'Create calendar event'} vehicles={formVehicles} eventTypes={formEventTypes} initialValue={formValue} onCancel={()=>setFormValue(null)} onSubmit={submitForm}/>} 
  </main>
}
