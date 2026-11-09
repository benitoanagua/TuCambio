-- TuCambio M1.8.3: evidence review is distinct from file integrity and movement verification.
begin;

alter table public.tenant_evidence
  add column review_status text not null default 'PRESENTADA',
  add constraint tenant_evidence_review_status check (
    review_status in ('PRESENTADA', 'EN_REVISION', 'VALIDA', 'OBSERVADA')
  );

create table public.evidence_review_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  evidence_id uuid not null,
  from_status text,
  to_status text not null,
  actor_membership_id uuid not null,
  actor_user_id uuid not null,
  reason text,
  occurred_at timestamptz not null default now(),
  constraint evidence_review_events_status check (
    (from_status is null and to_status = 'PRESENTADA')
    or (from_status = 'PRESENTADA' and to_status = 'EN_REVISION')
    or (from_status = 'EN_REVISION' and to_status in ('VALIDA', 'OBSERVADA'))
  ),
  constraint evidence_review_events_reason_length check (reason is null or char_length(btrim(reason)) between 1 and 500),
  constraint evidence_review_events_evidence_fk foreign key (tenant_id, evidence_id)
    references public.tenant_evidence(tenant_id, id) on delete restrict,
  constraint evidence_review_events_actor_fk foreign key (tenant_id, actor_membership_id, actor_user_id)
    references public.tenant_memberships(tenant_id, id, user_id) on delete restrict
);

create index evidence_review_events_history_idx
  on public.evidence_review_events(tenant_id, evidence_id, occurred_at, id);

create or replace function public.reject_evidence_review_event_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception 'Evidence review history is append-only' using errcode = '55000';
end;
$$;

create trigger evidence_review_events_append_only
before update or delete on public.evidence_review_events
for each row execute function public.reject_evidence_review_event_mutation();

alter table public.evidence_review_events enable row level security;
revoke all on table public.evidence_review_events from public, anon, authenticated, tucambio_backend;
revoke all on table public.tenant_evidence from public, anon, authenticated, tucambio_backend;

create or replace function public.command_review_tenant_evidence(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_evidence_id uuid,
  p_target_status text,
  p_reason text,
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
  v_evidence public.tenant_evidence%rowtype;
  v_event_id uuid;
  v_reason text;
begin
  v_membership_id := public.assert_financial_command_actor(
    p_actor_user_id, p_tenant_id, 'movements.verify'
  );
  v_replay_id := public.claim_financial_command(
    p_tenant_id, p_actor_user_id, 'REVIEW_TENANT_EVIDENCE',
    p_idempotency_key, p_request_sha256
  );
  if v_replay_id is not null then
    return jsonb_build_object('resourceId', v_replay_id, 'replayed', true);
  end if;

  if p_target_status not in ('EN_REVISION', 'VALIDA', 'OBSERVADA') then
    raise exception 'Unsupported evidence review target' using errcode = '22023';
  end if;
  v_reason := nullif(btrim(p_reason), '');
  if p_target_status = 'OBSERVADA' and v_reason is null then
    raise exception 'An observation reason is required' using errcode = '22023';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Evidence review reason is too long' using errcode = '22023';
  end if;

  select e.* into v_evidence
  from public.tenant_evidence e
  where e.tenant_id = p_tenant_id and e.id = p_evidence_id
  for update;
  if not found or v_evidence.status <> 'available' then
    raise exception 'Available evidence not found in tenant' using errcode = '23503';
  end if;

  if not (
    (v_evidence.review_status = 'PRESENTADA' and p_target_status = 'EN_REVISION')
    or (v_evidence.review_status = 'EN_REVISION' and p_target_status in ('VALIDA', 'OBSERVADA'))
  ) then
    raise exception 'Invalid evidence review transition' using errcode = '23514';
  end if;

  update public.tenant_evidence
  set review_status = p_target_status
  where tenant_id = p_tenant_id and id = p_evidence_id;

  insert into public.evidence_review_events (
    tenant_id, evidence_id, from_status, to_status,
    actor_membership_id, actor_user_id, reason
  ) values (
    p_tenant_id, p_evidence_id, v_evidence.review_status, p_target_status,
    v_membership_id, p_actor_user_id, v_reason
  ) returning id into v_event_id;

  perform public.finish_financial_command(
    p_tenant_id, p_actor_user_id, 'REVIEW_TENANT_EVIDENCE',
    p_idempotency_key, p_request_sha256, v_event_id
  );

  return jsonb_build_object(
    'resourceId', v_event_id,
    'evidenceId', p_evidence_id,
    'status', p_target_status,
    'replayed', false
  );
end;
$$;

revoke all on function public.command_review_tenant_evidence(uuid, uuid, uuid, text, text, text, bytea)
  from public, anon, authenticated;
grant execute on function public.command_review_tenant_evidence(uuid, uuid, uuid, text, text, text, bytea)
  to tucambio_backend;

comment on column public.tenant_evidence.status is
  'Storage integrity lifecycle: pending, available, rejected. Independent from review_status.';
comment on column public.tenant_evidence.review_status is
  'Business review lifecycle: PRESENTADA, EN_REVISION, VALIDA, OBSERVADA.';
comment on table public.evidence_review_events is
  'Append-only evidence review audit. Does not confirm or reject an external movement.';

commit;
