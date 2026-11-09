#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is required}"

tmp_dir="$(mktemp -d)"
holder_pid=""
cleanup() {
  if [[ -n "$holder_pid" ]]; then
    wait "$holder_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
-- Isolated, committed fixtures are required because the race participants
-- execute in independent PostgreSQL sessions.
insert into auth.users (id, email) values
  ('91000000-0000-0000-0000-000000000001', 'concurrency-a@example.test'),
  ('91000000-0000-0000-0000-000000000002', 'concurrency-b@example.test');
insert into public.tenants (id, name, slug, created_by_user_id) values
  ('92000000-0000-0000-0000-000000000001', 'Concurrency Test', 'concurrency-test',
   '91000000-0000-0000-0000-000000000001');
insert into public.tenant_memberships (id, tenant_id, user_id) values
  ('93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
   '91000000-0000-0000-0000-000000000001'),
  ('93000000-0000-0000-0000-000000000002', '92000000-0000-0000-0000-000000000001',
   '91000000-0000-0000-0000-000000000002');
insert into public.tenant_roles (id, tenant_id, code, name) values
  ('94000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001',
   'concurrency-reviewer', 'Concurrency Reviewer');
insert into public.tenant_role_capabilities (tenant_id, role_id, capability_code)
values ('92000000-0000-0000-0000-000000000001',
        '94000000-0000-0000-0000-000000000001', 'movements.verify');
insert into public.membership_roles (tenant_id, membership_id, role_id) values
  ('92000000-0000-0000-0000-000000000001',
   '93000000-0000-0000-0000-000000000001',
   '94000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-000000000001',
   '93000000-0000-0000-0000-000000000002',
   '94000000-0000-0000-0000-000000000001');
insert into public.tenant_currencies (
  tenant_id, code, name, decimal_places, created_by_membership_id, created_by_user_id
) values (
  '92000000-0000-0000-0000-000000000001', 'USD', 'US Dollar', 2,
  '93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001'
);
insert into public.external_movements (
  id, tenant_id, currency_code, amount, effective_at,
  created_by_membership_id, created_by_user_id
) values
  ('95000000-0000-0000-0000-000000000001',
   '92000000-0000-0000-0000-000000000001', 'USD', 25, now(),
   '93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001');
insert into public.tenant_evidence (
  id, tenant_id, created_by_user_id, bucket_id, object_path, mime_type,
  expected_size_bytes, sha256, status, uploaded_at, verified_at
) values (
  '96000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000001',
  'operation-evidence',
  '92000000-0000-0000-0000-000000000001/96000000-0000-0000-0000-000000000001',
  'image/png', 8, decode(repeat('ef', 32), 'hex'), 'available', now(), now());
SQL

# Move the movement to the state from which two operators can make competing
# final decisions. This is a separate committed command.
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -c "
  set role tucambio_backend;
  select public.command_transition_external_movement(
    '91000000-0000-0000-0000-000000000001',
    '92000000-0000-0000-0000-000000000001',
    '95000000-0000-0000-0000-000000000001',
    'IN_VERIFICATION', 'concurrency-start',
    decode(repeat('01', 32), 'hex')
  );
"

wait_until() {
  local sql="$1"
  local expected="$2"
  for _ in $(seq 1 100); do
    local value
    value="$(psql "$DATABASE_URL" -X -At -v ON_ERROR_STOP=1 -c "$sql")"
    if [[ "$value" == "$expected" ]]; then return 0; fi
    sleep 0.05
  done
  echo "Timed out waiting for PostgreSQL concurrency barrier: $sql" >&2
  return 1
}

start_holder() {
  local app="$1"
  local sql="$2"
  PGAPPNAME="$app" psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -c "$sql" \
    >"$tmp_dir/$app.log" 2>&1 &
  holder_pid=$!
  wait_until "select count(*) from pg_stat_activity where application_name = '$app' and wait_event = 'PgSleep'" "1"
}

wait_for_two_lock_waiters() {
  local app_a="$1"
  local app_b="$2"
  wait_until "select count(*) from pg_stat_activity where application_name in ('$app_a', '$app_b') and wait_event_type = 'Lock'" "2"
}

finish_holder() {
  wait "$holder_pid"
  holder_pid=""
}

run_competing_commands() {
  local label="$1"
  local app_a="$2"
  local sql_a="$3"
  local app_b="$4"
  local sql_b="$5"
  PGAPPNAME="$app_a" psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -c "$sql_a" >"$tmp_dir/$app_a.log" 2>&1 &
  local pid_a=$!
  PGAPPNAME="$app_b" psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -c "$sql_b" >"$tmp_dir/$app_b.log" 2>&1 &
  local pid_b=$!
  set +e
  wait "$pid_a"; local status_a=$?
  wait "$pid_b"; local status_b=$?
  set -e
  if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
    echo "$label: expected exactly one successful command and one rejected command" >&2
    cat "$tmp_dir/$app_a.log" "$tmp_dir/$app_b.log" >&2
    return 1
  fi
  echo "$label: one winner, one rejected stale transition"
}

# Race 1: two operators try opposite final decisions on the same movement.
start_holder "m184-movement-holder" "
  begin;
  select id from public.external_movements
   where id = '95000000-0000-0000-0000-000000000001' for update;
  select pg_sleep(2);
  commit;
"
movement_a="set role tucambio_backend; select public.command_transition_external_movement(
 '91000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001',
 '95000000-0000-0000-0000-000000000001','CONFIRMED','movement-race-a',decode(repeat('02',32),'hex'));"
