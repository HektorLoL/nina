begin;

create extension if not exists pgtap with schema extensions;

select plan(54);

select has_table(
  'public',
  'waitlist_signups',
  'waitlist signups are stored in a dedicated table'
);

select has_table(
  'public',
  'waitlist_submission_limits',
  'anonymous submission limits are stored separately'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.waitlist_signups'::regclass
  ),
  'waitlist signups have row level security enabled'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.waitlist_submission_limits'::regclass
  ),
  'waitlist rate limits have row level security enabled'
);

select ok(
  not has_table_privilege('anon', 'public.waitlist_signups', 'select'),
  'anonymous users cannot enumerate waitlist emails'
);

select ok(
  not has_table_privilege('authenticated', 'public.waitlist_signups', 'select'),
  'authenticated users cannot enumerate waitlist emails'
);

select ok(
  not has_table_privilege('anon', 'public.waitlist_submission_limits', 'select'),
  'anonymous users cannot inspect abuse fingerprints'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.register_waitlist_signup(text,text,boolean,text,text,text,text)',
    'execute'
  ),
  'anonymous clients cannot bypass the worker and its abuse controls'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.register_waitlist_signup(text,text,boolean,text,text,text,text)',
    'execute'
  ),
  'authenticated clients cannot bypass the worker and its abuse controls'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.register_waitlist_signup(text,text,boolean,text,text,text,text)',
    'execute'
  ),
  'the trusted website worker can execute the signup RPC'
);

select has_column(
  'public',
  'waitlist_signups',
  'unsubscribe_token',
  'waitlist signups have a private cancellation capability'
);

select has_column(
  'public',
  'waitlist_signups',
  'unsubscribed_at',
  'consent withdrawal is timestamped'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.unsubscribe_waitlist_signup(text)',
    'execute'
  ),
  'anonymous clients cannot call the unsubscribe RPC directly'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.unsubscribe_waitlist_signup(text)',
    'execute'
  ),
  'authenticated clients cannot call the unsubscribe RPC directly'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.unsubscribe_waitlist_signup(text)',
    'execute'
  ),
  'the trusted website worker can execute the unsubscribe RPC'
);

select has_function(
  'public',
  'waitlist_healthcheck',
  array[]::text[],
  'the waitlist exposes a dedicated read-only service health RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.waitlist_healthcheck()',
    'execute'
  ),
  'anonymous clients cannot call the waitlist health RPC directly'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.waitlist_healthcheck()',
    'execute'
  ),
  'authenticated clients cannot call the waitlist health RPC directly'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.waitlist_healthcheck()',
    'execute'
  ),
  'the trusted website worker can execute the waitlist health RPC'
);

set local role service_role;

select is(
  public.waitlist_healthcheck() ->> 'ready',
  'true',
  'the waitlist health RPC reports ready for the current schema'
);

select is(
  public.waitlist_healthcheck() ->> 'schema_version',
  '2026-08-02',
  'the waitlist health RPC identifies the expected schema contract'
);

select throws_ok(
  $$
    select public.register_waitlist_signup(
      'not-an-email',
      null,
      true,
      '2026-07-29',
      'landing',
      'pt-BR',
      repeat('a', 64)
    )
  $$,
  '22023',
  'waitlist_email_invalid',
  'the RPC rejects invalid email addresses'
);

select throws_ok(
  $$
    select public.register_waitlist_signup(
      'person@example.com',
      null,
      false,
      '2026-07-29',
      'landing',
      'pt-BR',
      repeat('a', 64)
    )
  $$,
  '22023',
  'waitlist_consent_required',
  'the RPC requires explicit consent'
);

select lives_ok(
  $$
    select public.register_waitlist_signup(
      '  Person@Example.COM ',
      '  Ana   Maria  ',
      true,
      '2026-07-29',
      'landing',
      'pt-BR',
      repeat('a', 64)
    )
  $$,
  'a valid worker-submitted signup is accepted'
);

reset role;

select is(
  (select email from public.waitlist_signups limit 1),
  'person@example.com',
  'email addresses are normalized before storage'
);

select is(
  (select first_name from public.waitlist_signups limit 1),
  'Ana Maria',
  'optional names are whitespace-normalized'
);

select ok(
  (
    select unsubscribe_token ~ '^[0-9a-f]{64}$'
    from public.waitlist_signups
    where email = 'person@example.com'
  ),
  'new signups receive a valid opaque cancellation capability'
);

create temporary table waitlist_test_tokens (
  label text primary key,
  token text not null
);

grant select on waitlist_test_tokens to service_role;

insert into waitlist_test_tokens (label, token)
select 'original', unsubscribe_token
from public.waitlist_signups
where email = 'person@example.com';

set local role service_role;

select lives_ok(
  $$
    select public.register_waitlist_signup(
      'person@example.com',
      'Ana',
      true,
      '2026-07-29',
      'footer',
      'pt-BR',
      repeat('a', 64)
    )
  $$,
  'submitting the same email again remains safe'
);

reset role;

select is(
  (select count(*)::integer from public.waitlist_signups),
  1,
  'duplicate emails are deduplicated'
);

select is(
  (select first_name from public.waitlist_signups limit 1),
  'Ana',
  'a fresh consent submission updates the existing signup'
);

