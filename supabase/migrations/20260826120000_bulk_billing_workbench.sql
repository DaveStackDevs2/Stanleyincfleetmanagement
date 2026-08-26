-- Issue #59: narrow, audited Bulk Updating persistence and secured engine wrappers.
create table public.billing_bulk_batches (
 id uuid primary key default gen_random_uuid(), actor_user_id uuid not null references public.app_users(id),
 requested_target_at timestamptz not null, created_at timestamptz not null default clock_timestamp(), applied_at timestamptz,
 undone_at timestamptz, undone_by_user_id uuid references public.app_users(id), status text not null check(status in('applied','partially_applied','failed','undone'))
);
create table public.billing_bulk_items (
 id uuid primary key default gen_random_uuid(), batch_id uuid not null references public.billing_bulk_batches(id) on delete restrict,
 transportation_event_id uuid not null references public.transportation_events(id), reservation_id uuid references public.reservations(id),
 identifier text not null, succeeded boolean not null, failure_reason text, before_reservation jsonb, before_lines jsonb, before_warranty jsonb,
 after_reservation jsonb, after_lines jsonb, after_warranty jsonb, created_at timestamptz not null default clock_timestamp(),
 unique(batch_id,transportation_event_id), check((succeeded and failure_reason is null) or (not succeeded and failure_reason is not null))
);
create table public.billing_bulk_helper_lines (
 id uuid primary key default gen_random_uuid(), batch_item_id uuid not null references public.billing_bulk_items(id) on delete restrict,
 line_order integer not null, ro_number text not null, billing_line_id uuid not null, days integer not null,
 amount numeric not null, tax numeric not null, note text, checked boolean not null default false,
 checked_at timestamptz, checked_by_user_id uuid references public.app_users(id), created_at timestamptz not null default clock_timestamp(),
 unique(batch_item_id,line_order)
);
alter table public.billing_bulk_batches enable row level security;
alter table public.billing_bulk_items enable row level security;
alter table public.billing_bulk_helper_lines enable row level security;
revoke all on table public.billing_bulk_batches,public.billing_bulk_items,public.billing_bulk_helper_lines from public,anon,authenticated;

create or replace function public.bulk_billing_actor_state() returns uuid language plpgsql security definer set search_path='' as $f$ declare v uuid;begin select u.id into v from public.app_users u where u.auth_user_id=auth.uid() and u.is_active; if v is null then raise exception 'Billing action access denied' using errcode='42501';end if;if coalesce(auth.jwt()->>'aal','')<>'aal2' then raise exception 'Billing action requires AAL2' using errcode='42501';end if;if not exists(select 1 from public.v_user_effective_permissions p where p.user_id=v and p.permission_key='billing.mark_billed_through') then raise exception 'Billing permission is required' using errcode='42501';end if;return v;end;$f$;

create or replace function public.get_bulk_billing_workspace_state(p_target_at timestamptz) returns jsonb language plpgsql security definer set search_path='' as $f$
declare v_actor uuid;v_items jsonb;begin v_actor:=public.bulk_billing_actor_state();if p_target_at is null then raise exception 'Bulk Billing Through is required' using errcode='22023';end if;
 select coalesce(jsonb_agg(jsonb_build_object('transportation_event_id',r.transportation_event_id,'reservation_id',r.id,'identifier',case when lower(btrim(r.reservation_type))='rental' then 'Rental '||left(r.id::text,8) else 'RO '||coalesce(r.ro_number,'unavailable') end,'reservation_type',r.reservation_type,'contract_out_at',p->>'contract_out_at','expected_return_at',r.expected_return_datetime,'billed_through_at',r.billed_through_datetime,'pay_type',p->>'pay_type','daily_rate',p->>'daily_rate','contract_days',case when p->>'contract_days'~'^\d+$' then (p->>'contract_days')::int end,'amount',p->>'subtotal','tax',p->>'tax_amount','state',case when lower(btrim(r.reservation_type))='rental' then 'rental' when p->>'status'<>'billing_preview_ready' then 'attention' when r.billed_through_datetime>p_target_at then 'later' when r.billed_through_datetime=p_target_at then 'exact' else 'eligible' end,'reason',case when lower(btrim(r.reservation_type))='rental' then 'Rental — separate payment / Extension workflow' when p->>'status'<>'billing_preview_ready' then coalesce(p->>'missing_dependency',p->>'missing_configuration','Authoritative preview unavailable') when r.billed_through_datetime>p_target_at then 'Already billed beyond target' when r.billed_through_datetime=p_target_at then 'Already at target' else 'Ready' end,'selectable',lower(btrim(r.reservation_type))<>'rental' and p->>'status'='billing_preview_ready' and (r.billed_through_datetime is null or r.billed_through_datetime<p_target_at)) order by coalesce(r.ro_number,r.id::text)),'[]'::jsonb) into v_items
 from public.reservations r cross join lateral public.get_billing_preview_state(r.transportation_event_id,p_target_at) p where lower(r.status)='active';
 return jsonb_build_object('status','bulk_billing_workspace_ready','target_at',p_target_at,'items',v_items);end;$f$;

