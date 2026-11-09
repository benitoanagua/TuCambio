-- Tenant-scoped evidence metadata and Storage RLS assertions.
begin;

-- Each assertion file runs in its own transaction/database session.
insert into auth.users (id, email) values
  ('51000000-0000-0000-0000-000000000001', 'admin-a@example.test'),
  ('51000000-0000-0000-0000-000000000002', 'member-b@example.test'),
  ('51000000-0000-0000-0000-000000000003', 'member-a@example.test');

insert into public.tenants (id, name, slug, created_by_user_id) values
  ('52000000-0000-0000-0000-000000000001', 'Tenant A', 'storage-tenant-a', '51000000-0000-0000-0000-000000000001'),
  ('52000000-0000-0000-0000-000000000002', 'Tenant B', 'storage-tenant-b', '51000000-0000-0000-0000-000000000002');

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

do $$
begin
  if has_table_privilege('anon', 'public.tenant_evidence', 'SELECT')
     or has_table_privilege('authenticated', 'public.tenant_evidence', 'INSERT')
     or has_table_privilege('authenticated', 'public.tenant_evidence', 'UPDATE')
     or has_table_privilege('authenticated', 'public.tenant_evidence', 'DELETE')
     or has_table_privilege('authenticated', 'storage.objects', 'UPDATE')
     or has_table_privilege('authenticated', 'storage.objects', 'DELETE')
     or has_table_privilege('anon', 'storage.objects', 'SELECT')
     or has_table_privilege('anon', 'storage.objects', 'INSERT')
     or has_function_privilege('authenticated',
       'public.create_tenant_evidence(uuid,uuid,uuid,text,bigint)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.complete_tenant_evidence(uuid,uuid,uuid,bytea)', 'EXECUTE')
     or has_function_privilege('authenticated',
       'public.get_tenant_evidence_for_download(uuid,uuid,uuid)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.get_pending_tenant_evidence_for_upload(uuid,uuid,uuid)', 'EXECUTE') then
    raise exception 'Evidence grants are broader than the reviewed contract';
  end if;
  if not has_function_privilege('tucambio_backend',
       'public.create_tenant_evidence(uuid,uuid,uuid,text,bigint)', 'EXECUTE')
     or not has_function_privilege('tucambio_backend',
       'public.complete_tenant_evidence(uuid,uuid,uuid,bytea)', 'EXECUTE')
     or not has_function_privilege('tucambio_backend',
       'public.get_tenant_evidence_for_download(uuid,uuid,uuid)', 'EXECUTE')
     or not has_function_privilege('tucambio_backend',
       'public.get_pending_tenant_evidence_for_upload(uuid,uuid,uuid)', 'EXECUTE') then
    raise exception 'Backend role cannot execute evidence lifecycle functions';
  end if;
end;
$$;

-- Backend creates pending metadata only for an active operator with capability.
set role tucambio_backend;
select * from public.create_tenant_evidence(
  '51000000-0000-0000-0000-000000000003',
  '52000000-0000-0000-0000-000000000001',
  '56000000-0000-0000-0000-000000000001',
  'image/png',
  2048
);
select * from public.create_tenant_evidence(
  '51000000-0000-0000-0000-000000000003',
  '52000000-0000-0000-0000-000000000001',
  '56000000-0000-0000-0000-000000000002',
  'application/pdf',
  4096
);

do $$
begin
  begin
    perform * from public.create_tenant_evidence(
      '51000000-0000-0000-0000-000000000002',
      '52000000-0000-0000-0000-000000000001',
      '56000000-0000-0000-0000-000000000003',
      'image/png',
      1024
    );
    raise exception 'Cross-tenant evidence creation unexpectedly succeeded';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

-- Tenant A operator can upload only the exact pending path with matching
-- declared content type and size.
set role authenticated;
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000003', true);

insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
  'operation-evidence',
  '52000000-0000-0000-0000-000000000001/56000000-0000-0000-0000-000000000001',
  auth.uid()::text,
  '{"mimetype":"image/png","size":2048}'::jsonb
);

do $$
begin
  if (select count(*) from storage.objects) <> 0 then
    raise exception 'Pending evidence object is readable before backend verification';
  end if;
end;
$$;

do $$
begin
  begin
    insert into storage.objects (bucket_id, name, owner_id, metadata)
    values (
      'operation-evidence',
      '52000000-0000-0000-0000-000000000001/56000000-0000-0000-0000-000000000002',
      auth.uid()::text,
      '{"mimetype":"application/pdf","size":4095}'::jsonb
    );
    raise exception 'Mismatched evidence size unexpectedly uploaded';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

-- Backend finalizes only when the matching object exists and metadata agrees.
set role tucambio_backend;
select public.complete_tenant_evidence(
  '51000000-0000-0000-0000-000000000003',
  '52000000-0000-0000-0000-000000000001',
  '56000000-0000-0000-0000-000000000001',
  decode(repeat('cd', 32), 'hex')
);
do $$
begin
  if public.complete_tenant_evidence(
    '51000000-0000-0000-0000-000000000003',
    '52000000-0000-0000-0000-000000000001',
    '56000000-0000-0000-0000-000000000002',
    decode(repeat('ef', 32), 'hex')
  ) then
    raise exception 'Evidence without a Storage object was finalized';
  end if;
  if (select count(*) from public.get_pending_tenant_evidence_for_upload(
      '51000000-0000-0000-0000-000000000003',
      '52000000-0000-0000-0000-000000000001',
      '56000000-0000-0000-0000-000000000002'
    )) <> 1 then
    raise exception 'Backend cannot retrieve creator-owned pending evidence for verification';
  end if;
  if (select count(*) from public.get_tenant_evidence_for_download(
      '51000000-0000-0000-0000-000000000003',
      '52000000-0000-0000-0000-000000000001',
      '56000000-0000-0000-0000-000000000001'
    )) <> 1 then
    raise exception 'Backend cannot authorize download for an active tenant operator';
  end if;
  if (select count(*) from public.get_tenant_evidence_for_download(
      '51000000-0000-0000-0000-000000000002',
      '52000000-0000-0000-0000-000000000001',
      '56000000-0000-0000-0000-000000000001'
    )) <> 0 then
    raise exception 'Backend download lookup allowed a cross-tenant actor';
  end if;
end;
$$;
reset role;

-- Verified evidence is visible to an authorized tenant member only.
set role authenticated;
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000003', true);

do $$
begin
  if (select count(*) from public.tenant_evidence) <> 2 then
    raise exception 'Tenant A operator cannot read its tenant evidence metadata';
  end if;
  if (select count(*) from storage.objects) <> 1 then
    raise exception 'Tenant A operator cannot read verified evidence object';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000002', true);
do $$
begin
  if (select count(*) from public.tenant_evidence) <> 0
     or (select count(*) from storage.objects) <> 0 then
    raise exception 'Tenant B can read Tenant A evidence';
  end if;
end;
$$;
reset role;

rollback;
