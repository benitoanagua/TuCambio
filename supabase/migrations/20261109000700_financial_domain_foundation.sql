-- TuCambio M1.7.1: tenant-scoped financial domain foundation.
-- No client DML grants. Financial commands are exposed only through reviewed
-- backend SECURITY DEFINER functions in subsequent slices.
begin;

create table public.tenant_currencies (
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  code text not null,
  name text not null,
  decimal_places smallint not null,
  status text not null default 'active',
  created_by_membership_id uuid not null,
  created_by_user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tenant_id, code),
  constraint tenant_currencies_author_fk foreign key (tenant_id, created_by_membership_id, created_by_user_id)
    references public.tenant_memberships(tenant_id, id, user_id) on delete restrict,
  constraint tenant_currencies_code_format check (code ~ '^[A-Z0-9]{3,12}$'),
  constraint tenant_currencies_name_length check (char_length(btrim(name)) between 1 and 80),
  constraint tenant_currencies_decimal_places check (decimal_places between 0 and 18),
  constraint tenant_currencies_status check (status in ('active', 'inactive'))
);

create table public.tenant_currency_pairs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  base_currency_code text not null,
  quote_currency_code text not null,
  status text not null default 'enabled',
  created_by_membership_id uuid not null,
  created_by_user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenant_currency_pairs_author_fk foreign key (tenant_id, created_by_membership_id, created_by_user_id)
    references public.tenant_memberships(tenant_id, id, user_id) on delete restrict,
  constraint tenant_currency_pairs_distinct check (base_currency_code <> quote_currency_code),
  constraint tenant_currency_pairs_status check (status in ('enabled', 'disabled')),
  constraint tenant_currency_pairs_tenant_id_unique unique (tenant_id, id),
  constraint tenant_currency_pairs_identity_unique unique (tenant_id, base_currency_code, quote_currency_code),
  constraint tenant_currency_pairs_base_fk foreign key (tenant_id, base_currency_code)
    references public.tenant_currencies(tenant_id, code) on delete restrict,
  constraint tenant_currency_pairs_quote_fk foreign key (tenant_id, quote_currency_code)
    references public.tenant_currencies(tenant_id, code) on delete restrict
);

create table public.currency_rates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  pair_id uuid not null,
  buy_rate numeric(38, 18) not null,
  sell_rate numeric(38, 18) not null,
  valid_from timestamptz not null,
  valid_until timestamptz,
  created_by_membership_id uuid not null,
  created_by_user_id uuid not null,
  created_at timestamptz not null default now(),
  constraint currency_rates_positive check (buy_rate > 0 and sell_rate > 0),
  constraint currency_rates_validity check (valid_until is null or valid_until > valid_from),
  constraint currency_rates_tenant_id_unique unique (tenant_id, id),
  constraint currency_rates_tenant_pair_id_unique unique (tenant_id, pair_id, id),
  constraint currency_rates_pair_fk foreign key (tenant_id, pair_id)
    references public.tenant_currency_pairs(tenant_id, id) on delete restrict,
  constraint currency_rates_author_fk foreign key (tenant_id, created_by_membership_id, created_by_user_id)
    references public.tenant_memberships(tenant_id, id, user_id) on delete restrict
);

create index currency_rates_pair_valid_from_idx
  on public.currency_rates(tenant_id, pair_id, valid_from desc);

-- Currency identity/precision and pair identity are historical configuration.
-- Availability can change, but identity and precision cannot be rewritten.
create or replace function public.protect_currency_configuration_identity()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_table_name = 'tenant_currencies' then
    if new.tenant_id is distinct from old.tenant_id
       or new.code is distinct from old.code
       or new.decimal_places is distinct from old.decimal_places then
      raise exception 'Currency identity and precision are immutable' using errcode = '55000';
    end if;
  elsif new.tenant_id is distinct from old.tenant_id
     or new.id is distinct from old.id
     or new.base_currency_code is distinct from old.base_currency_code
     or new.quote_currency_code is distinct from old.quote_currency_code then
    raise exception 'Currency pair identity is immutable' using errcode = '55000';
  end if;
  return new;
end;
$$;

create trigger tenant_currencies_identity_immutable
before update on public.tenant_currencies
for each row execute function public.protect_currency_configuration_identity();

create trigger tenant_currency_pairs_identity_immutable
before update on public.tenant_currency_pairs
for each row execute function public.protect_currency_configuration_identity();

