-- M1.8.4: rate selection and immutable verified-source amount snapshot.
-- Covers direction, half-open boundary, requested-vs-verified amount, no-rate behavior and audit trail.
begin;

insert into auth.users (id, email) values
  ('81000000-0000-0000-0000-000000000001', 'source-rate@example.test');
insert into public.tenants (id, name, slug, created_by_user_id) values
  ('82000000-0000-0000-0000-000000000001', 'Source Rate', 'source-rate',
   '81000000-0000-0000-0000-000000000001');
insert into public.tenant_memberships (id, tenant_id, user_id) values
  ('83000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001',
   '81000000-0000-0000-0000-000000000001');
insert into public.tenant_roles (id, tenant_id, code, name) values
  ('84000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001',
   'source-rate-reviewer', 'Source Rate Reviewer');
insert into public.tenant_role_capabilities (tenant_id, role_id, capability_code)
values ('82000000-0000-0000-0000-000000000001',
        '84000000-0000-0000-0000-000000000001', 'movements.verify'),
       ('82000000-0000-0000-0000-000000000001',
        '84000000-0000-0000-0000-000000000001', 'financial.read');
insert into public.membership_roles (tenant_id, membership_id, role_id)
values ('82000000-0000-0000-0000-000000000001',
        '83000000-0000-0000-0000-000000000001', '84000000-0000-0000-0000-000000000001');

