begin;

create extension if not exists pgtap with schema extensions;

select plan(48);

create function pg_temp.affected_rows(command text)
returns integer
language plpgsql
as $$
declare
  affected integer;
begin
  execute command;
  get diagnostics affected = row_count;
  return affected;
end;
$$;

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
    '20000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'rls-owner@example.com',
    '{"full_name":"RLS Owner"}'::jsonb,
    now(),
    now()
  ),
  (
    '20000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'rls-member@example.com',
    '{"full_name":"RLS Member"}'::jsonb,
    now(),
    now()
  ),
  (
    '20000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'rls-outsider@example.com',
    '{"full_name":"RLS Outsider"}'::jsonb,
    now(),
    now()
  );

insert into public.families (id, name, invite_code, created_by)
values
  (
    '30000000-0000-0000-0000-000000000001',
    'Owner Family',
    'casa-11111111111111111111111111111111',
    '20000000-0000-0000-0000-000000000001'
  ),
  (
    '30000000-0000-0000-0000-000000000002',
    'Outsider Family',
    'casa-22222222222222222222222222222222',
    '20000000-0000-0000-0000-000000000003'
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
    '40000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    'RLS Owner',
    'Owner',
    'adult',
    'owner',
    'mint'
  ),
  (
    '40000000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000002',
    'RLS Member',
    'Member',
    'adult',
    'member',
    'sky'
  ),
  (
    '40000000-0000-0000-0000-000000000003',
    '30000000-0000-0000-0000-000000000002',
    '20000000-0000-0000-0000-000000000003',
    'RLS Outsider',
    'Owner',
    'adult',
    'owner',
    'coral'
  );

update public.profiles
set active_family_id = case id
  when '20000000-0000-0000-0000-000000000001' then '30000000-0000-0000-0000-000000000001'::uuid
  when '20000000-0000-0000-0000-000000000002' then '30000000-0000-0000-0000-000000000001'::uuid
  else '30000000-0000-0000-0000-000000000002'::uuid
end
where id in (
  '20000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002',
  '20000000-0000-0000-0000-000000000003'
);

insert into public.task_sections (family_id, id, title)
values
  ('30000000-0000-0000-0000-000000000001', 'owner-section', 'Owner Section'),
  ('30000000-0000-0000-0000-000000000002', 'outsider-section', 'Outsider Section');

insert into public.task_categories (family_id, id, title)
values
  ('30000000-0000-0000-0000-000000000001', 'owner-category', 'Owner Category'),
  ('30000000-0000-0000-0000-000000000002', 'outsider-category', 'Outsider Category');

