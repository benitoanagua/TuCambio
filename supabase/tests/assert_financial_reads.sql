-- M1.9.3: financial read authorization, tenant isolation and pagination.
begin;

insert into auth.users (id, email) values
  ('71000000-0000-0000-0000-000000000001', 'read-a@example.test'),
  ('71000000-0000-0000-0000-000000000002', 'read-b@example.test'),
  ('71000000-0000-0000-0000-000000000003', 'read-no-capability@example.test');

insert into public.tenants (id, name, slug, created_by_user_id) values
  ('72000000-0000-0000-0000-000000000001', 'Read Tenant A', 'read-tenant-a', '71000000-0000-0000-0000-000000000001'),
  ('72000000-0000-0000-0000-000000000002', 'Read Tenant B', 'read-tenant-b', '71000000-0000-0000-0000-000000000002');

insert into public.tenant_memberships (id, tenant_id, user_id) values
  ('73000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001'),
  ('73000000-0000-0000-0000-000000000002', '72000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000002'),
  ('73000000-0000-0000-0000-000000000003', '72000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000003');

insert into public.tenant_roles (id, tenant_id, code, name) values
  ('74000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001', 'financial-reader', 'Financial Reader'),
  ('74000000-0000-0000-0000-000000000002', '72000000-0000-0000-0000-000000000001', 'ordinary-member', 'Ordinary Member');

insert into public.tenant_role_capabilities (tenant_id, role_id, capability_code) values
  ('72000000-0000-0000-0000-000000000001', '74000000-0000-0000-0000-000000000001', 'financial.read'),
  ('72000000-0000-0000-0000-000000000001', '74000000-0000-0000-0000-000000000002', 'operations.operate');

insert into public.membership_roles (tenant_id, membership_id, role_id) values
  ('72000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000001', '74000000-0000-0000-0000-000000000001'),
  ('72000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000003', '74000000-0000-0000-0000-000000000002');

insert into public.tenant_currencies (
  tenant_id, code, name, decimal_places, created_by_membership_id, created_by_user_id
) values
  ('72000000-0000-0000-0000-000000000001', 'USD', 'US Dollar', 2, '73000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001'),
  ('72000000-0000-0000-0000-000000000001', 'BOB', 'Boliviano', 2, '73000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001'),
  ('72000000-0000-0000-0000-000000000002', 'USD', 'US Dollar', 2, '73000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000002'),
  ('72000000-0000-0000-0000-000000000002', 'BOB', 'Boliviano', 2, '73000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000002');

insert into public.tenant_currency_pairs (
  id, tenant_id, base_currency_code, quote_currency_code,
  created_by_membership_id, created_by_user_id
) values
  ('75000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001', 'USD', 'BOB', '73000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001'),
  ('75000000-0000-0000-0000-000000000002', '72000000-0000-0000-0000-000000000002', 'USD', 'BOB', '73000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000002');

insert into public.currency_rates (
  id, tenant_id, pair_id, buy_rate, sell_rate, valid_from, valid_until,
  created_by_membership_id, created_by_user_id
) values
  ('78000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001',
   '75000000-0000-0000-0000-000000000001', 6.90, 6.95, '2026-11-01T10:00:00Z', '2026-11-01T11:00:00Z',
   '73000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001'),
  ('78000000-0000-0000-0000-000000000002', '72000000-0000-0000-0000-000000000002',
   '75000000-0000-0000-0000-000000000002', 7.00, 7.05, '2026-11-01T10:00:00Z', null,
   '73000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000002');

insert into public.financial_operations (
  id, tenant_id, pair_id, source_currency_code, target_currency_code,
  requested_amount, status, created_by_membership_id, created_by_user_id, created_at
) values
  ('76000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001', '75000000-0000-0000-0000-000000000001', 'USD', 'BOB', 100, 'PENDING', '73000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', '2026-11-01T10:00:00Z'),
  ('76000000-0000-0000-0000-000000000002', '72000000-0000-0000-0000-000000000001', '75000000-0000-0000-0000-000000000001', 'USD', 'BOB', 200, 'FINALIZED', '73000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', '2026-11-01T11:00:00Z'),
  ('76000000-0000-0000-0000-000000000003', '72000000-0000-0000-0000-000000000002', '75000000-0000-0000-0000-000000000002', 'USD', 'BOB', 300, 'PENDING', '73000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000002', '2026-11-01T12:00:00Z');

