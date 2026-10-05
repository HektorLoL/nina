begin;

create extension if not exists pgtap with schema extensions;

select plan(19);

insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
values
  ('71000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'leave-owner@example.com', '{"full_name":"Leave Owner"}'::jsonb, now(), now()),
  ('71000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'leave-member@example.com', '{"full_name":"Leave Member"}'::jsonb, now(), now()),
  ('71000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'leave-guardian@example.com', '{"full_name":"Leave Guardian"}'::jsonb, now(), now()),
  ('71000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'leave-outsider@example.com', '{"full_name":"Leave Outsider"}'::jsonb, now(), now()),
  ('71000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'leave-teen@example.com', '{"full_name":"Leave Teen"}'::jsonb, now(), now());

insert into private.account_age_status (user_id, status, minor_band, assurance, minor_since, recheck_after)
values ('71000000-0000-0000-0000-000000000005', 'minor', '12_15', 'self_declared', now(), now() + interval '30 days');

-- Every other fixture account is an Apple-confirmed adult.
insert into private.account_age_status (user_id, status, assurance, recheck_after)
select users.id, 'adult', 'confirmed', now() + interval '180 days'
from auth.users as users
where users.id::text like '71000000-%'
on conflict (user_id) do nothing;

set local role authenticated;
set local request.jwt.claim.sub = '71000000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.create_family('Casa Para Sair')$$,
  'the owner creates the house'
);

select set_config(
  'test.leave_family_id',
  (select active_family_id::text from public.profiles where id = auth.uid()),
  true
);

reset role;

insert into public.family_members (family_id, user_id, name, relationship, household_role, permission_role, tone)
values
  (current_setting('test.leave_family_id')::uuid, '71000000-0000-0000-0000-000000000002', 'Membro', 'Irmão', 'adult', 'member', 'sky'),
  (current_setting('test.leave_family_id')::uuid, '71000000-0000-0000-0000-000000000003', 'Guardiã', 'Mãe', 'adult', 'admin', 'coral');

update public.profiles
set active_family_id = current_setting('test.leave_family_id')::uuid
where id in ('71000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000003');

insert into public.tasks (family_id, title, owner_label, owner_member_id, created_by)
select
  members.family_id,
  'Levar o lixo',
  members.name,
  members.id,
  '71000000-0000-0000-0000-000000000001'
from public.family_members as members
where members.user_id = '71000000-0000-0000-0000-000000000002';

set local role authenticated;
set local request.jwt.claim.sub = '71000000-0000-0000-0000-000000000003';

select lives_ok(
  $$
    select public.add_minor_profile(
      current_setting('test.leave_family_id')::uuid,
      'Bia',
      'under_12',
      'mae',
      '2026-09-29',
      false,
      '{}'::text[],
      'Filha',
      'amber'
    )
  $$,
  'the guardian adds a child profile with a declaration and a consent'
);

set local request.jwt.claim.sub = '71000000-0000-0000-0000-000000000004';

select throws_ok(
  $$select public.leave_family(current_setting('test.leave_family_id')::uuid)$$,
  'P0002',
  'family_not_found',
  'someone outside the house cannot leave it, nor learn that it exists'
);

set local request.jwt.claim.sub = '71000000-0000-0000-0000-000000000001';
select set_config('test.leave_invite', public.get_current_home_context() #>> '{family,invite_code}', true);

set local request.jwt.claim.sub = '71000000-0000-0000-0000-000000000005';
select lives_ok(
  $$select public.request_family_join(current_setting('test.leave_invite'))$$,
  'a teen asks to join the house'
);

reset role;
select set_config(
  'test.leave_teen_request',
  (select id::text from public.family_join_requests where requester_user_id = '71000000-0000-0000-0000-000000000005'),
  true
);
set local role authenticated;

set local request.jwt.claim.sub = '71000000-0000-0000-0000-000000000001';
select lives_ok(
  $$select public.approve_family_join_request(current_setting('test.leave_teen_request')::uuid, 'member', 'mae', '12_15', true, '2026-09-29')$$,
  'the owner approves the teen as the teen''s guardian'
);

set local request.jwt.claim.sub = '71000000-0000-0000-0000-000000000005';
select throws_ok(
  $$select public.leave_family(current_setting('test.leave_family_id')::uuid)$$,
  '42501',
  'family_leave_denied',
  'a teen never leaves the house on their own; only a guardian takes them out'
);

set local request.jwt.claim.sub = '71000000-0000-0000-0000-000000000001';

select throws_ok(
  $$select public.leave_family(current_setting('test.leave_family_id')::uuid)$$,
  'P0001',
  'family_owner_cannot_leave',
  'the owner cannot leave the house without a successor'
);

set local request.jwt.claim.sub = '71000000-0000-0000-0000-000000000002';

select lives_ok(
  $$select public.leave_family(current_setting('test.leave_family_id')::uuid)$$,
  'an adult member leaves the house on their own'
);

reset role;

select is(
  (
    select count(*)::integer
    from public.family_members
    where family_id = current_setting('test.leave_family_id')::uuid
      and user_id = '71000000-0000-0000-0000-000000000002'
  ),
  0,
  'the leaver no longer has a place in the house'
);

select is(
  (select active_family_id from public.profiles where id = '71000000-0000-0000-0000-000000000002'),
  null,
  'the leaver has no active house any more'
);

select is(
  (
    select owner_member_id
    from public.tasks
    where family_id = current_setting('test.leave_family_id')::uuid
      and title = 'Levar o lixo'
  ),
  null,
  'the leaver''s task stays in the house and falls back to it'
);

select is(
  (
    select count(*)::integer
    from public.family_access_decisions
    where subject_user_id = '71000000-0000-0000-0000-000000000002'
  ),
  0,
  'leaving on purpose is not recorded as a removal the leaver must be told about'
);

select is(
  (
    select count(*)::integer
    from public.family_members
    where family_id = current_setting('test.leave_family_id')::uuid
      and user_id = '71000000-0000-0000-0000-000000000001'
  ),
  1,
  'the owner stays in the house'
);

set local role authenticated;
set local request.jwt.claim.sub = '71000000-0000-0000-0000-000000000003';

select lives_ok(
  $$select public.leave_family(current_setting('test.leave_family_id')::uuid)$$,
  'a guardian leaves the house'
);

reset role;

select is(
  (
    select count(*)::integer
    from private.minor_guardianships
    where guardian_user_id = '71000000-0000-0000-0000-000000000003'
      and ended_at is null
  ),
  0,
  'a guardianship never outlives the guardian''s place in the ward''s house'
);

select is(
  (
    select end_reason
    from private.minor_guardianships
    where guardian_user_id = '71000000-0000-0000-0000-000000000003'
    limit 1
  ),
  'guardian_left',
  'the guardianship ends as the guardian having left'
);

select is(
  (
    select count(*)::integer
    from private.minor_data_consents
    where guardian_user_hash = private.user_hash('71000000-0000-0000-0000-000000000003')
      and withdrawn_at is null
  ),
  0,
  'the consents the guardian gave in the house are withdrawn'
);

select ok(
  not has_function_privilege('anon', 'public.leave_family(uuid)', 'execute'),
  'a signed-out client cannot call leave_family'
);

select ok(
  has_function_privilege('authenticated', 'public.leave_family(uuid)', 'execute'),
  'a signed-in client can call leave_family'
);

select * from finish();
rollback;
