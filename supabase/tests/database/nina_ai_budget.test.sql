begin;

create extension if not exists pgtap with schema extensions;

select plan(55);

insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
values
  ('e1000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'budget-a1@example.com', '{"full_name":"Titular Um"}'::jsonb, now(), now()),
  ('e1000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'budget-a2@example.com', '{"full_name":"Parceiro Um"}'::jsonb, now(), now()),
  ('e1000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'budget-b1@example.com', '{"full_name":"Titular Dois"}'::jsonb, now(), now()),
  ('e1000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'budget-b2@example.com', '{"full_name":"Parceiro Dois"}'::jsonb, now(), now()),
  ('e1000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'budget-c1@example.com', '{"full_name":"Titular Tres"}'::jsonb, now(), now()),
  ('e1000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'budget-c2@example.com', '{"full_name":"Parceiro Tres"}'::jsonb, now(), now());

insert into private.account_age_status (user_id, status, assurance, recheck_after)
select users.id, 'adult', 'confirmed', now() + interval '180 days'
from auth.users as users
where users.id::text like 'e1000000-%'
on conflict (user_id) do nothing;

insert into public.families (id, name, invite_code, created_by)
values
  ('e2000000-0000-4000-8000-000000000001', 'Casa Um', 'casa-e2000000000000000000000000000001', 'e1000000-0000-4000-8000-000000000001'),
  ('e2000000-0000-4000-8000-000000000002', 'Casa Dois', 'casa-e2000000000000000000000000000002', 'e1000000-0000-4000-8000-000000000003'),
  ('e2000000-0000-4000-8000-000000000003', 'Casa Tres', 'casa-e2000000000000000000000000000003', 'e1000000-0000-4000-8000-000000000005');

insert into public.family_members (family_id, user_id, name, relationship, household_role, permission_role, tone)
values
  ('e2000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'Titular Um', 'Titular', 'adult', 'owner', 'mint'),
  ('e2000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000002', 'Parceiro Um', 'Parceiro', 'adult', 'member', 'sky'),
  ('e2000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000003', 'Titular Dois', 'Titular', 'adult', 'owner', 'mint'),
  ('e2000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000004', 'Parceiro Dois', 'Parceiro', 'adult', 'member', 'sky'),
  ('e2000000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000005', 'Titular Tres', 'Titular', 'adult', 'owner', 'mint'),
  ('e2000000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000006', 'Parceiro Tres', 'Parceiro', 'adult', 'member', 'sky');

insert into public.nina_ai_consents (family_id, user_id, policy_version, transfer_consented_at)
select members.family_id, members.user_id, '2026-09-29', now()
from public.family_members as members
where members.user_id::text like 'e1000000-%';

update public.profiles
set active_family_id = members.family_id
from public.family_members as members
where members.user_id = profiles.id
  and members.user_id::text like 'e1000000-%';

insert into public.premium_subscriptions (
  original_transaction_id,
  user_id,
  product_id,
  environment,
  status,
  is_active,
  transaction_id,
  expires_at,
  signed_transaction_info
)
values
  ('budget-original-1', 'e1000000-0000-4000-8000-000000000001', 'com.heitor.nina.premium.monthly', 'Sandbox', 'active', true, 'budget-transaction-1', now() + interval '30 days', 'signed-transaction-info-example'),
  ('budget-original-2', 'e1000000-0000-4000-8000-000000000003', 'com.heitor.nina.premium.monthly', 'Sandbox', 'active', true, 'budget-transaction-2', now() + interval '30 days', 'signed-transaction-info-example'),
  ('budget-original-3', 'e1000000-0000-4000-8000-000000000005', 'com.heitor.nina.premium.monthly', 'Sandbox', 'active', true, 'budget-transaction-3', now() + interval '30 days', 'signed-transaction-info-example');

insert into public.tasks (family_id, title, created_at)
select houses.id, 'Tarefa da semana passada ' || slot::text, now() - interval '7 days'
from public.families as houses
cross join generate_series(1, 5) as slot
where houses.id::text like 'e2000000-%';

select is(
  (
    select interactive_cap_microusd::text
      || ':' || insights_cap_microusd::text
      || ':' || household_interactive_cap_microusd::text
    from private.nina_ai_budget_settings
    where singleton
  ),
  '50000000:10000000:5000000',
  'the budget row holds US$50 for conversations, US$10 for insights and US$5 for one house'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'private.nina_ai_budget_settings'::regclass)
    and (select relrowsecurity from pg_class where oid = 'private.nina_ai_household_budget_months'::regclass),
  'both budget tables keep row level security on'
);

select ok(
  not exists (
    select 1
    from (values ('anon'), ('authenticated'), ('service_role')) as roles(name)
    cross join (
      values
        ('private.nina_ai_budget_settings'),
        ('private.nina_ai_household_budget_months')
    ) as tables(name)
    where has_table_privilege(
      roles.name,
      tables.name,
      'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
    )
  ),
  'no API role reads or writes the budget settings or any house share'
);

select ok(
  not exists (
    select 1
    from (values ('public'), ('anon'), ('authenticated'), ('service_role')) as roles(name)
    cross join (
      values
        ('private.current_month_start()'),
        ('private.invoke_nina_maintenance()')
    ) as routines(signature)
    where has_function_privilege(roles.name, routines.signature, 'execute')
  ),
  'neither PUBLIC nor any API role executes the month helper or the maintenance trigger'
);

select ok(
  not exists (
    select 1
    from (values ('public'), ('anon'), ('authenticated'), ('service_role')) as roles(name)
    cross join (
      values
        ('private.nina_insight_period_start(timestamp with time zone)'),
        ('private.settle_abandoned_ai_runs()'),
        ('private.settle_household_ai_runs(uuid)')
    ) as routines(signature)
    where has_function_privilege(roles.name, routines.signature, 'execute')
  ),
  'the week helper and both settlement sweeps run only inside the server''s own functions'
);

select throws_ok(
  $$update private.nina_ai_budget_settings
    set household_interactive_cap_microusd = 5000001
    where singleton$$,
  '23514',
  null,
  'one house can never be given more than a tenth of the conversation pool'
);

select is(
  private.nina_insight_period_start('2026-10-19 02:59:59+00'),
  '2026-10-05'::date,
  'at 23:59 on a Sunday in São Paulo the last whole week is the one before the week now ending'
);

select is(
  private.nina_insight_period_start('2026-10-19 03:00:00+00'),
  '2026-10-12'::date,
  'from Monday 00:00 in São Paulo the last whole week is the one that just ended'
);

set local role authenticated;
set local request.jwt.claim.sub = 'e1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select set_config(
    'test.completed_run',
    public.begin_nina_chat_run(
      'e2000000-0000-4000-8000-000000000001',
      'e3000000-0000-4000-8000-000000000001',
      'Primeira mensagem',
      '[]'::jsonb,
      'gpt-6-luna',
      1000,
      '2026-09-23'
    ) ->> 'run_id',
    true
  )$$,
  'an adult reserves a turn against the house share and the pool'
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (
    select cap_microusd::text || ':' || reserved_microusd::text || ':' || spent_microusd::text
    from private.nina_ai_household_budget_months
    where family_id = 'e2000000-0000-4000-8000-000000000001'
      and month_start = private.current_month_start()
  ),
  '5000000:1000:0',
  'the reservation is held on the house share, capped at the house cap'
);

select is(
  (
    select cap_microusd::text || ':' || reserved_microusd::text || ':' || spent_microusd::text
    from public.nina_ai_budget_months
    where month_start = private.current_month_start()
      and purpose = 'interactive'
  ),
  '50000000:1000:0',
  'the same reservation is held on the pool, capped at the conversation cap'
);

select lives_ok(
  $$select public.complete_nina_chat_run(
    current_setting('test.completed_run')::uuid,
    'e4000000-0000-4000-8000-000000000001',
    'Anotado.',
    '[]'::jsonb,
    100,
    0,
    20,
    0,
    400,
    50
  )$$,
  'the server completes the turn'
);

select is(
  (
    select (
      select reserved_microusd::text || ':' || spent_microusd::text
      from private.nina_ai_household_budget_months
      where family_id = 'e2000000-0000-4000-8000-000000000001'
        and month_start = private.current_month_start()
    ) || '/' || (
      select reserved_microusd::text || ':' || spent_microusd::text
      from public.nina_ai_budget_months
      where month_start = private.current_month_start()
        and purpose = 'interactive'
    )
  ),
  '0:400/0:400',
  'a completed turn releases its reservation and books what it cost on the house share and the pool'
);

set local role authenticated;
set local request.jwt.claim.sub = 'e1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select set_config(
    'test.failed_run',
    public.begin_nina_chat_run(
      'e2000000-0000-4000-8000-000000000001',
      'e3000000-0000-4000-8000-000000000002',
      'Mensagem que falha',
      '[]'::jsonb,
      'gpt-6-luna',
      2000,
      '2026-09-23'
    ) ->> 'run_id',
    true
  )$$,
  'a second turn reserves before the provider fails'
);

reset role;
set local request.jwt.claim.sub = '';

select lives_ok(
  $$select public.record_failed_nina_ai_run(
    current_setting('test.failed_run')::uuid,
    'provider_timeout',
    100,
    0,
    10,
    0,
    700,
    900
  )$$,
  'the server records the failed turn'
);

select is(
  (
    select (
      select reserved_microusd::text || ':' || spent_microusd::text
      from private.nina_ai_household_budget_months
      where family_id = 'e2000000-0000-4000-8000-000000000001'
        and month_start = private.current_month_start()
    ) || '/' || (
      select reserved_microusd::text || ':' || spent_microusd::text
      from public.nina_ai_budget_months
      where month_start = private.current_month_start()
        and purpose = 'interactive'
    )
  ),
  '0:1100/0:1100',
  'a failed turn releases its reservation and books what the provider charged on the house share and the pool'
);

update private.nina_ai_household_budget_months
set spent_microusd = 4999500
where family_id = 'e2000000-0000-4000-8000-000000000001'
  and month_start = private.current_month_start();

set local role authenticated;
set local request.jwt.claim.sub = 'e1000000-0000-4000-8000-000000000001';

select throws_ok(
  $$select public.begin_nina_chat_run(
    'e2000000-0000-4000-8000-000000000001',
    'e3000000-0000-4000-8000-000000000003',
    'Mensagem além da parte da casa',
    '[]'::jsonb,
    'gpt-6-luna',
    1000,
    '2026-09-23'
  )$$,
  'P0001',
  'nina_budget_exceeded',
  'a house past its share is refused with the code every build reads as a paused conversation'
);

reset role;
set local request.jwt.claim.sub = '';

select ok(
  not exists (
    select 1 from public.nina_ai_runs
    where request_message_id = 'e3000000-0000-4000-8000-000000000003'
  )
    and not exists (
      select 1 from public.chat_messages
      where id = 'e3000000-0000-4000-8000-000000000003'
    )
    and (
      select reserved_microusd
      from public.nina_ai_budget_months
      where month_start = private.current_month_start()
        and purpose = 'interactive'
    ) = 0,
  'a refused turn keeps no run, no message and no reservation on the pool'
);

set local role authenticated;
set local request.jwt.claim.sub = 'e1000000-0000-4000-8000-000000000003';

select lives_ok(
  $$select set_config(
    'test.other_house_run',
    public.begin_nina_chat_run(
      'e2000000-0000-4000-8000-000000000002',
      'e3000000-0000-4000-8000-000000000004',
      'A outra casa segue conversando',
      '[]'::jsonb,
      'gpt-6-luna',
      1000,
      '2026-09-23'
    ) ->> 'run_id',
    true
  )$$,
  'another house keeps talking while one house is paused'
);

reset role;
set local request.jwt.claim.sub = '';

select lives_ok(
  $$update private.nina_ai_budget_settings
    set interactive_cap_microusd = 60000000,
        household_interactive_cap_microusd = 6000000
    where singleton$$,
  'one statement raises the pool and the house share together'
);

set local role authenticated;
set local request.jwt.claim.sub = 'e1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select set_config(
    'test.raised_run',
    public.begin_nina_chat_run(
      'e2000000-0000-4000-8000-000000000001',
      'e3000000-0000-4000-8000-000000000005',
      'Depois de subir o teto',
      '[]'::jsonb,
      'gpt-6-luna',
      1000,
      '2026-09-23'
    ) ->> 'run_id',
    true
  )$$,
  'a raised cap lets the paused house talk again in the same month'
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (
    select (
      select cap_microusd::text || ':' || reserved_microusd::text
      from private.nina_ai_household_budget_months
      where family_id = 'e2000000-0000-4000-8000-000000000001'
        and month_start = private.current_month_start()
    ) || '/' || (
      select cap_microusd::text
      from public.nina_ai_budget_months
      where month_start = private.current_month_start()
        and purpose = 'interactive'
    )
  ),
  '6000000:1000/60000000',
  'this month''s rows carry the raised caps from the next reservation on'
);

