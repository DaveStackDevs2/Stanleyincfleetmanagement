-- Operational Billing Dashboard contract already verified in live project ycwejunodgnnkickjvsk.
-- This migration is declarative/idempotent and does not seed or rewrite operational data.

create or replace function public.get_billing_preview_state(p_transportation_event_id uuid, p_effective_at timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_user_id uuid; v_event public.transportation_events%rowtype; v_res public.reservations%rowtype;
  v_customer public.customers%rowtype; v_vehicle_event public.vehicle_events%rowtype;
  v_vehicle public.vehicles%rowtype; v_contract public.contract_periods%rowtype;
  v_line public.billing_lines%rowtype; v_rule public.pay_type_rules%rowtype;
  v_rate_state jsonb; v_tax_state jsonb; v_rate numeric; v_rate_source text;
  v_days integer; v_subtotal numeric; v_tax numeric; v_total numeric;
  v_segments jsonb; v_warranty jsonb; v_acc_subtotal numeric; v_acc_tax numeric;
begin
  select u.id into v_user_id from public.app_users u
   where u.auth_user_id=auth.uid() and u.is_active=true;
  if v_user_id is null or coalesce(auth.jwt()->>'aal','') <> 'aal2' then
    return jsonb_build_object('status','billing_preview_unavailable','message','Billing preview access is unavailable.');
  end if;
  if p_transportation_event_id is null or p_effective_at is null then
    return jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'effective_at',p_effective_at,'missing_dependencies',jsonb_build_array('transportation_event_or_effective_at'));
  end if;
  select * into v_event from public.transportation_events where id=p_transportation_event_id;
  if not found then return jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'effective_at',p_effective_at,'missing_dependencies',jsonb_build_array('transportation_event')); end if;
  if (select count(*) from public.reservations where transportation_event_id=p_transportation_event_id) <> 1 then
    return jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'effective_at',p_effective_at,'missing_dependencies',jsonb_build_array('reservation'));
  end if;
  select * into v_res from public.reservations where transportation_event_id=p_transportation_event_id;
  select * into v_customer from public.customers where id=coalesce(v_res.customer_id,v_event.customer_id);
  if (select count(*) from public.vehicle_events where transportation_event_id=p_transportation_event_id and is_open) > 1 then
    return jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'effective_at',p_effective_at,'missing_dependencies',jsonb_build_array('vehicle_assignment'));
  end if;
  select * into v_vehicle_event from public.vehicle_events where transportation_event_id=p_transportation_event_id and is_open order by actual_out_at desc,id desc limit 1;
  if v_vehicle_event.id is not null then
    select * into v_vehicle from public.vehicles where id=v_vehicle_event.vehicle_id;
    if (select count(*) from public.contract_periods where vehicle_event_id=v_vehicle_event.id and is_open) > 1 then
      return jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'effective_at',p_effective_at,'missing_dependencies',jsonb_build_array('contract_period'));
    end if;
    select * into v_contract from public.contract_periods where vehicle_event_id=v_vehicle_event.id and is_open order by contract_out_at desc,id desc limit 1;
  end if;
  if v_vehicle_event.id is null or v_contract.id is null then
    return jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'effective_at',p_effective_at,'missing_dependencies',to_jsonb(array_remove(array[case when v_vehicle_event.id is null then 'vehicle_assignment' end,case when v_contract.id is null then 'contract_period' end],null)));
  end if;
  select * into v_rule from public.pay_type_rules where pay_type=v_res.pay_type limit 1;
  if v_rule.id is null then return jsonb_build_object('status','billing_preview_missing_dependency','transportation_event_id',p_transportation_event_id,'effective_at',p_effective_at,'missing_dependencies',jsonb_build_array('pay_type')); end if;
  select * into v_line from public.billing_lines where transportation_event_id=p_transportation_event_id and parent_billing_line_id is null and is_open order by start_time desc nulls last,created_at desc,id desc limit 1;
  if v_line.daily_rate_override is not null then v_rate:=v_line.daily_rate_override; v_rate_source:='billing_line_daily_rate_override';
  elsif v_line.default_daily_rate_snapshot is not null then v_rate:=v_line.default_daily_rate_snapshot; v_rate_source:='billing_line_default_daily_rate_snapshot';
  else
    v_rate_state:=public.resolve_rental_daily_rate_state(v_res.requested_model,v_rule.id,coalesce(v_line.start_time,v_contract.contract_out_at));
    if v_rate_state->>'status'='rental_daily_rate_resolved' then v_rate:=(v_rate_state->>'daily_rate')::numeric; v_rate_source:='rental_rate_rule';
    elsif v_rule.default_daily_amount is not null then v_rate:=v_rule.default_daily_amount; v_rate_source:='pay_type_default_daily_amount'; end if;
  end if;
  if v_rate is null then return jsonb_build_object('status','billing_preview_missing_configuration','transportation_event_id',p_transportation_event_id,'effective_at',p_effective_at,'missing_configuration',jsonb_build_array('daily_rate')); end if;
  v_days:=public.business_contract_days(v_contract.contract_out_at,coalesce(v_res.actual_return_datetime,p_effective_at));
  v_subtotal:=v_days*v_rate; -- exact PostgreSQL numeric multiplication; without scale reduction.
  if v_line.id is not null then v_tax:=v_subtotal*v_line.tax_rate_snapshot;
  else v_tax_state:=public.resolve_billing_tax_state(v_res.pay_type,v_subtotal); v_tax:=(v_tax_state->>'tax_amount')::numeric; end if;
  v_total:=v_subtotal+v_tax;
  select coalesce(jsonb_agg(jsonb_build_object('billing_line_id',b.id,'line_type',b.line_type,'start_time',b.start_time,'end_time',b.end_time,'paid_through_at',b.paid_through_at,'daily_rate',coalesce(b.daily_rate_override,b.default_daily_rate_snapshot)::text,'subtotal',b.amount::text,'tax',b.tax_amount::text,'total',(b.amount+coalesce(b.tax_amount,0))::text,'tax_rate_snapshot',b.tax_rate_snapshot::text,'tax_rate_source_snapshot',b.tax_rate_source_snapshot) order by b.start_time,b.created_at,b.id),'[]'::jsonb),coalesce(sum(b.amount),0),coalesce(sum(b.tax_amount),0)
    into v_segments,v_acc_subtotal,v_acc_tax from public.billing_lines b where b.transportation_event_id=p_transportation_event_id and b.parent_billing_line_id is null and (v_line.id is null or b.id<>v_line.id);
  select coalesce(jsonb_build_object('configured',true,'provider_name',wp.name,'covered_days',coalesce(wc.approved_days,wc.default_covered_days_snapshot),'coverage_started_at',wc.coverage_started_at,'coverage_exhausted_at',wc.coverage_exhausted_at,'override_applied',wc.approved_days is not null,'split_required',wc.coverage_exhausted_at is not null and wc.coverage_exhausted_at<=p_effective_at),'{"configured":false}'::jsonb) into v_warranty from public.warranty_cases wc left join public.warranty_providers wp on wp.id=wc.provider_id where wc.transportation_event_id=p_transportation_event_id limit 1;
  return jsonb_build_object('status','billing_preview_ready','transportation_event_id',p_transportation_event_id,'effective_at',p_effective_at,
   'customer',jsonb_build_object('name',v_customer.name,'tekion_customer_number',v_customer.tekion_customer_number),
   'reservation',jsonb_build_object('reservation_id',v_res.id,'requested_model',v_res.requested_model,'pay_type',v_res.pay_type),
   'vehicle',jsonb_build_object('vehicle_id',v_vehicle.id,'model',v_vehicle.model,'vin',v_vehicle.vin,'stock_number',v_vehicle.stock_number,'tag',v_vehicle.current_tag),
   'contract_period',jsonb_build_object('contract_period_id',v_contract.id,'contract_out_at',v_contract.contract_out_at,'contract_in_at',v_contract.contract_in_at,'current_vehicle_contract_day',v_days),
   'vehicle_out_at',v_vehicle_event.actual_out_at,'expected_return_at',coalesce(v_event.expected_return_at,v_res.expected_return_datetime),'actual_return_at',v_res.actual_return_datetime,'billed_through_at',coalesce(v_line.paid_through_at,v_res.billed_through_datetime),
   'current_segment',jsonb_build_object('billing_line_id',v_line.id,'rate_source',v_rate_source,'daily_rate',v_rate::text,'billable_days',v_days,'subtotal',v_subtotal::text,'tax',v_tax::text,'total',v_total::text),
   'historical_segments',v_segments,'extended_warranty',v_warranty,'subtotal',v_subtotal::text,'tax',v_tax::text,'total',v_total::text,
   'accumulated_subtotal',(v_acc_subtotal+v_subtotal)::text,'accumulated_tax',(v_acc_tax+v_tax)::text,'accumulated_total',(v_acc_subtotal+v_acc_tax+v_subtotal+v_tax)::text);
