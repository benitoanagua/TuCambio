-- TuCambio M1.6: tenant-scoped evidence metadata and private Storage access.
-- Clients may upload only to a backend-created pending object path. Ktor must
-- validate the downloaded bytes and SHA-256 before finalizing the evidence.
begin;

create table public.tenant_evidence (
  id uuid primary key,
  tenant_id uuid not null,
  created_by_user_id uuid not null,
  bucket_id text not null default 'operation-evidence',
  object_path text not null,
  mime_type text not null,
  expected_size_bytes bigint not null,
  sha256 bytea,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  uploaded_at timestamptz,
  verified_at timestamptz,
  constraint tenant_evidence_bucket check (bucket_id = 'operation-evidence'),
  constraint tenant_evidence_path check (object_path = tenant_id::text || '/' || id::text),
  constraint tenant_evidence_mime check (
    mime_type in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')
  ),
  constraint tenant_evidence_size check (expected_size_bytes between 1 and 10485760),
  constraint tenant_evidence_sha256 check (sha256 is null or octet_length(sha256) = 32),
  constraint tenant_evidence_status check (status in ('pending', 'available', 'rejected')),
  constraint tenant_evidence_lifecycle check (
    (status = 'pending' and uploaded_at is null and verified_at is null and sha256 is null)
    or (status = 'available' and uploaded_at is not null and verified_at is not null and sha256 is not null)
    or (status = 'rejected' and verified_at is not null)
  ),
  constraint tenant_evidence_tenant_id_unique unique (tenant_id, id),
  constraint tenant_evidence_object_unique unique (bucket_id, object_path),
  constraint tenant_evidence_creator_membership_fk
    foreign key (tenant_id, created_by_user_id)
    references public.tenant_memberships(tenant_id, user_id) on delete restrict
);

create index tenant_evidence_tenant_created_idx
  on public.tenant_evidence (tenant_id, created_at desc);
create index tenant_evidence_creator_idx
  on public.tenant_evidence (tenant_id, created_by_user_id, created_at desc);

alter table public.tenant_evidence enable row level security;
revoke all on table public.tenant_evidence from public, anon, authenticated;
grant select on table public.tenant_evidence to authenticated;

create policy tenant_evidence_select_authorized_members
  on public.tenant_evidence for select to authenticated
  using (
    public.has_tenant_capability(tenant_id, 'operations.operate')
    or public.has_tenant_capability(tenant_id, 'movements.verify')
    or public.has_tenant_capability(tenant_id, 'operations.settle')
    or public.has_tenant_capability(tenant_id, 'tenant.administer')
  );

-- Only the backend role can create pending metadata and finalize an upload.
-- The actor ID is supplied by Ktor only after JWT validation; this role has
-- no direct table grants and no BYPASSRLS.
create or replace function public.create_tenant_evidence(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_evidence_id uuid,
  p_mime_type text,
  p_expected_size_bytes bigint
)
returns table (evidence_id uuid, bucket_id text, object_path text, status text)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if p_mime_type is null
     or p_mime_type not in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')
     or p_expected_size_bytes is null
     or p_expected_size_bytes not between 1 and 10485760 then
    raise exception 'Evidence content type or size is not allowed'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.tenants t
    join public.tenant_memberships m on m.tenant_id = t.id
    join public.membership_roles mr
      on mr.tenant_id = m.tenant_id and mr.membership_id = m.id
    join public.tenant_role_capabilities trc
      on trc.tenant_id = mr.tenant_id and trc.role_id = mr.role_id
    where t.id = p_tenant_id
      and t.status = 'active'
      and m.user_id = p_actor_user_id
      and m.status = 'active'
      and trc.capability_code = 'operations.operate'
  ) then
    raise exception 'Tenant evidence creation is not authorized'
      using errcode = '42501';
  end if;

  insert into public.tenant_evidence as e (
    id, tenant_id, created_by_user_id, object_path, mime_type, expected_size_bytes
  )
  values (
    p_evidence_id, p_tenant_id, p_actor_user_id,
    p_tenant_id::text || '/' || p_evidence_id::text,
    p_mime_type, p_expected_size_bytes
  );

  return query
    select e.id, e.bucket_id, e.object_path, e.status
    from public.tenant_evidence e
    where e.id = p_evidence_id and e.tenant_id = p_tenant_id;
end;
$$;

