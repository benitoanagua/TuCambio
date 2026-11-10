-- M1.10.2: tenant-scoped, metadata-only financial audit history.
-- Payload is intentionally excluded from the read model.
begin;

create or replace function public.query_financial_domain_events(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_entity_type text default null,
  p_entity_id uuid default null,
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
  if p_entity_type is not null and p_entity_type not in
    ('CURRENCY', 'CURRENCY_PAIR', 'RATE', 'OPERATION', 'MOVEMENT', 'EVIDENCE_LINK') then
    raise exception 'Invalid entity type' using errcode = '22023';
  end if;

  select count(*) into v_total
  from public.financial_domain_events e
  where e.tenant_id = p_tenant_id
    and (p_entity_type is null or e.entity_type = p_entity_type)
    and (p_entity_id is null or e.entity_id = p_entity_id);

  select coalesce(jsonb_agg(to_jsonb(page_row) order by page_row.occurred_at desc, page_row.id desc), '[]'::jsonb)
  into v_items
  from (
    select e.id, e.tenant_id, e.actor_user_id, e.entity_type, e.entity_id,
      e.event_type, e.request_id, e.occurred_at
    from public.financial_domain_events e
    where e.tenant_id = p_tenant_id
      and (p_entity_type is null or e.entity_type = p_entity_type)
      and (p_entity_id is null or e.entity_id = p_entity_id)
    order by e.occurred_at desc, e.id desc
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

revoke all on function public.query_financial_domain_events(uuid, uuid, text, uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.query_financial_domain_events(uuid, uuid, text, uuid, integer, integer)
  to tucambio_backend;

commit;
