-- TuCambio M1.3: server-only, fail-closed tenant access resolution.
-- The API connects with a dedicated login role that is a member of
-- tucambio_backend. The role receives EXECUTE on this narrow function only;
-- it receives no direct table privileges and no BYPASSRLS attribute.

begin;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'tucambio_backend') then
    create role tucambio_backend nologin;
  end if;
end;
$$;

create or replace function public.resolve_tenant_access(
  p_actor_user_id uuid,
  p_tenant_id uuid
)
returns table (
  membership_id uuid,
  capability_code text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select distinct
    m.id as membership_id,
    trc.capability_code
  from public.tenants t
  join public.tenant_memberships m
    on m.tenant_id = t.id
  left join public.membership_roles mr
    on mr.tenant_id = m.tenant_id
   and mr.membership_id = m.id
  left join public.tenant_role_capabilities trc
    on trc.tenant_id = mr.tenant_id
   and trc.role_id = mr.role_id
  where t.id = p_tenant_id
    and t.status = 'active'
    and m.user_id = p_actor_user_id
    and m.status = 'active';
$$;

revoke all on function public.resolve_tenant_access(uuid, uuid)
  from public, anon, authenticated;
grant usage on schema public to tucambio_backend;
grant execute on function public.resolve_tenant_access(uuid, uuid)
  to tucambio_backend;

commit;