insert into public.tenant_currencies (
  tenant_id, code, name, decimal_places, created_by_membership_id, created_by_user_id
) values
  ('82000000-0000-0000-0000-000000000001', 'USD', 'US Dollar', 2,
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('82000000-0000-0000-0000-000000000001', 'BOB', 'Boliviano', 2,
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001');

insert into public.tenant_currency_pairs (
  id, tenant_id, base_currency_code, quote_currency_code,
  created_by_membership_id, created_by_user_id
) values (
  '85000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000001', 'USD', 'BOB',
  '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'
);

insert into public.currency_rates (
  id, tenant_id, pair_id, buy_rate, sell_rate, valid_from, valid_until,
  created_by_membership_id, created_by_user_id
) values
  ('86000000-0000-0000-0000-000000000001',
   '82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001',
   6.90, 6.95, '2026-11-10T10:00:00Z', '2026-11-10T11:00:00Z',
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('86000000-0000-0000-0000-000000000002',
   '82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001',
   6.91, 6.96, '2026-11-10T11:00:00Z', '2026-11-10T12:00:00Z',
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001');

insert into public.financial_operations (
  id, tenant_id, pair_id, source_currency_code, target_currency_code,
  requested_amount, created_by_membership_id, created_by_user_id
) values
  ('87000000-0000-0000-0000-000000000001',
   '82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001',
   'USD', 'BOB', 100, '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('87000000-0000-0000-0000-000000000002',
   '82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001',
   'BOB', 'USD', 690, '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('87000000-0000-0000-0000-000000000003',
   '82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001',
   'USD', 'BOB', 100, '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('87000000-0000-0000-0000-000000000004',
   '82000000-0000-0000-0000-000000000001', '85000000-0000-0000-0000-000000000001',
   'USD', 'BOB', 100, '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001');

insert into public.external_movements (
  id, tenant_id, currency_code, amount, effective_at,
  created_by_membership_id, created_by_user_id
) values
  ('88000000-0000-0000-0000-000000000001',
   '82000000-0000-0000-0000-000000000001', 'USD', 98.75, '2026-11-10T10:59:59Z',
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('88000000-0000-0000-0000-000000000002',
   '82000000-0000-0000-0000-000000000001', 'BOB', 690, '2026-11-10T11:00:00Z',
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('88000000-0000-0000-0000-000000000003',
   '82000000-0000-0000-0000-000000000001', 'USD', 100, '2026-11-10T12:00:00Z',
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('88000000-0000-0000-0000-000000000004',
   '82000000-0000-0000-0000-000000000001', 'BOB', 690, '2026-11-10T10:30:00Z',
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('88000000-0000-0000-0000-000000000005',
   '82000000-0000-0000-0000-000000000001', 'BOB', 680.25, '2026-11-10T11:30:00Z',
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('88000000-0000-0000-0000-000000000006',
   '82000000-0000-0000-0000-000000000001', 'BOB', 700, '2026-11-10T11:40:00Z',
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001');

insert into public.operation_movements (
  tenant_id, operation_id, movement_id, movement_role,
  associated_by_membership_id, associated_by_user_id
) values
  ('82000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000001',
   '88000000-0000-0000-0000-000000000001', 'ORIGIN',
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('82000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000002',
   '88000000-0000-0000-0000-000000000002', 'ORIGIN',
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('82000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000003',
   '88000000-0000-0000-0000-000000000003', 'ORIGIN',
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('82000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000004',
   '88000000-0000-0000-0000-000000000004', 'ORIGIN',
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('82000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000001',
   '88000000-0000-0000-0000-000000000005', 'DESTINATION',
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001'),
  ('82000000-0000-0000-0000-000000000001', '87000000-0000-0000-0000-000000000002',
   '88000000-0000-0000-0000-000000000006', 'DESTINATION',
   '83000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001');

set local role tucambio_backend;
do $$
declare
  v_result jsonb;
  v_movement uuid;
  v_key text;
  v_hash text;
  i integer;
begin
  for i in 1..4 loop
    v_movement := case i
      when 1 then '88000000-0000-0000-0000-000000000001'::uuid
      when 2 then '88000000-0000-0000-0000-000000000002'::uuid
      when 3 then '88000000-0000-0000-0000-000000000003'::uuid
      else '88000000-0000-0000-0000-000000000004'::uuid
    end;
    v_key := 'source-rate-start-' || i;
    v_hash := case i when 1 then repeat('21', 32) when 2 then repeat('22', 32) when 3 then repeat('23', 32) else repeat('24', 32) end;
    perform public.command_transition_external_movement(
      '81000000-0000-0000-0000-000000000001',
      '82000000-0000-0000-0000-000000000001',
      v_movement, 'IN_VERIFICATION', v_key, decode(v_hash, 'hex')
    );
    v_key := 'source-rate-confirm-' || i;
    v_hash := case i when 1 then repeat('31', 32) when 2 then repeat('32', 32) when 3 then repeat('33', 32) else repeat('34', 32) end;
    v_result := public.command_transition_external_movement(
      '81000000-0000-0000-0000-000000000001',
      '82000000-0000-0000-0000-000000000001',
      v_movement, 'CONFIRMED', v_key, decode(v_hash, 'hex')
    );
    if i < 3 and v_result->>'sourceRateResolution' <> 'RATE_APPLIED' then
      raise exception 'Expected rate application for movement %: %', i, v_result;
    end if;
    if i = 3 and v_result->>'sourceRateResolution' <> 'RATE_NOT_FOUND' then
      raise exception 'Expected explicit missing-rate result: %', v_result;
    end if;
    if i = 4 and v_result->>'sourceRateResolution' <> 'SOURCE_CURRENCY_MISMATCH' then
      raise exception 'Expected explicit source-currency mismatch result: %', v_result;
    end if;
  end loop;
  -- Confirm the destination movements after their explicit associations.
  perform public.command_transition_external_movement(
    '81000000-0000-0000-0000-000000000001',
    '82000000-0000-0000-0000-000000000001',
    '88000000-0000-0000-0000-000000000005', 'IN_VERIFICATION',
    'destination-start-1', decode(repeat('41', 32), 'hex')
  );
  perform public.command_transition_external_movement(
    '81000000-0000-0000-0000-000000000001',
    '82000000-0000-0000-0000-000000000001',
    '88000000-0000-0000-0000-000000000005', 'CONFIRMED',
    'destination-confirm-1', decode(repeat('42', 32), 'hex')
  );
  perform public.command_transition_external_movement(
    '81000000-0000-0000-0000-000000000001',
    '82000000-0000-0000-0000-000000000001',
    '88000000-0000-0000-0000-000000000006', 'IN_VERIFICATION',
    'destination-start-2', decode(repeat('43', 32), 'hex')
  );
  perform public.command_transition_external_movement(
    '81000000-0000-0000-0000-000000000001',
    '82000000-0000-0000-0000-000000000001',
    '88000000-0000-0000-0000-000000000006', 'CONFIRMED',
    'destination-confirm-2', decode(repeat('44', 32), 'hex')
  );
end;
$$;
reset role;

set local role tucambio_backend;
do $read$
declare
  v_page jsonb;
  v_item jsonb;
begin
  v_page := public.query_financial_operations(
    '81000000-0000-0000-0000-000000000001',
    '82000000-0000-0000-0000-000000000001',
    null, 25, 0
  );
  select value into v_item
  from jsonb_array_elements(v_page->'items')
  where value->>'id' = '87000000-0000-0000-0000-000000000001';
  if (v_item->>'verified_destination_movement_id')::uuid <> '88000000-0000-0000-0000-000000000005'::uuid
     or (v_item->>'verified_destination_amount')::numeric <> 680.25::numeric
     or (v_item->>'destination_effective_at')::timestamptz <> '2026-11-10T11:30:00Z'::timestamptz then
    raise exception 'Financial operation read must expose the verified destination snapshot';
  end if;
end;
$read$;
reset role;

do $$
begin
  if not exists (
    select 1 from public.financial_operations
    where id = '87000000-0000-0000-0000-000000000001'
      and verified_destination_movement_id = '88000000-0000-0000-0000-000000000005'
      and verified_destination_amount = 680.25
      and destination_effective_at = '2026-11-10T11:30:00Z'
  ) then raise exception 'Confirmed destination amount must be snapshotted exactly'; end if;

  if exists (
    select 1 from public.financial_operations
    where id = '87000000-0000-0000-0000-000000000002'
      and verified_destination_movement_id is not null
  ) then raise exception 'Destination currency mismatch must not be snapshotted'; end if;

  begin
    update public.financial_operations
    set verified_destination_amount = 681
    where id = '87000000-0000-0000-0000-000000000001';
    raise exception 'Verified destination amount mutation should have been rejected';
  exception when sqlstate '55000' then
    null;
  end;

  if not exists (
    select 1 from public.financial_operations
    where id = '87000000-0000-0000-0000-000000000001'
      and source_effective_at = '2026-11-10T10:59:59Z'
      and applied_rate_id = '86000000-0000-0000-0000-000000000001'
      and applied_rate = 6.90
  ) then raise exception 'Base-currency source must apply buy_rate before boundary'; end if;

  if not exists (
    select 1 from public.financial_operations
    where id = '87000000-0000-0000-0000-000000000002'
      and source_effective_at = '2026-11-10T11:00:00Z'
      and applied_rate_id = '86000000-0000-0000-0000-000000000002'
      and applied_rate = 6.96
  ) then raise exception 'Quote-currency source must apply sell_rate at half-open boundary'; end if;

  if not exists (
    select 1 from public.financial_operations
    where id = '87000000-0000-0000-0000-000000000003'
      and source_effective_at = '2026-11-10T12:00:00Z'
      and applied_rate_id is null
      and applied_rate is null
  ) then raise exception 'Missing rate must preserve source instant without inventing a rate'; end if;

  if not exists (
    select 1 from public.financial_operations
    where id = '87000000-0000-0000-0000-000000000001'
      and verified_source_movement_id = '88000000-0000-0000-0000-000000000001'
      and verified_source_amount = 98.75
      and requested_amount = 100
  ) then raise exception 'Verified source amount must snapshot the movement, not the requested amount'; end if;

  if not exists (
    select 1 from public.financial_operations
    where id = '87000000-0000-0000-0000-000000000002'
      and verified_source_movement_id = '88000000-0000-0000-0000-000000000002'
      and verified_source_amount = 690
  ) then raise exception 'Quote-currency source amount must be snapshotted'; end if;

  if not exists (
    select 1 from public.financial_operations
    where id = '87000000-0000-0000-0000-000000000003'
      and verified_source_movement_id = '88000000-0000-0000-0000-000000000003'
      and verified_source_amount = 100
  ) then raise exception 'Verified source amount must be preserved even when no rate exists'; end if;

  if exists (
    select 1 from public.financial_operations
    where id = '87000000-0000-0000-0000-000000000004'
      and (verified_source_movement_id is not null or verified_source_amount is not null)
  ) then raise exception 'A mismatched source currency must not be snapshotted'; end if;

  begin
    update public.financial_operations
    set verified_source_amount = 99
    where id = '87000000-0000-0000-0000-000000000001';
    raise exception 'Verified source amount mutation should have been rejected';
  exception when sqlstate '55000' then
    null;
  end;

  if (select count(*) from public.financial_domain_events
      where entity_type = 'OPERATION'
        and event_type = 'OPERATION_SOURCE_RATE_APPLIED'
        and entity_id in (
          '87000000-0000-0000-0000-000000000001',
          '87000000-0000-0000-0000-000000000002'
        )) <> 2 then
    raise exception 'Applied source rates must be audited';
  end if;

  if (select count(*) from public.financial_domain_events
      where entity_type = 'OPERATION'
        and event_type = 'OPERATION_SOURCE_RATE_NOT_FOUND'
        and entity_id = '87000000-0000-0000-0000-000000000003') <> 1 then
    raise exception 'Missing source rate must be audited';
  end if;

  if exists (select 1 from public.financial_operations
             where id = '87000000-0000-0000-0000-000000000004'
               and (source_effective_at is not null or applied_rate_id is not null or applied_rate is not null)) then
    raise exception 'A mismatched source currency must not be applied to the operation';
  end if;
  if (select count(*) from public.financial_domain_events
      where entity_type = 'OPERATION'
        and event_type = 'OPERATION_SOURCE_CURRENCY_MISMATCH'
        and entity_id = '87000000-0000-0000-0000-000000000004') <> 1 then
    raise exception 'Source-currency mismatch must be audited';
  end if;
end;
$$;

rollback;
