begin;

create extension if not exists pgtap with schema extensions;

select plan(78);

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
    '81000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'premium-payer@example.com',
    '{"full_name":"Premium Payer"}'::jsonb,
    now(),
    now()
  ),
  (
    '81000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'premium-housemate@example.com',
    '{"full_name":"Premium Housemate"}'::jsonb,
    now(),
    now()
  ),
  (
    '81000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'premium-neighbour@example.com',
    '{"full_name":"Premium Neighbour"}'::jsonb,
    now(),
    now()
  );

insert into public.families (id, name, invite_code, created_by)
values
  (
    '82000000-0000-0000-0000-000000000001',
    'Paying home',
    'casa-88888888888888888888888888888888',
    '81000000-0000-0000-0000-000000000001'
  ),
  (
    '82000000-0000-0000-0000-000000000002',
    'Neighbour home',
    'casa-99999999999999999999999999999999',
    '81000000-0000-0000-0000-000000000003'
  );

insert into public.family_members (
  id,
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
    '83000000-0000-0000-0000-000000000001',
    '82000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000001',
    'Premium Payer',
    'Owner',
    'adult',
    'owner',
    'mint'
  ),
  (
    '83000000-0000-0000-0000-000000000002',
    '82000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000002',
    'Premium Housemate',
    'Member',
    'adult',
    'member',
    'sky'
  ),
  (
    '83000000-0000-0000-0000-000000000003',
    '82000000-0000-0000-0000-000000000002',
    '81000000-0000-0000-0000-000000000003',
    'Premium Neighbour',
    'Owner',
    'adult',
    'owner',
    'coral'
  );

update public.profiles
set active_family_id = case id
  when '81000000-0000-0000-0000-000000000001' then '82000000-0000-0000-0000-000000000001'::uuid
  when '81000000-0000-0000-0000-000000000002' then '82000000-0000-0000-0000-000000000001'::uuid
  else '82000000-0000-0000-0000-000000000002'::uuid
end
where id in (
  '81000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000002',
  '81000000-0000-0000-0000-000000000003'
);

insert into public.premium_subscriptions (
  original_transaction_id,
  user_id,
  app_account_token,
  product_id,
  environment,
  status,
  is_active,
  transaction_id,
  expires_at,
  signed_transaction_info
)
values (
  'premium-original-transaction',
  '81000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000001',
  'com.heitor.nina.premium.monthly',
  'Sandbox',
  'active',
  true,
  'premium-transaction',
  now() + interval '30 days',
  'signed-transaction-info-example'
);

insert into public.premium_subscription_transactions (
  transaction_id,
  original_transaction_id,
  user_id,
  product_id,
  environment,
  source,
  signed_transaction_info
)
values (
  'premium-transaction',
  'premium-original-transaction',
  '81000000-0000-0000-0000-000000000001',
  'com.heitor.nina.premium.monthly',
  'Sandbox',
  'app_sync',
  'signed-transaction-info-example'
);

select has_column(
  'public',
  'premium_subscriptions',
  'family_id',
  'a premium subscription records the household it covers'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.premium_subscriptions'::regclass
      and contype = 'f'
      and pg_get_constraintdef(oid) like 'FOREIGN KEY (family_id)%ON DELETE SET NULL'
  ),
  'a deleted household releases the premium link instead of erasing the purchase'
);

select has_function(
  'private',
  'family_has_premium',
  array['uuid'],
  'the household premium signal is answered by a private helper'
);

select has_trigger(
  'public',
  'premium_subscriptions',
  'premium_subscriptions_resolve_family',
  'the household link is server derived on every subscription write'
);

select has_trigger(
  'public',
  'profiles',
  'profiles_resolve_premium_family',
  'moving the payer to another home re-derives the household link'
);

select has_trigger(
  'public',
  'family_members',
  'family_members_resolve_premium_family',
  'membership changes re-derive the household link'
);