create table public.financial_operations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  pair_id uuid not null,
  source_currency_code text not null,
  target_currency_code text not null,
  requested_amount numeric(38, 18) not null,
  status text not null default 'PENDING',
  source_effective_at timestamptz,
  applied_rate_id uuid,
  applied_rate numeric(38, 18),
  created_by_membership_id uuid not null,
  created_by_user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint financial_operations_amount_positive check (requested_amount > 0),
  constraint financial_operations_status check (status in (
    'DRAFT', 'PENDING', 'IN_VERIFICATION', 'PENDING_SETTLEMENT',
    'IN_SETTLEMENT', 'FINALIZED', 'CANCELLED', 'EXPIRED', 'REJECTED'
  )),
  constraint financial_operations_currencies_distinct check (source_currency_code <> target_currency_code),
  constraint financial_operations_tenant_id_unique unique (tenant_id, id),
  constraint financial_operations_pair_fk foreign key (tenant_id, pair_id)
    references public.tenant_currency_pairs(tenant_id, id) on delete restrict,
  constraint financial_operations_source_currency_fk foreign key (tenant_id, source_currency_code)
    references public.tenant_currencies(tenant_id, code) on delete restrict,
  constraint financial_operations_target_currency_fk foreign key (tenant_id, target_currency_code)
    references public.tenant_currencies(tenant_id, code) on delete restrict,
  constraint financial_operations_author_fk foreign key (tenant_id, created_by_membership_id, created_by_user_id)
    references public.tenant_memberships(tenant_id, id, user_id) on delete restrict,
  constraint financial_operations_applied_rate_fk foreign key (tenant_id, pair_id, applied_rate_id)
    references public.currency_rates(tenant_id, pair_id, id) on delete restrict,
  constraint financial_operations_applied_rate_consistency check (
    (applied_rate_id is null and applied_rate is null)
    or (applied_rate_id is not null and applied_rate > 0 and source_effective_at is not null)
  )
);

create index financial_operations_tenant_status_created_idx
  on public.financial_operations(tenant_id, status, created_at desc);

-- Operation identity and requested economics never change. The applied rate
-- can be attached once, only when it covers the verified source instant.
create or replace function public.protect_financial_operation_facts()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  rate_row public.currency_rates%rowtype;
begin
  if new.tenant_id is distinct from old.tenant_id
     or new.id is distinct from old.id
     or new.pair_id is distinct from old.pair_id
     or new.source_currency_code is distinct from old.source_currency_code
     or new.target_currency_code is distinct from old.target_currency_code
     or new.requested_amount is distinct from old.requested_amount
     or new.created_by_membership_id is distinct from old.created_by_membership_id
     or new.created_by_user_id is distinct from old.created_by_user_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Financial operation identity and requested amount are immutable' using errcode = '55000';
  end if;

  if old.applied_rate_id is not null and (
       new.applied_rate_id is distinct from old.applied_rate_id
       or new.applied_rate is distinct from old.applied_rate
       or new.source_effective_at is distinct from old.source_effective_at
  ) then
    raise exception 'An applied operation rate is immutable' using errcode = '55000';
  end if;

  if old.applied_rate_id is null and new.applied_rate_id is not null then
    if new.source_effective_at is null then
      raise exception 'A verified source movement instant is required to apply a rate' using errcode = '23514';
    end if;
    select * into rate_row from public.currency_rates r
    where r.tenant_id = new.tenant_id
      and r.pair_id = new.pair_id
      and r.id = new.applied_rate_id
      and tstzrange(r.valid_from, r.valid_until, '[)') @> new.source_effective_at;
    if not found or rate_row.buy_rate <> new.applied_rate and rate_row.sell_rate <> new.applied_rate then
      raise exception 'Applied rate must match a rate valid at the verified source instant' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger financial_operations_facts_immutable
before update on public.financial_operations
for each row execute function public.protect_financial_operation_facts();

-- New operations must use the exact enabled pair and active tenant currencies.
create or replace function public.validate_financial_operation_pair()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if not exists (
    select 1
    from public.tenant_currency_pairs p
    join public.tenant_currencies base_c
      on base_c.tenant_id = p.tenant_id and base_c.code = p.base_currency_code
    join public.tenant_currencies quote_c
      on quote_c.tenant_id = p.tenant_id and quote_c.code = p.quote_currency_code
    where p.tenant_id = new.tenant_id
      and p.id = new.pair_id
      and p.status = 'enabled'
      and base_c.status = 'active'
      and quote_c.status = 'active'
      and (
        (new.source_currency_code = p.base_currency_code and new.target_currency_code = p.quote_currency_code)
        or
        (new.source_currency_code = p.quote_currency_code and new.target_currency_code = p.base_currency_code)
      )
  ) then
    raise exception 'Operation currencies must match an enabled tenant pair'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger financial_operations_pair_validation
before insert on public.financial_operations
for each row execute function public.validate_financial_operation_pair();

