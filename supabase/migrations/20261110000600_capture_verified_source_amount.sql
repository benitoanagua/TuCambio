-- TuCambio M1.8.4: preserve the verified origin amount as an immutable operation fact.
-- This deliberately does not calculate a final target amount while rounding policy P04 is open.
begin;

alter table public.financial_operations
  add column verified_source_movement_id uuid,
  add column verified_source_amount numeric(38, 18);

alter table public.financial_operations
  add constraint financial_operations_verified_source_pair
    check (
      (verified_source_movement_id is null and verified_source_amount is null)
      or
      (verified_source_movement_id is not null and verified_source_amount > 0)
    ),
  add constraint financial_operations_verified_source_movement_fk
    foreign key (tenant_id, verified_source_movement_id)
    references public.external_movements(tenant_id, id) on delete restrict;

create or replace function public.protect_verified_source_amount_snapshot()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_movement public.external_movements%rowtype;
  v_is_origin boolean;
begin
  if old.verified_source_movement_id is not null and (
       new.verified_source_movement_id is distinct from old.verified_source_movement_id
       or new.verified_source_amount is distinct from old.verified_source_amount
       or new.source_effective_at is distinct from old.source_effective_at
  ) then
    raise exception 'Verified source amount snapshot is immutable' using errcode = '55000';
  end if;

  if old.verified_source_movement_id is null and new.verified_source_movement_id is not null then
    select m.* into v_movement
    from public.external_movements m
    where m.tenant_id = new.tenant_id
      and m.id = new.verified_source_movement_id
    for key share;

    if not found or v_movement.status <> 'CONFIRMED'
       or v_movement.currency_code <> new.source_currency_code
       or v_movement.amount is distinct from new.verified_source_amount
       or v_movement.effective_at is distinct from new.source_effective_at then
      raise exception 'Verified source snapshot must match a confirmed source-currency movement'
        using errcode = '23514';
    end if;

    select exists (
      select 1
      from public.operation_movements om
      where om.tenant_id = new.tenant_id
        and om.operation_id = new.id
        and om.movement_id = new.verified_source_movement_id
        and om.movement_role = 'ORIGIN'
    ) into v_is_origin;

    if not v_is_origin then
      raise exception 'Verified source snapshot requires an ORIGIN movement association'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger financial_operations_verified_source_snapshot
before update on public.financial_operations
for each row execute function public.protect_verified_source_amount_snapshot();

create or replace function public.capture_confirmed_origin_amount()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_operation_id uuid;
  v_source_currency text;
begin
  if new.status = 'CONFIRMED' and old.status is distinct from new.status then
    select o.id, o.source_currency_code
      into v_operation_id, v_source_currency
    from public.operation_movements om
    join public.financial_operations o
      on o.tenant_id = om.tenant_id and o.id = om.operation_id
    where om.tenant_id = new.tenant_id
      and om.movement_id = new.id
      and om.movement_role = 'ORIGIN'
    for update of o;

    if v_operation_id is not null and v_source_currency = new.currency_code then
      update public.financial_operations
      set verified_source_movement_id = new.id,
          verified_source_amount = new.amount,
          source_effective_at = new.effective_at,
          updated_at = now()
      where tenant_id = new.tenant_id
        and id = v_operation_id;
    end if;
  end if;

  return new;
end;
$$;

create trigger external_movement_capture_confirmed_origin_amount
after update of status on public.external_movements
for each row execute function public.capture_confirmed_origin_amount();

comment on column public.financial_operations.verified_source_movement_id is
  'Confirmed ORIGIN movement whose exact amount was verified for this operation.';
comment on column public.financial_operations.verified_source_amount is
  'Immutable snapshot of the confirmed ORIGIN movement amount; not the calculated destination amount.';

commit;
