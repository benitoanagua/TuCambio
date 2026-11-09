-- TuCambio: private object bucket for operation evidence.
-- Access remains deny-by-default until tenant membership policies are introduced
-- alongside the canonical tenant schema. Trusted backend only in this phase.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'operation-evidence',
  'operation-evidence',
  false,
  10485760, -- 10 MiB application limit; below Supabase Free's 50 MB ceiling.
  array[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp'
  ]::text[]
)
on conflict (id) do update
set
  name = excluded.name,
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Intentionally no permissive storage.objects policies here.
-- Supabase Storage denies uploads without an applicable RLS policy.
-- Add tenant-aware SELECT/INSERT/UPDATE/DELETE policies only after the
-- canonical tenant membership table and trusted JWT claims are implemented.
-- Until then, all file operations must go through the authenticated,
-- authorization-enforcing Kotlin/Ktor backend using server-only credentials.
