begin;

create extension if not exists pgtap with schema extensions;

select plan(76);

insert into auth.users (
  id,
  aud,
  role,
  email,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '61000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'nina-adult-one@example.com',
    '{"full_name":"Adult One"}'::jsonb,
    now(),
    now()
  ),
  (
    '61000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'nina-adult-two@example.com',
    '{"full_name":"Adult Two"}'::jsonb,
    now(),
    now()
  ),
  (
    '61000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'nina-child@example.com',
    '{"full_name":"Child"}'::jsonb,
    now(),
    now()
  ),
  (
    '61000000-0000-0000-0000-000000000004',
    'authenticated',
    'authenticated',
    'nina-outsider@example.com',
    '{"full_name":"Outsider"}'::jsonb,
    now(),
    now()
  );

insert into public.families (id, name, invite_code, created_by)
values
  (
    '62000000-0000-0000-0000-000000000001',
    'Nina V2 Home',
    'casa-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    '61000000-0000-0000-0000-000000000001'
  ),
  (
    '62000000-0000-0000-0000-000000000002',
    'Other Home',
    'casa-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    '61000000-0000-0000-0000-000000000004'
  );

insert into public.family_members (
  family_id,
  user_id,
  name,
  relationship,
  household_role,
  permission_role,
  tone
)
values
  (
    '62000000-0000-0000-0000-000000000001',
    '61000000-0000-0000-0000-000000000001',
    'Adult One',
    'Owner',
    'adult',
    'owner',
    'mint'
  ),
  (
    '62000000-0000-0000-0000-000000000001',
    '61000000-0000-0000-0000-000000000002',
    'Adult Two',
    'Member',
    'adult',
    'member',
    'sky'
  ),
  (
    '62000000-0000-0000-0000-000000000001',
    '61000000-0000-0000-0000-000000000003',
    'Child',
    'Child',
    'child',
    'member',
    'amber'
  ),
  (
    '62000000-0000-0000-0000-000000000002',
    '61000000-0000-0000-0000-000000000004',
    'Outsider',
    'Owner',
    'adult',
    'owner',
    'coral'
  );

set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000003';

select throws_ok(
  $$select public.begin_nina_chat_run(
    '62000000-0000-0000-0000-000000000001',
    '63000000-0000-0000-0000-000000000003',
    'Mensagem de criança',
    '[]'::jsonb,
    'gpt-5.4-mini',
    1000,
    '2026-06-15'
  )$$,
  '42501',
  null,
  'children cannot start Nina chat runs'
);

select throws_ok(
  $$select public.record_nina_ai_consent('2026-06-16', true)$$,
  '42501',
  'nina_adult_access_required',
  'a child profile cannot consent to Nina on behalf of the household'
);

set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select is(
  public.record_nina_ai_consent('2026-06-16', true) -> 'ai_consent' ->> 'is_granted',
  'true',
  'an adult records server side consent to Nina'
);

select is(
  public.get_current_home_context() -> 'ai_consent' ->> 'policy_version',
  '2026-06-16',
  'the household context carries the policy version the adult accepted'
);

select is(
  (
    select count(*)::integer
    from jsonb_object_keys(public.get_current_home_context() -> 'ai_consent')
  ),
  3,
  'the AI consent block exposes exactly three fields'
);

select lives_ok(
  $$select set_config(
    'test.nina_run_one',
    public.begin_nina_chat_run(
      '62000000-0000-0000-0000-000000000001',
      '63000000-0000-0000-0000-000000000001',
      'Criar tarefa para amanhã',
      '[]'::jsonb,
      'gpt-5.4-mini',
      1000,
      '2026-06-15'
    ) ->> 'run_id',
    true
  )$$,
  'first adult can start a private Nina run'
);

select set_config(
  'test.nina_thread_one',
  (
    select id::text
    from public.nina_threads
    where owner_user_id = auth.uid()
      and family_id = '62000000-0000-0000-0000-000000000001'
  ),
  true
);