-- One canonical checkpoint engine.  The public single-case wrapper and Bulk both
-- route through this implementation; only the Bulk caller opts into future targets.
create or replace function public.checkpoint_case_internal_state(
 p_reservation_id uuid,p_target_at timestamptz,p_note text,p_allow_future boolean default false
) returns jsonb language plpgsql security definer set search_path='' as $f$
declare r public.reservations%rowtype;l public.billing_lines%rowtype;p jsonb;t jsonb;
 open_count integer;tax_count integer;set_result jsonb;
begin
 if p_reservation_id is null or p_target_at is null then raise exception 'Reservation and billed-through timestamp are required' using errcode='22023';end if;
 if not p_allow_future and p_target_at>clock_timestamp() then raise exception 'Billed-through timestamp cannot be in the future' using errcode='22023';end if;
 select * into r from public.reservations where id=p_reservation_id for update;
 if not found then raise exception 'Reservation was not found' using errcode='P0002';end if;
 if p_target_at<r.start_date then raise exception 'Billed-through timestamp cannot precede case start' using errcode='22023';end if;
 if r.billed_through_datetime is not null and p_target_at<r.billed_through_datetime then raise exception 'Billed-through timestamp cannot move backward' using errcode='22023';end if;
 select count(*) into open_count from public.billing_lines x where x.reservation_id=r.id and x.transportation_event_id=r.transportation_event_id and x.parent_billing_line_id is null and x.is_open;
 if open_count=0 then raise exception 'Open parent billing segment was not found' using errcode='P0002';end if;
 if open_count>1 then raise exception 'Multiple open parent billing segments were found' using errcode='21000';end if;
 select * into l from public.billing_lines x where x.reservation_id=r.id and x.transportation_event_id=r.transportation_event_id and x.parent_billing_line_id is null and x.is_open for update;
 p:=public.get_billing_preview_state(r.transportation_event_id,p_target_at);
 if p->>'status'<>'billing_preview_ready' then raise exception 'Authoritative checkpoint preview is not ready';end if;
 set_result:=public.set_reservation_billed_through_state(r.id,p_target_at,nullif(btrim(p_note),''));
 if set_result->>'status'<>'reservation_billed_through_set' then raise exception 'Reservation billed-through timestamp was not set';end if;
 update public.billing_lines set amount=(p->>'subtotal')::numeric,tax_amount=(p->>'tax_amount')::numeric,paid_through_at=p_target_at,updated_at=clock_timestamp() where id=l.id;
 t:=public.ensure_tax_child_line_state(l.id);
 update public.billing_lines set paid_through_at=p_target_at,updated_at=clock_timestamp() where parent_billing_line_id=l.id and line_type='tax';
 get diagnostics tax_count=row_count;
 if (p->>'tax_amount')::numeric>0 and tax_count<>1 then raise exception 'Positive checkpoint tax requires exactly one synchronized tax child';end if;
 return jsonb_build_object('status','billing_checkpoint_recorded','reservation_id',r.id,'transportation_event_id',r.transportation_event_id,'billing_line_id',l.id,'billed_through_at',p_target_at,'checkpoint_subtotal',p->>'subtotal','checkpoint_tax',p->>'tax_amount','checkpoint_total',p->>'total','tax_child_result',t);