insert into public.external_movements (
  id, tenant_id, currency_code, amount, effective_at, status,
  created_by_membership_id, created_by_user_id, created_at
) values
  ('77000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001', 'USD', 100, '2026-11-01T10:00:00Z', 'DECLARED', '73000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', '2026-11-01T10:00:00Z'),
  ('77000000-0000-0000-0000-000000000002', '72000000-0000-0000-0000-000000000001', 'USD', 200, '2026-11-01T11:00:00Z', 'CONFIRMED', '73000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', '2026-11-01T11:00:00Z'),
  ('77000000-0000-0000-0000-000000000003', '72000000-0000-0000-0000-000000000002', 'USD', 300, '2026-11-01T12:00:00Z', 'DECLARED', '73000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000002', '2026-11-01T12:00:00Z');

insert into public.financial_domain_events (
  id, tenant_id, actor_membership_id, actor_user_id, entity_type, entity_id, event_type, payload, occurred_at
) values
  ('79000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', 'MOVEMENT', '77000000-0000-0000-0000-000000000001', 'MOVEMENT_DECLARED', '{"internal":"must_not_be_exposed"}', '2026-11-01T10:00:00Z'),
  ('79000000-0000-0000-0000-000000000002', '72000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', 'MOVEMENT', '77000000-0000-0000-0000-000000000002', 'MOVEMENT_CONFIRMED', '{"status":"CONFIRMED"}', '2026-11-01T11:00:00Z'),
  ('79000000-0000-0000-0000-000000000003', '72000000-0000-0000-0000-000000000002', '73000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000002', 'MOVEMENT', '77000000-0000-0000-0000-000000000003', 'MOVEMENT_DECLARED', '{}', '2026-11-01T12:00:00Z');


do $$
declare
  result jsonb;
  denied boolean := false;
