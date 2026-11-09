-- TuCambio M1.8.1: audited, tenant-scoped external movement verification.
-- Only the declared -> in-verification -> confirmed/not-confirmed lifecycle is exposed.
begin;

create or replace function public.command_transition_external_movement(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_movement_id uuid,
  p_target_status text,
  p_idempotency_key text,
  p_request_sha256 bytea
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_membership_id uuid;
  v_resource_id uuid;
  v_previous_status text;
  v_event_type text;
begin
  v_membership_id := public.assert_financial_command_actor(
    p_actor_user_id, p_tenant_id, 'movements.verify'
  );
  v_resource_id := public.claim_financial_command(
    p_tenant_id, p_actor_user_id, 'TRANSITION_EXTERNAL_MOVEMENT',
    p_idempotency_key, p_request_sha256
  );
  if v_resource_id is not null then
    return jsonb_build_object('resourceId', v_resource_id, 'status', p_target_status, 'replayed', true);
  end if;

  if p_target_status not in ('IN_VERIFICATION', 'CONFIRMED', 'NOT_CONFIRMED') then
    raise exception 'Unsupported movement target status' using errcode = '22023';
  end if;

  select m.status into v_previous_status
  from public.external_movements m
  where m.tenant_id = p_tenant_id and m.id = p_movement_id
  for update;

  if not found then
    raise exception 'External movement not found in tenant' using errcode = '23503';
  end if;

  if not (
    (v_previous_status = 'DECLARED' and p_target_status = 'IN_VERIFICATION')
    or (v_previous_status = 'IN_VERIFICATION' and p_target_status in ('CONFIRMED', 'NOT_CONFIRMED'))
  ) then
    raise exception 'Invalid external movement status transition' using errcode = '23514';
  end if;

  update public.external_movements
  set status = p_target_status, updated_at = now()
  where tenant_id = p_tenant_id and id = p_movement_id;

  v_event_type := case p_target_status
    when 'IN_VERIFICATION' then 'MOVEMENT_VERIFICATION_STARTED'
    when 'CONFIRMED' then 'MOVEMENT_CONFIRMED'
    when 'NOT_CONFIRMED' then 'MOVEMENT_NOT_CONFIRMED'
  end;

  perform public.finish_financial_command(
    p_tenant_id, p_actor_user_id, 'TRANSITION_EXTERNAL_MOVEMENT',
    p_idempotency_key, p_request_sha256, p_movement_id
  );

  insert into public.financial_domain_events (
    tenant_id, actor_membership_id, actor_user_id,
    entity_type, entity_id, event_type, payload
  ) values (
    p_tenant_id, v_membership_id, p_actor_user_id,
    'MOVEMENT', p_movement_id, v_event_type,
    jsonb_build_object('previousStatus', v_previous_status, 'status', p_target_status)
  );

  return jsonb_build_object('resourceId', p_movement_id, 'status', p_target_status, 'replayed', false);
end;
$$;

revoke all on function public.command_transition_external_movement(uuid, uuid, uuid, text, text, bytea)
  from public, anon, authenticated;
grant execute on function public.command_transition_external_movement(uuid, uuid, uuid, text, text, bytea)
  to tucambio_backend;

commit;