end;$f$;

create or replace function public.mark_case_billed_through_and_get_preview_state(p_reservation_id uuid,p_billed_through_at timestamptz,p_note text default null) returns jsonb language plpgsql security definer set search_path='' as $f$
declare actor uuid;result jsonb;current_preview jsonb;begin
 select u.id into actor from public.app_users u where u.auth_user_id=auth.uid() and u.is_active;
 if actor is null then raise exception 'An active application user is required' using errcode='42501';end if;
 if not exists(select 1 from public.v_user_effective_permissions p where p.user_id=actor and p.permission_key='billing.mark_billed_through') then raise exception 'Permission denied' using errcode='42501';end if;
 result:=public.checkpoint_case_internal_state(p_reservation_id,p_billed_through_at,p_note,false);
 current_preview:=public.get_billing_preview_state((result->>'transportation_event_id')::uuid,clock_timestamp());
 if current_preview->>'status'<>'billing_preview_ready' then raise exception 'Current authoritative billing preview is not ready';end if;
 return result||jsonb_build_object('billing_preview',current_preview);
end;$f$;

create or replace function public.bulk_checkpoint_one_state(p_reservation_id uuid,p_target_at timestamptz,p_batch_id uuid) returns jsonb language plpgsql security definer set search_path='' as $f$
declare r public.reservations%rowtype;w public.warranty_cases%rowtype;boundary timestamptz;first_result jsonb;second_result jsonb;split_result jsonb;line_ids jsonb:='[]';crossed boolean:=false;begin
 select * into r from public.reservations where id=p_reservation_id for update;
 if not found then raise exception 'Reservation was not found';end if;
 if lower(btrim(r.reservation_type))='rental' then raise exception 'Rentals cannot be Bulk Updated';end if;
 if lower(r.status)<>'active' then raise exception 'Reservation is no longer active';end if;
 select * into w from public.warranty_cases where transportation_event_id=r.transportation_event_id for update;
 if found and w.coverage_started_at is not null and coalesce(w.approved_days,w.default_covered_days_snapshot) is not null then
  boundary:=w.coverage_started_at+make_interval(days=>coalesce(w.approved_days,w.default_covered_days_snapshot));
 end if;
 if boundary is not null and p_target_at>=boundary and w.coverage_exhausted_at is null then
  -- Finalize authoritative EW dollars/tax before the existing split engine closes it.
  first_result:=public.checkpoint_case_internal_state(r.id,boundary,'Bulk Updating batch '||p_batch_id,true);
  line_ids:=line_ids||jsonb_build_array(first_result->>'billing_line_id');
  split_result:=public.reconcile_extended_warranty_coverage_state(r.transportation_event_id,p_target_at);
  if split_result->>'status' not in ('extended_warranty_coverage_split','extended_warranty_coverage_already_split') then raise exception 'Extended Warranty cap split was not completed: %',split_result->>'status';end if;
  second_result:=public.checkpoint_case_internal_state(r.id,p_target_at,'Bulk Updating EW cap split batch '||p_batch_id,true);
  line_ids:=line_ids||jsonb_build_array(second_result->>'billing_line_id');crossed:=true;
 else
  split_result:=public.reconcile_extended_warranty_coverage_state(r.transportation_event_id,p_target_at);
  first_result:=public.checkpoint_case_internal_state(r.id,p_target_at,'Bulk Updating batch '||p_batch_id,true);
  line_ids:=line_ids||jsonb_build_array(first_result->>'billing_line_id');
 end if;
 return jsonb_build_object('billing_line_ids',line_ids,'ew_cap_crossed',crossed,'split_result',split_result);
end;$f$;

