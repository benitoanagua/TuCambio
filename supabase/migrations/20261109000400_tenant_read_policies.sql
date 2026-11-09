-- TuCambio M1.5: authenticated read policies with tenant isolation.
-- Client roles receive SELECT only. All writes remain server-side through Ktor.
begin;

create or replace function public.is_tenant_member(p_tenant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
  select exists (
    select 1
    from public.tenants t
    join public.tenant_memberships m on m.tenant_id = t.id
    where t.id = p_tenant_id
      and t.status = 'active'
      and m.user_id = auth.uid()
      and m.status = 'active'
  );
$$;

create or replace function public.has_tenant_capability(
  p_tenant_id uuid,
  p_capability_code text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
  select exists (
    select 1
    from public.tenants t
    join public.tenant_memberships m
      on m.tenant_id = t.id
    join public.membership_roles mr
      on mr.tenant_id = m.tenant_id
     and mr.membership_id = m.id
    join public.tenant_role_capabilities trc
      on trc.tenant_id = mr.tenant_id
     and trc.role_id = mr.role_id
    where t.id = p_tenant_id
      and t.status = 'active'
      and m.user_id = auth.uid()
      and m.status = 'active'
      and trc.capability_code = p_capability_code
  );
$$;

revoke all on function public.is_tenant_member(uuid) from public, anon, authenticated;
revoke all on function public.has_tenant_capability(uuid, text) from public, anon, authenticated;
grant usage on schema auth to authenticated;
grant execute on function public.is_tenant_member(uuid) to authenticated;
grant execute on function public.has_tenant_capability(uuid, text) to authenticated;

-- No anonymous access and no client-side mutations.
revoke all on table
  public.profiles,
  public.tenants,
  public.tenant_memberships,
  public.capabilities,
  public.tenant_roles,
  public.tenant_role_capabilities,
  public.membership_roles,
  public.tenant_invitations,
  public.tenant_invitation_roles,
  public.tenant_security_audit_events
from anon, authenticated;

grant select on table
  public.profiles,
  public.tenants,
  public.tenant_memberships,
  public.capabilities,
  public.tenant_roles,
  public.tenant_role_capabilities,
  public.membership_roles,
  public.tenant_invitations,
  public.tenant_invitation_roles,
  public.tenant_security_audit_events
to authenticated;

create policy profiles_select_self
  on public.profiles for select to authenticated
  using (user_id = auth.uid());

create policy tenants_select_membership
  on public.tenants for select to authenticated
  using (public.is_tenant_member(id));

create policy tenant_memberships_select_same_tenant
  on public.tenant_memberships for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy capabilities_select_authenticated
  on public.capabilities for select to authenticated
  using (true);

create policy tenant_roles_select_members
  on public.tenant_roles for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy tenant_role_capabilities_select_members
  on public.tenant_role_capabilities for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy membership_roles_select_members
  on public.membership_roles for select to authenticated
  using (public.is_tenant_member(tenant_id));

create policy tenant_invitations_select_admins
  on public.tenant_invitations for select to authenticated
  using (public.has_tenant_capability(tenant_id, 'tenant.administer'));

create policy tenant_invitation_roles_select_admins
  on public.tenant_invitation_roles for select to authenticated
  using (public.has_tenant_capability(tenant_id, 'tenant.administer'));

create policy tenant_security_audit_events_select_admins
  on public.tenant_security_audit_events for select to authenticated
  using (public.has_tenant_capability(tenant_id, 'tenant.administer'));

comment on function public.is_tenant_member(uuid) is
  'RLS helper: true only for the current authenticated user with an active membership in an active tenant.';
comment on function public.has_tenant_capability(uuid, text) is
  'RLS helper: checks current authenticated user capability through active tenant membership and assigned roles.';

commit;
