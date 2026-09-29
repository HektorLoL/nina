begin;

create extension if not exists pgtap with schema extensions;

select plan(34);

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
    '71000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'deleting-owner@example.com',
    '{"full_name":"Deleting Owner"}'::jsonb,
    now(),
    now()
  ),
  (
    '71000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'replacement-admin@example.com',
    '{"full_name":"Replacement Admin"}'::jsonb,
    now(),
    now()
  ),
  (
    '71000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'no-house@example.com',
    '{"full_name":"No House"}'::jsonb,
    now(),
    now()
  ),
  (
    '71000000-0000-0000-0000-000000000004',
    'authenticated',
    'authenticated',
    'minor-without-house@example.com',
    '{"full_name":"Minor Without House"}'::jsonb,
    now(),
    now()
  ),
  (
    '71000000-0000-0000-0000-000000000005',
    'authenticated',
    'authenticated',
    'minor-ward@example.com',
    '{"full_name":"Minor Ward"}'::jsonb,
    now(),
    now()
  ),
  (
    '71000000-0000-0000-0000-000000000006',
    'authenticated',
    'authenticated',
    'only-adult@example.com',
    '{"full_name":"Only Adult"}'::jsonb,
    now(),
    now()
  );

-- Every fixture account is an Apple-confirmed adult unless a test says otherwise.
insert into private.account_age_status (user_id, status, assurance, recheck_after)
select users.id, 'adult', 'confirmed', now() + interval '180 days'
from auth.users as users
on conflict (user_id) do nothing;

update private.account_age_status
set status = 'minor', minor_band = '12_15', assurance = 'self_declared', minor_since = now()
where user_id in (
  '71000000-0000-0000-0000-000000000004',
  '71000000-0000-0000-0000-000000000005'
);

insert into public.families (id, name, invite_code, created_by)
values (
  '72000000-0000-0000-0000-000000000004',
  'House with one adult',
  'casa-abababababababababababababababab',
  '71000000-0000-0000-0000-000000000006'
);

insert into public.family_members (id, family_id, user_id, name, relationship, household_role, permission_role, tone)
values
  (
    '73000000-0000-0000-0000-000000000006',
    '72000000-0000-0000-0000-000000000004',
    '71000000-0000-0000-0000-000000000006',
    'Only Adult',
    'Mãe',
    'adult',
    'owner',
    'mint'
  ),
  (
    '73000000-0000-0000-0000-000000000005',
    '72000000-0000-0000-0000-000000000004',
    '71000000-0000-0000-0000-000000000005',
    'Minor Ward',
    'Filho',
    'teen',
    'member',
    'sky'
  );

insert into private.minor_profiles (member_id, family_id, declared_band)
values (
  '73000000-0000-0000-0000-000000000005',
  '72000000-0000-0000-0000-000000000004',
  '12_15'
);

insert into private.minor_guardianships (
  family_id,
  member_id,
  guardian_user_id,
  guardian_user_hash,
  relationship,
  consent_text_version,
  guardian_assurance
)
values (
  '72000000-0000-0000-0000-000000000004',
  '73000000-0000-0000-0000-000000000005',
  '71000000-0000-0000-0000-000000000006',
  private.user_hash('71000000-0000-0000-0000-000000000006'),
  'mae',
  '2026-09-29',
  'confirmed'
);

insert into public.families (id, name, invite_code, created_by)
values
  (
    '72000000-0000-0000-0000-000000000001',
    'Shared deletion home',
    'casa-dddddddddddddddddddddddddddddddd',
    '71000000-0000-0000-0000-000000000001'
  ),
  (
    '72000000-0000-0000-0000-000000000002',
    'Solo deletion home',
    'casa-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    '71000000-0000-0000-0000-000000000001'
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
    '72000000-0000-0000-0000-000000000001',
    '71000000-0000-0000-0000-000000000001',
    'Deleting Owner',
    'Owner',
    'adult',
    'owner',
    'mint'
  ),
  (
    '72000000-0000-0000-0000-000000000001',
    '71000000-0000-0000-0000-000000000002',
    'Replacement Admin',
    'Admin',
    'adult',
    'admin',
    'sky'
  ),
  (
    '72000000-0000-0000-0000-000000000002',
    '71000000-0000-0000-0000-000000000001',
    'Deleting Owner',
    'Owner',
    'adult',
    'owner',
    'mint'
  );

insert into public.invites (
  token,
  family_id,
  expires_at,
  max_uses,
  accepted_by,
  created_by
)
values
  (
    'casa-dddddddddddddddddddddddddddddddd',
    '72000000-0000-0000-0000-000000000001',
    now() + interval '7 days',
    7,
    array[
      '71000000-0000-0000-0000-000000000001'::uuid,
      '71000000-0000-0000-0000-000000000002'::uuid
    ],
    '71000000-0000-0000-0000-000000000001'
  ),
  (
    'casa-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    '72000000-0000-0000-0000-000000000002',
    now() + interval '7 days',
    7,
    array[]::uuid[],
    '71000000-0000-0000-0000-000000000001'
  );

