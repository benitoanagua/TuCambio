-- TuCambio M1.10.1: tenant-scoped currency-rate history reads.
-- Rate history is immutable; this function exposes a bounded, authorized view.
begin;

create or replace function public.query_currency_rates(
  p_actor_user_id uuid,
  p_tenant_id uuid,
  p_pair_id uuid default null,
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

  if p_pair_id is not null and not exists (
    select 1 from public.tenant_currency_pairs p
    where p.tenant_id = p_tenant_id and p.id = p_pair_id
  ) then
    raise exception 'Currency pair not found for tenant' using errcode = '22023';
  end if;

  select count(*) into v_total
  from public.currency_rates r
  where r.tenant_id = p_tenant_id
    and (p_pair_id is null or r.pair_id = p_pair_id);

  select coalesce(jsonb_agg(to_jsonb(page_row) order by page_row.valid_from desc, page_row.id desc), '[]'::jsonb)
  into v_items
  from (
    select r.id, r.tenant_id, r.pair_id,
      p.base_currency_code, p.quote_currency_code,
      r.buy_rate, r.sell_rate, r.valid_from, r.valid_until, r.created_at
    from public.currency_rates r
    join public.tenant_currency_pairs p
      on p.tenant_id = r.tenant_id and p.id = r.pair_id
    where r.tenant_id = p_tenant_id
      and (p_pair_id is null or r.pair_id = p_pair_id)
    order by r.valid_from desc, r.id desc
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

revoke all on function public.query_currency_rates(uuid, uuid, uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.query_currency_rates(uuid, uuid, uuid, integer, integer) to tucambio_backend;

commit;