exception when others then
  return jsonb_build_object('status','billing_preview_unavailable','transportation_event_id',p_transportation_event_id,'effective_at',p_effective_at,'message','Billing preview is temporarily unavailable.');
end;$function$;

create or replace function public.get_billing_workspace_state(p_effective_at timestamptz)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare v_user_id uuid; v_item jsonb; v_items jsonb:='[]'; v_case record; v_ready int:=0; v_attention int:=0; v_sub numeric:=0; v_tax numeric:=0; v_total numeric:=0;
begin
 select id into v_user_id from public.app_users u where u.auth_user_id=auth.uid() and u.is_active=true;
 if v_user_id is null or coalesce(auth.jwt()->>'aal','')<>'aal2' then return jsonb_build_object('status','billing_workspace_unavailable','message','Billing workspace access is unavailable.'); end if;
 if p_effective_at is null then return jsonb_build_object('status','billing_workspace_unavailable','message','Billing workspace is temporarily unavailable.'); end if;
 for v_case in select id from public.transportation_events where status='active' order by created_at,id loop
   begin v_item:=public.get_billing_preview_state(v_case.id,p_effective_at); exception when others then v_item:=jsonb_build_object('status','billing_preview_unavailable','transportation_event_id',v_case.id,'effective_at',p_effective_at,'message','Billing preview is temporarily unavailable.'); end;
   if v_item->>'status'='billing_preview_ready' then v_ready:=v_ready+1; v_sub:=v_sub+(v_item->>'subtotal')::numeric; v_tax:=v_tax+(v_item->>'tax')::numeric; v_total:=v_total+(v_item->>'total')::numeric; else v_attention:=v_attention+1; end if;
   v_items:=v_items||jsonb_build_array(v_item);
 end loop;
 return jsonb_build_object('status','billing_workspace_ready','effective_at',p_effective_at,'case_count',jsonb_array_length(v_items),'ready_count',v_ready,'attention_count',v_attention,'accumulated_subtotal',v_sub::text,'accumulated_tax',v_tax::text,'accumulated_total',v_total::text,'items',v_items);
exception when others then return jsonb_build_object('status','billing_workspace_unavailable','message','Billing workspace is temporarily unavailable.'); end;$function$;

alter function public.get_billing_preview_state(uuid,timestamptz) owner to postgres;
alter function public.get_billing_workspace_state(timestamptz) owner to postgres;
revoke all on function public.get_billing_preview_state(uuid,timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.get_billing_workspace_state(timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.get_billing_preview_state(uuid,timestamptz) to authenticated;
grant execute on function public.get_billing_workspace_state(timestamptz) to authenticated;
