-- M1.7.2 command contract: capability checks, tenant isolation and idempotency.
begin;

insert into auth.users (id, email) values
  ('68000000-0000-0000-0000-000000000001', 'commands-a@example.test'),
  ('68000000-0000-0000-0000-000000000002', 'commands-b@example.test');

insert into public.tenants (id, name, slug, created_by_user_id) values
  ('69000000-0000-0000-0000-000000000001', 'Commands A', 'commands-a', '68000000-0000-0000-0000-000000000001'),
  ('69000000-0000-0000-0000-000000000002', 'Commands B', 'commands-b', '68000000-0000-0000-0000-000000000002');

insert into public.tenant_memberships (id, tenant_id, user_id) values
  ('6a000000-0000-0000-0000-000000000001', '69000000-0000-0000-0000-000000000001', '68000000-0000-0000-0000-000000000001'),
  ('6a000000-0000-0000-0000-000000000002', '69000000-0000-0000-0000-000000000002', '68000000-0000-0000-0000-000000000002');

insert into public.tenant_roles (id, tenant_id, code, name) values
  ('6b000000-0000-0000-0000-000000000001', '69000000-0000-0000-0000-000000000001', 'financial-admin', 'Financial Admin');

insert into public.tenant_role_capabilities (tenant_id, role_id, capability_code)
select '69000000-0000-0000-0000-000000000001',
       '6b000000-0000-0000-0000-000000000001',
       c.code
from public.capabilities c
where c.code in ('settings.manage', 'rates.manage', 'operations.operate', 'movements.verify');

insert into public.membership_roles (tenant_id, membership_id, role_id) values
  ('69000000-0000-0000-0000-000000000001',
   '6a000000-0000-0000-0000-000000000001',
   '6b000000-0000-0000-0000-000000000001');

set local role tucambio_backend;

do $$
declare
  v_first jsonb;
  v_replay jsonb;
  v_conflict boolean := false;
  v_usd jsonb;
  v_bob jsonb;
  v_pair jsonb;
  v_rate jsonb;
  v_operation jsonb;
  v_movement jsonb;
  v_association jsonb;
  v_tenant_b_denied boolean := false;
begin
  if has_function_privilege('anon',
       'public.command_create_financial_operation(uuid,uuid,uuid,text,text,numeric,text,bytea)', 'EXECUTE')
     or has_function_privilege('authenticated',
       'public.command_create_financial_operation(uuid,uuid,uuid,text,text,numeric,text,bytea)', 'EXECUTE') then
    raise exception 'Financial command functions must not be executable by client roles';
  end if;

  if not has_function_privilege('tucambio_backend',
       'public.command_create_financial_operation(uuid,uuid,uuid,text,text,numeric,text,bytea)', 'EXECUTE') then
    raise exception 'Backend role must be able to execute financial commands';
  end if;

  v_usd := public.command_create_tenant_currency(
    '68000000-0000-0000-0000-000000000001', '69000000-0000-0000-0000-000000000001',
    'USD', 'US Dollar', 2::smallint, 'currency-usd-1', decode(repeat('01', 32), 'hex'));
  v_first := public.command_create_tenant_currency(
    '68000000-0000-0000-0000-000000000001', '69000000-0000-0000-0000-000000000001',
    'BOB', 'Boliviano', 2::smallint, 'currency-bob-1', decode(repeat('02', 32), 'hex'));
  v_replay := public.command_create_tenant_currency(
    '68000000-0000-0000-0000-000000000001', '69000000-0000-0000-0000-000000000001',
    'BOB', 'Boliviano', 2::smallint, 'currency-bob-1', decode(repeat('02', 32), 'hex'));
  if (v_first->>'resourceId') <> (v_replay->>'resourceId') or (v_replay->>'replayed') <> 'true' then
    raise exception 'Same idempotency key must return the original resource';
  end if;

  begin
    perform public.command_create_tenant_currency(
      '68000000-0000-0000-0000-000000000001', '69000000-0000-0000-0000-000000000001',
      'BOB', 'Boliviano', 2::smallint, 'currency-bob-1', decode(repeat('03', 32), 'hex'));
    raise exception 'Changed payload with same idempotency key unexpectedly accepted';
  exception when unique_violation then v_conflict := true;
  end;
  if not v_conflict then raise exception 'Idempotency payload conflict was not rejected'; end if;

  v_pair := public.command_create_currency_pair(
    '68000000-0000-0000-0000-000000000001', '69000000-0000-0000-0000-000000000001',
    'USD', 'BOB', 'pair-usd-bob-1', decode(repeat('04', 32), 'hex'));

  v_rate := public.command_create_currency_rate(
    '68000000-0000-0000-0000-000000000001', '69000000-0000-0000-0000-000000000001',
    (v_pair->>'resourceId')::uuid, 6.90, 6.95,
    '2026-11-01T10:00:00Z', null, 'rate-1', decode(repeat('05', 32), 'hex'));

  v_operation := public.command_create_financial_operation(
    '68000000-0000-0000-0000-000000000001', '69000000-0000-0000-0000-000000000001',
    (v_pair->>'resourceId')::uuid, 'USD', 'BOB', 100,
    'operation-1', decode(repeat('06', 32), 'hex'));

  v_movement := public.command_create_external_movement(
    '68000000-0000-0000-0000-000000000001', '69000000-0000-0000-0000-000000000001',
    'USD', 100, '2026-11-01T10:30:00Z', 'external-ref-1', 'External deposit',
    'movement-1', decode(repeat('07', 32), 'hex'));

  v_association := public.command_associate_external_movement(
    '68000000-0000-0000-0000-000000000001', '69000000-0000-0000-0000-000000000001',
    (v_operation->>'resourceId')::uuid, (v_movement->>'resourceId')::uuid, 'ORIGIN',
    'associate-1', decode(repeat('08', 32), 'hex'));

  begin
    perform public.command_create_tenant_currency(
      '68000000-0000-0000-0000-000000000002', '69000000-0000-0000-0000-000000000001',
      'EUR', 'Euro', 2::smallint, 'cross-tenant-1', decode(repeat('09', 32), 'hex'));
    raise exception 'Cross-tenant actor unexpectedly created currency';
  exception when insufficient_privilege then v_tenant_b_denied := true;
  end;

  if not v_tenant_b_denied then raise exception 'Cross-tenant command was not denied'; end if;
end;
$$;

reset role;

do $$
begin
  if (select count(*) from public.tenant_currencies
      where tenant_id = '69000000-0000-0000-0000-000000000001') <> 2 then
    raise exception 'Unexpected currency command result count';
  end if;
  if (select count(*) from public.currency_rates
      where tenant_id = '69000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'Currency rate command did not persist';
  end if;
  if (select count(*) from public.financial_operations
      where tenant_id = '69000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'Operation command did not persist';
  end if;
  if (select count(*) from public.operation_movements
      where tenant_id = '69000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'Movement association command did not persist';
  end if;
  if (select count(*) from public.financial_domain_events
      where tenant_id = '69000000-0000-0000-0000-000000000001') <> 7 then
    raise exception 'Each successful financial command must append one domain event';
  end if;
end;
$$;

rollback;