select lives_ok(
  $$select private.settle_household_ai_runs('e2000000-0000-4000-8000-000000000001')$$,
  'settling a house that is being deleted completes'
);

select is(
  (
    select (
      select reserved_microusd::text || ':' || spent_microusd::text
      from private.nina_ai_household_budget_months
      where family_id = 'e2000000-0000-4000-8000-000000000001'
        and month_start = private.current_month_start()
    ) || '/' || (
      select status || ':' || error_code || ':' || actual_microusd::text
      from public.nina_ai_runs
      where id = current_setting('test.raised_run')::uuid
    )
  ),
  '0:5000500/failed:family_deleted:1000',
  'a run left open by a house deletion books its reservation as spent on the house share too'
);

select is(
  (
    select reserved_microusd::text || ':' || spent_microusd::text
    from public.nina_ai_budget_months
    where month_start = private.current_month_start()
      and purpose = 'interactive'
  ),
  '1000:2100',
  'the pool books the deleted house''s open run as spent and still holds the other house''s turn'
);

insert into private.nina_ai_household_budget_months (
  family_id,
  month_start,
  cap_microusd,
  reserved_microusd,
  spent_microusd
)
values (
  'e2000000-0000-4000-8000-000000000002',
  (private.current_month_start() - interval '1 month')::date,
  5000000,
  3000,
  0
);

