import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'

type ModelCapacity={vehicleClass:string;dailyLimit:number|null;configured:boolean}
const record=(value:unknown):Record<string,unknown>|null=>typeof value==='object'&&value!==null&&!Array.isArray(value)?value as Record<string,unknown>:null

export function ReservationCapacityManagement({onBack}:{onBack:()=>void}){
  const [models,setModels]=useState<ModelCapacity[]>([]);const [drafts,setDrafts]=useState<Record<string,string>>({});const [busy,setBusy]=useState(false);const [message,setMessage]=useState<string|null>(null)
  const load=useCallback(async()=>{setBusy(true);setMessage(null);const result=await supabase.rpc('get_admin_rental_reservation_capacity_state');const root=record(result.data)
    if(result.error||root?.status!=='admin_rental_reservation_capacity_ready'||!Array.isArray(root.models)){setMessage('Reservation Capacity configuration could not be loaded.');setBusy(false);return}
    const parsed=root.models.map(record).filter(Boolean).map(item=>({vehicleClass:typeof item!.vehicle_class==='string'?item!.vehicle_class:'',dailyLimit:typeof item!.daily_limit==='number'?item!.daily_limit:null,configured:item!.configured===true})).filter(item=>item.vehicleClass)
    setModels(parsed);setDrafts(Object.fromEntries(parsed.map(item=>[item.vehicleClass,item.dailyLimit===null?'':String(item.dailyLimit)])));setBusy(false)
  },[])
  useEffect(()=>{void load()},[load])
  const save=async(item:ModelCapacity)=>{const value=drafts[item.vehicleClass];if(!/^\d+$/.test(value)){setMessage('Reservation Capacity must be a whole number zero or greater.');return}setBusy(true);setMessage(null);const result=await supabase.rpc('upsert_admin_rental_reservation_capacity_state',{p_vehicle_class:item.vehicleClass,p_daily_limit:Number(value)});if(result.error)setMessage('Reservation Capacity could not be saved.');else await load();setBusy(false)}
  const remove=async(item:ModelCapacity)=>{setBusy(true);setMessage(null);const result=await supabase.rpc('remove_admin_rental_reservation_capacity_state',{p_vehicle_class:item.vehicleClass});if(result.error)setMessage('Reservation Capacity configuration could not be removed.');else await load();setBusy(false)}
  return <main className="content"><section className="page-heading"><div><p className="eyebrow">ADMIN / RENTAL</p><h1>Reservation Capacity</h1><p>Configure model-level capacity for future Rental Reservations. Missing configuration is unavailable; no defaults are invented.</p></div><div className="page-actions"><button type="button" onClick={onBack}>Back to Admin Console</button><button type="button" onClick={()=>void load()} disabled={busy}>Refresh</button></div></section>
    {message&&<div className="data-message error-message" role="alert">{message}</div>}
    <section className="vehicle-table-card"><div className="table-wrap"><table><thead><tr><th>Rental model/class</th><th>Current capacity</th><th>Configuration</th><th>Action</th></tr></thead><tbody>{models.map(item=><tr key={item.vehicleClass}><td><strong>{item.vehicleClass}</strong></td><td><input aria-label={`${item.vehicleClass} daily Reservation Capacity`} inputMode="numeric" value={drafts[item.vehicleClass]??''} placeholder="Not configured" onChange={event=>setDrafts(current=>({...current,[item.vehicleClass]:event.target.value}))}/></td><td>{item.configured?`Configured: ${item.dailyLimit}`:'Not configured'}</td><td><button type="button" disabled={busy} onClick={()=>void save(item)}>Save</button>{item.configured&&<button type="button" disabled={busy} onClick={()=>void remove(item)}>Remove</button>}</td></tr>)}</tbody></table></div>{!busy&&models.length===0&&<p className="empty-state">No active Rental rate-card models are available. Configure approved Rental rates first.</p>}</section>
  </main>
}
