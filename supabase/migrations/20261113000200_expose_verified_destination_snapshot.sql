-- TuCambio M1.12.1: expose the immutable destination movement snapshot in financial reads.
begin;

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
      o.applied_rate, o.verified_source_movement_id, o.verified_source_amount,
      o.verified_destination_movement_id, o.verified_destination_amount,
      o.destination_effective_at,
      o.created_by_membership_id, o.created_by_user_id, o.created_at, o.updated_at,
      source_currency.name as source_currency_name,
      source_currency.decimal_places as source_decimal_places,
      target_currency.name as target_currency_name,
      target_currency.decimal_places as target_decimal_places
    from public.financial_operations o
    join public.tenant_currencies source_currency
      on source_currency.tenant_id = o.tenant_id and source_currency.code = o.source_currency_code
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

revoke all on function public.query_financial_operations(uuid, uuid, text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.query_financial_operations(uuid, uuid, text, integer, integer)
  to tucambio_backend;

commit;
