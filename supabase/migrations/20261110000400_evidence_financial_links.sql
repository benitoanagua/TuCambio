-- TuCambio M1.11.1: explicit, append-only links from verified evidence to financial facts.
begin;

-- One evidence item may document an operation and one movement, but it cannot
-- be reused to silently support two distinct external movements.
create unique index evidence_financial_links_one_movement_per_evidence
  on public.evidence_financial_links(tenant_id, evidence_id)
  where movement_id is not null;

create or replace function public.command_link_financial_evidence(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_evidence_id uuid,
  p_target_type text,
  p_target_id uuid,
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
  v_replay_id uuid;
  v_target_type text := upper(btrim(p_target_type));
begin
  if v_target_type is null or v_target_type not in ('OPERATION', 'MOVEMENT') then
    raise exception 'Evidence target type must be OPERATION or MOVEMENT'
      using errcode = '22023';
  end if;

  v_membership_id := public.assert_financial_command_actor(
    p_actor_user_id,
    p_tenant_id,
    case when v_target_type = 'OPERATION' then 'operations.operate' else 'movements.verify' end
  );

  v_replay_id := public.claim_financial_command(
    p_tenant_id, p_actor_user_id, 'LINK_FINANCIAL_EVIDENCE',
    p_idempotency_key, p_request_sha256
  );
  if v_replay_id is not null then
    return jsonb_build_object('resourceId', v_replay_id, 'replayed', true);
  end if;

  -- Serialize links for the same evidence, including concurrent attempts to
  -- attach it to different movements.
  perform 1
  from public.tenant_evidence e
  where e.tenant_id = p_tenant_id
    and e.id = p_evidence_id
    and e.status = 'available'
  for update;
  if not found then
    raise exception 'Available evidence not found in tenant'
      using errcode = '23503';
  end if;

  if v_target_type = 'OPERATION' then
    perform 1 from public.financial_operations o
    where o.tenant_id = p_tenant_id and o.id = p_target_id
    for key share;
  else
    perform 1 from public.external_movements m
    where m.tenant_id = p_tenant_id and m.id = p_target_id
    for key share;
  end if;
  if not found then
    raise exception 'Financial evidence target not found in tenant'
      using errcode = '23503';
  end if;

  insert into public.evidence_financial_links (
    tenant_id, evidence_id, operation_id, movement_id,
    linked_by_membership_id, linked_by_user_id
  ) values (
    p_tenant_id, p_evidence_id,
    case when v_target_type = 'OPERATION' then p_target_id else null end,
    case when v_target_type = 'MOVEMENT' then p_target_id else null end,
    v_membership_id, p_actor_user_id
  );

  perform public.finish_financial_command(
    p_tenant_id, p_actor_user_id, 'LINK_FINANCIAL_EVIDENCE',
    p_idempotency_key, p_request_sha256, p_evidence_id
  );

  insert into public.financial_domain_events (
    tenant_id, actor_membership_id, actor_user_id,
    entity_type, entity_id, event_type, payload
  ) values (
    p_tenant_id, v_membership_id, p_actor_user_id,
    'EVIDENCE_LINK', p_evidence_id,
    case when v_target_type = 'OPERATION'
      then 'EVIDENCE_LINKED_TO_OPERATION'
      else 'EVIDENCE_LINKED_TO_MOVEMENT'
    end,
    jsonb_build_object('targetType', v_target_type, 'targetId', p_target_id)
  );

  return jsonb_build_object(
    'resourceId', p_evidence_id,
    'evidenceId', p_evidence_id,
    'targetType', v_target_type,
    'targetId', p_target_id,
    'replayed', false
  );
end;
$$;

revoke all on function public.command_link_financial_evidence(uuid, uuid, uuid, text, uuid, text, bytea)
  from public, anon, authenticated;
grant execute on function public.command_link_financial_evidence(uuid, uuid, uuid, text, uuid, text, bytea)
  to tucambio_backend;

comment on function public.command_link_financial_evidence(uuid, uuid, uuid, text, uuid, text, bytea) is
  'Backend-only idempotent append-only link of available evidence to one tenant operation or external movement. Does not change evidence review or movement status.';

commit;