set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000002';

select is(
  public.record_nina_ai_consent('2026-06-16', true) -> 'ai_consent' ->> 'is_granted',
  'true',
  'the second adult records their own consent'
);

select lives_ok(
  $$select set_config(
    'test.nina_run_two',
    public.begin_nina_chat_run(
      '62000000-0000-0000-0000-000000000001',
      '63000000-0000-0000-0000-000000000002',
      'Minha conversa privada',
      '[]'::jsonb,
      'gpt-5.4-mini',
      1000,
      '2026-06-15'
    ) ->> 'run_id',
    true
  )$$,
  'second adult can start a separate private Nina run'
);

select set_config(
  'test.nina_thread_two',
  (
    select id::text
    from public.nina_threads
    where owner_user_id = auth.uid()
      and family_id = '62000000-0000-0000-0000-000000000001'
  ),
  true
);

select isnt(
  current_setting('test.nina_thread_one'),
  current_setting('test.nina_thread_two'),
  'adults receive distinct private threads'
);

set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select is(
  (select count(*)::integer from public.nina_threads),
  1,
  'thread RLS exposes only the current adult thread'
);

select is(
  (select count(*)::integer from public.chat_messages where thread_id is not null),
  1,
  'message RLS hides the other adult private message'
);

set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000002';

select is(
  (select count(*)::integer from public.chat_messages where thread_id is not null),
  1,
  'the second adult sees only their private message'
);

reset role;
set local request.jwt.claim.sub = '';

insert into public.memory_items (
  id,
  family_id,
  title,
  body,
  owner_user_id,
  visibility,
  status,
  confirmed_at,
  confirmed_by
)
values
  (
    '64000000-0000-0000-0000-000000000001',
    '62000000-0000-0000-0000-000000000001',
    'Private preference',
    'Only Adult One',
    '61000000-0000-0000-0000-000000000001',
    'private',
    'confirmed',
    now(),
    '61000000-0000-0000-0000-000000000001'
  ),
  (
    '64000000-0000-0000-0000-000000000002',
    '62000000-0000-0000-0000-000000000001',
    'Shared preference',
    'Visible to the home',
    '61000000-0000-0000-0000-000000000001',
    'shared',
    'confirmed',
    now(),
    '61000000-0000-0000-0000-000000000001'
  );

set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select is(
  (select count(*)::integer from public.memory_items),
  2,
  'a memory owner sees their private and shared memories'
);

set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000002';

select is(
  (select count(*)::integer from public.memory_items),
  1,
  'another adult sees only shared memories'
);

select is(
  (select count(*)::integer from public.memory_items where title = 'Private preference'),
  0,
  'private memories never leak to another adult'
);

select throws_ok(
  $$select public.get_current_nina_state('62000000-0000-0000-0000-000000000002')$$,
  '42501',
  null,
  'Nina state denies cross-family access'
);

reset role;
set local request.jwt.claim.sub = '';

select lives_ok(
  format(
    $$select public.complete_nina_chat_run(
      %L::uuid,
      '65000000-0000-0000-0000-000000000001',
      'Preparei uma proposta para você confirmar.',
      %L::jsonb,
      500,
      100,
      120,
      20,
      500,
      250
    )$$,
    current_setting('test.nina_run_one'),
    jsonb_build_array(
      jsonb_build_object(
        'id', '66000000-0000-0000-0000-000000000001',
        'kind', 'task',
        'title', 'Tarefa de amanhã',
        'detail', 'Ainda não foi criada',
        'action_title', 'Criar tarefa',
        'payload', jsonb_build_object(
          'title', 'Separar documentos',
          'detail', 'Deixar tudo pronto',
          'owner', 'Adult One',
          'due_label', 'Amanhã',
          'due_at', '2026-06-16T12:00:00-03:00',
          'category', 'home',
          'symbol_name', 'doc.fill',
          'amount', '',
          'visibility', null,
          'confidence', null,
          'deduplication_key', 'task-documents-2026-06-16'
        )
      )
    )::text
  ),
  'a service completion stores the assistant response and proposals'
);

