-- TuCambio M1.8.2: resolve the operation rate from the verified origin movement instant.
-- The external movement remains an independent fact. Missing rates or a mismatched
-- association are recorded explicitly; no estimated/final amount is inferred.
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
  v_movement_currency text;
  v_movement_effective_at timestamptz;
  v_operation_id uuid;
  v_source_currency text;
  v_pair_id uuid;
  v_rate_id uuid;
  v_rate numeric(38, 18);
  v_rate_side text;
  v_rate_resolution text := 'NOT_ORIGIN_MOVEMENT';
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

  select m.status, m.currency_code, m.effective_at
    into v_previous_status, v_movement_currency, v_movement_effective_at
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

  if p_target_status = 'CONFIRMED' then
    select om.operation_id into v_operation_id
    from public.operation_movements om
    where om.tenant_id = p_tenant_id
      and om.movement_id = p_movement_id
      and om.movement_role = 'ORIGIN';

    if v_operation_id is not null then
      select o.pair_id, o.source_currency_code
        into v_pair_id, v_source_currency
      from public.financial_operations o
      where o.tenant_id = p_tenant_id and o.id = v_operation_id
      for update;

      if v_source_currency is distinct from v_movement_currency then
        v_rate_resolution := 'SOURCE_CURRENCY_MISMATCH';
        insert into public.financial_domain_events (
          tenant_id, actor_membership_id, actor_user_id,
          entity_type, entity_id, event_type, payload
        ) values (
          p_tenant_id, v_membership_id, p_actor_user_id,
          'OPERATION', v_operation_id, 'OPERATION_SOURCE_CURRENCY_MISMATCH',
          jsonb_build_object(
            'movementId', p_movement_id,
            'movementCurrency', v_movement_currency,
            'operationSourceCurrency', v_source_currency
          )
        );
      else
        -- The customer delivers the source currency. When that currency is
        -- the pair's base currency the operator buys the base (buy_rate);
        -- when it is the quote currency the operator sells the base (sell_rate).
        select r.id,
          case
            when v_source_currency = p.base_currency_code then r.buy_rate
            else r.sell_rate
          end,
          case
            when v_source_currency = p.base_currency_code then 'BUY'
            else 'SELL'
          end
        into v_rate_id, v_rate, v_rate_side
        from public.currency_rates r
        join public.tenant_currency_pairs p
          on p.tenant_id = r.tenant_id and p.id = r.pair_id
        where r.tenant_id = p_tenant_id
          and r.pair_id = v_pair_id
          and tstzrange(r.valid_from, r.valid_until, '[)') @> v_movement_effective_at
        order by r.valid_from desc, r.id desc
        limit 1;

        if v_rate_id is null then
          v_rate_resolution := 'RATE_NOT_FOUND';
          update public.financial_operations
          set source_effective_at = v_movement_effective_at,
              updated_at = now()
          where tenant_id = p_tenant_id and id = v_operation_id;

          insert into public.financial_domain_events (
            tenant_id, actor_membership_id, actor_user_id,
            entity_type, entity_id, event_type, payload
          ) values (
            p_tenant_id, v_membership_id, p_actor_user_id,
            'OPERATION', v_operation_id, 'OPERATION_SOURCE_RATE_NOT_FOUND',
            jsonb_build_object(
              'movementId', p_movement_id,
              'sourceEffectiveAt', v_movement_effective_at
            )
          );
        else
          update public.financial_operations
          set source_effective_at = v_movement_effective_at,
              applied_rate_id = v_rate_id,
              applied_rate = v_rate,
              updated_at = now()
          where tenant_id = p_tenant_id and id = v_operation_id;

          v_rate_resolution := 'RATE_APPLIED';
          insert into public.financial_domain_events (
            tenant_id, actor_membership_id, actor_user_id,
            entity_type, entity_id, event_type, payload
          ) values (
            p_tenant_id, v_membership_id, p_actor_user_id,
            'OPERATION', v_operation_id, 'OPERATION_SOURCE_RATE_APPLIED',
            jsonb_build_object(
              'movementId', p_movement_id,
              'sourceEffectiveAt', v_movement_effective_at,
              'rateId', v_rate_id,
              'rateSide', v_rate_side,
              'rate', v_rate
            )
          );
        end if;
      end if;
    end if;
  end if;

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

  return jsonb_build_object(
    'resourceId', p_movement_id,
    'status', p_target_status,
    'sourceRateResolution', v_rate_resolution,
    'replayed', false
  );
end;
$$;

revoke all on function public.command_transition_external_movement(uuid, uuid, uuid, text, text, bytea)
  from public, anon, authenticated;
grant execute on function public.command_transition_external_movement(uuid, uuid, uuid, text, text, bytea)
  to tucambio_backend;

comment on column public.financial_operations.source_effective_at is
  'Effective instant of the confirmed ORIGIN movement; the sole temporal basis for the applied rate.';
comment on column public.financial_operations.applied_rate_id is
  'Immutable historical rate selected when the associated ORIGIN movement is confirmed.';
comment on column public.financial_operations.applied_rate is
  'Direction-specific buy_rate or sell_rate selected from the confirmed ORIGIN movement.';

commit;