create or replace function public.complete_tenant_evidence(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_evidence_id uuid,
  p_sha256 bytea
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  updated_count integer;
begin
  if p_sha256 is null or octet_length(p_sha256) <> 32 then
    raise exception 'Evidence SHA-256 must contain exactly 32 bytes'
      using errcode = '22023';
  end if;

  update public.tenant_evidence e
     set status = 'available',
         sha256 = p_sha256,
         uploaded_at = now(),
         verified_at = now()
   where e.id = p_evidence_id
     and e.tenant_id = p_tenant_id
     and e.created_by_user_id = p_actor_user_id
     and e.status = 'pending'
     and exists (
       select 1
       from public.tenants t
       join public.tenant_memberships m on m.tenant_id = t.id
       join public.membership_roles mr
         on mr.tenant_id = m.tenant_id and mr.membership_id = m.id
       join public.tenant_role_capabilities trc
         on trc.tenant_id = mr.tenant_id and trc.role_id = mr.role_id
       where t.id = e.tenant_id
         and t.status = 'active'
         and m.user_id = p_actor_user_id
         and m.status = 'active'
         and trc.capability_code = 'operations.operate'
     )
     and exists (
       select 1
       from storage.objects o
       where o.bucket_id = e.bucket_id
         and o.name = e.object_path
         and o.metadata ->> 'mimetype' = e.mime_type
         and case
           when (o.metadata ->> 'size') ~ '^[0-9]+$'
             then (o.metadata ->> 'size')::bigint = e.expected_size_bytes
           else false
         end
     );

  get diagnostics updated_count = row_count;
  return updated_count = 1;
end;
$$;

revoke all on function public.create_tenant_evidence(uuid, uuid, uuid, text, bigint)
  from public, anon, authenticated;
revoke all on function public.complete_tenant_evidence(uuid, uuid, uuid, bytea)
  from public, anon, authenticated;
grant usage on schema public to tucambio_backend;
grant execute on function public.create_tenant_evidence(uuid, uuid, uuid, text, bigint)
  to tucambio_backend;
grant execute on function public.complete_tenant_evidence(uuid, uuid, uuid, bytea)
  to tucambio_backend;

-- Storage API access is restricted to the one private bucket and to object
-- paths backed by pending/available metadata for an active tenant membership.
alter table storage.objects enable row level security;
revoke all on table storage.objects from public, anon, authenticated;
grant usage on schema storage to authenticated;
grant select, insert on table storage.objects to authenticated;

create policy operation_evidence_upload_pending_only
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'operation-evidence'
    and exists (
      select 1
      from public.tenant_evidence e
      where e.bucket_id = storage.objects.bucket_id
        and e.object_path = storage.objects.name
        and e.status = 'pending'
        and e.created_by_user_id = auth.uid()
        and public.has_tenant_capability(e.tenant_id, 'operations.operate')
        and storage.objects.metadata ->> 'mimetype' = e.mime_type
        and case
          when (storage.objects.metadata ->> 'size') ~ '^[0-9]+$'
            then (storage.objects.metadata ->> 'size')::bigint = e.expected_size_bytes
          else false
        end
    )
  );

create policy operation_evidence_read_verified_only
  on storage.objects for select to authenticated
  using (
    bucket_id = 'operation-evidence'
    and exists (
      select 1
      from public.tenant_evidence e
      where e.bucket_id = storage.objects.bucket_id
        and e.object_path = storage.objects.name
        and e.status = 'available'
        and (
          public.has_tenant_capability(e.tenant_id, 'operations.operate')
          or public.has_tenant_capability(e.tenant_id, 'movements.verify')
          or public.has_tenant_capability(e.tenant_id, 'operations.settle')
          or public.has_tenant_capability(e.tenant_id, 'tenant.administer')
        )
    )
  );

comment on table public.tenant_evidence is
  'Private evidence metadata. Object paths are tenant/evidence UUID pairs; upload lifecycle is controlled by backend functions.';
comment on function public.create_tenant_evidence(uuid, uuid, uuid, text, bigint) is
  'Backend-only: creates a pending evidence record after checking active membership and operations.operate.';
comment on function public.complete_tenant_evidence(uuid, uuid, uuid, bytea) is
  'Backend-only: marks evidence available only when the matching Storage object and declared size/type exist; Ktor must independently verify bytes and SHA-256.';

commit;