select is(
  (select count(*)::integer from public.tasks where title = 'Separar documentos'),
  0,
  'proposals never mutate household data before confirmation'
);

set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000002';

select throws_ok(
  $$select public.resolve_nina_proposal(
    '66000000-0000-0000-0000-000000000001',
    'accept',
    '{}'::jsonb,
    null
  )$$,
  '42501',
  null,
  'another adult cannot resolve an owned proposal'
);

set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.resolve_nina_proposal(
    '66000000-0000-0000-0000-000000000001',
    'accept',
    '{"detail":"Editado antes de confirmar"}'::jsonb,
    null
  )$$,
  'the proposal owner can confirm with permitted edits'
);

select is(
  (select count(*)::integer from public.tasks where title = 'Separar documentos'),
  1,
  'confirmation creates exactly one task'
);

select is(
  (
    select due_at
    from public.tasks
    where title = 'Separar documentos'
  ),
  '2026-06-16 15:00:00+00'::timestamptz,
  'confirmed tasks retain a real due date'
);

select lives_ok(
  $$select public.resolve_nina_proposal(
    '66000000-0000-0000-0000-000000000001',
    'accept',
    '{}'::jsonb,
    null
  )$$,
  'resolving an accepted proposal is idempotent'
);

select is(
  (select count(*)::integer from public.tasks where title = 'Separar documentos'),
  1,
  'idempotent confirmation does not duplicate the task'
);

reset role;
set local request.jwt.claim.sub = '';

select lives_ok(
  format(
    $$select public.fail_nina_ai_run(%L::uuid, 'test_cleanup', 10)$$,
    current_setting('test.nina_run_two')
  ),
  'failed runs release their reserved budget'
);

insert into public.nina_chat_rate_limits (
  user_id,
  window_started_at,
  request_count
)
values (
  '61000000-0000-0000-0000-000000000001',
  now(),
  30
)
on conflict (user_id) do update
set window_started_at = now(), request_count = 30;

set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select throws_ok(
  $$select public.begin_nina_chat_run(
    '62000000-0000-0000-0000-000000000001',
    '63000000-0000-0000-0000-000000000011',
    'Rate limit user',
    '[]'::jsonb,
    'gpt-5.4-mini',
    1000,
    '2026-06-15'
  )$$,
  'P0001',
  null,
  'the hourly per-user limit rejects request 31'
);

reset role;
set local request.jwt.claim.sub = '';

update public.nina_chat_rate_limits
set request_count = 0
where user_id = '61000000-0000-0000-0000-000000000001';

insert into public.nina_ai_family_rate_limits (
  family_id,
  window_started_at,
  request_count
)
values (
  '62000000-0000-0000-0000-000000000001',
  now(),
  100
)
on conflict (family_id) do update
set window_started_at = now(), request_count = 100;

set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select throws_ok(
  $$select public.begin_nina_chat_run(
    '62000000-0000-0000-0000-000000000001',
    '63000000-0000-0000-0000-000000000012',
    'Rate limit family',
    '[]'::jsonb,
    'gpt-5.4-mini',
    1000,
    '2026-06-15'
  )$$,
  'P0001',
  null,
  'the daily family limit rejects request 101'
);

reset role;
set local request.jwt.claim.sub = '';

update public.nina_ai_family_rate_limits
set request_count = 0
where family_id = '62000000-0000-0000-0000-000000000001';

update public.nina_ai_budget_months
set reserved_microusd = 0, spent_microusd = cap_microusd
where month_start = date_trunc('month', now())::date
  and purpose = 'interactive';

set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select throws_ok(
  $$select public.begin_nina_chat_run(
    '62000000-0000-0000-0000-000000000001',
    '63000000-0000-0000-0000-000000000013',
    'Budget limit',
    '[]'::jsonb,
    'gpt-5.4-mini',
    1,
    '2026-06-15'
  )$$,
  'P0001',
  null,
  'the interactive monthly budget rejects reservations above the cap'
);

