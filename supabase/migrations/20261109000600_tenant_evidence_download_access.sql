-- Backend-only lookup for issuing short-lived download URLs after authorization.
begin;

create or replace function public.get_tenant_evidence_for_download(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_evidence_id uuid
)
returns table (
  evidence_id uuid,
  bucket_id text,
  object_path text,
  mime_type text,
  expected_size_bytes bigint,
  sha256 bytea
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select e.id, e.bucket_id, e.object_path, e.mime_type, e.expected_size_bytes, e.sha256
  from public.tenant_evidence e
  join public.tenants t on t.id = e.tenant_id and t.status = 'active'
  join public.tenant_memberships m
    on m.tenant_id = t.id and m.user_id = p_actor_user_id and m.status = 'active'
  join public.membership_roles mr
    on mr.tenant_id = m.tenant_id and mr.membership_id = m.id
  join public.tenant_role_capabilities trc
    on trc.tenant_id = mr.tenant_id and trc.role_id = mr.role_id
  where e.tenant_id = p_tenant_id
    and e.id = p_evidence_id
    and e.status = 'available'
    and trc.capability_code in (
      'operations.operate',
      'movements.verify',
      'operations.settle',
      'tenant.administer'
    )
  limit 1;
$$;

revoke all on function public.get_tenant_evidence_for_download(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.get_tenant_evidence_for_download(uuid, uuid, uuid)
  to tucambio_backend;

create or replace function public.get_pending_tenant_evidence_for_upload(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_evidence_id uuid
)
returns table (
  evidence_id uuid,
  bucket_id text,
  object_path text,
  mime_type text,
  expected_size_bytes bigint
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select e.id, e.bucket_id, e.object_path, e.mime_type, e.expected_size_bytes
  from public.tenant_evidence e
  join public.tenants t on t.id = e.tenant_id and t.status = 'active'
  join public.tenant_memberships m
    on m.tenant_id = t.id
   and m.user_id = p_actor_user_id
   and m.status = 'active'
  join public.membership_roles mr
    on mr.tenant_id = m.tenant_id and mr.membership_id = m.id
  join public.tenant_role_capabilities trc
    on trc.tenant_id = mr.tenant_id and trc.role_id = mr.role_id
  where e.tenant_id = p_tenant_id
    and e.id = p_evidence_id
    and e.created_by_user_id = p_actor_user_id
    and e.status = 'pending'
    and trc.capability_code = 'operations.operate'
  limit 1;
$$;

revoke all on function public.get_pending_tenant_evidence_for_upload(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.get_pending_tenant_evidence_for_upload(uuid, uuid, uuid)
  to tucambio_backend;

comment on function public.get_pending_tenant_evidence_for_upload(uuid, uuid, uuid) is
  'Backend-only lookup for verifying a pending upload created by the authenticated actor.';

comment on function public.get_tenant_evidence_for_download(uuid, uuid, uuid) is
  'Backend-only authorization gate for issuing short-lived download URLs to active tenant members with an evidence-reading capability.';

commit;