update public.profiles
set active_family_id = '72000000-0000-0000-0000-000000000001'
where id = '71000000-0000-0000-0000-000000000001';

insert into public.nina_threads (id, family_id, owner_user_id, visibility)
values (
  '73000000-0000-0000-0000-000000000001',
  '72000000-0000-0000-0000-000000000001',
  '71000000-0000-0000-0000-000000000001',
  'private'
);

insert into public.chat_messages (
  id,
  family_id,
  sender,
  text,
  created_by,
  thread_id
)
values (
  '74000000-0000-0000-0000-000000000001',
  '72000000-0000-0000-0000-000000000001',
  'user',
  'Private deletion fixture',
  '71000000-0000-0000-0000-000000000001',
  '73000000-0000-0000-0000-000000000001'
);

insert into public.memory_items (
  id,
  family_id,
  title,
  body,
  source,
  created_by,
  owner_user_id,
  visibility,
  status
)
values (
  '75000000-0000-0000-0000-000000000001',
  '72000000-0000-0000-0000-000000000001',
  'Private deletion memory',
  'Fixture body',
  'manual',
  '71000000-0000-0000-0000-000000000001',
  '71000000-0000-0000-0000-000000000001',
  'private',
  'confirmed'
);

insert into public.tasks (
  id,
  family_id,
  title,
  created_by,
  created_by_label
)
values (
  '76000000-0000-0000-0000-000000000001',
  '72000000-0000-0000-0000-000000000001',
  'Shared task survives account deletion',
  '71000000-0000-0000-0000-000000000001',
  'Deleting Owner'
);

select has_function(
  'public',
  'prepare_account_deletion',
  array['uuid'],
  'account deletion has a transactional preparation RPC'
);

select has_trigger(
  'auth',
  'users',
  'prepare_account_deletion_before_auth_delete',
  'Auth deletion repeats preparation in the same transaction'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.prepare_account_deletion(uuid)',
    'execute'
  ),
  'anonymous clients cannot prepare another account for deletion'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.prepare_account_deletion(uuid)',
    'execute'
  ),
  'authenticated clients cannot call the privileged deletion RPC directly'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.prepare_account_deletion(uuid)',
    'execute'
  ),
  'the account deletion Edge Function can execute the preparation RPC'
);

set local role service_role;

select throws_ok(
  $$select public.prepare_account_deletion(null)$$,
  '22023',
  'account_deletion_user_required',
  'the preparation RPC rejects a missing target user'
);

select set_config(
  'test.account_deletion_result',
  public.prepare_account_deletion(
    '71000000-0000-0000-0000-000000000001'
  )::text,
  true
);

select is(
  current_setting('test.account_deletion_result')::jsonb ->> 'prepared',
  'true',
  'the database preparation completes'
);

reset role;

select is(
  (
    select created_by
    from public.families
    where id = '72000000-0000-0000-0000-000000000001'
  ),
  '71000000-0000-0000-0000-000000000002'::uuid,
  'the shared family creator transfers to the replacement adult'
);

select is(
  (
    select permission_role
    from public.family_members
    where family_id = '72000000-0000-0000-0000-000000000001'
      and user_id = '71000000-0000-0000-0000-000000000002'
  ),
  'owner',
  'the replacement adult becomes owner when no owner remains'
);

select is(
  (
    select count(*)::integer
    from public.family_members
    where user_id = '71000000-0000-0000-0000-000000000001'
  ),
  0,
  'the departing account has no remaining household membership'
);

select is(
  (
    select created_by
    from public.invites
    where token = 'casa-dddddddddddddddddddddddddddddddd'
  ),
  '71000000-0000-0000-0000-000000000002'::uuid,
  'shared invite ownership transfers away from the departing account'
);

select ok(
  (
    select revoked_at is not null
    from public.invites
    where token = 'casa-dddddddddddddddddddddddddddddddd'
  ),
  'an active invite created by the departing owner is revoked'
);

select ok(
  not (
    '71000000-0000-0000-0000-000000000001'::uuid = any(
      coalesce(
        (
          select accepted_by
          from public.invites
          where token = 'casa-dddddddddddddddddddddddddddddddd'
        ),
        '{}'::uuid[]
      )
    )
  ),
  'the departing user identifier is removed from invite acceptance history'
);

select is(
  (
    select count(*)::integer
    from public.families
    where id = '72000000-0000-0000-0000-000000000002'
  ),
  0,
  'a home with no other claimed member is deleted'
);

select is(
  (
    select count(*)::integer
    from public.invites
    where token = 'casa-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
  ),
  0,
  'the solo home invite is removed by cascade'
);

select is(
  (
    select count(*)::integer
    from public.nina_threads
    where owner_user_id = '71000000-0000-0000-0000-000000000001'
  ),
  0,
  'private Nina threads are removed'
);