insert into public.nina_ai_budget_months (
  month_start,
  purpose,
  cap_microusd,
  reserved_microusd,
  spent_microusd
)
values (
  (private.current_month_start() - interval '1 month')::date,
  'interactive',
  20000000,
  3000,
  0
)
on conflict (month_start, purpose) do update
set reserved_microusd = excluded.reserved_microusd, spent_microusd = 0;

insert into public.nina_ai_runs (
  id,
  family_id,
  user_id,
  purpose,
  model,
  status,
  pricing_version,
  reserved_microusd,
  budget_month_start
)
values (
  'e5000000-0000-4000-8000-000000000001',
  'e2000000-0000-4000-8000-000000000002',
  'e1000000-0000-4000-8000-000000000003',
  'interactive',
  'gpt-6-luna',
  'running',
  '2026-09-23',
  3000,
  (private.current_month_start() - interval '1 month')::date
);

select lives_ok(
  $$select public.record_failed_nina_ai_run(
    'e5000000-0000-4000-8000-000000000001',
    'provider_timeout',
    0,
    0,
    0,
    0,
    1200,
    900
  )$$,
  'a turn reserved last month fails after the month turned'
);

select is(
  (
    select (
      select reserved_microusd::text || ':' || spent_microusd::text
      from private.nina_ai_household_budget_months
      where family_id = 'e2000000-0000-4000-8000-000000000002'
        and month_start = (private.current_month_start() - interval '1 month')::date
    ) || '/' || (
      select reserved_microusd::text || ':' || spent_microusd::text
      from private.nina_ai_household_budget_months
      where family_id = 'e2000000-0000-4000-8000-000000000002'
        and month_start = private.current_month_start()
    )
  ),
  '0:1200/1000:0',
  'a house share settles in the month it reserved in and never charges the new month'
);

