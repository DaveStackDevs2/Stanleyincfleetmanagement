-- Reconcile the production Extension note helper with the actual note-table columns.
-- The signature, JSON response contract, owner, security mode, and existing grants are unchanged.
CREATE OR REPLACE FUNCTION public.add_estimated_return_change_note_state(
  p_transportation_event_id uuid, p_old_expected_return_at timestamptz,
  p_new_expected_return_at timestamptz, p_reason_code text,
  p_optional_note text DEFAULT NULL, p_entered_by_user_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER AS $function$
DECLARE v_note_id uuid; v_note_text text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.transportation_events WHERE id=p_transportation_event_id) THEN RAISE EXCEPTION 'Transportation event % does not exist',p_transportation_event_id; END IF;
  IF p_entered_by_user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.app_users WHERE id=p_entered_by_user_id) THEN RAISE EXCEPTION 'User % does not exist',p_entered_by_user_id; END IF;
  IF p_reason_code IS NULL OR btrim(p_reason_code)='' THEN RAISE EXCEPTION 'Reason code is required for estimated return changes'; END IF;
  v_note_text:=coalesce(p_optional_note,'');
  INSERT INTO public.transportation_event_notes (transportation_event_id,note_type,old_estimated_return,new_estimated_return,reason_code,note_text,entered_by_user_id,entered_at)
  VALUES (p_transportation_event_id,'estimated_return_change',p_old_expected_return_at,p_new_expected_return_at,p_reason_code,v_note_text,p_entered_by_user_id,now()) RETURNING id INTO v_note_id;
  RETURN jsonb_build_object('status','estimated_return_change_note_created','note_id',v_note_id,'transportation_event_id',p_transportation_event_id,'old_expected_return_at',p_old_expected_return_at,'new_expected_return_at',p_new_expected_return_at,'reason_code',p_reason_code);
END;
$function$;
ALTER FUNCTION public.add_estimated_return_change_note_state(uuid,timestamptz,timestamptz,text,text,uuid) OWNER TO postgres;
ALTER FUNCTION public.add_estimated_return_change_note_state(uuid,timestamptz,timestamptz,text,text,uuid) SECURITY INVOKER;