begin
  if not has_function_privilege('tucambio_backend', 'public.query_financial_operations(uuid,uuid,text,integer,integer)', 'EXECUTE')
     or not has_function_privilege('tucambio_backend', 'public.query_external_movements(uuid,uuid,text,integer,integer)', 'EXECUTE')
     or not has_function_privilege('tucambio_backend', 'public.query_currency_rates(uuid,uuid,uuid,integer,integer)', 'EXECUTE')
     or not has_function_privilege('tucambio_backend', 'public.query_financial_domain_events(uuid,uuid,text,uuid,integer,integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.query_currency_rates(uuid,uuid,uuid,integer,integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.query_financial_domain_events(uuid,uuid,text,uuid,integer,integer)', 'EXECUTE') then
    raise exception 'Backend role must execute both financial read functions';
  end if;
  if has_function_privilege('authenticated', 'public.query_financial_operations(uuid,uuid,text,integer,integer)', 'EXECUTE')
     or has_function_privilege('anon', 'public.query_external_movements(uuid,uuid,text,integer,integer)', 'EXECUTE')
     or has_table_privilege('tucambio_backend', 'public.financial_operations', 'SELECT')
     or has_table_privilege('tucambio_backend', 'public.external_movements', 'SELECT')
     or has_table_privilege('tucambio_backend', 'public.financial_domain_events', 'SELECT') then
    raise exception 'Financial read functions or tables expose excessive privileges';
  end if;

  result := public.query_financial_operations(
    '71000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000001', null, 100, 0
  );
  if (result->>'total')::integer <> 2 or jsonb_array_length(result->'items') <> 2 then
    raise exception 'Financial operations query did not remain tenant-scoped';
  end if;
  if result->'items'->0->>'id' <> '76000000-0000-0000-0000-000000000002'
     or result->'items'->1->>'id' <> '76000000-0000-0000-0000-000000000001' then
    raise exception 'Financial operations ordering is not deterministic';
  end if;

  result := public.query_financial_operations(
    '71000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000001', 'PENDING', 1, 0
  );
  if (result->>'total')::integer <> 1
     or jsonb_array_length(result->'items') <> 1
     or result->'items'->0->>'status' <> 'PENDING' then
    raise exception 'Financial operation status filter or total is incorrect';
  end if;

  result := public.query_financial_operations(
    '71000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000001', null, 1, 1
  );
  if jsonb_array_length(result->'items') <> 1
     or result->'items'->0->>'id' <> '76000000-0000-0000-0000-000000000001' then
    raise exception 'Financial operation pagination boundary is incorrect';
  end if;

  result := public.query_external_movements(
    '71000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000001', null, 100, 0
  );
  if (result->>'total')::integer <> 2 or jsonb_array_length(result->'items') <> 2 then
    raise exception 'External movements query did not remain tenant-scoped';
  end if;
  if result->'items'->0->>'id' <> '77000000-0000-0000-0000-000000000002' then
    raise exception 'External movements ordering is not deterministic';
  end if;

  result := public.query_external_movements(
    '71000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000001', 'CONFIRMED', 25, 0
  );
  if (result->>'total')::integer <> 1
     or result->'items'->0->>'status' <> 'CONFIRMED' then
    raise exception 'External movement status filter or total is incorrect';
  end if;

  begin
    perform public.query_financial_operations(
      '71000000-0000-0000-0000-000000000002',
      '72000000-0000-0000-0000-000000000001', null, 25, 0
    );
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'Cross-tenant actor unexpectedly read operations'; end if;

  denied := false;
  begin
    perform public.query_external_movements(
      '71000000-0000-0000-0000-000000000003',
      '72000000-0000-0000-0000-000000000001', null, 25, 0
    );
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'Member without financial.read unexpectedly read movements'; end if;

  denied := false;
  begin
    perform public.query_financial_operations(
      '71000000-0000-0000-0000-000000000001',
      '72000000-0000-0000-0000-000000000001', null, 0, 0
    );
  exception when invalid_parameter_value then
    denied := true;
  end;
  if not denied then raise exception 'Invalid page size unexpectedly accepted'; end if;

  denied := false;
  begin
    perform public.query_external_movements(
      '71000000-0000-0000-0000-000000000001',
      '72000000-0000-0000-0000-000000000001', null, 25, 10001
    );
  exception when invalid_parameter_value then
    denied := true;
  end;
  if not denied then raise exception 'Out-of-range offset unexpectedly accepted'; end if;

  result := public.query_currency_rates(
    '71000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000001', null, 25, 0
  );
  if (result->>'total')::integer <> 1
     or jsonb_array_length(result->'items') <> 1
     or result->'items'->0->>'buy_rate' <> '6.900000000000000000'
     or result->'items'->0->>'base_currency_code' <> 'USD' then
    raise exception 'Currency rate history must be tenant-scoped and include pair identity';
  end if;

  result := public.query_currency_rates(
    '71000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000001',
    '75000000-0000-0000-0000-000000000001', 1, 0
  );
  if (result->>'total')::integer <> 1 or jsonb_array_length(result->'items') <> 1 then
    raise exception 'Currency rate pair filter or pagination is incorrect';
  end if;

  denied := false;
  begin
    perform public.query_currency_rates(
      '71000000-0000-0000-0000-000000000002',
      '72000000-0000-0000-0000-000000000001', null, 25, 0
    );
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'Cross-tenant actor unexpectedly read currency rates'; end if;

  result := public.query_financial_domain_events(
    '71000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000001', null, null, 100, 0
  );
  if (result->>'total')::integer <> 2 or jsonb_array_length(result->'items') <> 2 then
    raise exception 'Financial event history did not remain tenant-scoped';
  end if;
  if result->'items'->0->>'id' <> '79000000-0000-0000-0000-000000000002'
     or result->'items'->1->>'id' <> '79000000-0000-0000-0000-000000000001' then
    raise exception 'Financial event ordering is not deterministic';
  end if;
  if result->'items'->0 ? 'payload' or result->'items'->0 ? 'actor_membership_id' then
    raise exception 'Audit read model exposed internal payload or membership identifiers';
  end if;

  result := public.query_financial_domain_events(
    '71000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000001', 'MOVEMENT',
    '77000000-0000-0000-0000-000000000001', 25, 0
  );
  if (result->>'total')::integer <> 1
     or result->'items'->0->>'event_type' <> 'MOVEMENT_DECLARED' then
    raise exception 'Financial event entity filters are incorrect';
  end if;

  denied := false;
  begin
    perform public.query_financial_domain_events(
      '71000000-0000-0000-0000-000000000002',
      '72000000-0000-0000-0000-000000000001', null, null, 25, 0
    );
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then raise exception 'Cross-tenant actor unexpectedly read financial events'; end if;

  denied := false;
  begin
    perform public.query_financial_domain_events(
      '71000000-0000-0000-0000-000000000001',
      '72000000-0000-0000-0000-000000000001', 'INVALID', null, 25, 0
    );
  exception when invalid_parameter_value then
    denied := true;
  end;
  if not denied then raise exception 'Invalid financial event entity type unexpectedly accepted'; end if;
end;
$$;

rollback;