update private.nina_ai_household_budget_months
set reserved_microusd = reserved_microusd + 4500
where family_id = 'e2000000-0000-4000-8000-000000000002'
  and month_start = private.current_month_start();

update public.nina_ai_budget_months
set reserved_microusd = reserved_microusd + 4500
where month_start = private.current_month_start()
  and purpose = 'interactive';

insert into public.nina_ai_runs (
  id,
  family_id,
  user_id,
  purpose,
  model,
  status,
  pricing_version,
  reserved_microusd,
  budget_month_start,
  created_at
)
values
  (
    'e5000000-0000-4000-8000-000000000002',
    'e2000000-0000-4000-8000-000000000002',
    'e1000000-0000-4000-8000-000000000003',
    'interactive',
    'gpt-6-luna',
    'running',
    '2026-09-23',
    4000,
    private.current_month_start(),
    now() - interval '16 minutes'
  ),
  (
    'e5000000-0000-4000-8000-000000000003',
    'e2000000-0000-4000-8000-000000000002',
    'e1000000-0000-4000-8000-000000000003',
    'interactive',
    'gpt-6-luna',
    'reserved',
    '2026-09-23',
    500,
    private.current_month_start(),
    now() - interval '14 minutes'
  );

select is(
  public.run_nina_retention() ->> 'abandoned_runs',
  '1',
  'the daily retention settles the one run left open for more than fifteen minutes'
);