select ok(
  not has_function_privilege(
    'anon',
    'private.family_has_premium(uuid)',
    'execute'
  ),
  'anonymous clients cannot probe whether a household is covered'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'private.family_has_premium(uuid)',
    'execute'
  ),
  'authenticated clients cannot probe another household for premium'
);

select ok(
  not has_function_privilege(
    'service_role',
    'private.family_has_premium(uuid)',
    'execute'
  ),
  'no Edge Function reaches the household premium helper directly'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.resolve_premium_subscription_family()',
    'execute'
  ),
  'authenticated clients cannot invoke the household link derivation'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_current_home_context()',
    'execute'
  ),
  'the home context RPC stays granted to the client role'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.get_current_home_context()',
    'execute'
  ),
  'anonymous callers cannot read a household premium block'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.get_current_home_context()',
    'execute'
  ),
  'no server path reads the household context on behalf of a member'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_current_premium_status()',
    'execute'
  ),
  'the payer own purchase RPC stays granted to the client role'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.get_current_premium_status()',
    'execute'
  ),
  'anonymous callers cannot read a purchase status'
);

select is(
  (
    select count(*)::integer
    from pg_class
    join pg_namespace on pg_namespace.oid = pg_class.relnamespace
    where pg_namespace.nspname = 'public'
      and pg_class.relname in (
        'premium_subscriptions',
        'premium_subscription_transactions',
        'app_store_server_notifications'
      )
      and pg_class.relrowsecurity
  ),
  3,
  'every premium table has row level security enabled'
);

select ok(
  has_table_privilege('authenticated', 'public.premium_subscriptions', 'select'),
  'the payer can read their own premium subscription row'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.premium_subscriptions',
    'insert, update, delete'
  ),
  'authenticated users cannot write premium subscription state'
);

select ok(
  has_table_privilege(
    'authenticated',
    'public.premium_subscription_transactions',
    'select'
  ),
  'the payer can read their own premium transaction history'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.premium_subscription_transactions',
    'insert, update, delete'
  ),
  'authenticated users cannot write premium transaction history'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.app_store_server_notifications',
    'select'
  ),
  'authenticated users cannot read App Store notification payloads'
);

select ok(
  not has_table_privilege('anon', 'public.premium_subscriptions', 'select'),
  'anonymous clients hold no privilege on premium subscriptions'
);

select ok(
  not has_table_privilege(
    'anon',
    'public.premium_subscription_transactions',
    'select'
  ),
  'anonymous clients hold no privilege on premium transactions'
);

select ok(
  not has_table_privilege(
    'anon',
    'public.app_store_server_notifications',
    'select'
  ),
  'anonymous clients hold no privilege on App Store notifications'
);

select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'public'
      and tablename = 'premium_subscriptions'
  ),
  1,
  'premium subscriptions keep exactly one read policy'
);

select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'public'
      and tablename = 'premium_subscriptions'
      and qual like '%is_family_member%'
  ),
  0,
  'the premium subscription read policy is deliberately not broadened to household members'
);

select ok(
  private.family_has_premium('82000000-0000-0000-0000-000000000001'),
  'a household with an active subscription is covered'
);

select ok(
  not private.family_has_premium('82000000-0000-0000-0000-000000000002'),
  'a household with no subscription is not covered'
);

select ok(
  not private.family_has_premium(null::uuid),
  'a missing household identifier is never covered'
);

select is(
  (
    select family_id
    from public.premium_subscriptions
    where original_transaction_id = 'premium-original-transaction'
  ),
  '82000000-0000-0000-0000-000000000001'::uuid,
  'the payer subscription resolves to the home they belong to'
);

set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000001';

select is(
  public.get_current_home_context() -> 'premium' ->> 'is_active',
  'true',
  'the payer reads the household premium signal'
);

select is(
  public.get_current_home_context() -> 'premium' ->> 'status',
  'active',
  'the household premium block carries the subscription status'
);

