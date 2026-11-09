-- TuCambio M1.7.2: narrow, backend-only financial domain commands.
-- All commands are tenant/actor scoped, capability checked, idempotent and
-- append their domain event in the same PostgreSQL transaction as the write.

begin;

-- Give the natural-key currency catalogue a stable resource identifier for
-- events and idempotency results without changing its tenant/code identity.
alter table public.tenant_currencies
  add column id uuid not null default gen_random_uuid();
alter table public.tenant_currencies
  add constraint tenant_currencies_tenant_id_unique unique (tenant_id, id);

create or replace function public.protect_currency_configuration_identity()
returns trigger
language plpgsql
set search_path = pg_catalog
as $
begin
  if tg_table_name = 'tenant_currencies' then
    if new.id is distinct from old.id
       or new.tenant_id is distinct from old.tenant_id
       or new.code is distinct from old.code
       or new.decimal_places is distinct from old.decimal_places then
      raise exception 'Currency identity and precision are immutable' using errcode = '55000';
    end if;
  elsif new.tenant_id is distinct from old.tenant_id
     or new.id is distinct from old.id
     or new.base_currency_code is distinct from old.base_currency_code
     or new.quote_currency_code is distinct from old.quote_currency_code then
    raise exception 'Currency pair identity is immutable' using errcode = '55000';
  end if;
  return new;
end;
$;

alter table public.financial_domain_events
  drop constraint financial_domain_events_entity_type;
alter table public.financial_domain_events
  add constraint financial_domain_events_entity_type
  check (entity_type in ('CURRENCY', 'CURRENCY_PAIR', 'OPERATION', 'MOVEMENT', 'RATE', 'EVIDENCE_LINK'));

create or replace function public.assert_financial_command_actor(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_capability text
)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_membership_id uuid;
begin
  select a.membership_id into v_membership_id
  from public.resolve_tenant_access(p_actor_user_id, p_tenant_id) a
  where a.capability_code = p_capability
     or (p_capability = 'settings.manage' and a.capability_code = 'tenant.administer')
  limit 1;

  if v_membership_id is null then
    raise exception 'Tenant capability denied' using errcode = '42501';
  end if;
  return v_membership_id;
end;
$$;

revoke all on function public.assert_financial_command_actor(uuid, uuid, text)
  from public, anon, authenticated, tucambio_backend;

create or replace function public.claim_financial_command(
  p_tenant_id uuid,
  p_actor_user_id uuid,
  p_command_type text,
  p_idempotency_key text,
  p_request_sha256 bytea
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_resource_id uuid;
  v_existing_hash bytea;
begin
  if p_idempotency_key is null or char_length(p_idempotency_key) not between 1 and 200
     or p_request_sha256 is null or octet_length(p_request_sha256) <> 32 then
    raise exception 'Invalid idempotency metadata' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_tenant_id::text || ':' || p_actor_user_id::text || ':' ||
    p_command_type || ':' || p_idempotency_key, 0
  ));

  select i.request_sha256, i.result_resource_id
    into v_existing_hash, v_resource_id
  from public.financial_command_idempotency i
  where i.tenant_id = p_tenant_id
    and i.actor_user_id = p_actor_user_id
    and i.command_type = p_command_type
    and i.idempotency_key = p_idempotency_key;

  if found then
    if v_existing_hash <> p_request_sha256 then
      raise exception 'Idempotency key reused with different request' using errcode = '23505';
    end if;
    return v_resource_id;
  end if;
  return null;
end;
$$;

revoke all on function public.claim_financial_command(uuid, uuid, text, text, bytea)
  from public, anon, authenticated, tucambio_backend;

create or replace function public.finish_financial_command(
  p_tenant_id uuid,
  p_actor_user_id uuid,
  p_command_type text,
  p_idempotency_key text,
  p_request_sha256 bytea,
  p_resource_id uuid
)
returns void
language sql
security definer
set search_path = pg_catalog, public
as $$
  insert into public.financial_command_idempotency (
    tenant_id, actor_user_id, command_type, idempotency_key,
    request_sha256, result_resource_id
  ) values (
    p_tenant_id, p_actor_user_id, p_command_type, p_idempotency_key,
    p_request_sha256, p_resource_id
  );