select is(
  (
    select string_agg(
      status || ':' || coalesce(error_code, '-') || ':' || coalesce(actual_microusd::text, '-'),
      ',' order by id
    )
    from public.nina_ai_runs
    where id in (
      'e5000000-0000-4000-8000-000000000002',
      'e5000000-0000-4000-8000-000000000003'
    )
  ),
  'failed:run_abandoned:4000,reserved:-:-',
  'an abandoned run is failed with its reservation as its cost, and a younger one is left to finish'
);

select is(
  (
    select (
      select reserved_microusd::text || ':' || spent_microusd::text
      from private.nina_ai_household_budget_months
      where family_id = 'e2000000-0000-4000-8000-000000000002'
        and month_start = private.current_month_start()
    ) || '/' || (
      select reserved_microusd::text || ':' || spent_microusd::text
      from public.nina_ai_budget_months
      where month_start = private.current_month_start()
        and purpose = 'interactive'
    )
  ),
  '1500:4000/1500:6100',
  'an abandoned run moves from reserved to spent on the house share and the pool, so neither cap shrinks or grows'
);

select is(
  public.run_nina_retention() ->> 'abandoned_runs',
  '0',
  'a settled run is never settled twice'
);

select throws_ok(
  $$update private.nina_ai_household_budget_months
    set spent_microusd = cap_microusd
    where family_id = 'e2000000-0000-4000-8000-000000000002'
      and month_start = private.current_month_start()$$,
  '23514',
  null,
  'a house share can never hold more than its cap'
);

select is(
  (
    select coalesce(
      jsonb_agg(candidate.metrics ->> 'family_id' order by candidate.position),
      '[]'::jsonb
    )
    from jsonb_array_elements(public.get_nina_weekly_candidates())
      with ordinality as candidate(metrics, position)
  ),
  '["e2000000-0000-4000-8000-000000000001", "e2000000-0000-4000-8000-000000000002", "e2000000-0000-4000-8000-000000000003"]'::jsonb,
  'houses nobody has tried this week and that never had an insight come in a stable order'
);

select is(
  (
    select string_agg(
      (candidate.metrics ->> 'period_start') || '..' || (candidate.metrics ->> 'period_end'),
      ',' order by candidate.metrics ->> 'family_id'
    )
    from jsonb_array_elements(public.get_nina_weekly_candidates()) as candidate(metrics)
  ),
  (
    select string_agg(week.text, ',')
    from (
      select private.nina_insight_period_start(now())::text
        || '..' || (private.nina_insight_period_start(now()) + 6)::text as text
      from generate_series(1, 3)
    ) as week
  ),
  'every candidate describes the last whole Monday-to-Sunday week in São Paulo'
);

select is(
  (
    select (private.nina_weekly_metrics('e2000000-0000-4000-8000-000000000001') ->> 'tasks_created')::integer
  ),
  5,
  'the metrics count what was written in that week'
);

insert into public.tasks (family_id, title)
values ('e2000000-0000-4000-8000-000000000001', 'Tarefa desta semana');

select is(
  (
    select (private.nina_weekly_metrics('e2000000-0000-4000-8000-000000000001') ->> 'tasks_created')::integer
  ),
  5,
  'work written in the week now running waits for next week''s insight'
);

