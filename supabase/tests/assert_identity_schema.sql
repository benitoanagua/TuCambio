-- Structural and tenant-isolation assertions for M1.1 and M1.3.
do $$
declare
  table_name text;
  expected_tables text[] := array[
    'profiles', 'tenants', 'tenant_memberships', 'capabilities',
    'tenant_roles', 'tenant_role_capabilities', 'membership_roles',
    'tenant_invitations', 'tenant_invitation_roles', 'tenant_security_audit_events'
  ];
begin
  if (select count(*) from public.capabilities
      where code in (
        'operations.operate', 'movements.verify', 'operations.settle',
        'rates.manage', 'settings.manage', 'tenant.administer'
      )) <> 6 then
    raise exception 'Expected all six canonical business capabilities';
  end if;

  if not exists (select 1 from public.capabilities where code = 'financial.read') then
    raise exception 'Expected the financial.read capability to be registered';
  end if;

  foreach table_name in array expected_tables loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = table_name and c.relrowsecurity
    ) then
      raise exception 'RLS is not enabled on public.%', table_name;
    end if;
    if has_table_privilege('anon', format('public.%I', table_name), 'SELECT')
       or not has_table_privilege('authenticated', format('public.%I', table_name), 'SELECT')
       or has_table_privilege('anon', format('public.%I', table_name), 'INSERT')
       or has_table_privilege('authenticated', format('public.%I', table_name), 'INSERT')
       or has_table_privilege('authenticated', format('public.%I', table_name), 'UPDATE')
       or has_table_privilege('authenticated', format('public.%I', table_name), 'DELETE')
       or has_table_privilege('authenticated', format('public.%I', table_name), 'TRUNCATE') then
      raise exception 'Unexpected client table privilege on public.%', table_name;
    end if;
  end loop;

  if not has_function_privilege('tucambio_backend', 'public.resolve_tenant_access(uuid,uuid)', 'EXECUTE') then
    raise exception 'Backend role cannot execute tenant resolver';
  end if;
  if has_function_privilege('anon', 'public.resolve_tenant_access(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.resolve_tenant_access(uuid,uuid)', 'EXECUTE') then
    raise exception 'Client roles can execute tenant resolver';
  end if;
  if not has_function_privilege('authenticated', 'public.is_tenant_member(uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.has_tenant_capability(uuid,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.is_tenant_member(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.has_tenant_capability(uuid,text)', 'EXECUTE') then
    raise exception 'RLS helper function grants are incorrect';
  end if;
  if (select rolbypassrls from pg_roles where rolname = 'tucambio_backend') then
    raise exception 'Backend group role must not bypass RLS';
  end if;
end;
$$;

begin;

insert into auth.users (id, email) values
  ('10000000-0000-0000-0000-000000000001', 'owner-a@example.test'),
  ('10000000-0000-0000-0000-000000000002', 'member-b@example.test');

insert into public.tenants (id, name, slug, created_by_user_id) values
  ('20000000-0000-0000-0000-000000000001', 'Tenant A', 'tenant-a', '10000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002', 'Tenant B', 'tenant-b', '10000000-0000-0000-0000-000000000001');

insert into public.tenant_memberships (id, tenant_id, user_id) values
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001'),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002');

insert into public.tenant_roles (id, tenant_id, code, name) values
  ('40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'operator', 'Operator A'),
  ('40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'operator', 'Operator B');

do $fk$
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
      null;
  end;
end;
$fk$;

insert into public.tenant_role_capabilities (tenant_id, role_id, capability_code) values
  ('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 'operations.operate'),
  ('20000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000002', 'rates.manage');

insert into public.membership_roles (tenant_id, membership_id, role_id) values
  ('20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001');

do $$
declare
  resolved_membership uuid;
  resolved_capability text;
begin
  select membership_id, capability_code into resolved_membership, resolved_capability
  from public.resolve_tenant_access(
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001'
  );
  if resolved_membership <> '30000000-0000-0000-0000-000000000001'
     or resolved_capability <> 'operations.operate' then
    raise exception 'Active tenant membership/capability was not resolved';
  end if;

  if exists (select 1 from public.resolve_tenant_access(
      '10000000-0000-0000-0000-000000000002',
      '20000000-0000-0000-0000-000000000001')) then
    raise exception 'Cross-user tenant access unexpectedly resolved';
  end if;

  if exists (select 1 from public.resolve_tenant_access(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000002')) then
    raise exception 'Cross-tenant membership unexpectedly resolved';
  end if;

  update public.tenant_memberships set status = 'suspended'
  where id = '30000000-0000-0000-0000-000000000001';
  if exists (select 1 from public.resolve_tenant_access(
      '10000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000001')) then
    raise exception 'Suspended membership unexpectedly resolved';
  end if;
end;
$$;

rollback;
