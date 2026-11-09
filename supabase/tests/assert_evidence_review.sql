-- M1.8.3 evidence review is independent from Storage integrity and movement status.
begin;

insert into auth.users (id, email) values
  ('81000000-0000-0000-0000-000000000001', 'evidence-review@example.test');
insert into public.tenants (id, name, slug, created_by_user_id) values
  ('82000000-0000-0000-0000-000000000001', 'Evidence Review', 'evidence-review',
   '81000000-0000-0000-0000-000000000001');
insert into public.tenant_memberships (id, tenant_id, user_id) values
  ('83000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001',
   '81000000-0000-0000-0000-000000000001');
insert into public.tenant_roles (id, tenant_id, code, name) values
  ('84000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001',
   'reviewer', 'Evidence Reviewer');
insert into public.tenant_role_capabilities (tenant_id, role_id, capability_code)
values ('82000000-0000-0000-0000-000000000001',
        '84000000-0000-0000-0000-000000000001', 'movements.verify');
insert into public.membership_roles (tenant_id, membership_id, role_id) values
  ('82000000-0000-0000-0000-000000000001',
   '83000000-0000-0000-0000-000000000001',
   '84000000-0000-0000-0000-000000000001');

insert into public.tenant_evidence (
  id, tenant_id, created_by_user_id, bucket_id, object_path, mime_type,
  expected_size_bytes, sha256, status, uploaded_at, verified_at
) values
  ('85000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001',
   '81000000-0000-0000-0000-000000000001', 'operation-evidence',
   '82000000-0000-0000-0000-000000000001/85000000-0000-0000-0000-000000000001',
   'image/png', 8, decode(repeat('ab',32),'hex'), 'available', now(), now()),
  ('85000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000001',
   '81000000-0000-0000-0000-000000000001', 'operation-evidence',
   '82000000-0000-0000-0000-000000000001/85000000-0000-0000-0000-000000000002',
   'image/png', 8, decode(repeat('cd',32),'hex'), 'available', now(), now());

set local role tucambio_backend;
do $$
declare
  v_started jsonb;
  v_started_replay jsonb;
  v_observed jsonb;
  v_valid_started jsonb;
  v_valid jsonb;
  v_denied boolean := false;
begin
  if has_function_privilege('authenticated',
       'public.command_review_tenant_evidence(uuid,uuid,uuid,text,text,text,bytea)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.command_review_tenant_evidence(uuid,uuid,uuid,text,text,text,bytea)', 'EXECUTE') then
    raise exception 'Client roles must not execute evidence review command';
  end if;

  v_started := public.command_review_tenant_evidence(
    '81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001',
    '85000000-0000-0000-0000-000000000001','EN_REVISION',null,
    'review-start-1',decode(repeat('11',32),'hex'));
  v_started_replay := public.command_review_tenant_evidence(
    '81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001',
    '85000000-0000-0000-0000-000000000001','EN_REVISION',null,
    'review-start-1',decode(repeat('11',32),'hex'));
  if v_started->>'resourceId' <> v_started_replay->>'resourceId'
     or v_started_replay->>'replayed' <> 'true' then
    raise exception 'Evidence review retry is not idempotent';
  end if;

  begin
    perform public.command_review_tenant_evidence(
      '81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001',
      '85000000-0000-0000-0000-000000000001','OBSERVADA',null,
      'review-observe-no-reason',decode(repeat('12',32),'hex'));
    raise exception 'Observation without reason unexpectedly succeeded';
  exception when invalid_parameter_value then null;
  end;

  v_observed := public.command_review_tenant_evidence(
    '81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001',
    '85000000-0000-0000-0000-000000000001','OBSERVADA','Comprobante ilegible',
    'review-observe-1',decode(repeat('13',32),'hex'));

  v_valid_started := public.command_review_tenant_evidence(
    '81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001',
    '85000000-0000-0000-0000-000000000002','EN_REVISION',null,
    'review-valid-start-1',decode(repeat('14',32),'hex'));
  v_valid := public.command_review_tenant_evidence(
    '81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001',
    '85000000-0000-0000-0000-000000000002','VALIDA',null,
    'review-valid-1',decode(repeat('15',32),'hex'));

  begin
    perform public.command_review_tenant_evidence(
      '81000000-0000-0000-0000-000000000001','82000000-0000-0000-0000-000000000001',
      '85000000-0000-0000-0000-000000000001','VALIDA',null,
      'review-invalid-transition',decode(repeat('16',32),'hex'));
    raise exception 'Invalid review transition unexpectedly succeeded';
  exception when check_violation then null;
  end;
end;
$$;
reset role;

do $$
begin
  if (select review_status from public.tenant_evidence
      where id = '85000000-0000-0000-0000-000000000001') <> 'OBSERVADA' then
    raise exception 'Observed evidence state was not persisted';
  end if;
  if (select review_status from public.tenant_evidence
      where id = '85000000-0000-0000-0000-000000000002') <> 'VALIDA' then
    raise exception 'Valid evidence state was not persisted';
  end if;
  if (select count(*) from public.evidence_review_events
      where tenant_id = '82000000-0000-0000-0000-000000000001') <> 4 then
    raise exception 'Evidence review event history is incomplete or duplicated';
  end if;
  if (select count(*) from public.tenant_evidence
      where tenant_id = '82000000-0000-0000-0000-000000000001'
        and status = 'available') <> 2 then
    raise exception 'Review must not mutate Storage integrity status';
  end if;
end;
$$;

rollback;