reset role;
set local request.jwt.claim.sub = '';

update public.nina_ai_budget_months
set reserved_microusd = 0, spent_microusd = 0
where month_start = date_trunc('month', now())::date
  and purpose = 'interactive';

set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select lives_ok(
  $$select set_config(
    'test.failed_nina_run',
    public.begin_nina_chat_run(
      '62000000-0000-0000-0000-000000000001',
      '63000000-0000-0000-0000-000000000014',
      'Run that will fail after provider usage',
      '[]'::jsonb,
      'gpt-5.4-mini',
      10000,
      '2026-06-15'
    ) ->> 'run_id',
    true
  )$$,
  'a run can be reserved before provider work'
);

reset role;
set local request.jwt.claim.sub = '';

select lives_ok(
  $$select public.record_failed_nina_ai_run(
    current_setting('test.failed_nina_run')::uuid,
    'invalid_assistant_response',
    1000,
    100,
    200,
    10,
    1234,
    345
  )$$,
  'failed provider runs settle actual usage and cost'
);

select is(
  (
    select status || ':' || actual_microusd::text || ':' || input_tokens::text || ':' || output_tokens::text
    from public.nina_ai_runs
    where id = current_setting('test.failed_nina_run')::uuid
  ),
  'failed:1234:1000:200',
  'failed runs keep content-free usage and cost metadata'
);

select is(
  (
    select reserved_microusd::text || ':' || spent_microusd::text
    from public.nina_ai_budget_months
    where month_start = date_trunc('month', now())::date
      and purpose = 'interactive'
  ),
  '0:1234',
  'failed run settlement releases reservation and adds actual spend'
);

select is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'nina_ai_runs'
      and column_name in (
        'prompt',
        'response',
        'attachments',
        'message_text',
        'request_body',
        'output_text'
      )
  ),
  0,
  'operational AI logs contain no prompt, response, attachment, or message content'
);

select is(
  (private.nina_weekly_metrics('62000000-0000-0000-0000-000000000001') ->> 'shared_memory_events')::integer,
  1,
  'weekly metrics count confirmed shared memories'
);

select is(
  (
    private.nina_weekly_metrics('62000000-0000-0000-0000-000000000001')
      -> 'open_tasks_by_owner'
      ->> 'Adult One'
  )::integer,
  1,
  'weekly workload metrics are deterministic SQL counts'
);

insert into public.chat_messages (
  id,
  family_id,
  sender,
  text,
  retained_until,
  created_at
)
values (
  '67000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001',
  'nina',
  'Old raw chat',
  now() - interval '1 day',
  now() - interval '31 days'
);

insert into public.nina_proposals (
  id,
  family_id,
  owner_user_id,
  kind,
  state,
  title,
  resolved_at,
  created_at
)
values (
  '68000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001',
  '61000000-0000-0000-0000-000000000001',
  'task',
  'rejected',
  'Old proposal',
  now() - interval '31 days',
  now() - interval '40 days'
);

insert into public.nina_ai_runs (
  id,
  family_id,
  purpose,
  model,
  status,
  pricing_version,
  created_at,
  completed_at
)
values (
  '69000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001',
  'insights',
  'gpt-5.5',
  'completed',
  '2026-06-15',
  now() - interval '91 days',
  now() - interval '91 days'
);

insert into public.household_insights (
  id,
  family_id,
  title,
  expires_at,
  created_at
)
values (
  '6a000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001',
  'Old insight',
  now() - interval '1 day',
  now() - interval '91 days'
);

select lives_ok(
  $$select public.run_nina_retention()$$,
  'daily retention completes'
);

select is(
  (select count(*)::integer from public.chat_messages where id = '67000000-0000-0000-0000-000000000001'),
  0,
  'raw chat older than 30 days is deleted'
);

