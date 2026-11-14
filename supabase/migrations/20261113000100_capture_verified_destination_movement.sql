-- TuCambio M1.12: capture the verified destination movement as an immutable fact.
-- This records what was externally paid; it deliberately does not decide whether
-- the amount is sufficient/excessive or finalize the operation (P13/P14 remain open).
begin;

alter table public.financial_operations
  add column verified_destination_movement_id uuid,
  add column verified_destination_amount numeric(38, 18),
  add column destination_effective_at timestamptz,
  add constraint financial_operations_destination_movement_fk
    foreign key (tenant_id, verified_destination_movement_id)
    references public.external_movements(tenant_id, id) on delete restrict,
  add constraint financial_operations_destination_snapshot_complete check (
    (verified_destination_movement_id is null
      and verified_destination_amount is null
      and destination_effective_at is null)
    or
    (verified_destination_movement_id is not null
      and verified_destination_amount > 0
      and destination_effective_at is not null)
  );

create or replace function public.protect_verified_destination_snapshot()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_currency text;
  v_amount numeric(38, 18);
  v_effective_at timestamptz;
  v_status text;
  v_role text;
begin
  if old.verified_destination_movement_id is not null and (
    new.verified_destination_movement_id is distinct from old.verified_destination_movement_id
    or new.verified_destination_amount is distinct from old.verified_destination_amount
    or new.destination_effective_at is distinct from old.destination_effective_at
  ) then
    raise exception 'Verified destination snapshot is immutable' using errcode = '55000';
  end if;

  if old.verified_destination_movement_id is null
     and new.verified_destination_movement_id is not null then
    select m.currency_code, m.amount, m.effective_at, m.status, om.movement_role
      into v_currency, v_amount, v_effective_at, v_status, v_role
    from public.external_movements m
    join public.operation_movements om
      on om.tenant_id = m.tenant_id and om.movement_id = m.id
    where m.tenant_id = new.tenant_id
      and m.id = new.verified_destination_movement_id
      and om.operation_id = new.id
    for key share of m;

    if not found
       or v_role <> 'DESTINATION'
       or v_status <> 'CONFIRMED'
       or v_currency <> new.target_currency_code
       or v_amount is distinct from new.verified_destination_amount
       or v_effective_at is distinct from new.destination_effective_at then
      raise exception 'Destination snapshot must match a confirmed destination movement'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger financial_operations_destination_snapshot_guard
before update on public.financial_operations
for each row execute function public.protect_verified_destination_snapshot();

create or replace function public.capture_verified_destination_movement()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_operation_id uuid;
  v_target_currency text;
  v_membership_id uuid;
begin
  if old.status = new.status or new.status <> 'CONFIRMED' then
    return new;
  end if;

  select om.operation_id into v_operation_id
  from public.operation_movements om
  where om.tenant_id = new.tenant_id
    and om.movement_id = new.id
    and om.movement_role = 'DESTINATION';

  if v_operation_id is null then
    return new;
  end if;

  select o.target_currency_code into v_target_currency
  from public.financial_operations o
  where o.tenant_id = new.tenant_id and o.id = v_operation_id
  for update;

  if v_target_currency is distinct from new.currency_code then
    select tm.id into v_membership_id
    from public.tenant_memberships tm
    where tm.tenant_id = new.tenant_id
      and tm.user_id = new.created_by_user_id
    limit 1;

    insert into public.financial_domain_events (
      tenant_id, actor_membership_id, actor_user_id,
      entity_type, entity_id, event_type, payload
    ) values (
      new.tenant_id, v_membership_id, new.created_by_user_id,
      'OPERATION', v_operation_id, 'OPERATION_DESTINATION_CURRENCY_MISMATCH',
      jsonb_build_object(
        'movementId', new.id,
        'movementCurrency', new.currency_code,
        'operationTargetCurrency', v_target_currency
      )
    );
    return new;
  end if;

  select tm.id into v_membership_id
  from public.tenant_memberships tm
  where tm.tenant_id = new.tenant_id
    and tm.user_id = new.created_by_user_id
  limit 1;

  update public.financial_operations
  set verified_destination_movement_id = new.id,
      verified_destination_amount = new.amount,
      destination_effective_at = new.effective_at,
      updated_at = now()
  where tenant_id = new.tenant_id and id = v_operation_id;

  insert into public.financial_domain_events (
    tenant_id, actor_membership_id, actor_user_id,
    entity_type, entity_id, event_type, payload
  ) values (
    new.tenant_id, v_membership_id, new.created_by_user_id,
    'OPERATION', v_operation_id, 'OPERATION_DESTINATION_MOVEMENT_CONFIRMED',
    jsonb_build_object(
      'movementId', new.id,
      'currencyCode', new.currency_code,
      'amount', new.amount,
      'effectiveAt', new.effective_at
    )
  );

  return new;
end;
$$;

create trigger external_movement_capture_destination
after update of status on public.external_movements
for each row execute function public.capture_verified_destination_movement();

comment on column public.financial_operations.verified_destination_movement_id is
  'Confirmed external DESTINATION movement captured as immutable evidence of the amount paid.';
comment on column public.financial_operations.verified_destination_amount is
  'Exact amount of the confirmed external destination movement; not an approved settlement amount.';
comment on column public.financial_operations.destination_effective_at is
  'Effective instant reported by the confirmed external destination movement.';

commit;
