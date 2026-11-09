-- Structural and tenant-isolation assertions for M1.1.
do $$
declare
  table_name text;
  expected_tables text[] := array[
    'profiles',
    'tenants',
    'tenant_memberships',
    'capabilities',
    'tenant_roles',
    'tenant_role_capabilities',
    'membership_roles',
    'tenant_invitations',
    'tenant_invitation_roles',
    'tenant_security_audit_events'
  ];
begin
  if (select count(*) from public.capabilities) <> 6 then
    raise exception 'Expected six canonical business capabilities';
  end if;

  foreach table_name in array expected_tables loop
    if not exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = table_name
        and c.relrowsecurity
    ) then
      raise exception 'RLS is not enabled on public.%', table_name;
    end if;

    if has_table_privilege('anon', format('public.%I', table_name), 'SELECT')
       or has_table_privilege('authenticated', format('public.%I', table_name), 'SELECT')
       or has_table_privilege('anon', format('public.%I', table_name), 'INSERT')
       or has_table_privilege('authenticated', format('public.%I', table_name), 'INSERT') then
      raise exception 'Unexpected client table privilege on public.%', table_name;
    end if;
  end loop;
end;
$$;

begin;

insert into auth.users (id, email) values
  ('10000000-0000-0000-0000-000000000001', 'owner-a@example.test');

insert into public.tenants (id, name, slug, created_by_user_id) values
  ('20000000-0000-0000-0000-000000000001', 'Tenant A', 'tenant-a', '10000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002', 'Tenant B', 'tenant-b', '10000000-0000-0000-0000-000000000001');

insert into public.tenant_memberships (id, tenant_id, user_id) values
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001');

insert into public.tenant_roles (id, tenant_id, code, name) values
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'operator', 'Operator A'),
  ('40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'operator', 'Operator B');

do $$
begin
  begin
    insert into public.membership_roles (tenant_id, membership_id, role_id)
    values (
      '20000000-0000-0000-0000-000000000001',
      '30000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000002'
    );
    raise exception 'Cross-tenant role assignment unexpectedly succeeded';
  exception
    when foreign_key_violation then
      null; -- Expected: role belongs to Tenant B, membership to Tenant A.
  end;
end;
$$;

rollback;