select is(
  public.get_current_premium_status() ->> 'original_transaction_id',
  'premium-original-transaction',
  'the payer still reads their own purchase identifiers'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000002';

select is(
  public.get_current_home_context() -> 'premium' ->> 'is_active',
  'true',
  'a second adult in the paying home reads the household premium signal'
);

select is(
  public.get_current_home_context() -> 'premium' ->> 'status',
  'active',
  'a second adult reads the household premium status'
);

select ok(
  (public.get_current_home_context() -> 'premium' ->> 'expires_at') is not null,
  'a second adult learns when household cover ends'
);

select is(
  (
    select count(*)::integer
    from jsonb_object_keys(public.get_current_home_context() -> 'premium')
  ),
  3,
  'the household premium block exposes exactly three fields'
);

select is(
  position(
    'premium-original-transaction' in public.get_current_home_context()::text
  ),
  0,
  'the household context never carries the payer purchase identifiers'
);

select is(
  (select count(*)::integer from public.premium_subscriptions),
  0,
  'a covered housemate cannot read the payer subscription row'
);

select is(
  (select count(*)::integer from public.premium_subscription_transactions),
  0,
  'a covered housemate cannot read the payer transaction history'
);

select is(
  public.get_current_premium_status() ->> 'is_active',
  'false',
  'a covered housemate still has no purchase of their own'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000003';

select is(
  public.get_current_home_context() -> 'premium' ->> 'is_active',
  'false',
  'a different household does not inherit premium'
);

select is(
  public.get_current_home_context() -> 'premium' ->> 'status',
  'inactive',
  'a household with no subscription reports an inactive status'
);

select ok(
  (public.get_current_home_context() -> 'premium' ->> 'expires_at') is null,
  'a household with no subscription reports no expiry'
);

select is(
  (select count(*)::integer from public.premium_subscriptions),
  0,
  'a neighbouring household cannot read the paying household subscription'
);

reset role;

select has_column(
  'public',
  'families',
  'weekly_digest_enabled',
  'the household carries its own weekly digest switch'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.get_nina_weekly_candidates()',
    'execute'
  ),
  'the nightly maintenance role still selects weekly digest candidates'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.get_nina_weekly_candidates()',
    'execute'
  ),
  'clients cannot enumerate the households due a weekly digest'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.update_family_settings(uuid,text,boolean)',
    'execute'
  ),
  'the weekly digest switch is set through the family update RPC'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.update_family_settings(uuid,text,boolean)',
    'execute'
  ),
  'anonymous callers cannot move a house level switch'
);

insert into public.tasks (family_id, title)
select
  '82000000-0000-0000-0000-000000000001'::uuid,
  'Tarefa da casa que paga ' || slot::text
from generate_series(1, 5) as slot;

insert into public.tasks (family_id, title)
select
  '82000000-0000-0000-0000-000000000002'::uuid,
  'Tarefa da casa vizinha ' || slot::text
from generate_series(1, 5) as slot;

set local role service_role;

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      public.get_nina_weekly_candidates()
    ) as candidate(metrics)
    where candidate.metrics ->> 'family_id' = '82000000-0000-0000-0000-000000000001'
  ),
  'a paying household with the weekly digest on is a candidate'
);

select ok(
  not exists (
    select 1
    from jsonb_array_elements(
      public.get_nina_weekly_candidates()
    ) as candidate(metrics)
    where candidate.metrics ->> 'family_id' = '82000000-0000-0000-0000-000000000002'
  ),
  'a free household never spends the weekly insights budget'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000002';

select throws_ok(
  $$select public.update_family_settings(
    '82000000-0000-0000-0000-000000000001',
    'Paying home',
    false
  )$$,
  '42501',
  'family_management_denied',
  'a plain member cannot switch the household weekly digest'
);

set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000001';

select is(
  public.get_current_home_context() -> 'family' ->> 'weekly_digest_enabled',
  'true',
  'the household context carries the weekly digest switch'
);

select is(
  public.update_family_settings(
    '82000000-0000-0000-0000-000000000001',
    'Paying home',
    false
  ) -> 'family' ->> 'weekly_digest_enabled',
  'false',
  'an owner can turn the weekly digest off'
);

reset role;
set local role service_role;

select ok(
  not exists (
    select 1
    from jsonb_array_elements(
      public.get_nina_weekly_candidates()
    ) as candidate(metrics)
    where candidate.metrics ->> 'family_id' = '82000000-0000-0000-0000-000000000001'
  ),
  'a household that switched the weekly digest off is skipped by the nightly job'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000001';

select is(
  public.update_family_settings(
    '82000000-0000-0000-0000-000000000001',
    'Paying home',
    true
  ) -> 'family' ->> 'weekly_digest_enabled',
  'true',
  'an owner can turn the weekly digest back on'
);

reset role;
set local role service_role;

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      public.get_nina_weekly_candidates()
    ) as candidate(metrics)
    where candidate.metrics ->> 'family_id' = '82000000-0000-0000-0000-000000000001'
  ),
  'turning the weekly digest back on restores the household as a candidate'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000003';

