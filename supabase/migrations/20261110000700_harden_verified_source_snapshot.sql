-- TuCambio M1.8.4.1: tighten verified-source snapshot constraints and trigger-function privileges.
begin;

alter table public.financial_operations
  drop constraint financial_operations_verified_source_pair,
  add constraint financial_operations_verified_source_pair
    check (
      (verified_source_movement_id is null and verified_source_amount is null)
      or
      (
        verified_source_movement_id is not null
        and verified_source_amount is not null
        and verified_source_amount > 0
      )
    );

revoke all on function public.protect_verified_source_amount_snapshot() from public, anon, authenticated;
revoke all on function public.capture_confirmed_origin_amount() from public, anon, authenticated;

commit;