create or replace function public.apply_bulk_billing_batch_state(p_target_at timestamptz,p_transportation_event_ids uuid[]) returns jsonb language plpgsql security definer set search_path='' as $f$
declare actor uuid;b uuid:=gen_random_uuid();te uuid;r public.reservations%rowtype;i uuid;before_r jsonb;before_l jsonb;before_w jsonb;after_r jsonb;after_l jsonb;after_w jsonb;result jsonb;reason text;successes jsonb:='[]';failures jsonb:='[]';helpers jsonb:='[]';line_id_text text;n int;line public.billing_lines%rowtype;normalized uuid[];begin
 actor:=public.bulk_billing_actor_state();if p_target_at is null then raise exception 'Bulk Billing Through is required';end if;
 select array_agg(distinct x order by x) into normalized from unnest(p_transportation_event_ids)x where x is not null;
 if coalesce(array_length(normalized,1),0)=0 then raise exception 'Select at least one valid RO to update.';end if;
 insert into public.billing_bulk_batches(id,actor_user_id,requested_target_at,status) values(b,actor,p_target_at,'failed');
 foreach te in array normalized loop begin
  r:=null;select * into r from public.reservations where transportation_event_id=te;if not found then raise exception 'Reservation was not found';end if;
  before_r:=to_jsonb(r);select coalesce(jsonb_agg(to_jsonb(l) order by l.created_at,l.id),'[]') into before_l from public.billing_lines l where l.transportation_event_id=te;select to_jsonb(w) into before_w from public.warranty_cases w where w.transportation_event_id=te;
  result:=public.bulk_checkpoint_one_state(r.id,p_target_at,b);
  select to_jsonb(x) into after_r from public.reservations x where x.id=r.id;select coalesce(jsonb_agg(to_jsonb(l) order by l.created_at,l.id),'[]') into after_l from public.billing_lines l where l.transportation_event_id=te;select to_jsonb(w) into after_w from public.warranty_cases w where w.transportation_event_id=te;
  insert into public.billing_bulk_items(batch_id,transportation_event_id,reservation_id,identifier,succeeded,before_reservation,before_lines,before_warranty,after_reservation,after_lines,after_warranty) values(b,te,r.id,coalesce(r.ro_number,r.id::text),true,before_r,before_l,before_w,after_r,after_l,after_w) returning id into i;
  successes:=successes||jsonb_build_array(jsonb_build_object('transportation_event_id',te,'identifier',coalesce(r.ro_number,r.id::text)));n:=0;
  -- IDs describe semantic writes (EW then CP), not incidental row ordering.
  for line_id_text in select value #>> '{}' from jsonb_array_elements(result->'billing_line_ids') loop
   select * into strict line from public.billing_lines where id=line_id_text::uuid;n:=n+1;
   insert into public.billing_bulk_helper_lines(batch_item_id,line_order,ro_number,billing_line_id,days,amount,tax,note) values(i,n,coalesce(r.ro_number,r.id::text),line.id,public.business_contract_days(line.start_time,coalesce(line.paid_through_at,line.end_time)),line.amount,line.tax_amount,case when (result->>'ew_cap_crossed')::boolean and line.id=(result->'billing_line_ids'->>1)::uuid then 'New Customer Pay line required after Extended Warranty coverage cap' end);
  end loop;
 exception when others then
  reason:=sqlerrm;insert into public.billing_bulk_items(batch_id,transportation_event_id,reservation_id,identifier,succeeded,failure_reason) values(b,te,r.id,coalesce(r.ro_number,te::text),false,reason);failures:=failures||jsonb_build_array(jsonb_build_object('transportation_event_id',te,'identifier',coalesce(r.ro_number,te::text),'reason',reason));
 end;end loop;
 update public.billing_bulk_batches set applied_at=clock_timestamp(),status=case when jsonb_array_length(successes)=0 then 'failed' when jsonb_array_length(failures)>0 then 'partially_applied' else 'applied' end where id=b;
 insert into public.audit_log(entity_type,entity_id,action_type,metadata,actor_user_id) values('billing_bulk_batch',b::text,'bulk_billing_apply',jsonb_build_object('target_at',p_target_at,'success_count',jsonb_array_length(successes),'failure_count',jsonb_array_length(failures)),actor::text);
 select coalesce(jsonb_agg(jsonb_build_object('id',h.id,'ro_number',h.ro_number,'days',h.days,'amount',h.amount::text,'tax',h.tax::text,'note',h.note,'checked',h.checked) order by h.created_at,h.line_order),'[]') into helpers from public.billing_bulk_helper_lines h join public.billing_bulk_items bi on bi.id=h.batch_item_id where bi.batch_id=b;
 return jsonb_build_object('status','bulk_billing_batch_applied','batch_id',b,'success_count',jsonb_array_length(successes),'successes',successes,'failures',failures,'helper_lines',helpers);
