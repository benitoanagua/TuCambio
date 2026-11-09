-- Minimal Supabase-compatible schemas for migration integration tests.
create role anon nologin;
create role authenticated nologin;
create role tucambio_backend nologin;

create schema auth;
create table auth.users (
  id uuid primary key,
  email text
);

create schema storage;
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);

-- Minimal Storage objects contract used by M1.6 policy tests.
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null references storage.buckets(id),
  name text not null,
  owner_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (bucket_id, name)
);

-- Supabase Auth helper used by RLS policies in a managed project.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