$$;

revoke all on function public.finish_financial_command(uuid, uuid, text, text, bytea, uuid)
  from public, anon, authenticated, tucambio_backend;

create or replace function public.command_create_tenant_currency(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_code text,
  p_name text,
  p_decimal_places smallint,
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
begin
  v_membership_id := public.assert_financial_command_actor(p_actor_user_id, p_tenant_id, 'settings.manage');
  v_resource_id := public.claim_financial_command(p_tenant_id, p_actor_user_id, 'CREATE_CURRENCY', p_idempotency_key, p_request_sha256);
  if v_resource_id is not null then
    return jsonb_build_object('resourceId', v_resource_id, 'replayed', true);
  end if;

  insert into public.tenant_currencies (
    tenant_id, code, name, decimal_places, created_by_membership_id, created_by_user_id
  ) values (
    p_tenant_id, upper(btrim(p_code)), btrim(p_name), p_decimal_places, v_membership_id, p_actor_user_id
  ) returning id into v_resource_id;

  perform public.finish_financial_command(p_tenant_id, p_actor_user_id, 'CREATE_CURRENCY',
    p_idempotency_key, p_request_sha256, v_resource_id);
  insert into public.financial_domain_events (
    tenant_id, actor_membership_id, actor_user_id, entity_type, entity_id, event_type
  ) values (p_tenant_id, v_membership_id, p_actor_user_id, 'CURRENCY', v_resource_id, 'CURRENCY_CREATED');

  return jsonb_build_object('resourceId', v_resource_id, 'code', upper(btrim(p_code)), 'replayed', false);
end;
$$;

create or replace function public.command_create_currency_pair(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_base_currency_code text,
  p_quote_currency_code text,
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
begin
  v_membership_id := public.assert_financial_command_actor(p_actor_user_id, p_tenant_id, 'settings.manage');
  v_resource_id := public.claim_financial_command(p_tenant_id, p_actor_user_id, 'CREATE_CURRENCY_PAIR', p_idempotency_key, p_request_sha256);
  if v_resource_id is not null then
    return jsonb_build_object('resourceId', v_resource_id, 'replayed', true);
  end if;

  insert into public.tenant_currency_pairs (
    tenant_id, base_currency_code, quote_currency_code, created_by_membership_id, created_by_user_id
  ) values (
    p_tenant_id, upper(btrim(p_base_currency_code)), upper(btrim(p_quote_currency_code)),
    v_membership_id, p_actor_user_id
  ) returning id into v_resource_id;

  perform public.finish_financial_command(p_tenant_id, p_actor_user_id, 'CREATE_CURRENCY_PAIR',
    p_idempotency_key, p_request_sha256, v_resource_id);
  insert into public.financial_domain_events (
    tenant_id, actor_membership_id, actor_user_id, entity_type, entity_id, event_type
  ) values (p_tenant_id, v_membership_id, p_actor_user_id, 'CURRENCY_PAIR', v_resource_id, 'CURRENCY_PAIR_CREATED');

  return jsonb_build_object('resourceId', v_resource_id, 'replayed', false);
end;
$$;

create or replace function public.command_create_currency_rate(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_pair_id uuid,
  p_buy_rate numeric,
  p_sell_rate numeric,
  p_valid_from timestamptz,
  p_valid_until timestamptz,
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
begin
  v_membership_id := public.assert_financial_command_actor(p_actor_user_id, p_tenant_id, 'rates.manage');
  v_resource_id := public.claim_financial_command(p_tenant_id, p_actor_user_id, 'CREATE_CURRENCY_RATE', p_idempotency_key, p_request_sha256);
  if v_resource_id is not null then
    return jsonb_build_object('resourceId', v_resource_id, 'replayed', true);
  end if;

  if not exists (
    select 1 from public.tenant_currency_pairs p
    join public.tenant_currencies b on b.tenant_id = p.tenant_id and b.code = p.base_currency_code and b.status = 'active'
    join public.tenant_currencies q on q.tenant_id = p.tenant_id and q.code = p.quote_currency_code and q.status = 'active'
    where p.tenant_id = p_tenant_id and p.id = p_pair_id and p.status = 'enabled'
  ) then
    raise exception 'Currency pair is not enabled with active currencies' using errcode = '23514';
  end if;

  insert into public.currency_rates (
    tenant_id, pair_id, buy_rate, sell_rate, valid_from, valid_until,
    created_by_membership_id, created_by_user_id
  ) values (
    p_tenant_id, p_pair_id, p_buy_rate, p_sell_rate, p_valid_from, p_valid_until,
    v_membership_id, p_actor_user_id
  ) returning id into v_resource_id;

  perform public.finish_financial_command(p_tenant_id, p_actor_user_id, 'CREATE_CURRENCY_RATE',
    p_idempotency_key, p_request_sha256, v_resource_id);
  insert into public.financial_domain_events (
    tenant_id, actor_membership_id, actor_user_id, entity_type, entity_id, event_type
  ) values (p_tenant_id, v_membership_id, p_actor_user_id, 'RATE', v_resource_id, 'CURRENCY_RATE_CREATED');

  return jsonb_build_object('resourceId', v_resource_id, 'replayed', false);
end;
$$;

create or replace function public.command_create_financial_operation(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_pair_id uuid,
  p_source_currency_code text,
  p_target_currency_code text,
  p_requested_amount numeric,
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
begin
  v_membership_id := public.assert_financial_command_actor(p_actor_user_id, p_tenant_id, 'operations.operate');
  v_resource_id := public.claim_financial_command(p_tenant_id, p_actor_user_id, 'CREATE_FINANCIAL_OPERATION', p_idempotency_key, p_request_sha256);
  if v_resource_id is not null then
    return jsonb_build_object('resourceId', v_resource_id, 'replayed', true);
  end if;

  insert into public.financial_operations (
    tenant_id, pair_id, source_currency_code, target_currency_code,
    requested_amount, created_by_membership_id, created_by_user_id
  ) values (
    p_tenant_id, p_pair_id, upper(btrim(p_source_currency_code)), upper(btrim(p_target_currency_code)),
    p_requested_amount, v_membership_id, p_actor_user_id
  ) returning id into v_resource_id;

  perform public.finish_financial_command(p_tenant_id, p_actor_user_id, 'CREATE_FINANCIAL_OPERATION',
    p_idempotency_key, p_request_sha256, v_resource_id);
  insert into public.financial_domain_events (
    tenant_id, actor_membership_id, actor_user_id, entity_type, entity_id, event_type
  ) values (p_tenant_id, v_membership_id, p_actor_user_id, 'OPERATION', v_resource_id, 'OPERATION_CREATED');

  return jsonb_build_object('resourceId', v_resource_id, 'replayed', false);
end;
$$;

create or replace function public.command_create_external_movement(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_currency_code text,
  p_amount numeric,
  p_effective_at timestamptz,
  p_external_reference text,
  p_description text,
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
begin
  v_membership_id := public.assert_financial_command_actor(p_actor_user_id, p_tenant_id, 'movements.verify');
  v_resource_id := public.claim_financial_command(p_tenant_id, p_actor_user_id, 'CREATE_EXTERNAL_MOVEMENT', p_idempotency_key, p_request_sha256);
  if v_resource_id is not null then
    return jsonb_build_object('resourceId', v_resource_id, 'replayed', true);
  end if;

  insert into public.external_movements (
    tenant_id, currency_code, amount, effective_at, external_reference, description,
    created_by_membership_id, created_by_user_id
  ) values (
    p_tenant_id, upper(btrim(p_currency_code)), p_amount, p_effective_at, p_external_reference, p_description,
    v_membership_id, p_actor_user_id
  ) returning id into v_resource_id;

  perform public.finish_financial_command(p_tenant_id, p_actor_user_id, 'CREATE_EXTERNAL_MOVEMENT',
    p_idempotency_key, p_request_sha256, v_resource_id);
  insert into public.financial_domain_events (
    tenant_id, actor_membership_id, actor_user_id, entity_type, entity_id, event_type
  ) values (p_tenant_id, v_membership_id, p_actor_user_id, 'MOVEMENT', v_resource_id, 'MOVEMENT_DECLARED');

  return jsonb_build_object('resourceId', v_resource_id, 'replayed', false);
end;
$$;

create or replace function public.command_associate_external_movement(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_operation_id uuid,
  p_movement_id uuid,
  p_movement_role text,
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
  v_existing_operation uuid;
begin
  v_membership_id := public.assert_financial_command_actor(p_actor_user_id, p_tenant_id, 'operations.operate');
  v_resource_id := public.claim_financial_command(p_tenant_id, p_actor_user_id, 'ASSOCIATE_EXTERNAL_MOVEMENT', p_idempotency_key, p_request_sha256);
  if v_resource_id is not null then
    return jsonb_build_object('resourceId', v_resource_id, 'replayed', true);
  end if;

  perform 1 from public.external_movements m
  where m.tenant_id = p_tenant_id and m.id = p_movement_id
  for update;
  if not found then
    raise exception 'External movement not found in tenant' using errcode = '23503';
  end if;

  select om.operation_id into v_existing_operation
  from public.operation_movements om
  where om.tenant_id = p_tenant_id and om.movement_id = p_movement_id;
  if found then
    raise exception 'External movement is already associated' using errcode = '23505';
  end if;

  insert into public.operation_movements (
    tenant_id, operation_id, movement_id, movement_role,
    associated_by_membership_id, associated_by_user_id
  ) values (
    p_tenant_id, p_operation_id, p_movement_id, p_movement_role,
    v_membership_id, p_actor_user_id
  ) returning movement_id into v_resource_id;

  perform public.finish_financial_command(p_tenant_id, p_actor_user_id, 'ASSOCIATE_EXTERNAL_MOVEMENT',
    p_idempotency_key, p_request_sha256, v_resource_id);
  insert into public.financial_domain_events (
    tenant_id, actor_membership_id, actor_user_id, entity_type, entity_id, event_type,
    payload
  ) values (
    p_tenant_id, v_membership_id, p_actor_user_id, 'MOVEMENT', p_movement_id, 'MOVEMENT_ASSOCIATED',
    jsonb_build_object('operationId', p_operation_id, 'role', p_movement_role)
  );

  return jsonb_build_object('resourceId', v_resource_id, 'replayed', false);
end;
$$;

revoke all on function public.command_create_tenant_currency(uuid, uuid, text, text, smallint, text, bytea)
  from public, anon, authenticated;
revoke all on function public.command_create_currency_pair(uuid, uuid, text, text, text, bytea)
  from public, anon, authenticated;
revoke all on function public.command_create_currency_rate(uuid, uuid, uuid, numeric, numeric, timestamptz, timestamptz, text, bytea)
  from public, anon, authenticated;
revoke all on function public.command_create_financial_operation(uuid, uuid, uuid, text, text, numeric, text, bytea)
  from public, anon, authenticated;
revoke all on function public.command_create_external_movement(uuid, uuid, text, numeric, timestamptz, text, text, text, bytea)
  from public, anon, authenticated;
revoke all on function public.command_associate_external_movement(uuid, uuid, uuid, uuid, text, text, bytea)
  from public, anon, authenticated;

grant execute on function public.command_create_tenant_currency(uuid, uuid, text, text, smallint, text, bytea) to tucambio_backend;
grant execute on function public.command_create_currency_pair(uuid, uuid, text, text, text, bytea) to tucambio_backend;
grant execute on function public.command_create_currency_rate(uuid, uuid, uuid, numeric, numeric, timestamptz, timestamptz, text, bytea) to tucambio_backend;
grant execute on function public.command_create_financial_operation(uuid, uuid, uuid, text, text, numeric, text, bytea) to tucambio_backend;
grant execute on function public.command_create_external_movement(uuid, uuid, text, numeric, timestamptz, text, text, text, bytea) to tucambio_backend;
grant execute on function public.command_associate_external_movement(uuid, uuid, uuid, uuid, text, text, bytea) to tucambio_backend;

commit;
