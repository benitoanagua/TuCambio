-- TuCambio M1.9.1: tenant-scoped, read-only financial list queries.
-- Read access is an explicit tenant capability; no table SELECT/DML is granted.
begin;

insert into public.capabilities (code, description)
values ('financial.read', 'Consultar información financiera del tenant')
on conflict (code) do update set description = excluded.description;

create or replace function public.assert_financial_read_actor(
  p_actor_user_id uuid,
  p_tenant_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_membership_id uuid;
begin
  select a.membership_id into v_membership_id
  from public.resolve_tenant_access(p_actor_user_id, p_tenant_id) a
  where a.capability_code = 'financial.read'
  limit 1;

  if v_membership_id is null then
    raise exception 'Financial read access denied' using errcode = '42501';
  end if;
  return v_membership_id;
end;
$$;

create or replace function public.query_financial_operations(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_status text default null,
  p_page_size integer default 25,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_total bigint;
  v_items jsonb;
begin
  perform public.assert_financial_read_actor(p_actor_user_id, p_tenant_id);
  if p_page_size not between 1 and 100 or p_offset not between 0 and 10000 then
    raise exception 'Invalid pagination window' using errcode = '22023';
  end if;

  select count(*) into v_total
  from public.financial_operations o
  where o.tenant_id = p_tenant_id
    and (p_status is null or o.status = p_status);

  select coalesce(jsonb_agg(to_jsonb(page_row) order by page_row.created_at desc, page_row.id desc), '[]'::jsonb)
  into v_items
  from (
    select
      o.id, o.tenant_id, o.pair_id, o.source_currency_code, o.target_currency_code,
      o.requested_amount, o.status, o.source_effective_at, o.applied_rate_id,
      o.applied_rate, o.created_by_membership_id, o.created_by_user_id,
      o.created_at, o.updated_at,
      base_currency.name as source_currency_name,
      base_currency.decimal_places as source_decimal_places,
      target_currency.name as target_currency_name,
      target_currency.decimal_places as target_decimal_places
    from public.financial_operations o
    join public.tenant_currencies base_currency
      on base_currency.tenant_id = o.tenant_id and base_currency.code = o.source_currency_code
    join public.tenant_currencies target_currency
      on target_currency.tenant_id = o.tenant_id and target_currency.code = o.target_currency_code
    where o.tenant_id = p_tenant_id
      and (p_status is null or o.status = p_status)
    order by o.created_at desc, o.id desc
    limit p_page_size offset p_offset
  ) page_row;

  return jsonb_build_object(
    'items', v_items,
    'total', v_total,
    'pageSize', p_page_size,
    'offset', p_offset
  );
end;
$$;

create or replace function public.query_external_movements(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_status text default null,
  p_page_size integer default 25,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_total bigint;
  v_items jsonb;
begin
  perform public.assert_financial_read_actor(p_actor_user_id, p_tenant_id);
  if p_page_size not between 1 and 100 or p_offset not between 0 and 10000 then
    raise exception 'Invalid pagination window' using errcode = '22023';
  end if;

  select count(*) into v_total
  from public.external_movements m
  where m.tenant_id = p_tenant_id
    and (p_status is null or m.status = p_status);

  select coalesce(jsonb_agg(to_jsonb(page_row) order by page_row.created_at desc, page_row.id desc), '[]'::jsonb)
  into v_items
  from (
    select
      m.id, m.tenant_id, m.currency_code, m.amount, m.effective_at, m.status,
      m.external_reference, m.description, m.created_by_membership_id,
      m.created_by_user_id, m.created_at, m.updated_at,
      currency.name as currency_name,
      currency.decimal_places,
      association.operation_id,
      association.movement_role
    from public.external_movements m
    join public.tenant_currencies currency
      on currency.tenant_id = m.tenant_id and currency.code = m.currency_code
    left join public.operation_movements association
      on association.tenant_id = m.tenant_id and association.movement_id = m.id
    where m.tenant_id = p_tenant_id
      and (p_status is null or m.status = p_status)
    order by m.created_at desc, m.id desc
    limit p_page_size offset p_offset
  ) page_row;

  return jsonb_build_object(
    'items', v_items,
    'total', v_total,
    'pageSize', p_page_size,
    'offset', p_offset
  );
end;
$$;

revoke all on function public.assert_financial_read_actor(uuid, uuid) from public, anon, authenticated;
revoke all on function public.query_financial_operations(uuid, uuid, text, integer, integer) from public, anon, authenticated;
revoke all on function public.query_external_movements(uuid, uuid, text, integer, integer) from public, anon, authenticated;

grant execute on function public.assert_financial_read_actor(uuid, uuid) to tucambio_backend;
grant execute on function public.query_financial_operations(uuid, uuid, text, integer, integer) to tucambio_backend;
grant execute on function public.query_external_movements(uuid, uuid, text, integer, integer) to tucambio_backend;

commit;