movement_b="set role tucambio_backend; select public.command_transition_external_movement(
 '91000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000001',
 '95000000-0000-0000-0000-000000000001','NOT_CONFIRMED','movement-race-b',decode(repeat('03',32),'hex'));"
PGAPPNAME="m184-movement-a" psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -c "$movement_a" >"$tmp_dir/m184-movement-a.log" 2>&1 &
pid_a=$!
PGAPPNAME="m184-movement-b" psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -c "$movement_b" >"$tmp_dir/m184-movement-b.log" 2>&1 &
pid_b=$!
wait_for_two_lock_waiters "m184-movement-a" "m184-movement-b"
finish_holder
set +e
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
  echo "Movement race did not serialize to exactly one winner" >&2
  cat "$tmp_dir/m184-movement-a.log" "$tmp_dir/m184-movement-b.log" >&2
  exit 1
fi
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
do $$
begin
  if (select status from public.external_movements
      where id = '95000000-0000-0000-0000-000000000001')
     not in ('CONFIRMED', 'NOT_CONFIRMED') then
    raise exception 'Movement did not reach exactly one final decision';
  end if;
  if (select count(*) from public.financial_domain_events
      where entity_id = '95000000-0000-0000-0000-000000000001'
        and event_type in ('MOVEMENT_CONFIRMED', 'MOVEMENT_NOT_CONFIRMED')) <> 1 then
    raise exception 'Movement race must append exactly one final decision event';
  end if;
end;
$$;
SQL
echo "movement race: one winner, one rejected stale transition"

# Race 2: two operators attempt to start review of the same evidence.
start_holder "m184-evidence-holder" "
  begin;
  select id from public.tenant_evidence
   where id = '96000000-0000-0000-0000-000000000001' for update;
  select pg_sleep(2);
  commit;
"
evidence_a="set role tucambio_backend; select public.command_review_tenant_evidence(
 '91000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001',
 '96000000-0000-0000-0000-000000000001','EN_REVISION',null,'evidence-race-a',decode(repeat('04',32),'hex'));"
evidence_b="set role tucambio_backend; select public.command_review_tenant_evidence(
 '91000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000001',
 '96000000-0000-0000-0000-000000000001','EN_REVISION',null,'evidence-race-b',decode(repeat('05',32),'hex'));"