insert into public.tasks (id, family_id, title)
values
  ('50000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Owner Task'),
  ('50000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 'Outsider Task');

insert into public.shopping_items (id, family_id, title)
values
  ('51000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Owner Item'),
  ('51000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 'Outsider Item');

insert into public.chat_messages (id, family_id, sender, text)
values
  ('53000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'user', 'Owner Message'),
  ('53000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 'user', 'Outsider Message');

insert into public.memory_items (id, family_id, title)
values
  ('54000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Owner Memory'),
  ('54000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 'Outsider Memory');

insert into public.household_insights (id, family_id, title)
values
  ('55000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Owner Insight'),
  ('55000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', 'Outsider Insight');

insert into public.family_snapshots (family_id, data)
values
  ('30000000-0000-0000-0000-000000000001', '{"owner":true}'::jsonb),
  ('30000000-0000-0000-0000-000000000002', '{"outsider":true}'::jsonb);

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
  'rls-original-transaction',
  '20000000-0000-0000-0000-000000000001',
  'com.heitor.nina.premium.monthly',
  'Sandbox',
  'active',
  true,
  'rls-transaction',
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
  'rls-transaction',
  'rls-original-transaction',
  '20000000-0000-0000-0000-000000000001',
  'com.heitor.nina.premium.monthly',
  'Sandbox',
  'app_sync',
  'signed-transaction-info-example'
);

select is(
  (
    select count(*)::integer
    from pg_class
    join pg_namespace on pg_namespace.oid = pg_class.relnamespace
    where pg_namespace.nspname = 'public'
      and pg_class.relname in (
        'profiles',
        'families',
        'family_members',
        'task_sections',
        'task_categories',
        'tasks',
        'shopping_items',
        'chat_messages',
        'memory_items',
        'household_insights',
        'family_snapshots',
        'invites',
        'family_join_requests',
        'family_access_decisions',
        'nina_chat_rate_limits',
        'nina_threads',
        'nina_ai_budget_months',
        'nina_ai_family_rate_limits',
        'nina_ai_runs',
        'nina_ai_consents',
        'nina_proposals',
        'waitlist_signups',
        'waitlist_submission_limits',
        'waitlist_deliveries',
        'premium_subscriptions',
        'premium_subscription_transactions',
        'app_store_server_notifications'
      )
      and pg_class.relrowsecurity
  ),
  27,
  'all sensitive public tables have row level security enabled'
);

select hasnt_table(
  'public',
  'reminders',
  'reminders are unified into tasks and no separate table remains'
);

-- Postgres grants execute to PUBLIC on every new function and PUBLIC includes
-- anon, so naming the known offenders would only ever catch the known ones.
-- The canary is the whole set instead: any function added to public without a
-- revoke changes this string and fails the suite. Trigger functions are left
-- out because Postgres refuses to call them directly, and extension-owned
-- functions because they are not ours to grant.
select is(
  (
    select coalesce(
      string_agg(routines.proname, ', ' order by routines.proname),
      ''
    )
    from pg_catalog.pg_proc as routines
    join pg_catalog.pg_namespace as schemas
      on schemas.oid = routines.pronamespace
    where schemas.nspname = 'public'
      and routines.prorettype <> 'pg_catalog.trigger'::regtype
      and not exists (
        select 1
        from pg_catalog.pg_depend as dependencies
        where dependencies.classid = 'pg_catalog.pg_proc'::regclass
          and dependencies.objid = routines.oid
          and dependencies.deptype = 'e'
      )
      and has_function_privilege('anon', routines.oid, 'execute')
  ),
  'get_family_invite_preview',
  'the public invite preview is the only function in public an anonymous client may execute'
);

select is(
  (
    select count(*)::integer
    from pg_catalog.pg_proc as routines
    join pg_catalog.pg_namespace as schemas
      on schemas.oid = routines.pronamespace
    where schemas.nspname = 'public'
      and routines.proname in (
        'is_family_member',
        'can_manage_family',
        'is_family_creator',
        'shares_family_with'
      )
      and has_function_privilege('authenticated', routines.oid, 'execute')
  ),
  4,
  'signed-in clients keep execute on the membership predicates every content policy evaluates'
);

set local role authenticated;
set local request.jwt.claim.sub = '20000000-0000-0000-0000-000000000001';

select is((select count(*)::integer from public.families), 1, 'owner sees only their family');
select is((select count(*)::integer from public.family_members), 2, 'owner sees only their family memberships');
select is((select count(*)::integer from public.profiles), 2, 'owner sees only profiles in their family');
select is((select count(*)::integer from public.task_sections), 1, 'task sections are family scoped');
select is((select count(*)::integer from public.task_categories), 1, 'task categories are family scoped');
select is((select count(*)::integer from public.tasks), 1, 'tasks are family scoped');
select is((select count(*)::integer from public.shopping_items), 1, 'shopping items are family scoped');
select is((select count(*)::integer from public.chat_messages), 1, 'chat messages are family scoped');
select is((select count(*)::integer from public.memory_items), 1, 'memory items are family scoped');
select is((select count(*)::integer from public.household_insights), 1, 'household insights are family scoped');
select is((select count(*)::integer from public.family_snapshots), 1, 'family snapshots are family scoped');
select is((select count(*)::integer from public.premium_subscriptions), 1, 'the payer reads only their own premium subscription');
select is((select count(*)::integer from public.premium_subscription_transactions), 1, 'the payer reads only their own premium transactions');

select lives_ok(
  $$insert into public.tasks (family_id, title) values ('30000000-0000-0000-0000-000000000001', 'New Owner Task')$$,
  'owner can insert a task in their family'
);

select is(
  (select count(*)::integer from public.tasks where title = 'New Owner Task'),
  1,
  'owner can read the task they inserted'
);

select throws_ok(
  $$insert into public.tasks (family_id, title) values ('30000000-0000-0000-0000-000000000002', 'Cross Family Task')$$,
  '42501',
  null,
  'owner cannot insert a task in another family'
);

select is(
  pg_temp.affected_rows(
    $$update public.tasks
      set title = 'Updated Owner Task'
      where id = '50000000-0000-0000-0000-000000000001'$$
  ),
  1,
  'owner can update a task in their family'
);

select is(
  pg_temp.affected_rows(
    $$update public.tasks
      set title = 'Hidden Update'
      where id = '50000000-0000-0000-0000-000000000002'$$
  ),
  0,
  'owner cannot update a task in another family'
);

select is(
  pg_temp.affected_rows(
    $$delete from public.tasks
      where title = 'New Owner Task'$$
  ),
  1,
  'owner can delete a task in their family'
);

select ok(
  not has_table_privilege('authenticated', 'public.family_snapshots', 'insert'),
  'authenticated users cannot insert legacy snapshots'
);

select ok(
  not has_table_privilege('authenticated', 'public.family_snapshots', 'update'),
  'authenticated users cannot update legacy snapshots'
);

select ok(
  not has_table_privilege('authenticated', 'public.families', 'update'),
  'authenticated users cannot directly update families'
);

select ok(
  not has_table_privilege('authenticated', 'public.family_members', 'update'),
  'authenticated users cannot directly update memberships'
);

select ok(
  not has_table_privilege('authenticated', 'public.invites', 'select'),
  'authenticated users cannot directly read invite rows'
);

select ok(
  not has_table_privilege('authenticated', 'public.nina_ai_consents', 'select'),
  'authenticated users cannot directly read AI consent records'
);

select ok(
  not has_table_privilege('authenticated', 'public.family_access_decisions', 'select'),
  'authenticated users cannot directly read who was declined or removed'
);

select ok(
  not has_table_privilege('authenticated', 'public.app_store_server_notifications', 'select'),
  'authenticated users cannot read App Store notification payloads'
);

select ok(
  not has_table_privilege('authenticated', 'public.premium_subscriptions', 'insert, update, delete'),
  'authenticated users cannot write premium subscription state'
);

select is(
  pg_temp.affected_rows(
    $$update public.profiles
      set display_name = 'Not Allowed'
      where id = '20000000-0000-0000-0000-000000000002'$$
  ),
  0,
  'owner cannot update another family member profile'
);

set local request.jwt.claim.sub = '20000000-0000-0000-0000-000000000002';

select is((select count(*)::integer from public.families), 1, 'regular member can read their family');

select lives_ok(
  $$insert into public.shopping_items (family_id, title) values ('30000000-0000-0000-0000-000000000001', 'Member Item')$$,
  'regular member can add family shopping items'
);

select is(
  (select count(*)::integer from public.premium_subscriptions),
  0,
  'household members cannot read the payer premium subscription row'
);

select is(
  (select count(*)::integer from public.premium_subscription_transactions),
  0,
  'household members cannot read the payer premium transactions'
);

set local request.jwt.claim.sub = '20000000-0000-0000-0000-000000000003';

select is(
  (select count(*)::integer from public.families where id = '30000000-0000-0000-0000-000000000001'),
  0,
  'outsider cannot read another family'
);

select is(
  (select count(*)::integer from public.family_members where family_id = '30000000-0000-0000-0000-000000000001'),
  0,
  'outsider cannot read another family memberships'
);

select is(
  (select count(*)::integer from public.profiles where id = '20000000-0000-0000-0000-000000000001'),
  0,
  'outsider cannot read another family profiles'
);

select is(
  (select count(*)::integer from public.tasks where family_id = '30000000-0000-0000-0000-000000000001'),
  0,
  'outsider cannot read another family tasks'
);

select throws_ok(
  $$insert into public.tasks (family_id, title) values ('30000000-0000-0000-0000-000000000001', 'Outsider Task')$$,
  '42501',
  null,
  'outsider cannot insert a task in another family'
);

select is(
  (select count(*)::integer from public.family_snapshots where family_id = '30000000-0000-0000-0000-000000000001'),
  0,
  'outsider cannot read another family snapshot'
);

select is(
  (select count(*)::integer from public.premium_subscriptions),
  0,
  'outsider cannot read another household premium subscription'
);

reset role;

select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'Users can % their own profile photos'
  ),
  4,
  'profile photos have read, upload, update, and delete ownership policies'
);

select is(
  (select public from storage.buckets where id = 'profile-photos'),
  false,
  'profile photo bucket is private'
);

select is(
  (select file_size_limit from storage.buckets where id = 'profile-photos'),
  5242880::bigint,
  'profile photo bucket limits files to five megabytes'
);

select is(
  (select allowed_mime_types from storage.buckets where id = 'profile-photos'),
  array['image/jpeg']::text[],
  'profile photo bucket accepts only JPEG images'
);

select * from finish();

rollback;