select is(
  (select count(*)::integer from public.nina_proposals where id = '68000000-0000-0000-0000-000000000001'),
  0,
  'resolved proposals older than 30 days are deleted'
);

select is(
  (select count(*)::integer from public.nina_ai_runs where id = '69000000-0000-0000-0000-000000000001'),
  0,
  'content-free operational logs older than 90 days are deleted'
);

select is(
  (select count(*)::integer from public.household_insights where id = '6a000000-0000-0000-0000-000000000001'),
  0,
  'insights older than 90 days are deleted'
);

set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.delete_current_nina_chat_history('62000000-0000-0000-0000-000000000001')$$,
  'an adult can delete their own private chat history'
);

select is(
  (select count(*)::integer from public.chat_messages where thread_id = current_setting('test.nina_thread_one')::uuid),
  0,
  'chat history deletion clears only the current adult thread'
);

set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000002';

select is(
  (select count(*)::integer from public.chat_messages where thread_id = current_setting('test.nina_thread_two')::uuid),
  1,
  'deleting one private history leaves another adult thread intact'
);

reset role;
set local request.jwt.claim.sub = '';

update public.nina_ai_budget_months
set reserved_microusd = 0, spent_microusd = 0
where month_start = date_trunc('month', now())::date
  and purpose = 'interactive';

insert into public.nina_ai_budget_months (
  month_start,
  purpose,
  cap_microusd,
  reserved_microusd,
  spent_microusd
)
values (
  (date_trunc('month', now()) - interval '1 month')::date,
  'interactive',
  20000000,
  0,
  0
)
on conflict (month_start, purpose) do nothing;

set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select set_config(
  'test.month_boundary_run',
  public.begin_nina_chat_run(
    '62000000-0000-0000-0000-000000000001',
    '63000000-0000-0000-0000-000000000015',
    'Mensagem enviada no fim do mês',
    '[]'::jsonb,
    'gpt-5.4-mini',
    7000,
    '2026-06-15'
  ) ->> 'run_id',
  true
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (
    select budget_month_start
    from public.nina_ai_runs
    where id = current_setting('test.month_boundary_run')::uuid
  ),
  private.current_month_start(),
  'a reservation pins the budget month it charged'
);

update public.nina_ai_runs
set budget_month_start = (date_trunc('month', now()) - interval '1 month')::date
where id = current_setting('test.month_boundary_run')::uuid;

update public.nina_ai_budget_months
set reserved_microusd = 7000
where month_start = (date_trunc('month', now()) - interval '1 month')::date
  and purpose = 'interactive';

update public.nina_ai_budget_months
set reserved_microusd = 0
where month_start = date_trunc('month', now())::date
  and purpose = 'interactive';

select lives_ok(
  format(
    $$select public.complete_nina_chat_run(
      %L::uuid,
      '65000000-0000-0000-0000-000000000002',
      'Respondi depois da virada do mês.',
      '[]'::jsonb,
      400,
      0,
      100,
      0,
      4500,
      200
    )$$,
    current_setting('test.month_boundary_run')
  ),
  'a run completes after the month it reserved in has ended'
);

select is(
  (
    select reserved_microusd::text || ':' || spent_microusd::text
    from public.nina_ai_budget_months
    where month_start = (date_trunc('month', now()) - interval '1 month')::date
      and purpose = 'interactive'
  ),
  '0:4500',
  'a completed run releases its reservation in the month it reserved in'
);

select is(
  (
    select reserved_microusd::text || ':' || spent_microusd::text
    from public.nina_ai_budget_months
    where month_start = date_trunc('month', now())::date
      and purpose = 'interactive'
  ),
  '0:0',
  'completing a previous month run never charges the new month'
);

set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select set_config(
  'test.month_boundary_failed_run',
  public.begin_nina_chat_run(
    '62000000-0000-0000-0000-000000000001',
    '63000000-0000-0000-0000-000000000016',
    'Mensagem que falha depois da virada',
    '[]'::jsonb,
    'gpt-5.4-mini',
    9000,
    '2026-06-15'
  ) ->> 'run_id',
  true
);

