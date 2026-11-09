-- TuCambio M1.1: canonical multi-tenant identity and authorization schema.
-- Supabase Auth owns credentials; this schema owns application profiles,
-- tenant membership and business capabilities. No client-facing policies
-- are granted in this migration: RLS is enabled with default deny.

begin;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  locale text not null default 'es',
  time_zone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_display_name_length check (
    display_name is null or char_length(btrim(display_name)) between 1 and 120
  ),
  constraint profiles_locale_length check (char_length(locale) between 2 and 35),
  constraint profiles_time_zone_length check (char_length(time_zone) between 1 and 64)
);

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  status text not null default 'active',
  created_by_user_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenants_name_length check (char_length(btrim(name)) between 2 and 120),
  constraint tenants_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint tenants_status check (status in ('active', 'suspended', 'closed'))
);

create table public.tenant_memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  status text not null default 'active',
  joined_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenant_memberships_status check (status in ('active', 'suspended', 'revoked')),
  constraint tenant_memberships_tenant_user_unique unique (tenant_id, user_id),
  constraint tenant_memberships_tenant_id_unique unique (tenant_id, id),
  constraint tenant_memberships_tenant_id_user_unique unique (tenant_id, id, user_id)
);

create table public.capabilities (
  code text primary key,
  description text not null,
  created_at timestamptz not null default now(),
  constraint capabilities_code_format check (code ~ '^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$')
);

insert into public.capabilities (code, description) values
  ('operations.operate', 'Crear y gestionar operaciones'),
  ('movements.verify', 'Verificar movimientos y sus evidencias'),
  ('operations.settle', 'Registrar la liquidación de operaciones'),
  ('rates.manage', 'Crear y administrar tasas'),
  ('settings.manage', 'Administrar configuración del tenant'),
  ('tenant.administer', 'Administrar miembros, invitaciones y permisos')
on conflict (code) do update set description = excluded.description;

create table public.tenant_roles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  code text not null,
  name text not null,
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tenant_roles_code_format check (code ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  constraint tenant_roles_name_length check (char_length(btrim(name)) between 2 and 80),
  constraint tenant_roles_tenant_code_unique unique (tenant_id, code),
  constraint tenant_roles_tenant_id_unique unique (tenant_id, id)
);

create table public.tenant_role_capabilities (
  tenant_id uuid not null,
  role_id uuid not null,
  capability_code text not null references public.capabilities(code) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (tenant_id, role_id, capability_code),
  constraint tenant_role_capabilities_role_fk
    foreign key (tenant_id, role_id)
    references public.tenant_roles(tenant_id, id) on delete cascade
);

create table public.membership_roles (
  tenant_id uuid not null,
  membership_id uuid not null,
  role_id uuid not null,
  assigned_at timestamptz not null default now(),
  primary key (tenant_id, membership_id, role_id),
  constraint membership_roles_membership_fk
    foreign key (tenant_id, membership_id)
    references public.tenant_memberships(tenant_id, id) on delete cascade,
  constraint membership_roles_role_fk
    foreign key (tenant_id, role_id)
    references public.tenant_roles(tenant_id, id) on delete cascade
);

create table public.tenant_invitations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  email_normalized text not null,
  token_hash bytea not null,
  invited_by_membership_id uuid not null,
  accepted_by_user_id uuid references auth.users(id) on delete restrict,
  expires_at timestamptz not null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint tenant_invitations_email_normalized check (
    email_normalized = lower(btrim(email_normalized))
    and char_length(email_normalized) between 3 and 320
  ),
  constraint tenant_invitations_token_hash_sha256 check (octet_length(token_hash) = 32),
  constraint tenant_invitations_expiry check (expires_at > created_at),
  constraint tenant_invitations_accept_revoke_exclusive check (
    accepted_at is null or revoked_at is null
  ),
  constraint tenant_invitations_tenant_id_unique unique (tenant_id, id),
  constraint tenant_invitations_inviter_fk
    foreign key (tenant_id, invited_by_membership_id)
    references public.tenant_memberships(tenant_id, id) on delete restrict,
  constraint tenant_invitations_accepted_consistency check (
    (accepted_at is null and accepted_by_user_id is null)
    or (accepted_at is not null and accepted_by_user_id is not null)
  ),
  constraint tenant_invitations_token_unique unique (tenant_id, token_hash)
);

create index tenant_memberships_user_status_idx
  on public.tenant_memberships (user_id, status);
create index tenant_memberships_tenant_status_idx
  on public.tenant_memberships (tenant_id, status);
create index tenant_role_capabilities_capability_idx
  on public.tenant_role_capabilities (capability_code, tenant_id);
create index membership_roles_membership_idx
  on public.membership_roles (tenant_id, membership_id);
create index tenant_invitations_pending_email_idx
  on public.tenant_invitations (tenant_id, email_normalized, expires_at)
  where accepted_at is null and revoked_at is null;

create table public.tenant_invitation_roles (
  tenant_id uuid not null,
  invitation_id uuid not null,
  role_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (tenant_id, invitation_id, role_id),
  constraint tenant_invitation_roles_invitation_fk
    foreign key (tenant_id, invitation_id)
    references public.tenant_invitations(tenant_id, id) on delete cascade,
  constraint tenant_invitation_roles_role_fk
    foreign key (tenant_id, role_id)
    references public.tenant_roles(tenant_id, id) on delete restrict
);

create table public.tenant_security_audit_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  actor_membership_id uuid not null,
  action_code text not null,
  subject_type text not null,
  subject_id uuid,
  details jsonb not null default '{}'::jsonb,
  request_id uuid,
  occurred_at timestamptz not null default now(),
  constraint tenant_security_audit_action_length check (char_length(action_code) between 3 and 100),
  constraint tenant_security_audit_subject_length check (char_length(subject_type) between 2 and 80),
  constraint tenant_security_audit_actor_membership_fk
    foreign key (tenant_id, actor_membership_id, actor_user_id)
    references public.tenant_memberships(tenant_id, id, user_id) on delete restrict
);

create index tenant_security_audit_tenant_time_idx
  on public.tenant_security_audit_events (tenant_id, occurred_at desc);
create index tenant_security_audit_actor_time_idx
  on public.tenant_security_audit_events (actor_user_id, occurred_at desc);

-- Default deny until the dedicated RLS milestone adds reviewed policies.
alter table public.profiles enable row level security;
alter table public.tenants enable row level security;
alter table public.tenant_memberships enable row level security;
alter table public.capabilities enable row level security;
alter table public.tenant_roles enable row level security;
alter table public.tenant_role_capabilities enable row level security;
alter table public.membership_roles enable row level security;
alter table public.tenant_invitations enable row level security;
alter table public.tenant_invitation_roles enable row level security;
alter table public.tenant_security_audit_events enable row level security;

revoke all on table
  public.profiles,
  public.tenants,
  public.tenant_memberships,
  public.capabilities,
  public.tenant_roles,
  public.tenant_role_capabilities,
  public.membership_roles,
  public.tenant_invitations,
  public.tenant_invitation_roles,
  public.tenant_security_audit_events
from anon, authenticated;

commit;