end;$f$;

create or replace function public.get_recent_bulk_billing_batches_state() returns jsonb language plpgsql security definer set search_path='' as $f$ declare actor uuid;payload jsonb;begin actor:=public.bulk_billing_actor_state();select coalesce(jsonb_agg(jsonb_build_object('batch_id',b.id,'target_at',b.requested_target_at,'created_at',b.created_at,'status',b.status,'failures',(select coalesce(jsonb_agg(jsonb_build_object('transportation_event_id',i.transportation_event_id,'identifier',i.identifier,'reason',i.failure_reason) order by i.created_at),'[]') from public.billing_bulk_items i where i.batch_id=b.id and not i.succeeded),'helper_lines',(select coalesce(jsonb_agg(jsonb_build_object('id',h.id,'ro_number',h.ro_number,'days',h.days,'amount',h.amount::text,'tax',h.tax::text,'note',h.note,'checked',h.checked) order by h.line_order),'[]') from public.billing_bulk_items i join public.billing_bulk_helper_lines h on h.batch_item_id=i.id where i.batch_id=b.id)) order by b.created_at desc),'[]') into payload from (select * from public.billing_bulk_batches where actor_user_id=actor order by created_at desc limit 20)b;return jsonb_build_object('status','recent_bulk_billing_batches_ready','batches',payload);end;$f$;
create or replace function public.set_bulk_helper_line_checked_state(p_helper_line_id uuid,p_checked boolean) returns jsonb language plpgsql security definer set search_path='' as $f$ declare actor uuid;begin actor:=public.bulk_billing_actor_state();update public.billing_bulk_helper_lines set checked=p_checked,checked_at=case when p_checked then clock_timestamp() end,checked_by_user_id=case when p_checked then actor end where id=p_helper_line_id;if not found then raise exception 'Tekion helper line was not found';end if;insert into public.audit_log(entity_type,entity_id,action_type,new_value,actor_user_id)values('billing_bulk_helper_line',p_helper_line_id::text,'tekion_checkoff',p_checked::text,actor::text);return jsonb_build_object('status','bulk_helper_line_check_set','helper_line_id',p_helper_line_id,'checked',p_checked);end;$f$;
create or replace function public.undo_latest_bulk_billing_batch_state() returns jsonb language plpgsql security definer set search_path='' as $f$
declare actor uuid;b public.billing_bulk_batches%rowtype;i public.billing_bulk_items%rowtype;current_r jsonb;current_l jsonb;current_w jsonb;s jsonb;old public.billing_lines%rowtype;old_w public.warranty_cases%rowtype;begin
 actor:=public.bulk_billing_actor_state();select * into b from public.billing_bulk_batches where status in('applied','partially_applied') order by applied_at desc limit 1 for update;if not found then raise exception 'No applicable Bulk Updating batch is available to Undo';end if;
 for i in select * from public.billing_bulk_items where batch_id=b.id and succeeded order by id for update loop
  select to_jsonb(r) into current_r from public.reservations r where r.id=i.reservation_id for update;
  select coalesce(jsonb_agg(to_jsonb(l) order by l.created_at,l.id),'[]') into current_l from public.billing_lines l where l.transportation_event_id=i.transportation_event_id;
  select to_jsonb(w) into current_w from public.warranty_cases w where w.transportation_event_id=i.transportation_event_id for update;
  if current_r is distinct from i.after_reservation or current_l is distinct from i.after_lines or current_w is distinct from i.after_warranty then raise exception 'Undo refused: legitimate Billing work changed after this Bulk batch for %',i.identifier;end if;
  delete from public.billing_lines where transportation_event_id=i.transportation_event_id and not (id=any(array(select (x->>'id')::uuid from jsonb_array_elements(i.before_lines)x)));
  for s in select value from jsonb_array_elements(i.before_lines) loop old:=jsonb_populate_record(null::public.billing_lines,s);insert into public.billing_lines select old.* on conflict(id) do update set amount=excluded.amount,tax_amount=excluded.tax_amount,start_time=excluded.start_time,end_time=excluded.end_time,pay_type=excluded.pay_type,pay_type_rule_id=excluded.pay_type_rule_id,line_type=excluded.line_type,parent_billing_line_id=excluded.parent_billing_line_id,is_open=excluded.is_open,paid_through_at=excluded.paid_through_at,updated_at=excluded.updated_at;end loop;
  if i.before_warranty is null then delete from public.warranty_cases where transportation_event_id=i.transportation_event_id;else old_w:=jsonb_populate_record(null::public.warranty_cases,i.before_warranty);delete from public.warranty_cases where transportation_event_id=i.transportation_event_id;insert into public.warranty_cases select old_w.*;end if;
  update public.reservations set billed_through_datetime=(i.before_reservation->>'billed_through_datetime')::timestamptz,notes=i.before_reservation->>'notes' where id=i.reservation_id;
 end loop;
 update public.billing_bulk_batches set status='undone',undone_at=clock_timestamp(),undone_by_user_id=actor where id=b.id;
 insert into public.audit_log(entity_type,entity_id,action_type,metadata,actor_user_id) values('billing_bulk_batch',b.id::text,'bulk_billing_undo',jsonb_build_object('fail_closed_post_state_verified',true,'reservation_notes_restored',true,'warranty_state_restored',true),actor::text);
 return jsonb_build_object('status','bulk_billing_batch_undone','batch_id',b.id);
