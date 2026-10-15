begin;

create extension if not exists pgtap with schema extensions;

select plan(47);

insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
values
  ('d1000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'delete-owner@example.com', '{"full_name":"Delete Owner"}'::jsonb, now(), now()),
  ('d1000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'delete-admin@example.com', '{"full_name":"Delete Admin"}'::jsonb, now(), now()),
  ('d1000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'delete-member@example.com', '{"full_name":"Delete Member"}'::jsonb, now(), now()),
  ('d1000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'delete-teen@example.com', '{"full_name":"Delete Teen"}'::jsonb, now() - interval '60 days', now()),
  ('d1000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'delete-outsider@example.com', '{"full_name":"Delete Outsider"}'::jsonb, now(), now()),
  ('d1000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'delete-requester@example.com', '{"full_name":"Delete Requester"}'::jsonb, now(), now()),
  ('d1000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'delete-solo@example.com', '{"full_name":"Delete Solo"}'::jsonb, now(), now()),
  ('d1000000-0000-4000-8000-000000000008', 'authenticated', 'authenticated', 'delete-former-adult@example.com', '{"full_name":"Delete Former Adult"}'::jsonb, now(), now()),
  ('d1000000-0000-4000-8000-000000000009', 'authenticated', 'authenticated', 'delete-removed@example.com', '{"full_name":"Delete Removed"}'::jsonb, now(), now());

insert into private.account_age_status (user_id, status, minor_band, assurance, minor_since, recheck_after)
values ('d1000000-0000-4000-8000-000000000004', 'minor', '12_15', 'self_declared', now() - interval '60 days', now() + interval '30 days');

-- Every other fixture account is an Apple-confirmed adult.
insert into private.account_age_status (user_id, status, assurance, recheck_after)
select users.id, 'adult', 'confirmed', now() + interval '180 days'
from auth.users as users
where users.id::text like 'd1000000-%'
on conflict (user_id) do nothing;

set local role authenticated;

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.create_family('Casa da Lúcia')$$,
  'the titular creates the house'
);
select set_config(
  'test.shared_family_id',
  (select active_family_id::text from public.profiles where id = auth.uid()),
  true
);
select set_config('test.shared_invite', public.get_current_home_context() #>> '{family,invite_code}', true);

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000007';
select lives_ok(
  $$select public.create_family('Casa Só Minha')$$,
  'a person alone creates a house of their own'
);
select set_config(
  'test.solo_family_id',
  (select active_family_id::text from public.profiles where id = auth.uid()),
  true
);

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000008';
select lives_ok(
  $$select public.create_family('Casa de Quem Mudou')$$,
  'an adult creates a house before the age reading changes'
);
select set_config(
  'test.former_family_id',
  (select active_family_id::text from public.profiles where id = auth.uid()),
  true
);

reset role;

insert into public.family_members (family_id, user_id, name, relationship, household_role, permission_role, tone)
values
  (current_setting('test.shared_family_id')::uuid, 'd1000000-0000-4000-8000-000000000002', 'Admin', 'Irmão', 'adult', 'admin', 'sky'),
  (current_setting('test.shared_family_id')::uuid, 'd1000000-0000-4000-8000-000000000003', 'Membro', 'Primo', 'adult', 'member', 'coral'),
  (current_setting('test.shared_family_id')::uuid, 'd1000000-0000-4000-8000-000000000009', 'Removida', 'Amiga', 'adult', 'member', 'mint');

update public.profiles
set active_family_id = current_setting('test.shared_family_id')::uuid
where id in (
  'd1000000-0000-4000-8000-000000000002',
  'd1000000-0000-4000-8000-000000000003',
  'd1000000-0000-4000-8000-000000000009'
);

set local role authenticated;

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000004';
select lives_ok(
  $$select public.request_family_join(current_setting('test.shared_invite'))$$,
  'a teen asks to join the house'
);

reset role;
select set_config(
  'test.teen_request',
  (select id::text from public.family_join_requests where requester_user_id = 'd1000000-0000-4000-8000-000000000004'),
  true
);
set local role authenticated;

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000001';
select lives_ok(
  $$select public.approve_family_join_request(current_setting('test.teen_request')::uuid, 'member', 'mae', '12_15', true, '2026-09-29')$$,
  'the titular approves the teen as the teen''s guardian'
);

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000006';
select lives_ok(
  $$select public.request_family_join(current_setting('test.shared_invite'))$$,
  'an adult asks to join and is still waiting when the house is deleted'
);

reset role;

select set_config(
  'test.teen_member_id',
  (
    select id::text
    from public.family_members
    where user_id = 'd1000000-0000-4000-8000-000000000004'
  ),
  true
);

select set_config(
  'test.teen_links',
  (
    select string_agg(id::text, ',')
    from private.minor_guardianships
    where member_id = current_setting('test.teen_member_id')::uuid
  ),
  true
);

select set_config(
  'test.teen_consents',
  (
    select string_agg(id::text, ',')
    from private.minor_data_consents
    where member_id = current_setting('test.teen_member_id')::uuid
  ),
  true
);

insert into public.nina_threads (id, family_id, owner_user_id, visibility)
values ('d3000000-0000-4000-8000-000000000001', current_setting('test.shared_family_id')::uuid, 'd1000000-0000-4000-8000-000000000003', 'private');

insert into public.chat_messages (id, family_id, sender, text, created_by, thread_id)
values (
  'd3000000-0000-4000-8000-000000000002',
  current_setting('test.shared_family_id')::uuid,
  'user',
  'Mensagem antes da casa ser apagada',
  'd1000000-0000-4000-8000-000000000003',
  'd3000000-0000-4000-8000-000000000001'
);

insert into private.child_safety_holds (id, user_id, family_id, content)
values (
  'd4000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000003',
  current_setting('test.shared_family_id')::uuid,
  'conteúdo retido'
);

insert into public.nina_threads (id, family_id, owner_user_id, visibility)
values ('d3000000-0000-4000-8000-000000000010', current_setting('test.shared_family_id')::uuid, 'd1000000-0000-4000-8000-000000000009', 'private');

insert into public.chat_messages (id, family_id, sender, text, created_by, thread_id)
values (
  'd3000000-0000-4000-8000-000000000011',
  current_setting('test.shared_family_id')::uuid,
  'user',
  'Mensagem de quem foi removida antes da casa ser apagada',
  'd1000000-0000-4000-8000-000000000009',
  'd3000000-0000-4000-8000-000000000010'
);

insert into private.child_safety_holds (id, user_id, family_id, content)
values (
  'd4000000-0000-4000-8000-000000000002',
  'd1000000-0000-4000-8000-000000000009',
  current_setting('test.shared_family_id')::uuid,
  'conteúdo retido de quem foi removida'
);

insert into public.nina_ai_budget_months (month_start, purpose, cap_microusd, reserved_microusd, spent_microusd)
values ('2026-01-01', 'interactive', 1000000, 5000, 1000);

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
  'd5000000-0000-4000-8000-000000000001',
  current_setting('test.shared_family_id')::uuid,
  'd1000000-0000-4000-8000-000000000002',
  'interactive',
  'gpt-6-luna',
  'running',
  '2026-09-23',
  5000,
  '2026-01-01'
);

insert into public.nina_ai_consents (id, family_id, user_id, policy_version, transfer_consented_at)
values (
  'd6000000-0000-4000-8000-000000000001',
  current_setting('test.shared_family_id')::uuid,
  'd1000000-0000-4000-8000-000000000002',
  '2026-09-29',
  now()
);

insert into public.nina_threads (id, family_id, owner_user_id, visibility)
values ('d3000000-0000-4000-8000-000000000003', current_setting('test.shared_family_id')::uuid, 'd1000000-0000-4000-8000-000000000002', 'private');

insert into public.chat_messages (id, family_id, sender, text, created_by, thread_id)
values (
  'd3000000-0000-4000-8000-000000000004',
  current_setting('test.shared_family_id')::uuid,
  'user',
  'Pergunta que levou à resposta denunciada',
  'd1000000-0000-4000-8000-000000000002',
  'd3000000-0000-4000-8000-000000000003'
);

insert into public.nina_ai_runs (
  id,
  family_id,
  user_id,
  thread_id,
  request_message_id,
  purpose,
  model,
  status,
  pricing_version,
  reserved_microusd,
  budget_month_start
)
values (
  'd5000000-0000-4000-8000-000000000002',
  current_setting('test.shared_family_id')::uuid,
  'd1000000-0000-4000-8000-000000000002',
  'd3000000-0000-4000-8000-000000000003',
  'd3000000-0000-4000-8000-000000000004',
  'interactive',
  'gpt-6-luna',
  'completed',
  '2026-09-23',
  0,
  '2026-01-01'
);

insert into public.chat_messages (id, family_id, sender, text, thread_id, run_id)
values (
  'd3000000-0000-4000-8000-000000000005',
  current_setting('test.shared_family_id')::uuid,
  'nina',
  'Resposta denunciada da Nina',
  'd3000000-0000-4000-8000-000000000003',
  'd5000000-0000-4000-8000-000000000002'
);

set local role authenticated;
set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000002';
select is(
  public.report_nina_reply('d3000000-0000-4000-8000-000000000005', 'risk_to_someone') ->> 'reported',
  'true',
  'another adult reports a Nina reply in their own thread before the house is deleted'
);
reset role;

insert into public.nina_ai_runs (
  id,
  family_id,
  user_id,
  thread_id,
  request_message_id,
  purpose,
  model,
  status,
  pricing_version,
  reserved_microusd,
  budget_month_start
)
values
  (
    'd5000000-0000-4000-8000-000000000003',
    current_setting('test.shared_family_id')::uuid,
    'd1000000-0000-4000-8000-000000000003',
    'd3000000-0000-4000-8000-000000000001',
    'd3000000-0000-4000-8000-000000000002',
    'interactive',
    'gpt-6-luna',
    'completed',
    '2026-09-23',
    0,
    '2026-01-01'
  );

insert into public.chat_messages (id, family_id, sender, text, thread_id, run_id)
values (
  'd3000000-0000-4000-8000-000000000006',
  current_setting('test.shared_family_id')::uuid,
  'nina',
  'Resposta que o membro denunciou',
  'd3000000-0000-4000-8000-000000000001',
  'd5000000-0000-4000-8000-000000000003'
);

insert into public.nina_threads (id, family_id, owner_user_id, visibility)
values ('d3000000-0000-4000-8000-000000000007', current_setting('test.shared_family_id')::uuid, 'd1000000-0000-4000-8000-000000000001', 'private');

insert into public.chat_messages (id, family_id, sender, text, created_by, thread_id)
values (
  'd3000000-0000-4000-8000-000000000008',
  current_setting('test.shared_family_id')::uuid,
  'user',
  'Pergunta do titular',
  'd1000000-0000-4000-8000-000000000001',
  'd3000000-0000-4000-8000-000000000007'
);

insert into public.nina_ai_runs (
  id,
  family_id,
  user_id,
  thread_id,
  request_message_id,
  purpose,
  model,
  status,
  pricing_version,
  reserved_microusd,
  budget_month_start
)
values (
  'd5000000-0000-4000-8000-000000000004',
  current_setting('test.shared_family_id')::uuid,
  'd1000000-0000-4000-8000-000000000001',
  'd3000000-0000-4000-8000-000000000007',
  'd3000000-0000-4000-8000-000000000008',
  'interactive',
  'gpt-6-luna',
  'completed',
  '2026-09-23',
  0,
  '2026-01-01'
);

insert into public.chat_messages (id, family_id, sender, text, thread_id, run_id)
values (
  'd3000000-0000-4000-8000-000000000009',
  current_setting('test.shared_family_id')::uuid,
  'nina',
  'Resposta que o titular denunciou',
  'd3000000-0000-4000-8000-000000000007',
  'd5000000-0000-4000-8000-000000000004'
);

set local role authenticated;
set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000003';
select is(
  public.report_nina_reply('d3000000-0000-4000-8000-000000000006', 'other') ->> 'reported',
  'true',
  'a second adult reports a Nina reply in their own thread before the house is deleted'
);

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000001';
select is(
  public.report_nina_reply('d3000000-0000-4000-8000-000000000009', 'inappropriate') ->> 'reported',
  'true',
  'the titular reports a Nina reply in their own thread before deleting the house'
);
reset role;

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
  'delete-family-original-transaction',
  'd1000000-0000-4000-8000-000000000001',
  'd1000000-0000-4000-8000-000000000001',
  'com.heitor.nina.premium.monthly',
  'Sandbox',
  'active',
  true,
  'delete-family-transaction',
  now() + interval '30 days',
  'signed-transaction-info-example'
);

select is(
  (
    select family_id
    from public.premium_subscriptions
    where original_transaction_id = 'delete-family-original-transaction'
  ),
  current_setting('test.shared_family_id')::uuid,
  'the titular''s Premium covers the house before it is deleted'
);

select ok(
  not has_function_privilege('anon', 'public.delete_family(uuid, text)', 'execute')
    and not has_function_privilege('service_role', 'public.delete_family(uuid, text)', 'execute')
    and has_function_privilege('authenticated', 'public.delete_family(uuid, text)', 'execute'),
  'only a signed-in client calls delete_family'
);

select ok(
  not has_function_privilege('authenticated', 'private.delete_household(uuid, uuid)', 'execute')
    and not has_function_privilege('service_role', 'private.delete_household(uuid, uuid)', 'execute')
    and not has_function_privilege('authenticated', 'private.settle_household_ai_runs(uuid)', 'execute')
    and not has_function_privilege('service_role', 'private.settle_household_ai_runs(uuid)', 'execute'),
  'no API role reaches the house deletion itself'
);

set local role authenticated;

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000005';
select throws_ok(
  $$select public.delete_family(current_setting('test.shared_family_id')::uuid, 'Casa da Lúcia')$$,
  'P0002',
  'family_not_found',
  'someone outside the house cannot delete it, nor learn that it exists'
);

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000002';
select throws_ok(
  $$select public.delete_family(current_setting('test.shared_family_id')::uuid, 'Casa da Lúcia')$$,
  '42501',
  'family_delete_denied',
  'an admin never deletes the house over the titular'
);

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000003';
select throws_ok(
  $$select public.delete_family(current_setting('test.shared_family_id')::uuid, 'Casa da Lúcia')$$,
  '42501',
  'family_delete_denied',
  'a plain member cannot delete the house'
);

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000004';
select throws_ok(
  $$select public.delete_family(current_setting('test.shared_family_id')::uuid, 'Casa da Lúcia')$$,
  '42501',
  'family_delete_denied',
  'a teen cannot delete the house'
);

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.delete_family(current_setting('test.shared_family_id')::uuid, 'Casa da Lucia Errada')$$,
  '22023',
  'family_delete_name_mismatch',
  'the titular deletes nothing on a name that is not the house''s'
);

select throws_ok(
  $$select public.delete_family(current_setting('test.shared_family_id')::uuid, null)$$,
  '22023',
  'family_delete_name_mismatch',
  'the titular deletes nothing without confirming the name'
);

reset role;

select ok(
  exists (select 1 from public.families where id = current_setting('test.shared_family_id')::uuid)
    and (select status from public.nina_ai_runs where id = 'd5000000-0000-4000-8000-000000000001') = 'running'
    and (
      select reserved_microusd::text || ':' || spent_microusd::text
      from public.nina_ai_budget_months
      where month_start = '2026-01-01' and purpose = 'interactive'
    ) = '5000:1000',
  'a refused deletion changes nothing, the open run and its reservation included'
);

update private.account_age_status
set status = 'minor', minor_band = '16_17', assurance = 'self_declared', minor_since = now()
where user_id = 'd1000000-0000-4000-8000-000000000008';

set local role authenticated;
set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000008';
select throws_ok(
  $$select public.delete_family(current_setting('test.former_family_id')::uuid, 'Casa de Quem Mudou')$$,
  '42501',
  'family_delete_denied',
  'a titular who became a minor keeps the role on the row but cannot delete the house'
);

set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000007';
select lives_ok(
  $$select public.delete_family(current_setting('test.solo_family_id')::uuid, 'Casa Só Minha')$$,
  'a titular alone in the house deletes it'
);

select is(
  public.get_current_home_context() ->> 'family',
  null,
  'the titular who deleted the house is left without one'
);

reset role;

select ok(
  not exists (select 1 from public.families where id = current_setting('test.solo_family_id')::uuid)
    and not exists (select 1 from public.family_members where family_id = current_setting('test.solo_family_id')::uuid)
    and (select active_family_id from public.profiles where id = 'd1000000-0000-4000-8000-000000000007') is null,
  'the solo house, its members and the titular''s active house are gone'
);

select is(
  (
    select count(*)::integer
    from public.family_access_decisions
    where subject_user_id = 'd1000000-0000-4000-8000-000000000007'
  ),
  0,
  'the titular who deleted the house is not told about it as a decision'
);

set local role authenticated;
set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000001';
select public.remove_family_member(
  (
    select members.id
    from public.family_members as members
    where members.family_id = current_setting('test.shared_family_id')::uuid
      and members.user_id = 'd1000000-0000-4000-8000-000000000009'
  )
);
select lives_ok(
  $$select public.delete_family(current_setting('test.shared_family_id')::uuid, '  casa da lúcia ')$$,
  'the titular deletes a house other adults live in, confirming its name in any case'
);

reset role;

select ok(
  not exists (select 1 from public.families where id = current_setting('test.shared_family_id')::uuid)
    and not exists (select 1 from public.family_members where family_id = current_setting('test.shared_family_id')::uuid)
    and not exists (select 1 from public.tasks where family_id = current_setting('test.shared_family_id')::uuid)
    and not exists (select 1 from public.chat_messages where family_id = current_setting('test.shared_family_id')::uuid)
    and not exists (select 1 from public.invites where family_id = current_setting('test.shared_family_id')::uuid)
    and not exists (select 1 from public.family_join_requests where family_id = current_setting('test.shared_family_id')::uuid),
  'the house goes with its members, its content, its invite and its requests'
);

select is(
  (
    select count(*)::integer
    from public.profiles
    where active_family_id = current_setting('test.shared_family_id')::uuid
  ),
  0,
  'nobody keeps the deleted house as their active house'
);

select is(
  (
    select array_agg(subject_user_id::text || ':' || outcome || ':' || house_deleted::text order by subject_user_id)
    from public.family_access_decisions
    where family_name = 'Casa da Lúcia'
  ),
  array[
    'd1000000-0000-4000-8000-000000000002:removed:true',
    'd1000000-0000-4000-8000-000000000003:removed:true',
    'd1000000-0000-4000-8000-000000000004:removed:true',
    'd1000000-0000-4000-8000-000000000006:declined:true',
    'd1000000-0000-4000-8000-000000000009:removed:false'
  ],
  'every other person in the house, and the person still waiting, is told the house was deleted'
);

set local role authenticated;
set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000003';

select is(
  public.get_current_home_context() ->> 'family',
  null,
  'another adult of the deleted house loses it on the next load'
);

select is(
  (public.get_family_access_decision() ->> 'house_deleted')::boolean,
  true,
  'that adult reads the decision as the house having been deleted'
);

select is(
  public.get_family_access_decision() ->> 'outcome',
  'removed',
  'a build that predates the flag still reads a removal, never a refused request'
);

reset role;

select ok(
  (
    select count(*)
    from private.minor_guardianships
    where id = any(string_to_array(current_setting('test.teen_links'), ',')::uuid[])
  ) > 0
    and not exists (
      select 1 from private.minor_guardianships
      where id = any(string_to_array(current_setting('test.teen_links'), ',')::uuid[])
        and (ended_at is null or family_id is not null)
    ),
  'the teen''s guardianship ends with the house and its proof is kept'
);

select ok(
  (
    select count(*)
    from private.minor_data_consents
    where id = any(string_to_array(current_setting('test.teen_consents'), ',')::uuid[])
  ) > 0
    and not exists (
      select 1 from private.minor_data_consents
      where id = any(string_to_array(current_setting('test.teen_consents'), ',')::uuid[])
        and withdrawn_at is null
    ),
  'the consents given for the teen are withdrawn and kept as proof'
);

select ok(
  not exists (
    select 1
    from public.list_minor_accounts_due_for_deletion(100) as due(user_id)
    where due.user_id = 'd1000000-0000-4000-8000-000000000004'
  ),
  'a teen whose house was deleted gets the full thirty days, however old the account'
);

select ok(
  exists (
    select 1 from private.child_safety_holds
    where id = 'd4000000-0000-4000-8000-000000000001'
      and user_id = 'd1000000-0000-4000-8000-000000000003'
      and family_id = current_setting('test.shared_family_id')::uuid
      and content = 'conteúdo retido'
      and deleted_at is null
  ),
  'a child-safety hold is untouched by the house deletion'
);

select ok(
  exists (
    select 1 from private.child_safety_preserved_accounts
    where hold_id = 'd4000000-0000-4000-8000-000000000001'
      and user_id = 'd1000000-0000-4000-8000-000000000003'
      and messages::text like '%Mensagem antes da casa ser apagada%'
  ),
  'an account under a hold has what it wrote in the house sealed before the house goes'
);

select ok(
  exists (
    select 1 from private.child_safety_preserved_accounts
    where hold_id = 'd4000000-0000-4000-8000-000000000002'
      and user_id = 'd1000000-0000-4000-8000-000000000009'
      and memberships = '[]'::jsonb
      and messages::text like '%Mensagem de quem foi removida antes da casa ser apagada%'
  ),
  'an adult under a hold whom the titular removed before deleting the house has what they wrote there sealed too'
);

select is(
  (
    select reserved_microusd::text || ':' || spent_microusd::text
    from public.nina_ai_budget_months
    where month_start = '2026-01-01' and purpose = 'interactive'
  ),
  '0:6000',
  'a run left open by the deletion books its reservation as spent and never strands it'
);

select ok(
  exists (
    select 1
    from public.premium_subscriptions
    where original_transaction_id = 'delete-family-original-transaction'
      and family_id is null
      and is_active
      and status = 'active'
  ),
  'deleting the house leaves the titular''s subscription active and covering no house'
);

select ok(
  exists (
    select 1
    from public.nina_ai_consents
    where id = 'd6000000-0000-4000-8000-000000000001'
      and user_id = 'd1000000-0000-4000-8000-000000000002'
      and family_id is null
      and revoked_at is not null
      and revoke_reason = 'house_deleted'
      and transfer_consented_at is not null
  ),
  'another adult''s AI consent outlives the house, withdrawn and still proving the grant and the transfer'
);

select ok(
  exists (
    select 1
    from private.nina_reply_reports
    where reporter_user_id = 'd1000000-0000-4000-8000-000000000002'
      and reason = 'risk_to_someone'
      and reply_text = 'Resposta denunciada da Nina'
      and request_text = 'Pergunta que levou à resposta denunciada'
      and message_id is null
      and run_id is null
      and family_id is null
  ),
  'a reply another adult reported keeps its words and the request behind it for review after the titular deletes the house'
);

select ok(
  exists (
    select 1
    from private.nina_reply_reports
    where reporter_user_id = 'd1000000-0000-4000-8000-000000000003'
      and reply_text = 'Resposta que o membro denunciou'
      and request_text = 'Mensagem antes da casa ser apagada'
  ),
  'a second adult''s report keeps its own copy after the house is deleted'
);

select ok(
  exists (
    select 1
    from private.nina_reply_reports
    where reporter_user_id = 'd1000000-0000-4000-8000-000000000001'
      and reason = 'inappropriate'
      and reply_text is null
      and request_text is null
      and message_id is null
  ),
  'a reply the titular reported goes with the house they deleted, as clearing their own conversation would take it'
);

set local role authenticated;
set local request.jwt.claim.sub = 'd1000000-0000-4000-8000-000000000003';
select set_config(
  'test.new_family_id',
  public.create_family('Casa Nova') #>> '{family,id}',
  true
);
reset role;

select public.prepare_account_deletion('d1000000-0000-4000-8000-000000000003');

select ok(
  exists (
    select 1
    from private.child_safety_preserved_accounts as preserved
    where preserved.hold_id = 'd4000000-0000-4000-8000-000000000001'
      and jsonb_array_length(preserved.memberships) = 2
      and preserved.memberships @> jsonb_build_array(
        jsonb_build_object('family_id', current_setting('test.shared_family_id'))
      )
      and preserved.memberships @> jsonb_build_array(
        jsonb_build_object('family_id', current_setting('test.new_family_id'))
      )
      and preserved.messages::text like '%Mensagem antes da casa ser apagada%'
  ),
  'a held account deleted after its house adds the house it made since to the preserved copy, losing nothing taken before'
);

select ok(
  exists (
    select 1
    from private.nina_reply_reports
    where reporter_user_id = 'd1000000-0000-4000-8000-000000000003'
      and reason = 'other'
      and reply_text is null
      and request_text is null
  ),
  'the reporter''s account deletion erases the words a deleted house left on their report and keeps the report'
);

do $retention$ begin perform public.run_nina_retention(); end $retention$;

select ok(
  exists (
    select 1
    from private.nina_reply_reports
    where reporter_user_id = 'd1000000-0000-4000-8000-000000000002'
      and reply_text is not null
      and request_text is not null
  ),
  'retention keeps the words a deleted house left on a report inside its ninety days'
);

update private.nina_reply_reports
set created_at = now() - interval '91 days'
where reporter_user_id = 'd1000000-0000-4000-8000-000000000002';

do $retention$ begin perform public.run_nina_retention(); end $retention$;

select ok(
  exists (
    select 1
    from private.nina_reply_reports
    where reporter_user_id = 'd1000000-0000-4000-8000-000000000002'
      and reason = 'risk_to_someone'
      and reply_text is null
      and request_text is null
  ),
  'ninety days after the report, retention clears the kept words and keeps the report'
);

select * from finish();
rollback;