reset role;
set local request.jwt.claim.sub = '';

update public.nina_ai_runs
set budget_month_start = (date_trunc('month', now()) - interval '1 month')::date
where id = current_setting('test.month_boundary_failed_run')::uuid;

update public.nina_ai_budget_months
set reserved_microusd = 9000
where month_start = (date_trunc('month', now()) - interval '1 month')::date
  and purpose = 'interactive';

update public.nina_ai_budget_months
set reserved_microusd = 0
where month_start = date_trunc('month', now())::date
  and purpose = 'interactive';

select lives_ok(
  $$select public.record_failed_nina_ai_run(
    current_setting('test.month_boundary_failed_run')::uuid,
    'provider_timeout',
    500,
    0,
    0,
    0,
    2500,
    900
  )$$,
  'a failed run settles after the month it reserved in has ended'
);

select is(
  (
    select reserved_microusd::text || ':' || spent_microusd::text
    from public.nina_ai_budget_months
    where month_start = (date_trunc('month', now()) - interval '1 month')::date
      and purpose = 'interactive'
  ),
  '0:7000',
  'a failed run releases its reservation in the month it reserved in'
);

select is(
  (
    select reserved_microusd::text || ':' || spent_microusd::text
    from public.nina_ai_budget_months
    where month_start = date_trunc('month', now())::date
      and purpose = 'interactive'
  ),
  '0:0',
  'settling a previous month failure never charges the new month'
);

select is(
  (
    select is_nullable::text
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'nina_ai_runs'
      and column_name = 'budget_month_start'
  ),
  'NO',
  'every Nina run carries a pinned budget month'
);

update public.profiles
set active_family_id = '62000000-0000-0000-0000-000000000001'
where id in (
  '61000000-0000-0000-0000-000000000001',
  '61000000-0000-0000-0000-000000000002'
);

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
values (
  'nina-consent-original-transaction',
  '61000000-0000-0000-0000-000000000001',
  'com.heitor.nina.premium.monthly',
  'Sandbox',
  'active',
  true,
  'nina-consent-transaction',
  now() + interval '30 days',
  'signed-transaction-info-example'
);

insert into public.tasks (family_id, title)
select
  '62000000-0000-0000-0000-000000000001'::uuid,
  'Tarefa da semana ' || slot::text
from generate_series(1, 5) as slot;

set local role service_role;

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      public.get_nina_weekly_candidates()
    ) as candidate(metrics)
    where candidate.metrics ->> 'family_id' = '62000000-0000-0000-0000-000000000001'
  ),
  'a covered household with a consenting adult is a weekly digest candidate'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select is(
  public.record_nina_ai_consent('2026-06-16', false) -> 'ai_consent' ->> 'is_granted',
  'false',
  'withdrawing consent clears the household context signal'
);

select throws_ok(
  $$select public.begin_nina_chat_run(
    '62000000-0000-0000-0000-000000000001',
    '63000000-0000-0000-0000-000000000017',
    'Mensagem depois de revogar',
    '[]'::jsonb,
    'gpt-5.4-mini',
    1000,
    '2026-06-15'
  )$$,
  '42501',
  'nina_ai_consent_required',
  'an adult who withdrew consent cannot start a Nina run'
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (
    select count(*)::integer
    from public.nina_ai_consents
    where user_id = '61000000-0000-0000-0000-000000000001'
      and family_id = '62000000-0000-0000-0000-000000000001'
  ),
  1,
  'a withdrawal keeps the consent it ended as a record'
);

select ok(
  (
    select revoked_at is not null
    from public.nina_ai_consents
    where user_id = '61000000-0000-0000-0000-000000000001'
      and family_id = '62000000-0000-0000-0000-000000000001'
  ),
  'a withdrawal is stamped on the consent row rather than deleting it'
);