PGAPPNAME="m184-evidence-a" psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -c "$evidence_a" >"$tmp_dir/m184-evidence-a.log" 2>&1 &
pid_a=$!
PGAPPNAME="m184-evidence-b" psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -c "$evidence_b" >"$tmp_dir/m184-evidence-b.log" 2>&1 &
pid_b=$!
wait_for_two_lock_waiters "m184-evidence-a" "m184-evidence-b"
finish_holder
set +e
wait "$pid_a"; status_a=$?
wait "$pid_b"; status_b=$?
set -e
if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] || [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
  echo "Evidence race did not serialize to exactly one winner" >&2
  cat "$tmp_dir/m184-evidence-a.log" "$tmp_dir/m184-evidence-b.log" >&2
  exit 1
fi
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
do $$
begin
  if (select review_status from public.tenant_evidence
      where id = '96000000-0000-0000-0000-000000000001') <> 'EN_REVISION' then
    raise exception 'Evidence race did not persist EN_REVISION';
  end if;
  if (select count(*) from public.evidence_review_events
      where evidence_id = '96000000-0000-0000-0000-000000000001'
        and to_status = 'EN_REVISION') <> 1 then
    raise exception 'Evidence race must append exactly one review event';
  end if;
end;
$$;
SQL
echo "evidence race: one winner, one rejected stale transition"

# Race 3: simultaneous identical requests share one idempotency result.
# The test holds the exact advisory lock used by claim_financial_command until
# both request sessions are waiting, then releases them together.
idempotency_lock="92000000-0000-0000-0000-000000000001:91000000-0000-0000-0000-000000000001:REVIEW_TENANT_EVIDENCE:evidence-idem-race"
start_holder "m184-idem-holder" "
  select pg_advisory_lock(hashtextextended('$idempotency_lock', 0));
  select pg_sleep(2);
  select pg_advisory_unlock(hashtextextended('$idempotency_lock', 0));
"
idem_sql="set role tucambio_backend; select public.command_review_tenant_evidence(
 '91000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001',
 '96000000-0000-0000-0000-000000000001','EN_REVISION',null,'evidence-idem-race',decode(repeat('06',32),'hex'));"
PGAPPNAME="m184-idem-a" psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -c "$idem_sql" >"$tmp_dir/m184-idem-a.log" 2>&1 &
pid_a=$!
PGAPPNAME="m184-idem-b" psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -c "$idem_sql" >"$tmp_dir/m184-idem-b.log" 2>&1 &
pid_b=$!
wait_for_two_lock_waiters "m184-idem-a" "m184-idem-b"
finish_holder
wait "$pid_a"
wait "$pid_b"
if [[ "$(grep -h -c '"replayed": false' "$tmp_dir/m184-idem-"*.log | awk -F: '{s += $NF} END {print s+0}')" -ne 1 ]] ||
   [[ "$(grep -h -c '"replayed": true' "$tmp_dir/m184-idem-"*.log | awk -F: '{s += $NF} END {print s+0}')" -ne 1 ]]; then
  echo "Concurrent idempotent retry did not return one original and one replay" >&2
  cat "$tmp_dir/m184-idem-a.log" "$tmp_dir/m184-idem-b.log" >&2
  exit 1
fi
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -c "
  do \$\$
  begin
    if (select count(*) from public.evidence_review_events
        where evidence_id = '96000000-0000-0000-0000-000000000001') <> 1 then
      raise exception 'Idempotent race must not duplicate review events';
    end if;
    if (select count(*) from public.financial_command_idempotency
        where tenant_id = '92000000-0000-0000-0000-000000000001'
          and actor_user_id = '91000000-0000-0000-0000-000000000001'
          and command_type = 'REVIEW_TENANT_EVIDENCE'
          and idempotency_key = 'evidence-idem-race') <> 1 then
      raise exception 'Idempotent race must persist exactly one command result';
    end if;
  end;
  \$\$;
"
echo "idempotency race: one original result, one replay, one audit event"
echo "M1.8.4 PostgreSQL concurrency assertions passed"