select throws_ok(
  $$select public.begin_nina_chat_run(
    '82000000-0000-0000-0000-000000000002',
    '84000000-0000-0000-0000-000000000001',
    'Segue o boleto da escola',
    '[{"kind":"document","filename":"boleto.pdf","mime_type":"application/pdf","byte_count":1024}]'::jsonb,
    'gpt-5.4-mini',
    1000,
    '2026-08-09'
  )$$,
  'P0001',
  'nina_attachments_require_premium',
  'a free household cannot send Nina a document'
);

reset role;

select is(
  (
    select count(*)::integer
    from public.nina_ai_runs
    where family_id = '82000000-0000-0000-0000-000000000002'
  ),
  0,
  'a refused attachment never reserves a Nina run'
);

set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.begin_nina_chat_run(
    '82000000-0000-0000-0000-000000000001',
    '84000000-0000-0000-0000-000000000002',
    'Segue o boleto da escola',
    '[{"kind":"document","filename":"boleto.pdf","mime_type":"application/pdf","byte_count":1024}]'::jsonb,
    'gpt-5.4-mini',
    1000,
    '2026-08-09'
  )$$,
  'a paying household can send Nina a document'
);

reset role;

insert into public.nina_chat_rate_limits (
  user_id,
  window_started_at,
  request_count
)
values (
  '81000000-0000-0000-0000-000000000003',
  now() - interval '2 hours',
  10
)
on conflict (user_id) do update
set window_started_at = excluded.window_started_at,
    request_count = excluded.request_count;

set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000003';

select throws_ok(
  $$select public.begin_nina_chat_run(
    '82000000-0000-0000-0000-000000000002',
    '84000000-0000-0000-0000-000000000003',
    'Mais uma mensagem',
    '[]'::jsonb,
    'gpt-5.4-mini',
    1000,
    '2026-08-09'
  )$$,
  'P0001',
  'nina_rate_limited',
  'the free household daily window is still closed two hours in'
);

reset role;

update public.nina_chat_rate_limits
set window_started_at = now(), request_count = 9
where user_id = '81000000-0000-0000-0000-000000000003';

set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000003';

select lives_ok(
  $$select public.begin_nina_chat_run(
    '82000000-0000-0000-0000-000000000002',
    '84000000-0000-0000-0000-000000000004',
    'Décima mensagem do dia',
    '[]'::jsonb,
    'gpt-5.4-mini',
    1000,
    '2026-08-09'
  )$$,
  'a free household still gets its tenth message of the day'
);

reset role;

select is(
  (
    select request_count
    from public.nina_chat_rate_limits
    where user_id = '81000000-0000-0000-0000-000000000003'
  ),
  10,
  'the free household claim counts up to ten inside a daily window'
);

insert into public.nina_chat_rate_limits (
  user_id,
  window_started_at,
  request_count
)
values (
  '81000000-0000-0000-0000-000000000001',
  now() - interval '2 hours',
  30
)
on conflict (user_id) do update
set window_started_at = excluded.window_started_at,
    request_count = excluded.request_count;

