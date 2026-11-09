-- M1.7.1 structural, isolation, temporal and immutability assertions.
begin;

insert into auth.users (id, email) values
  ('61000000-0000-0000-0000-000000000001', 'financial-a@example.test'),
  ('61000000-0000-0000-0000-000000000002', 'financial-b@example.test');

insert into public.tenants (id, name, slug, created_by_user_id) values
  ('62000000-0000-0000-0000-000000000001', 'Financial A', 'financial-a', '61000000-0000-0000-0000-000000000001'),
  ('62000000-0000-0000-0000-000000000002', 'Financial B', 'financial-b', '61000000-0000-0000-0000-000000000002');

insert into public.tenant_memberships (id, tenant_id, user_id) values
  ('63000000-0000-0000-0000-000000000001', '62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001'),
  ('63000000-0000-0000-0000-000000000002', '62000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000002');

insert into public.tenant_currencies (
  tenant_id, code, name, decimal_places, created_by_membership_id, created_by_user_id
) values
  ('62000000-0000-0000-0000-000000000001', 'USD', 'US Dollar', 2, '63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001'),
  ('62000000-0000-0000-0000-000000000001', 'BOB', 'Boliviano', 2, '63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001'),
  ('62000000-0000-0000-0000-000000000001', 'EUR', 'Euro', 2, '63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001'),
  ('62000000-0000-0000-0000-000000000002', 'USD', 'US Dollar', 2, '63000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000002');

insert into public.tenant_currency_pairs (
  id, tenant_id, base_currency_code, quote_currency_code,
  created_by_membership_id, created_by_user_id
) values (
  '64000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001', 'USD', 'BOB',
  '63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001'
);

do $$
begin
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'financial_operations' and c.relrowsecurity
  ) then raise exception 'Financial operations must have RLS enabled'; end if;

  if has_table_privilege('anon', 'public.financial_operations', 'SELECT')
     or has_table_privilege('authenticated', 'public.financial_operations', 'INSERT')
     or has_table_privilege('authenticated', 'public.external_movements', 'UPDATE')
     or has_table_privilege('tucambio_backend', 'public.financial_operations', 'SELECT')
     or has_table_privilege('tucambio_backend', 'public.financial_operations', 'INSERT') then
    raise exception 'Financial domain tables expose direct privileges';
  end if;

  if (select count(*) from public.tenant_currencies where tenant_id = '62000000-0000-0000-0000-000000000001') <> 3 then
    raise exception 'Tenant currency catalogue not persisted';
  end if;

  begin
    insert into public.financial_operations (
      tenant_id, pair_id, source_currency_code, target_currency_code,
      requested_amount, created_by_membership_id, created_by_user_id
    ) values (
      '62000000-0000-0000-0000-000000000001',
      '64000000-0000-0000-0000-000000000001',
      'USD', 'EUR', 10,
      '63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001'
    );
    raise exception 'Operation with mismatched pair unexpectedly accepted';
  exception when check_violation then null;
  end;

  begin
    insert into public.tenant_currency_pairs (tenant_id, base_currency_code, quote_currency_code)
    values ('62000000-0000-0000-0000-000000000001', 'USD', 'USD');
    raise exception 'Self-referential currency pair unexpectedly accepted';
  exception when check_violation then null;
  end;

  begin
    insert into public.tenant_currency_pairs (tenant_id, base_currency_code, quote_currency_code)
    values ('62000000-0000-0000-0000-000000000001', 'USD', 'EUR');
    raise exception 'Pair with unconfigured tenant currency unexpectedly accepted';
  exception when foreign_key_violation then null;
  end;
end;
$$;

insert into public.currency_rates (
  id, tenant_id, pair_id, buy_rate, sell_rate, valid_from, valid_until,
  created_by_membership_id, created_by_user_id
) values (
  '65000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001',
  '64000000-0000-0000-0000-000000000001',
  6.90, 6.95, '2026-11-01T10:00:00Z', '2026-11-01T11:00:00Z',
  '63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001'
);

insert into public.currency_rates (
  id, tenant_id, pair_id, buy_rate, sell_rate, valid_from, valid_until,
  created_by_membership_id, created_by_user_id
) values (
  '65000000-0000-0000-0000-000000000002',
  '62000000-0000-0000-0000-000000000001',
  '64000000-0000-0000-0000-000000000001',
  6.91, 6.96, '2026-11-01T11:00:00Z', null,
  '63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001'
);