insert into public.household_insights (family_id, title, period_start, period_end)
values
  (
    'e2000000-0000-4000-8000-000000000001',
    'Resumo antigo',
    private.nina_insight_period_start(now()) - 14,
    private.nina_insight_period_start(now()) - 8
  ),
  (
    'e2000000-0000-4000-8000-000000000003',
    'Resumo da semana passada',
    private.nina_insight_period_start(now()),
    private.nina_insight_period_start(now()) + 6
  );

select is(
  (
    select coalesce(
      jsonb_agg(candidate.metrics ->> 'family_id' order by candidate.position),
      '[]'::jsonb
    )
    from jsonb_array_elements(public.get_nina_weekly_candidates())
      with ordinality as candidate(metrics, position)
  ),
  '["e2000000-0000-4000-8000-000000000002", "e2000000-0000-4000-8000-000000000001"]'::jsonb,
  'a house that already has last week''s insight is not chosen again, and a house never given one goes before a house given one before'
);

insert into public.nina_ai_runs (
  family_id,
  purpose,
  model,
  status,
  pricing_version,
  error_code
)
values (
  'e2000000-0000-4000-8000-000000000002',
  'insights',
  'gpt-6-luna',
  'failed',
  '2026-09-23',
  'invalid_assistant_response'
);

select is(
  (
    select coalesce(
      jsonb_agg(candidate.metrics ->> 'family_id' order by candidate.position),
      '[]'::jsonb
    )
    from jsonb_array_elements(public.get_nina_weekly_candidates())
      with ordinality as candidate(metrics, position)
  ),
  '["e2000000-0000-4000-8000-000000000001", "e2000000-0000-4000-8000-000000000002"]'::jsonb,
  'a house whose insight failed this week waits behind every house not yet tried, and is still chosen'
);

set local role service_role;

select lives_ok(
  $$select set_config(
    'test.insight_run',
    public.reserve_nina_insight_run(
      'e2000000-0000-4000-8000-000000000001',
      'gpt-6-luna',
      2000,
      '2026-09-23'
    )::text,
    true
  )$$,
  'the nightly job reserves an insight against the insights cap'
);

reset role;

select is(
  (
    select cap_microusd::text || ':' || reserved_microusd::text
    from public.nina_ai_budget_months
    where month_start = private.current_month_start()
      and purpose = 'insights'
  ),
  '10000000:2000',
  'the insights pool is capped at US$10 a month'
);

set local role service_role;

select lives_ok(
  $$select public.complete_nina_insight_run(
    current_setting('test.insight_run')::uuid,
    '[{"title":"Semana da casa","message":"A casa andou.","metric":"5 tarefas"}]'::jsonb,
    300,
    0,
    50,
    0,
    800,
    1200
  )$$,
  'the nightly job completes the insight'
);

reset role;

select is(
  (
    select period_start::text || '..' || period_end::text
    from public.household_insights
    where source_run_id = current_setting('test.insight_run')::uuid
  ),
  private.nina_insight_period_start(now())::text
    || '..' || (private.nina_insight_period_start(now()) + 6)::text,
  'an insight is stored for the last whole Monday-to-Sunday week, whatever day it was written'
);

select is(
  (
    select reserved_microusd::text || ':' || spent_microusd::text
    from public.nina_ai_budget_months
    where month_start = private.current_month_start()
      and purpose = 'insights'
  ),
  '0:800',
  'a completed insight releases its reservation and books its cost'
);

select is(
  (
    select count(*)::integer
    from private.nina_ai_household_budget_months
    where family_id = 'e2000000-0000-4000-8000-000000000001'
      and month_start = private.current_month_start()
      and reserved_microusd = 0
      and spent_microusd = 5000500
  ),
  1,
  'an insight never draws on a house''s conversation share'
);

select is(
  (
    select coalesce(
      jsonb_agg(candidate.metrics ->> 'family_id' order by candidate.position),
      '[]'::jsonb
    )
    from jsonb_array_elements(public.get_nina_weekly_candidates())
      with ordinality as candidate(metrics, position)
  ),
  '["e2000000-0000-4000-8000-000000000002"]'::jsonb,
  'a house is never processed twice in one week'
);