create table public.external_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  currency_code text not null,
  amount numeric(38, 18) not null,
  effective_at timestamptz not null,
  status text not null default 'DECLARED',
  external_reference text,
  description text,
  created_by_membership_id uuid not null,
  created_by_user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint external_movements_amount_positive check (amount > 0),
  constraint external_movements_status check (status in ('DECLARED', 'IN_VERIFICATION', 'CONFIRMED', 'NOT_CONFIRMED')),
  constraint external_movements_reference_length check (external_reference is null or char_length(external_reference) <= 200),
  constraint external_movements_description_length check (description is null or char_length(description) <= 1000),
  constraint external_movements_tenant_id_unique unique (tenant_id, id),
  constraint external_movements_currency_fk foreign key (tenant_id, currency_code)
    references public.tenant_currencies(tenant_id, code) on delete restrict,
  constraint external_movements_author_fk foreign key (tenant_id, created_by_membership_id, created_by_user_id)
    references public.tenant_memberships(tenant_id, id, user_id) on delete restrict
);

create index external_movements_tenant_effective_idx
  on public.external_movements(tenant_id, effective_at desc);

-- A confirmed external fact is immutable; corrections are separate records/events.
create or replace function public.protect_confirmed_external_movement()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if old.status = 'CONFIRMED' then
    raise exception 'A confirmed external movement is immutable' using errcode = '55000';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'External movement history is retained' using errcode = '55000';
  end if;
  return new;
end;
$$;

create trigger external_movements_confirmed_immutable
before update or delete on public.external_movements
for each row execute function public.protect_confirmed_external_movement();

create table public.operation_movements (
  tenant_id uuid not null,
  operation_id uuid not null,
  movement_id uuid not null,
  movement_role text not null,
  associated_by_membership_id uuid not null,
  associated_by_user_id uuid not null,
  associated_at timestamptz not null default now(),
  primary key (tenant_id, operation_id, movement_role),
  constraint operation_movements_role check (movement_role in ('ORIGIN', 'DESTINATION')),
  constraint operation_movements_movement_unique unique (tenant_id, movement_id),
  constraint operation_movements_operation_fk foreign key (tenant_id, operation_id)
    references public.financial_operations(tenant_id, id) on delete restrict,
  constraint operation_movements_movement_fk foreign key (tenant_id, movement_id)
    references public.external_movements(tenant_id, id) on delete restrict,
  constraint operation_movements_actor_fk foreign key (tenant_id, associated_by_membership_id, associated_by_user_id)
    references public.tenant_memberships(tenant_id, id, user_id) on delete restrict
);

create table public.evidence_financial_links (
  tenant_id uuid not null,
  evidence_id uuid not null,
  operation_id uuid,
  movement_id uuid,
  linked_by_membership_id uuid not null,
  linked_by_user_id uuid not null,
  linked_at timestamptz not null default now(),
  constraint evidence_financial_links_one_target check (
    (operation_id is not null and movement_id is null)
    or (operation_id is null and movement_id is not null)
  ),
  constraint evidence_financial_links_evidence_fk foreign key (tenant_id, evidence_id)
    references public.tenant_evidence(tenant_id, id) on delete restrict,
  constraint evidence_financial_links_operation_fk foreign key (tenant_id, operation_id)
    references public.financial_operations(tenant_id, id) on delete restrict,
  constraint evidence_financial_links_movement_fk foreign key (tenant_id, movement_id)
    references public.external_movements(tenant_id, id) on delete restrict,
  constraint evidence_financial_links_actor_fk foreign key (tenant_id, linked_by_membership_id, linked_by_user_id)
    references public.tenant_memberships(tenant_id, id, user_id) on delete restrict
);

create unique index evidence_financial_links_operation_unique
  on public.evidence_financial_links(tenant_id, evidence_id, operation_id) where operation_id is not null;
create unique index evidence_financial_links_movement_unique
  on public.evidence_financial_links(tenant_id, evidence_id, movement_id) where movement_id is not null;
create index evidence_financial_links_operation_idx
  on public.evidence_financial_links(tenant_id, operation_id) where operation_id is not null;
create index evidence_financial_links_movement_idx
  on public.evidence_financial_links(tenant_id, movement_id) where movement_id is not null;

create or replace function public.reject_financial_link_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception 'Financial evidence associations are append-only' using errcode = '55000';
end;
$$;

create trigger evidence_financial_links_append_only
before update or delete on public.evidence_financial_links
for each row execute function public.reject_financial_link_mutation();