end;$f$;

alter function public.bulk_billing_actor_state() owner to postgres;alter function public.checkpoint_case_internal_state(uuid,timestamptz,text,boolean) owner to postgres;alter function public.mark_case_billed_through_and_get_preview_state(uuid,timestamptz,text) owner to postgres;alter function public.get_bulk_billing_workspace_state(timestamptz) owner to postgres;alter function public.bulk_checkpoint_one_state(uuid,timestamptz,uuid) owner to postgres;alter function public.apply_bulk_billing_batch_state(timestamptz,uuid[]) owner to postgres;alter function public.get_recent_bulk_billing_batches_state() owner to postgres;alter function public.set_bulk_helper_line_checked_state(uuid,boolean) owner to postgres;alter function public.undo_latest_bulk_billing_batch_state() owner to postgres;
revoke all on function public.bulk_billing_actor_state(),public.checkpoint_case_internal_state(uuid,timestamptz,text,boolean),public.get_bulk_billing_workspace_state(timestamptz),public.bulk_checkpoint_one_state(uuid,timestamptz,uuid),public.apply_bulk_billing_batch_state(timestamptz,uuid[]),public.get_recent_bulk_billing_batches_state(),public.set_bulk_helper_line_checked_state(uuid,boolean),public.undo_latest_bulk_billing_batch_state() from public,anon,authenticated;
grant execute on function public.get_bulk_billing_workspace_state(timestamptz),public.apply_bulk_billing_batch_state(timestamptz,uuid[]),public.get_recent_bulk_billing_batches_state(),public.set_bulk_helper_line_checked_state(uuid,boolean),public.undo_latest_bulk_billing_batch_state() to authenticated;
grant execute on function public.bulk_billing_actor_state(),public.bulk_checkpoint_one_state(uuid,timestamptz,uuid) to service_role;

revoke all on function public.mark_case_billed_through_and_get_preview_state(uuid,timestamptz,text) from public,anon,authenticated,service_role;
grant execute on function public.mark_case_billed_through_and_get_preview_state(uuid,timestamptz,text) to authenticated,service_role;
grant execute on function public.checkpoint_case_internal_state(uuid,timestamptz,text,boolean) to postgres,service_role;