select ok(
  not exists (
    select 1
    from pg_constraint
    where conrelid = 'private.nina_ai_household_budget_months'::regclass
      and contype = 'f'
      and confdeltype <> 'c'
  ),
  'a house share goes with its house'
);

delete from public.families where id = 'e2000000-0000-4000-8000-000000000001';

select is(
  (
    select count(*)::integer
    from private.nina_ai_household_budget_months
    where family_id = 'e2000000-0000-4000-8000-000000000001'
  ),
  0,
  'a deleted house leaves no share behind'
);

select is(
  (
    select count(*)::integer
    from pg_trigger
    where tgrelid in (
      'private.nina_ai_budget_settings'::regclass,
      'private.nina_ai_household_budget_months'::regclass
    )
      and tgname like '%set_updated_at'
  ),
  2,
  'both budget tables stamp when they last changed'
);

insert into private.nina_ai_household_budget_months (
  family_id,
  month_start,
  cap_microusd,
  reserved_microusd,
  spent_microusd
)
values (
  'e2000000-0000-4000-8000-000000000003',
  private.current_month_start(),
  5000000,
  1000,
  0
);

update private.nina_ai_household_budget_months
set reserved_microusd = reserved_microusd + 700
where family_id = 'e2000000-0000-4000-8000-000000000002'
  and month_start = (private.current_month_start() - interval '1 month')::date;

update public.nina_ai_budget_months
set reserved_microusd = reserved_microusd + case
  when month_start < private.current_month_start() then 700
  when purpose = 'interactive' then 1000
  else 300
end
where month_start >= (private.current_month_start() - interval '1 month')::date;

insert into public.nina_ai_runs (
  id,
  family_id,
  user_id,
  purpose,
  model,
  status,
  pricing_version,
  reserved_microusd,
  budget_month_start,
  created_at
)
values
  (
    'e5000000-0000-4000-8000-000000000004',
    'e2000000-0000-4000-8000-000000000002',
    'e1000000-0000-4000-8000-000000000003',
    'interactive',
    'gpt-6-luna',
    'running',
    '2026-09-23',
    700,
    (private.current_month_start() - interval '1 month')::date,
    now() - interval '20 minutes'
  ),
  (
    'e5000000-0000-4000-8000-000000000005',
    'e2000000-0000-4000-8000-000000000003',
    'e1000000-0000-4000-8000-000000000005',
    'interactive',
    'gpt-6-luna',
    'reserved',
    '2026-09-23',
    900,
    private.current_month_start(),
    now() - interval '30 minutes'
  ),
  (
    'e5000000-0000-4000-8000-000000000006',
    'e2000000-0000-4000-8000-000000000003',
    'e1000000-0000-4000-8000-000000000006',
    'interactive',
    'gpt-6-luna',
    'running',
    '2026-09-23',
    100,
    private.current_month_start(),
    now() - interval '16 minutes'
  ),
  (
    'e5000000-0000-4000-8000-000000000007',
    'e2000000-0000-4000-8000-000000000003',
    null,
    'insights',
    'gpt-6-luna',
    'running',
    '2026-09-23',
    300,
    private.current_month_start(),
    now() - interval '40 minutes'
  );

select is(
  private.settle_abandoned_ai_runs(),
  4,
  'one sweep settles every abandoned run across houses, months and purposes'
);

select is(
  (
    select string_agg(
      reserved_microusd::text || ':' || spent_microusd::text,
      '/' order by family_id, month_start
    )
    from private.nina_ai_household_budget_months
    where family_id in (
      'e2000000-0000-4000-8000-000000000002',
      'e2000000-0000-4000-8000-000000000003'
    )
  ),
  '0:1900/1500:4000/0:1000',
  'each house share is booked once with the sum of its abandoned turns in the month they reserved in, and a share with only young turns is left alone'
);

select is(
  (
    select string_agg(
      reserved_microusd::text || ':' || spent_microusd::text,
      '/' order by month_start, purpose
    )
    from public.nina_ai_budget_months
    where month_start >= (private.current_month_start() - interval '1 month')::date
  ),
  '0:1900/0:1100/1500:7100',
  'each pool row is booked once with the sum of its abandoned runs, by month and purpose'
);

