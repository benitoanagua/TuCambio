-- M1.8.1 movement verification lifecycle, authorization, audit and replay.
begin;

insert into auth.users (id, email) values
  ('6c000000-0000-0000-0000-000000000001', 'movement-review@example.test');
insert into public.tenants (id, name, slug, created_by_user_id) values
  ('6d000000-0000-0000-0000-000000000001', 'Movement Review', 'movement-review',
   '6c000000-0000-0000-0000-000000000001');
insert into public.tenant_memberships (id, tenant_id, user_id) values
  ('6e000000-0000-0000-0000-000000000001', '6d000000-0000-0000-0000-000000000001',
   '6c000000-0000-0000-0000-000000000001');
insert into public.tenant_roles (id, tenant_id, code, name) values
  ('6f000000-0000-0000-0000-000000000001', '6d000000-0000-0000-0000-000000000001',
   'movement-reviewer', 'Movement Reviewer');
insert into public.tenant_role_capabilities (tenant_id, role_id, capability_code)
values ('6d000000-0000-0000-0000-000000000001',
        '6f000000-0000-0000-0000-000000000001', 'movements.verify');
insert into public.membership_roles (tenant_id, membership_id, role_id)
values ('6d000000-0000-0000-0000-000000000001',
        '6e000000-0000-0000-0000-000000000001', '6f000000-0000-0000-0000-000000000001');
insert into public.tenant_currencies (
  tenant_id, code, name, decimal_places, created_by_membership_id, created_by_user_id
) values (
  '6d000000-0000-0000-0000-000000000001', 'USD', 'US Dollar', 2,
  '6e000000-0000-0000-0000-000000000001', '6c000000-0000-0000-0000-000000000001'
);
insert into public.external_movements (
  id, tenant_id, currency_code, amount, effective_at,
  created_by_membership_id, created_by_user_id
) values (
  '70000000-0000-0000-0000-000000000001',
  '6d000000-0000-0000-0000-000000000001', 'USD', 50, now(),
  '6e000000-0000-0000-0000-000000000001', '6c000000-0000-0000-0000-000000000001'
);

set local role tucambio_backend;
do $$
declare
  v_started jsonb;
  v_replay jsonb;
  v_confirmed jsonb;
  v_invalid boolean := false;
begin
  v_started := public.command_transition_external_movement(
    '6c000000-0000-0000-0000-000000000001',
    '6d000000-0000-0000-0000-000000000001',
    '70000000-0000-0000-0000-000000000001',
    'IN_VERIFICATION', 'movement-start-1', decode(repeat('11', 32), 'hex')
  );
  if v_started->>'status' <> 'IN_VERIFICATION' or v_started->>'replayed' <> 'false' then
    raise exception 'Movement did not enter verification';
  end if;

  v_replay := public.command_transition_external_movement(
    '6c000000-0000-0000-0000-000000000001',
    '6d000000-0000-0000-0000-000000000001',
    '70000000-0000-0000-0000-000000000001',
    'IN_VERIFICATION', 'movement-start-1', decode(repeat('11', 32), 'hex')
  );
  if v_replay->>'replayed' <> 'true' then
    raise exception 'Transition retry was not idempotent';
  end if;

  v_confirmed := public.command_transition_external_movement(
    '6c000000-0000-0000-0000-000000000001',
    '6d000000-0000-0000-0000-000000000001',
    '70000000-0000-0000-0000-000000000001',
    'CONFIRMED', 'movement-confirm-1', decode(repeat('12', 32), 'hex')
  );
  if v_confirmed->>'status' <> 'CONFIRMED' then
    raise exception 'Movement did not become confirmed';
  end if;

  begin
    perform public.command_transition_external_movement(
      '6c000000-0000-0000-0000-000000000001',
      '6d000000-0000-0000-0000-000000000001',
      '70000000-0000-0000-0000-000000000001',
      'NOT_CONFIRMED', 'movement-reverse-1', decode(repeat('13', 32), 'hex')
    );
    raise exception 'Confirmed movement transition unexpectedly reversed';
  exception when check_violation then v_invalid := true;
  end;
  if not v_invalid then raise exception 'Invalid transition was not rejected'; end if;
end;
$$;
reset role;

do $$
begin
  if (select status from public.external_movements
      where id = '70000000-0000-0000-0000-000000000001') <> 'CONFIRMED' then
    raise exception 'Final movement status was not persisted';
  end if;
  if (select count(*) from public.financial_domain_events
      where entity_id = '70000000-0000-0000-0000-000000000001'
        and event_type in ('MOVEMENT_VERIFICATION_STARTED', 'MOVEMENT_CONFIRMED')) <> 2 then
    raise exception 'Expected exactly two audited lifecycle events';
  end if;
end;
$$;

rollback;
