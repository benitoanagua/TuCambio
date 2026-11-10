-- M1.11 evidence links are append-only, tenant-scoped and independent from review/movement state.
begin;

insert into auth.users (id, email) values
  ('91000000-0000-0000-0000-000000000001', 'evidence-link-operator@example.test'),
  ('91000000-0000-0000-0000-000000000002', 'evidence-link-denied@example.test');

insert into public.tenants (id, name, slug, created_by_user_id) values
  ('92000000-0000-0000-0000-000000000001', 'Evidence Link Tenant', 'evidence-link-tenant',
   '91000000-0000-0000-0000-000000000001');

insert into public.tenant_memberships (id, tenant_id, user_id) values
  ('93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001'),
  ('93000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000002');

insert into public.tenant_roles (id, tenant_id, code, name) values
  ('94000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', 'evidence-operator', 'Evidence Operator');

insert into public.tenant_role_capabilities (tenant_id, role_id, capability_code) values
  ('92000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000001', 'operations.operate'),
  ('92000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000001', 'movements.verify');

insert into public.membership_roles (tenant_id, membership_id, role_id) values
  ('92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', '94000000-0000-0000-0000-000000000001');

insert into public.tenant_currencies (
  tenant_id, code, name, decimal_places, created_by_membership_id, created_by_user_id
) values
  ('92000000-0000-0000-0000-000000000001', 'USD', 'US Dollar', 2, '93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-000000000001', 'BOB', 'Boliviano', 2, '93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001');

insert into public.tenant_currency_pairs (
  id, tenant_id, base_currency_code, quote_currency_code, created_by_membership_id, created_by_user_id
) values (
  '95000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
  'USD', 'BOB', '93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001'
);

insert into public.financial_operations (
  id, tenant_id, pair_id, source_currency_code, target_currency_code,
  requested_amount, created_by_membership_id, created_by_user_id
) values (
  '96000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
  '95000000-0000-0000-0000-000000000001', 'USD', 'BOB', 100,
  '93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001'
);

insert into public.external_movements (
  id, tenant_id, currency_code, amount, effective_at, created_by_membership_id, created_by_user_id
) values
  ('97000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
   'USD', 100, '2026-11-10T10:00:00Z', '93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001'),
  ('97000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000001',
   'USD', 100, '2026-11-10T11:00:00Z', '93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001');

insert into public.tenant_evidence (
  id, tenant_id, created_by_user_id, object_path, mime_type, expected_size_bytes,
  sha256, status, uploaded_at, verified_at
) values
  ('98000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
   '91000000-0000-0000-0000-000000000001',
   '92000000-0000-0000-0000-000000000001/98000000-0000-0000-0000-000000000001',
   'image/png', 8, decode(repeat('ab', 32), 'hex'), 'available', now(), now()),
  ('98000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000001',
   '91000000-0000-0000-0000-000000000001',
   '92000000-0000-0000-0000-000000000001/98000000-0000-0000-0000-000000000002',
   'image/png', 8, null, 'pending', null, null);

set local role tucambio_backend;
do $$
declare
  linked_operation jsonb;
  linked_operation_replay jsonb;
  linked_movement jsonb;
  denied boolean := false;
begin
  if has_function_privilege('authenticated',
       'public.command_link_financial_evidence(uuid,uuid,uuid,text,uuid,text,bytea)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.command_link_financial_evidence(uuid,uuid,uuid,text,uuid,text,bytea)', 'EXECUTE')
     or not has_function_privilege('tucambio_backend',
       'public.command_link_financial_evidence(uuid,uuid,uuid,text,uuid,text,bytea)', 'EXECUTE') then
    raise exception 'Evidence link command privileges are incorrect';
  end if;

  linked_operation := public.command_link_financial_evidence(
    '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
    '98000000-0000-0000-0000-000000000001', 'OPERATION',
    '96000000-0000-0000-0000-000000000001', 'link-operation-1', decode(repeat('11',32),'hex')
  );
  linked_operation_replay := public.command_link_financial_evidence(
    '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
    '98000000-0000-0000-0000-000000000001', 'OPERATION',
    '96000000-0000-0000-0000-000000000001', 'link-operation-1', decode(repeat('11',32),'hex')
  );
  if linked_operation_replay->>'replayed' <> 'true'
     or linked_operation->>'resourceId' <> linked_operation_replay->>'resourceId' then
    raise exception 'Evidence link retry is not idempotent';
  end if;

  -- The same proof may document its operation and its related movement.
  linked_movement := public.command_link_financial_evidence(
    '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
    '98000000-0000-0000-0000-000000000001', 'MOVEMENT',
    '97000000-0000-0000-0000-000000000001', 'link-movement-1', decode(repeat('12',32),'hex')
  );

  begin
    perform public.command_link_financial_evidence(
      '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
      '98000000-0000-0000-0000-000000000001', 'MOVEMENT',
      '97000000-0000-0000-0000-000000000002', 'link-movement-2', decode(repeat('13',32),'hex')
    );
    raise exception 'Evidence was unexpectedly reused across two movements';
  exception when unique_violation then null;
  end;

  begin
    perform public.command_link_financial_evidence(
      '91000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000001',
      '98000000-0000-0000-0000-000000000001', 'OPERATION',
      '96000000-0000-0000-0000-000000000001', 'link-denied-1', decode(repeat('14',32),'hex')
    );
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'Member without capability unexpectedly linked evidence'; end if;

  begin
    perform public.command_link_financial_evidence(
      '91000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
      '98000000-0000-0000-0000-000000000002', 'OPERATION',
      '96000000-0000-0000-0000-000000000001', 'link-pending-1', decode(repeat('15',32),'hex')
    );
    raise exception 'Pending evidence was unexpectedly linked';
  exception when foreign_key_violation then null;
  end;
end;
$$;
reset role;

do $$
begin
  if (select count(*) from public.evidence_financial_links
      where tenant_id = '92000000-0000-0000-0000-000000000001'
        and evidence_id = '98000000-0000-0000-0000-000000000001') <> 2 then
    raise exception 'Expected operation and movement links for the evidence';
  end if;
  if (select status from public.external_movements
      where id = '97000000-0000-0000-0000-000000000001') <> 'DECLARED' then
    raise exception 'Linking evidence must not change movement verification state';
  end if;
  if (select review_status from public.tenant_evidence
      where id = '98000000-0000-0000-0000-000000000001') <> 'PRESENTADA' then
    raise exception 'Linking evidence must not change its review state';
  end if;
  if (select count(*) from public.financial_domain_events
      where tenant_id = '92000000-0000-0000-0000-000000000001'
        and entity_type = 'EVIDENCE_LINK') <> 2 then
    raise exception 'Evidence link audit events are incomplete or duplicated';
  end if;
end;
$$;

rollback;