select is(
  (
    select count(*)::integer
    from public.memory_items
    where owner_user_id = '71000000-0000-0000-0000-000000000001'
       or created_by = '71000000-0000-0000-0000-000000000001'
  ),
  0,
  'private and authored Nina memories are removed'
);

select is(
  (
    select count(*)::integer
    from public.chat_messages
    where created_by = '71000000-0000-0000-0000-000000000001'
  ),
  0,
  'private authored chat messages are removed'
);

select is(
  (
    select count(*)::integer
    from public.tasks
    where id = '76000000-0000-0000-0000-000000000001'
  ),
  1,
  'shared household tasks remain available to the other member'
);

select is(
  (
    select active_family_id
    from public.profiles
    where id = '71000000-0000-0000-0000-000000000001'
  ),
  null,
  'the departing profile no longer points at a shared home'
);

select lives_ok(
  $$
    select public.prepare_account_deletion(
      '71000000-0000-0000-0000-000000000001'
    )
  $$,
  'database preparation is idempotent'
);

reset role;

-- Simulate a restrictive row created after the Edge Function preparation but
-- before the Auth Admin API reaches the database.
insert into public.families (id, name, invite_code, created_by)
values (
  '72000000-0000-0000-0000-000000000003',
  'Late deletion home',
  'casa-ffffffffffffffffffffffffffffffff',
  '71000000-0000-0000-0000-000000000001'
);

insert into public.invites (
  token,
  family_id,
  expires_at,
  max_uses,
  created_by
)
values (
  'casa-ffffffffffffffffffffffffffffffff',
  '72000000-0000-0000-0000-000000000003',
  now() + interval '7 days',
  7,
  '71000000-0000-0000-0000-000000000001'
);

select lives_ok(
  $$
    delete from auth.users
    where id = '71000000-0000-0000-0000-000000000001'
  $$,
  'Auth deletion is no longer blocked by restrictive family or invite references'
);

select is(
  (
    select count(*)::integer
    from auth.users
    where id = '71000000-0000-0000-0000-000000000001'
  ),
  0,
  'the target Auth user is deleted'
);

select is(
  (
    select count(*)::integer
    from public.families
    where id = '72000000-0000-0000-0000-000000000003'
  ),
  0,
  'the Auth trigger removes a late restrictive reference before deletion'
);

select is(
  (
    select count(*)::integer
    from public.families
    where id = '72000000-0000-0000-0000-000000000001'
  ),
  1,
  'the shared family remains after Auth deletion'
);

select is(
  (
    select created_by
    from public.tasks
    where id = '76000000-0000-0000-0000-000000000001'
  ),
  null,
  'shared records automatically unlink the deleted creator identifier'
);

select is(
  (
    select count(*)::integer
    from public.invites
    where created_by = '71000000-0000-0000-0000-000000000001'
       or '71000000-0000-0000-0000-000000000001'::uuid = any(accepted_by)
  ),
  0,
  'no invitation retains the deleted user identifier'
);

set local role service_role;

select is(
  public.prepare_account_deletion('71000000-0000-0000-0000-000000000003') ->> 'prepared',
  'true',
  'a signed-in person with no house is prepared for deletion like anyone else'
);

reset role;

select lives_ok(
  $$
    delete from auth.users
    where id = '71000000-0000-0000-0000-000000000003'
  $$,
  'a person with no house is deleted from Auth without a membership to unwind'
);

set local role service_role;

select is(
  public.prepare_account_deletion('71000000-0000-0000-0000-000000000006') ->> 'solo_families_deleted',
  '1',
  'a house is never handed to a minor: with no adult left it is deleted'
);

reset role;

select is(
  (
    select outcome
    from public.family_access_decisions
    where subject_user_id = '71000000-0000-0000-0000-000000000005'
    order by decided_at desc
    limit 1
  ),
  'removed',
  'the minor left behind is told the house is gone instead of being dropped silently'
);

select is(
  (
    select end_reason
    from private.minor_guardianships
    where guardian_user_hash = private.user_hash('71000000-0000-0000-0000-000000000006')
  ),
  'account_deleted',
  'a guardianship ends, and its proof stays, when the guardian deletes the account'
);

select ok(
  not exists (
    select 1
    from public.list_minor_accounts_due_for_deletion(100) as due(user_id)
    where due.user_id = '71000000-0000-0000-0000-000000000004'
  ),
  'a minor account without a house is not deleted before thirty days have passed'
);

update auth.users
set created_at = now() - interval '31 days'
where id = '71000000-0000-0000-0000-000000000004';

update private.account_age_status
set minor_since = now() - interval '31 days'
where user_id = '71000000-0000-0000-0000-000000000004';

select ok(
  exists (
    select 1
    from public.list_minor_accounts_due_for_deletion(100) as due(user_id)
    where due.user_id = '71000000-0000-0000-0000-000000000004'
  ),
  'a minor account thirty days without a house is handed to maintenance for deletion'
);

select * from finish();
rollback;
