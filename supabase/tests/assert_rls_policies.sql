-- Negative and positive RLS assertions for tenant-scoped authenticated reads.
begin;

insert into auth.users (id, email) values
  ('51000000-0000-0000-0000-000000000001', 'admin-a@example.test'),
  ('51000000-0000-0000-0000-000000000002', 'member-b@example.test'),
  ('51000000-0000-0000-0000-000000000003', 'member-a@example.test');

insert into public.profiles (user_id, display_name) values
  ('51000000-0000-0000-0000-000000000001', 'Admin A'),
  ('51000000-0000-0000-0000-000000000002', 'Member B'),
  ('51000000-0000-0000-0000-000000000003', 'Member A');

insert into public.tenants (id, name, slug, created_by_user_id) values
  ('52000000-0000-0000-0000-000000000001', 'Tenant A', 'rls-tenant-a', '51000000-0000-0000-0000-000000000001'),
  ('52000000-0000-0000-0000-000000000002', 'Tenant B', 'rls-tenant-b', '51000000-0000-0000-0000-000000000002');

insert into public.tenant_memberships (id, tenant_id, user_id) values
  ('53000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001'),
  ('53000000-0000-0000-0000-000000000002', '52000000-0000-0000-0000-000000000002', '51000000-0000-0000-0000-000000000002'),
  ('53000000-0000-0000-0000-000000000003', '52000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000003');

insert into public.tenant_roles (id, tenant_id, code, name) values
  ('54000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000001', 'administrator', 'Administrator A'),
  ('54000000-0000-0000-0000-000000000002', '52000000-0000-0000-0000-000000000002', 'operator', 'Operator B'),
  ('54000000-0000-0000-0000-000000000003', '52000000-0000-0000-0000-000000000001', 'operator', 'Operator A');

insert into public.tenant_role_capabilities (tenant_id, role_id, capability_code) values
  ('52000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000001', 'tenant.administer'),
  ('52000000-0000-0000-0000-000000000002', '54000000-0000-0000-0000-000000000002', 'operations.operate'),
  ('52000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000003', 'operations.operate');

insert into public.membership_roles (tenant_id, membership_id, role_id) values
  ('52000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000001'),
  ('52000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000002', '54000000-0000-0000-0000-000000000002'),
  ('52000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000003', '54000000-0000-0000-0000-000000000003');

insert into public.tenant_invitations (
  id, tenant_id, email_normalized, token_hash, invited_by_membership_id, expires_at
) values (
  '55000000-0000-0000-0000-000000000001',
  '52000000-0000-0000-0000-000000000001',
  'invite@example.test',
  decode(repeat('ab', 32), 'hex'),
  '53000000-0000-0000-0000-000000000001',
  now() + interval '1 day'
);

insert into public.tenant_invitation_roles (tenant_id, invitation_id, role_id) values
  ('52000000-0000-0000-0000-000000000001', '55000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000003');

insert into public.tenant_security_audit_events (
  tenant_id, actor_user_id, actor_membership_id, action_code, subject_type
) values (
  '52000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000001',
  '53000000-0000-0000-0000-000000000001',
  'member.invited',
  'tenant_invitation'
);

do $$
begin
  if has_table_privilege('anon', 'public.tenants', 'SELECT')
     or has_table_privilege('authenticated', 'public.tenants', 'INSERT')
     or has_table_privilege('authenticated', 'public.tenants', 'UPDATE')
     or has_table_privilege('authenticated', 'public.tenants', 'DELETE')
     or has_table_privilege('authenticated', 'public.tenants', 'TRUNCATE') then
    raise exception 'Client grants exceed authenticated read-only access';
  end if;
end;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000001', true);

do $$
begin
  if (select count(*) from public.profiles) <> 1 then
    raise exception 'Profile policy exposed another user profile';
  end if;
  if (select count(*) from public.tenants) <> 1 then
    raise exception 'Tenant A administrator can see unexpected tenant rows';
  end if;
  if (select count(*) from public.tenant_memberships) <> 2 then
    raise exception 'Tenant member roster is not scoped to Tenant A';
  end if;
  if (select count(*) from public.tenant_invitations) <> 1
     or (select count(*) from public.tenant_invitation_roles) <> 1
     or (select count(*) from public.tenant_security_audit_events) <> 1 then
    raise exception 'Tenant administrator cannot read tenant administration records';
  end if;
  if (select count(*) from public.capabilities
      where code in (
        'operations.operate', 'movements.verify', 'operations.settle',
        'rates.manage', 'settings.manage', 'tenant.administer'
      )) <> 6
     or not exists (select 1 from public.capabilities where code = 'financial.read') then
    raise exception 'Authenticated capability catalog should expose all canonical capabilities';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000002', true);

do $$
begin
  if (select count(*) from public.profiles) <> 1
     or exists (select 1 from public.profiles where user_id <> auth.uid()) then
    raise exception 'Profile policy leaked a different user profile';
  end if;
  if (select count(*) from public.tenants) <> 1
     or exists (select 1 from public.tenants where id <> '52000000-0000-0000-0000-000000000002') then
    raise exception 'Cross-tenant data is visible to Tenant B member';
  end if;
  if (select count(*) from public.tenant_memberships) <> 1
     or exists (select 1 from public.tenant_memberships where tenant_id <> '52000000-0000-0000-0000-000000000002') then
    raise exception 'Cross-tenant membership rows are visible';
  end if;
  if (select count(*) from public.tenant_invitations) <> 0
     or (select count(*) from public.tenant_invitation_roles) <> 0
     or (select count(*) from public.tenant_security_audit_events) <> 0 then
    raise exception 'Tenant B member can read Tenant A administrative records';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000003', true);

do $$
begin
  if (select count(*) from public.tenants) <> 1 then
    raise exception 'Ordinary Tenant A member cannot read its tenant';
  end if;
  if (select count(*) from public.tenant_invitations) <> 0
     or (select count(*) from public.tenant_invitation_roles) <> 0
     or (select count(*) from public.tenant_security_audit_events) <> 0 then
    raise exception 'Non-admin member can read tenant administration records';
  end if;
end;
$$;

reset role;
rollback;
