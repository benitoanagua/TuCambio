-- TuCambio M1.8.2: apply an immutable rate from the verified origin movement instant.
begin;

create or replace function public.command_apply_operation_rate(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_operation_id uuid,
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
  v_operation public.financial_operations%rowtype;
  v_movement public.external_movements%rowtype;
  v_rate public.currency_rates%rowtype;
  v_applied_rate numeric(38,18);
begin
  v_membership_id := public.assert_financial_command_actor(
    p_actor_user_id, p_tenant_id, 'operations.operate'
  );
  v_resource_id := public.claim_financial_command(
    p_tenant_id, p_actor_user_id, 'APPLY_OPERATION_RATE',
    p_idempotency_key, p_request_sha256
  );
  if v_resource_id is not null then
    select o.applied_rate_id, o.applied_rate
      into v_operation.applied_rate_id, v_operation.applied_rate
    from public.financial_operations o
    where o.tenant_id = p_tenant_id and o.id = p_operation_id;
    return jsonb_build_object(
      'resourceId', v_resource_id,
      'rateId', v_operation.applied_rate_id,
      'rate', v_operation.applied_rate,
      'replayed', true
    );
  end if;

  select * into v_operation
  from public.financial_operations o
  where o.tenant_id = p_tenant_id and o.id = p_operation_id
  for update;
  if not found then
    raise exception 'Financial operation not found in tenant' using errcode = '23503';
  end if;
  if v_operation.applied_rate_id is not null then
    raise exception 'Operation rate has already been applied' using errcode = '23505';
  end if;

  select m.* into v_movement
  from public.operation_movements om
  join public.external_movements m
    on m.tenant_id = om.tenant_id and m.id = om.movement_id
  where om.tenant_id = p_tenant_id
    and om.operation_id = p_operation_id
    and om.movement_role = 'ORIGIN'
  for update of m;
  if not found then
    raise exception 'Verified origin movement is required' using errcode = '23514';
  end if;
  if v_movement.status <> 'CONFIRMED'
     or v_movement.currency_code <> v_operation.source_currency_code then
    raise exception 'Origin movement must be confirmed and match operation source currency'
      using errcode = '23514';
  end if;

  select r.* into v_rate
  from public.currency_rates r
  where r.tenant_id = p_tenant_id
    and r.pair_id = v_operation.pair_id
    and tstzrange(r.valid_from, r.valid_until, '[)') @> v_movement.effective_at;
  if not found then
    raise exception 'No rate is valid at the verified origin movement instant'
      using errcode = 'P0002';
  end if;

  -- Rates are expressed as quote currency per base currency. From the
  -- operator perspective, receiving base means buying base; receiving quote
  -- means selling base.
  if v_operation.source_currency_code = (
    select p.base_currency_code from public.tenant_currency_pairs p
    where p.tenant_id = p_tenant_id and p.id = v_operation.pair_id
  ) then
    v_applied_rate := v_rate.buy_rate;
  else
    v_applied_rate := v_rate.sell_rate;
  end if;

  update public.financial_operations
  set source_effective_at = v_movement.effective_at,
      applied_rate_id = v_rate.id,
      applied_rate = v_applied_rate,
      updated_at = now()
  where tenant_id = p_tenant_id and id = p_operation_id;

  perform public.finish_financial_command(
    p_tenant_id, p_actor_user_id, 'APPLY_OPERATION_RATE',
    p_idempotency_key, p_request_sha256, p_operation_id
  );
  insert into public.financial_domain_events (
    tenant_id, actor_membership_id, actor_user_id,
    entity_type, entity_id, event_type, payload
  ) values (
    p_tenant_id, v_membership_id, p_actor_user_id,
    'OPERATION', p_operation_id, 'OPERATION_RATE_APPLIED',
    jsonb_build_object(
      'movementId', v_movement.id,
      'sourceEffectiveAt', v_movement.effective_at,
      'rateId', v_rate.id,
      'rate', v_applied_rate,
      'direction', case
        when v_operation.source_currency_code = (
          select p.base_currency_code from public.tenant_currency_pairs p
          where p.tenant_id = p_tenant_id and p.id = v_operation.pair_id
        ) then 'BUY_BASE'
        else 'SELL_BASE'
      end
    )
  );

  return jsonb_build_object(
    'resourceId', p_operation_id,
    'rateId', v_rate.id,
    'rate', v_applied_rate,
    'replayed', false
  );
end;
$$;

revoke all on function public.command_apply_operation_rate(uuid, uuid, uuid, text, bytea)
  from public, anon, authenticated;
grant execute on function public.command_apply_operation_rate(uuid, uuid, uuid, text, bytea)
  to tucambio_backend;

commit;