select is(
  (
    select string_agg(
      status || ':' || coalesce(error_code, '-') || ':' || coalesce(actual_microusd::text, '-'),
      ',' order by id
    )
    from public.nina_ai_runs
    where id in (
      'e5000000-0000-4000-8000-000000000003',
      'e5000000-0000-4000-8000-000000000004',
      'e5000000-0000-4000-8000-000000000005',
      'e5000000-0000-4000-8000-000000000006',
      'e5000000-0000-4000-8000-000000000007'
    )
  ),
  'reserved:-:-,failed:run_abandoned:700,failed:run_abandoned:900,failed:run_abandoned:100,failed:run_abandoned:300',
  'every abandoned run is failed at its reservation, and a run still young is left to finish'
);

insert into private.nina_ai_household_budget_months (
  family_id,
  month_start,
  cap_microusd,
  reserved_microusd,
  spent_microusd
)
values (
  'e2000000-0000-4000-8000-000000000003',
  (private.current_month_start() - interval '1 month')::date,
  5000000,
  400,
  0
);

update private.nina_ai_household_budget_months
set reserved_microusd = reserved_microusd + 250
where family_id = 'e2000000-0000-4000-8000-000000000003'
  and month_start = private.current_month_start();

update public.nina_ai_budget_months
set reserved_microusd = reserved_microusd + case
  when month_start < private.current_month_start() then 400
  when purpose = 'interactive' then 250
  else 50
end
where month_start >= (private.current_month_start() - interval '1 month')::date;

insert into public.nina_ai_runs (
  id,
  family_id,
  user_id,
  purpose,
  model,
  status,
  pricing_version,
  reserved_microusd,
  budget_month_start
)
values
  (
    'e5000000-0000-4000-8000-000000000008',
    'e2000000-0000-4000-8000-000000000003',
    'e1000000-0000-4000-8000-000000000005',
    'interactive',
    'gpt-6-luna',
    'running',
    '2026-09-23',
    400,
    (private.current_month_start() - interval '1 month')::date
  ),
  (
    'e5000000-0000-4000-8000-000000000009',
    'e2000000-0000-4000-8000-000000000003',
    'e1000000-0000-4000-8000-000000000006',
    'interactive',
    'gpt-6-luna',
    'running',
    '2026-09-23',
    250,
    private.current_month_start()
  ),
  (
    'e5000000-0000-4000-8000-00000000000a',
    'e2000000-0000-4000-8000-000000000003',
    null,
    'insights',
    'gpt-6-luna',
    'running',
    '2026-09-23',
    50,
    private.current_month_start()
  );

select lives_ok(
  $$select private.settle_household_ai_runs('e2000000-0000-4000-8000-000000000003')$$,
  'a house deletion settles open runs reserved in two months and for both purposes'
);

select is(
  (
    select (
      select string_agg(
        reserved_microusd::text || ':' || spent_microusd::text,
        '/' order by month_start
      )
      from private.nina_ai_household_budget_months
      where family_id = 'e2000000-0000-4000-8000-000000000003'
    ) || '|' || (
      select string_agg(
        reserved_microusd::text || ':' || spent_microusd::text,
        '/' order by month_start, purpose
      )
      from public.nina_ai_budget_months
      where month_start >= (private.current_month_start() - interval '1 month')::date
    )
  ),
  '0:400/0:1250|0:2300/0:1150/1500:7350',
  'a house deletion books each of its shares and each pool row once, in the month each run reserved in, and leaves another house''s open turns reserved'
);

select is(
  (
    select string_agg(
      status || ':' || coalesce(error_code, '-') || ':' || coalesce(actual_microusd::text, '-'),
      ',' order by id
    )
    from public.nina_ai_runs
    where id in (
      'e5000000-0000-4000-8000-000000000008',
      'e5000000-0000-4000-8000-000000000009',
      'e5000000-0000-4000-8000-00000000000a'
    )
  ),
  'failed:family_deleted:400,failed:family_deleted:250,failed:family_deleted:50',
  'every open run of the deleted house is failed at its reservation'
);

select * from finish();
rollback;