set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.begin_nina_chat_run(
    '82000000-0000-0000-0000-000000000001',
    '84000000-0000-0000-0000-000000000005',
    'Primeira mensagem da nova hora',
    '[]'::jsonb,
    'gpt-5.4-mini',
    1000,
    '2026-08-09'
  )$$,
  'a paying household window reopens an hour later'
);

reset role;

select is(
  (
    select request_count
    from public.nina_chat_rate_limits
    where user_id = '81000000-0000-0000-0000-000000000001'
  ),
  1,
  'the paying household claim starts a fresh hourly window'
);

update public.nina_chat_rate_limits
set window_started_at = now(), request_count = 29
where user_id = '81000000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.begin_nina_chat_run(
    '82000000-0000-0000-0000-000000000001',
    '84000000-0000-0000-0000-000000000006',
    'Trigésima mensagem da hora',
    '[]'::jsonb,
    'gpt-5.4-mini',
    1000,
    '2026-08-09'
  )$$,
  'a paying household gets thirty messages inside the hour'
);

reset role;

update public.nina_chat_rate_limits
set window_started_at = now(), request_count = 30
where user_id = '81000000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000001';

select throws_ok(
  $$select public.begin_nina_chat_run(
    '82000000-0000-0000-0000-000000000001',
    '84000000-0000-0000-0000-000000000007',
    'Mensagem trinta e um',
    '[]'::jsonb,
    'gpt-5.4-mini',
    1000,
    '2026-08-09'
  )$$,
  'P0001',
  'nina_rate_limited',
  'the paying household hourly quota still stops at thirty'
);

reset role;

-- The supplied family identifier is deliberately wrong: only the server
-- derivation may decide which household a purchase covers.
insert into public.premium_subscriptions (
  original_transaction_id,
  user_id,
  family_id,
  product_id,
  environment,
  status,
  is_active,
  transaction_id,
  expires_at,
  signed_transaction_info
)
values (
  'premium-neighbour-original-transaction',
  '81000000-0000-0000-0000-000000000003',
  '82000000-0000-0000-0000-000000000001',
  'com.heitor.nina.premium.monthly',
  'Sandbox',
  'expired',
  false,
  'premium-neighbour-transaction',
  now() - interval '1 day',
  'signed-transaction-info-example'
);

select is(
  (
    select family_id
    from public.premium_subscriptions
    where original_transaction_id = 'premium-neighbour-original-transaction'
  ),
  '82000000-0000-0000-0000-000000000002'::uuid,
  'a supplied household identifier is replaced by the payer own home'
);

select ok(
  not private.family_has_premium('82000000-0000-0000-0000-000000000002'),
  'an inactive subscription does not cover the household'
);

set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000003';

select is(
  public.get_current_home_context() -> 'premium' ->> 'is_active',
  'false',
  'an expired household subscription leaves the home uncovered'
);

select is(
  public.get_current_home_context() -> 'premium' ->> 'status',
  'expired',
  'the household premium block reports why cover ended'
);

reset role;

delete from public.family_members
where family_id = '82000000-0000-0000-0000-000000000001'
  and user_id = '81000000-0000-0000-0000-000000000001';

select is(
  (
    select family_id
    from public.premium_subscriptions
    where original_transaction_id = 'premium-original-transaction'
  ),
  null::uuid,
  'the payer leaving the home releases the household link'
);

select ok(
  not private.family_has_premium('82000000-0000-0000-0000-000000000001'),
  'the remaining household loses cover when the payer leaves'
);

set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000002';

select is(
  public.get_current_home_context() -> 'premium' ->> 'is_active',
  'false',
  'the next context refresh removes premium from the remaining member'
);

select is(
  public.get_current_home_context() -> 'premium' ->> 'status',
  'inactive',
  'the remaining member sees no residual status from the departed payer'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '81000000-0000-0000-0000-000000000001';

select is(
  public.get_current_premium_status() ->> 'is_active',
  'true',
  'the departing payer keeps their own subscription'
);

select is(
  public.get_current_home_context() -> 'premium' ->> 'is_active',
  'false',
  'a member of no household reads an inactive premium block'
);

reset role;

select * from finish();
rollback;