do $$
begin
  if (select count(*) from public.currency_rates
      where tenant_id = '62000000-0000-0000-0000-000000000001'
        and tstzrange(valid_from, valid_until, '[)') @> '2026-11-01T11:00:00Z'::timestamptz) <> 1 then
    raise exception 'Half-open rate boundary must select exactly one rate';
  end if;

  begin
    insert into public.currency_rates (
      tenant_id, pair_id, buy_rate, sell_rate, valid_from, valid_until,
      created_by_membership_id, created_by_user_id
    ) values (
      '62000000-0000-0000-0000-000000000001',
      '64000000-0000-0000-0000-000000000001',
      7, 7, '2026-11-01T10:30:00Z', '2026-11-01T11:30:00Z',
      '63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001'
    );
    raise exception 'Overlapping rate interval unexpectedly accepted';
  exception when exclusion_violation then null;
  end;

  begin
    update public.currency_rates set buy_rate = 8
    where id = '65000000-0000-0000-0000-000000000001';
    raise exception 'Rate values unexpectedly mutable';
  exception when object_not_in_prerequisite_state then null;
  end;

  begin
    delete from public.currency_rates where id = '65000000-0000-0000-0000-000000000001';
    raise exception 'Rate history unexpectedly deletable';
  exception when object_not_in_prerequisite_state then null;
  end;
end;
$$;

insert into public.financial_operations (
  id, tenant_id, pair_id, source_currency_code, target_currency_code,
  requested_amount, created_by_membership_id, created_by_user_id
) values (
  '66000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001',
  '64000000-0000-0000-0000-000000000001',
  'USD', 'BOB', 100,
  '63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001'
);

update public.financial_operations
set source_effective_at = '2026-11-01T10:45:00Z',
    applied_rate_id = '65000000-0000-0000-0000-000000000001',
    applied_rate = 6.90
where id = '66000000-0000-0000-0000-000000000001';

do $
begin
  begin
    update public.financial_operations set applied_rate = 6.91
    where id = '66000000-0000-0000-0000-000000000001';
    raise exception 'Applied operation rate was unexpectedly mutable';
  exception when object_not_in_prerequisite_state then null;
  end;
end;
$;

insert into public.external_movements (
  id, tenant_id, currency_code, amount, effective_at,
  created_by_membership_id, created_by_user_id
) values (
  '67000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001',
  'USD', 100, '2026-11-01T10:45:00Z',
  '63000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001'
);

insert into public.operation_movements (
  tenant_id, operation_id, movement_id, movement_role,
  associated_by_membership_id, associated_by_user_id
) values (
  '62000000-0000-0000-0000-000000000001',
  '66000000-0000-0000-0000-000000000001',
  '67000000-0000-0000-0000-000000000001',
  'ORIGIN',
  '63000000-0000-0000-0000-000000000001',
  '61000000-0000-0000-0000-000000000001'
);

do $$
begin
  if (select count(*) from public.external_movements where id = '67000000-0000-0000-0000-000000000001') <> 1 then
    raise exception 'Movement may not exist independently of an association';
  end if;

  update public.external_movements set status = 'CONFIRMED'
  where id = '67000000-0000-0000-0000-000000000001';

  begin
    update public.external_movements set amount = 101
    where id = '67000000-0000-0000-0000-000000000001';
    raise exception 'Confirmed movement was unexpectedly mutable';
  exception when object_not_in_prerequisite_state then null;
  end;

  begin
    delete from public.external_movements where id = '67000000-0000-0000-0000-000000000001';
    raise exception 'External movement history was unexpectedly deletable';
  exception when object_not_in_prerequisite_state then null;
  end;
  begin
    insert into public.operation_movements (
      tenant_id, operation_id, movement_id, movement_role,
      associated_by_membership_id, associated_by_user_id
    ) values (
      '62000000-0000-0000-0000-000000000001',
      '66000000-0000-0000-0000-000000000001',
      '67000000-0000-0000-0000-000000000001',
      'DESTINATION',
      '63000000-0000-0000-0000-000000000001',
      '61000000-0000-0000-0000-000000000001'
    );
    raise exception 'A movement was associated twice';
  exception when unique_violation then null;
  end;
end;
$$;

rollback;
