-- M1.8.2 verified source instant rate selection, direction, immutability and replay.
begin;

insert into auth.users (id, email) values
  ('71000000-0000-0000-0000-000000000001', 'rate-application@example.test');
insert into public.tenants (id, name, slug, created_by_user_id) values
  ('72000000-0000-0000-0000-000000000001', 'Rate Application', 'rate-application',
   '71000000-0000-0000-0000-000000000001');
insert into public.tenant_memberships (id, tenant_id, user_id) values
  ('73000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
   '71000000-0000-0000-0000-000000000001');
insert into public.tenant_roles (id, tenant_id, code, name) values
  ('74000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
   'rate-operator', 'Rate Operator');
insert into public.tenant_role_capabilities (tenant_id, role_id, capability_code)
select '72000000-0000-0000-0000-000000000001',
       '74000000-0000-0000-0000-000000000001', c.code
from public.capabilities c
where c.code in ('settings.manage', 'rates.manage', 'operations.operate', 'movements.verify');
insert into public.membership_roles (tenant_id, membership_id, role_id) values
  ('72000000-0000-0000-0000-000000000001',
   '73000000-0000-0000-0000-000000000001',
   '74000000-0000-0000-0000-000000000001');

set local role tucambio_backend;
do $$
declare
  v_usd jsonb;
  v_bob jsonb;
  v_pair jsonb;
  v_rate_old jsonb;
  v_rate_new jsonb;
  v_operation jsonb;
  v_movement jsonb;
  v_result jsonb;
  v_replay jsonb;
begin
  v_usd := public.command_create_tenant_currency(
    '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
    'USD', 'US Dollar', 2, 'rate-test-usd', decode(repeat('21',32),'hex'));
  v_bob := public.command_create_tenant_currency(
    '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
    'BOB', 'Boliviano', 2, 'rate-test-bob', decode(repeat('22',32),'hex'));
  v_pair := public.command_create_currency_pair(
    '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
    'USD', 'BOB', 'rate-test-pair', decode(repeat('23',32),'hex'));
  v_rate_old := public.command_create_currency_rate(
    '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
    (v_pair->>'resourceId')::uuid, 6.90, 6.95,
    '2026-11-01T10:00:00Z', '2026-11-01T11:00:00Z',
    'rate-test-old', decode(repeat('24',32),'hex'));
  v_rate_new := public.command_create_currency_rate(
    '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
    (v_pair->>'resourceId')::uuid, 7.10, 7.15,
    '2026-11-01T11:00:00Z', null,
    'rate-test-new', decode(repeat('25',32),'hex'));
  v_operation := public.command_create_financial_operation(
    '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
    (v_pair->>'resourceId')::uuid, 'USD', 'BOB', 100,
    'rate-test-operation', decode(repeat('26',32),'hex'));
  v_movement := public.command_create_external_movement(
    '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
    'USD', 100, '2026-11-01T10:30:00Z', 'rate-test-origin', 'Verified origin',
    'rate-test-movement', decode(repeat('27',32),'hex'));
  perform public.command_associate_external_movement(
    '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
    (v_operation->>'resourceId')::uuid, (v_movement->>'resourceId')::uuid, 'ORIGIN',
    'rate-test-associate', decode(repeat('28',32),'hex'));
  perform public.command_transition_external_movement(
    '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
    (v_movement->>'resourceId')::uuid, 'IN_VERIFICATION',
    'rate-test-start', decode(repeat('29',32),'hex'));
  perform public.command_transition_external_movement(
    '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
    (v_movement->>'resourceId')::uuid, 'CONFIRMED',
    'rate-test-confirm', decode(repeat('2a',32),'hex'));

  v_result := public.command_apply_operation_rate(
    '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
    (v_operation->>'resourceId')::uuid, 'rate-apply-1', decode(repeat('2b',32),'hex'));
  if v_result->>'rateId' <> v_rate_old->>'resourceId'
     or (v_result->>'rate')::numeric <> 6.90
     or v_result->>'replayed' <> 'false' then
    raise exception 'Rate was not selected at the verified source instant';
  end if;

  v_replay := public.command_apply_operation_rate(
    '71000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
    (v_operation->>'resourceId')::uuid, 'rate-apply-1', decode(repeat('2b',32),'hex'));
  if v_replay->>'replayed' <> 'true' or v_replay->>'rateId' <> v_rate_old->>'resourceId' then
    raise exception 'Rate application retry was not idempotent';
  end if;
end;
$$;
reset role;

do $$
begin
  if not exists (
    select 1 from public.financial_operations o
    join public.external_movements m on m.tenant_id = o.tenant_id
    join public.operation_movements om on om.tenant_id = o.tenant_id
      and om.operation_id = o.id and om.movement_id = m.id and om.movement_role = 'ORIGIN'
    where o.tenant_id = '72000000-0000-0000-0000-000000000001'
      and m.status = 'CONFIRMED'
      and o.source_effective_at = m.effective_at
      and o.applied_rate = 6.90
  ) then raise exception 'Applied rate/source instant was not persisted'; end if;

  if (select count(*) from public.financial_domain_events
      where tenant_id = '72000000-0000-0000-0000-000000000001'
        and entity_type = 'OPERATION' and event_type = 'OPERATION_RATE_APPLIED') <> 1 then
    raise exception 'Rate application audit event missing or duplicated';
  end if;
end;
$$;

rollback;