create table public.financial_domain_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  actor_membership_id uuid not null,
  actor_user_id uuid not null,
  entity_type text not null,
  entity_id uuid not null,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  request_id uuid,
  occurred_at timestamptz not null default now(),
  constraint financial_domain_events_entity_type check (entity_type in ('OPERATION', 'MOVEMENT', 'RATE', 'EVIDENCE_LINK')),
  constraint financial_domain_events_type_length check (char_length(event_type) between 3 and 100),
  constraint financial_domain_events_payload_object check (jsonb_typeof(payload) = 'object'),
  constraint financial_domain_events_actor_fk foreign key (tenant_id, actor_membership_id, actor_user_id)
    references public.tenant_memberships(tenant_id, id, user_id) on delete restrict
);

create index financial_domain_events_entity_time_idx
  on public.financial_domain_events(tenant_id, entity_type, entity_id, occurred_at);

create trigger financial_command_idempotency_append_only
before update or delete on public.financial_command_idempotency
for each row execute function public.reject_financial_link_mutation();

create table public.financial_command_idempotency (
  tenant_id uuid not null,
  actor_user_id uuid not null,
  command_type text not null,
  idempotency_key text not null,
  request_sha256 bytea not null,
  result_resource_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (tenant_id, actor_user_id, command_type, idempotency_key),
  constraint financial_command_idempotency_hash check (octet_length(request_sha256) = 32),
  constraint financial_command_idempotency_key_length check (char_length(idempotency_key) between 1 and 200),
  constraint financial_command_idempotency_type_length check (char_length(command_type) between 3 and 80),
  constraint financial_command_idempotency_actor_fk foreign key (tenant_id, actor_user_id)
    references public.tenant_memberships(tenant_id, user_id) on delete restrict
);

-- Rate intervals are half-open [valid_from, valid_until). Overlap is rejected
-- under a per-tenant/pair transaction lock; gaps remain valid domain states.
create or replace function public.enforce_currency_rate_interval()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.tenant_id::text || ':' || new.pair_id::text, 0));
  if exists (
    select 1
    from public.currency_rates r
    where r.tenant_id = new.tenant_id
      and r.pair_id = new.pair_id
      and r.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
      and tstzrange(r.valid_from, r.valid_until, '[)')
          && tstzrange(new.valid_from, new.valid_until, '[)')
  ) then
    raise exception 'Currency rate validity intervals cannot overlap'
      using errcode = '23P01';
  end if;
  return new;
end;
$$;

create trigger currency_rates_no_overlap
before insert or update of valid_from, valid_until, pair_id, tenant_id
on public.currency_rates
for each row execute function public.enforce_currency_rate_interval();

create or replace function public.protect_currency_rate_history()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Currency rate history is append-only' using errcode = '55000';
  end if;

  if (to_jsonb(new) - 'valid_until') <> (to_jsonb(old) - 'valid_until') then
    raise exception 'Currency rate values and identity are immutable' using errcode = '55000';
  end if;

  if new.valid_until is distinct from old.valid_until then
    if old.valid_until is not null or new.valid_until is null or new.valid_until <= old.valid_from then
      raise exception 'Only an open rate interval may be closed once' using errcode = '55000';
    end if;
    if exists (select 1 from public.financial_operations o where o.tenant_id = old.tenant_id and o.applied_rate_id = old.id) then
      raise exception 'A rate used by a financial operation is immutable' using errcode = '55000';
    end if;
  end if;
  return new;
end;
$$;

create trigger currency_rates_append_only
before update or delete on public.currency_rates
for each row execute function public.protect_currency_rate_history();

-- Append-only domain event history.
create or replace function public.reject_financial_event_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  raise exception 'Financial domain events are append-only' using errcode = '55000';
end;
$$;

create trigger financial_domain_events_append_only
before update or delete on public.financial_domain_events
for each row execute function public.reject_financial_event_mutation();

-- No direct client or backend table DML. Subsequent migrations expose only
-- narrow SECURITY DEFINER command/query functions to tucambio_backend.
alter table public.tenant_currencies enable row level security;
alter table public.tenant_currency_pairs enable row level security;
alter table public.currency_rates enable row level security;
alter table public.financial_operations enable row level security;
alter table public.external_movements enable row level security;
alter table public.operation_movements enable row level security;
alter table public.evidence_financial_links enable row level security;
alter table public.financial_domain_events enable row level security;
alter table public.financial_command_idempotency enable row level security;

revoke all on table
  public.tenant_currencies,
  public.tenant_currency_pairs,
  public.currency_rates,
  public.financial_operations,
  public.external_movements,
  public.operation_movements,
  public.evidence_financial_links,
  public.financial_domain_events,
  public.financial_command_idempotency
from anon, authenticated, tucambio_backend;

grant usage on schema public to tucambio_backend;

commit;