select isnt(
  (
    select unsubscribe_token
    from public.waitlist_signups
    where email = 'person@example.com'
  ),
  (select token from waitlist_test_tokens where label = 'original'),
  'renewed consent invalidates the previous cancellation capability'
);

insert into waitlist_test_tokens (label, token)
select 'renewed', unsubscribe_token
from public.waitlist_signups
where email = 'person@example.com';

set local role service_role;

select is(
  public.unsubscribe_waitlist_signup(
    (select token from waitlist_test_tokens where label = 'original')
  ) ->> 'accepted',
  'true',
  'a stale cancellation capability receives a generic accepted response'
);

reset role;

select is(
  (
    select status
    from public.waitlist_signups
    where email = 'person@example.com'
  ),
  'subscribed',
  'a stale cancellation capability cannot withdraw renewed consent'
);

set local role service_role;

select is(
  public.unsubscribe_waitlist_signup(
    (select token from waitlist_test_tokens where label = 'renewed')
  ) ->> 'accepted',
  'true',
  'the current cancellation capability receives an accepted response'
);

reset role;

select is(
  (
    select status
    from public.waitlist_signups
    where email = 'person@example.com'
  ),
  'unsubscribed',
  'the current cancellation capability withdraws consent'
);

select ok(
  (
    select unsubscribed_at is not null
    from public.waitlist_signups
    where email = 'person@example.com'
  ),
  'withdrawal records its completion time'
);

set local role service_role;

select is(
  public.unsubscribe_waitlist_signup(repeat('f', 64)) ->> 'accepted',
  'true',
  'an unknown cancellation capability receives the same response'
);

select lives_ok(
  $$
    select public.register_waitlist_signup(
      'person@example.com',
      'Ana',
      true,
      '2026-07-29',
      'footer',
      'pt-BR',
      repeat('a', 64)
    )
  $$,
  'explicit renewed consent can restore a withdrawn signup'
);

reset role;

select is(
  (
    select status
    from public.waitlist_signups
    where email = 'person@example.com'
  ),
  'subscribed',
  'renewed consent restores subscribed status'
);

select ok(
  (
    select unsubscribed_at is null
    from public.waitlist_signups
    where email = 'person@example.com'
  ),
  'renewed consent clears the withdrawal timestamp'
);

select isnt(
  (
    select unsubscribe_token
    from public.waitlist_signups
    where email = 'person@example.com'
  ),
  (select token from waitlist_test_tokens where label = 'renewed'),
  'renewed consent rotates the used cancellation capability'
);

set local role service_role;

select is(
  (
    select bool_and(
      (
        public.register_waitlist_signup(
          format('rate-%s@example.com', attempt),
          null,
          true,
          '2026-07-29',
          'landing',
          'pt-BR',
          repeat('b', 64)
        ) ->> 'accepted'
      )::boolean
    )
    from generate_series(1, 5) as attempts(attempt)
  ),
  true,
  'the first five submissions in an hour are accepted'
);

select is(
  public.register_waitlist_signup(
    'rate-limited@example.com',
    null,
    true,
    '2026-07-29',
    'landing',
    'pt-BR',
    repeat('b', 64)
  ) ->> 'reason',
  'rate_limited',
  'the sixth submission receives a committed generic rate limit result'
);

reset role;

select is(
  (
    select attempts
    from public.waitlist_submission_limits
    where fingerprint = repeat('b', 64)
  ),
  6,
  'rate limit attempts remain recorded after throttling'
);

select hasnt_column(
  'public',
  'waitlist_signups',
  'ip_address',
  'waitlist rows do not store raw IP addresses'
);

select hasnt_column(
  'public',
  'waitlist_submission_limits',
  'email',
  'short-lived abuse limits are not linked to email addresses'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.run_waitlist_retention()',
    'execute'
  ),
  'only the maintenance service can run waitlist retention'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.run_waitlist_retention()',
    'execute'
  ),
  'anonymous users cannot run waitlist retention'
);

set local role service_role;

select lives_ok(
  $$
    select public.register_waitlist_signup(
      'withdrawal@example.com',
      null,
      true,
      '2026-07-29',
      'landing',
      'pt-BR',
      repeat('c', 64)
    )
  $$,
  'a separate signup can exercise withdrawal retention'
);

select is(
  public.unsubscribe_waitlist_signup(
    (
      select unsubscribe_token
      from public.waitlist_signups
      where email = 'withdrawal@example.com'
    )
  ) ->> 'accepted',
  'true',
  'the separate signup can withdraw consent'
);

reset role;

update public.waitlist_signups
set last_submitted_at = now() - interval '25 months'
where email = 'person@example.com';

update public.waitlist_submission_limits
set expires_at = now() - interval '1 minute'
where fingerprint = repeat('b', 64);

select lives_ok(
  $$select public.run_waitlist_retention()$$,
  'waitlist retention completes'
);

select is(
  (
    select count(*)::integer
    from public.waitlist_signups
    where email = 'person@example.com'
  ),
  0,
  'consent records older than 24 months are removed'
);

select is(
  (
    select count(*)::integer
    from public.waitlist_signups
    where email = 'withdrawal@example.com'
  ),
  0,
  'withdrawn consent records are removed by retention'
);

select is(
  (
    select count(*)::integer
    from public.waitlist_submission_limits
    where fingerprint = repeat('b', 64)
  ),
  0,
  'expired anonymous rate limit fingerprints are removed'
);

select * from finish();
rollback;