set local role service_role;

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      public.get_nina_weekly_candidates()
    ) as candidate(metrics)
    where candidate.metrics ->> 'family_id' = '62000000-0000-0000-0000-000000000001'
  ),
  'a household keeps its weekly digest while another adult still consents'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000002';

select is(
  public.record_nina_ai_consent('2026-06-16', false) -> 'ai_consent' ->> 'is_granted',
  'false',
  'the second adult withdraws consent as well'
);

reset role;
set local role service_role;

select ok(
  not exists (
    select 1
    from jsonb_array_elements(
      public.get_nina_weekly_candidates()
    ) as candidate(metrics)
    where candidate.metrics ->> 'family_id' = '62000000-0000-0000-0000-000000000001'
  ),
  'a household with no consenting adult is never a weekly digest candidate'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000002';

select is(
  public.record_nina_ai_consent('2026-06-16', true) -> 'ai_consent' ->> 'is_granted',
  'true',
  'an adult can consent again after withdrawing'
);

reset role;
set local request.jwt.claim.sub = '';

select is(
  (
    select count(*)::integer
    from public.nina_ai_consents
    where user_id = '61000000-0000-0000-0000-000000000002'
      and family_id = '62000000-0000-0000-0000-000000000001'
  ),
  2,
  'consenting again records a second grant instead of reviving the first'
);

set local role service_role;

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      public.get_nina_weekly_candidates()
    ) as candidate(metrics)
    where candidate.metrics ->> 'family_id' = '62000000-0000-0000-0000-000000000001'
  ),
  'the household returns as a weekly digest candidate once an adult consents again'
);

reset role;

select ok(
  not has_function_privilege(
    'anon',
    'public.begin_nina_chat_run(uuid,uuid,text,jsonb,text,bigint,date)',
    'execute'
  ),
  'anonymous users cannot reserve Nina chat runs'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.complete_nina_chat_run(uuid,uuid,text,jsonb,integer,integer,integer,integer,bigint,integer)',
    'execute'
  ),
  'anonymous users cannot complete Nina chat runs'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.complete_nina_chat_run(uuid,uuid,text,jsonb,integer,integer,integer,integer,bigint,integer)',
    'execute'
  ),
  'authenticated clients cannot forge assistant completions'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.verify_nina_maintenance_secret(text)',
    'execute'
  ),
  'authenticated clients cannot probe the maintenance secret'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.complete_nina_chat_run(uuid,uuid,text,jsonb,integer,integer,integer,integer,bigint,integer)',
    'execute'
  ),
  'the service role can complete Nina chat runs'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.record_failed_nina_ai_run(uuid,text,integer,integer,integer,integer,bigint,integer)',
    'execute'
  ),
  'authenticated clients cannot settle failed Nina runs'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.record_failed_nina_ai_run(uuid,text,integer,integer,integer,integer,bigint,integer)',
    'execute'
  ),
  'the service role can settle failed Nina runs'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.resolve_nina_proposal(uuid,text,jsonb,text)',
    'execute'
  ),
  'authenticated owners can call the proposal resolution RPC'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.record_nina_ai_consent(text,boolean)',
    'execute'
  ),
  'an adult records their own AI consent through the client role'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.record_nina_ai_consent(text,boolean)',
    'execute'
  ),
  'anonymous callers cannot record AI consent'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.record_nina_ai_consent(text,boolean)',
    'execute'
  ),
  'no server path records AI consent on behalf of a person'
);

select ok(
  not has_table_privilege('authenticated', 'public.nina_ai_consents', 'select'),
  'authenticated clients cannot read AI consent records directly'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.nina_ai_consents',
    'insert, update, delete'
  ),
  'authenticated clients cannot write AI consent state directly'
);

select ok(
  not has_table_privilege('anon', 'public.nina_ai_consents', 'select'),
  'anonymous clients hold no privilege on AI consent records'
);

select * from finish();
rollback;
