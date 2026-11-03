begin;

create extension if not exists pgtap with schema extensions;

select plan(25);

insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
values
  ('7a000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'one-alice@example.com', '{"full_name":"Alice Titular"}'::jsonb, now(), now()),
  ('7a000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'one-bruno@example.com', '{"full_name":"Bruno Titular"}'::jsonb, now(), now()),
  ('7a000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'one-carla@example.com', '{"full_name":"Carla Membro"}'::jsonb, now(), now()),
  ('7a000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'one-davi@example.com', '{"full_name":"Davi Pedido"}'::jsonb, now(), now()),
  ('7a000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'one-eva@example.com', '{"full_name":"Eva Criadora"}'::jsonb, now(), now()),
  ('7a000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'one-fabio@example.com', '{"full_name":"Fabio Volta"}'::jsonb, now(), now()),
  ('7a000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'one-gil@example.com', '{"full_name":"Gil Ido"}'::jsonb, now(), now()),
  ('7a000000-0000-4000-8000-000000000008', 'authenticated', 'authenticated', 'one-hugo@example.com', '{"full_name":"Hugo Antigo"}'::jsonb, now(), now());

-- Every fixture account is an Apple-confirmed adult.
insert into private.account_age_status (user_id, status, assurance, recheck_after)
select users.id, 'adult', 'confirmed', now() + interval '180 days'
from auth.users as users
where users.id::text like '7a000000-%';

set local role authenticated;

set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000001';
select lives_ok($$select public.create_family('Casa Alfa')$$, 'a person with no house creates one');
select set_config('test.house_a', (select active_family_id::text from public.profiles where id = auth.uid()), true);
select set_config('test.invite_a', public.get_current_home_context() #>> '{family,invite_code}', true);

set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000002';
select lives_ok($$select public.create_family('Casa Beta')$$, 'another person with no house creates another');
select set_config('test.house_b', (select active_family_id::text from public.profiles where id = auth.uid()), true);
select set_config('test.invite_b', public.get_current_home_context() #>> '{family,invite_code}', true);

set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000003';
select public.request_family_join(current_setting('test.invite_a'));

reset role;
select set_config('test.request_carla', (select id::text from public.family_join_requests where requester_user_id = '7a000000-0000-4000-8000-000000000003'), true);
set local role authenticated;

set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000001';
select public.approve_family_join_request(current_setting('test.request_carla')::uuid, 'member');

set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000003';

select throws_ok(
  $$select public.request_family_join(current_setting('test.invite_b'))$$,
  'P0001',
  'family_membership_exists',
  'a member of one house cannot ask to join another'
);

select throws_ok(
  $$select public.create_family('Casa da Carla')$$,
  'P0001',
  'family_membership_exists',
  'a member of one house cannot create another'
);

select is(
  public.request_family_join(current_setting('test.invite_a')) ->> 'status',
  'member',
  'a member opening their own house''s invite still lands in it'
);

set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000001';

select throws_ok(
  $$select public.request_family_join(current_setting('test.invite_b'))$$,
  'P0001',
  'family_membership_exists',
  'a titular cannot ask to join another house'
);

select throws_ok(
  $$select public.create_family('Casa Alfa Dois')$$,
  'P0001',
  'family_membership_exists',
  'a titular cannot create a second house'
);

select throws_ok(
  $$select public.create_family('Casa Alfa Dois', 'casa-alfa-dois')$$,
  '42501',
  null,
  'the two-argument create_family stays out of reach of the signed-in role'
);

set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000004';
select public.request_family_join(current_setting('test.invite_a'));
select public.request_family_join(current_setting('test.invite_b'));

reset role;

select is(
  (
    select string_agg(requests.status, ',' order by families.name)
    from public.family_join_requests as requests
    join public.families on families.id = requests.family_id
    where requests.requester_user_id = '7a000000-0000-4000-8000-000000000004'
  ),
  'cancelled,pending',
  'a new request cancels the person''s request to another house, so one stays pending'
);

set local role authenticated;
set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000005';
select public.request_family_join(current_setting('test.invite_b'));
select lives_ok($$select public.create_family('Casa Eva')$$, 'a person with a pending request may still create a house');

reset role;

select set_config('test.request_eva', (select id::text from public.family_join_requests where requester_user_id = '7a000000-0000-4000-8000-000000000005'), true);

select is(
  (select status from public.family_join_requests where id = current_setting('test.request_eva')::uuid),
  'cancelled',
  'creating a house cancels the person''s pending request'
);

set local role authenticated;
set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000002';

select throws_ok(
  $$select public.approve_family_join_request(current_setting('test.request_eva')::uuid, 'member')$$,
  'P0002',
  'join_request_not_pending',
  'approving someone who created a house meanwhile reads as a request that no longer holds'
);

set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000007';
select public.request_family_join(current_setting('test.invite_b'));

reset role;

select set_config('test.request_gil', (select id::text from public.family_join_requests where requester_user_id = '7a000000-0000-4000-8000-000000000007'), true);

insert into public.family_members (family_id, user_id, name, relationship, household_role, permission_role, tone)
values (current_setting('test.house_a')::uuid, '7a000000-0000-4000-8000-000000000007', 'Gil', 'Amigo', 'adult', 'member', 'sky');

set local role authenticated;
set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000002';

select throws_ok(
  $$select public.approve_family_join_request(current_setting('test.request_gil')::uuid, 'member')$$,
  'P0002',
  'join_request_not_pending',
  'an approval re-checks the requester and names no other house when they are already in one'
);

reset role;

select ok(
  not exists (
    select 1
    from public.family_members
    where family_id = current_setting('test.house_b')::uuid
      and user_id = '7a000000-0000-4000-8000-000000000007'
  ),
  'the refused approval adds nobody to the house'
);

select throws_ok(
  $$insert into public.family_members (family_id, user_id, name, relationship, household_role, permission_role, tone) values (current_setting('test.house_b')::uuid, '7a000000-0000-4000-8000-000000000003', 'Carla', 'Amiga', 'adult', 'member', 'sky')$$,
  'P0001',
  'family_membership_exists',
  'the table refuses a second claimed membership even without the RPCs'
);

select lives_ok(
  $$insert into public.family_members (family_id, name, relationship, household_role, permission_role, tone) values (current_setting('test.house_a')::uuid, 'Pedro', 'Filho', 'pet', 'member', 'sky'), (current_setting('test.house_b')::uuid, 'Pedro', 'Filho', 'pet', 'member', 'sky')$$,
  'profiles without an account may be listed in two houses'
);

select is(
  (
    select count(*)::integer
    from pg_proc
    where proname in ('lock_account', 'claimed_house_elsewhere', 'enforce_one_house_per_account', 'retire_access_decisions_on_join')
      and pronamespace = 'private'::regnamespace
      and (
        has_function_privilege('anon', oid, 'execute')
        or has_function_privilege('authenticated', oid, 'execute')
        or has_function_privilege('service_role', oid, 'execute')
      )
  ),
  0,
  'no API role executes the one-house helpers'
);

select ok(
  position('pg_advisory_xact_lock' in lower(pg_get_functiondef('public.request_family_join(text)'::regprocedure)))
    < position('private.lock_account' in lower(pg_get_functiondef('public.request_family_join(text)'::regprocedure)))
  and position('private.lock_account' in lower(pg_get_functiondef('public.request_family_join(text)'::regprocedure)))
    < position('for update' in lower(pg_get_functiondef('public.request_family_join(text)'::regprocedure))),
  'a join request takes the account lock after the family lock and before any row lock'
);

select ok(
  position('pg_advisory_xact_lock' in lower(pg_get_functiondef('public.approve_family_join_request(uuid,text,text,text,boolean,text,boolean,text[])'::regprocedure)))
    < position('private.lock_account' in lower(pg_get_functiondef('public.approve_family_join_request(uuid,text,text,text,boolean,text,boolean,text[])'::regprocedure)))
  and position('private.lock_account' in lower(pg_get_functiondef('public.approve_family_join_request(uuid,text,text,text,boolean,text,boolean,text[])'::regprocedure)))
    < position('for update' in lower(pg_get_functiondef('public.approve_family_join_request(uuid,text,text,text,boolean,text,boolean,text[])'::regprocedure))),
  'an approval takes the requester''s account lock after the family lock and before any row lock'
);

set local role authenticated;
set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000003';
select public.leave_family(current_setting('test.house_a')::uuid);

select is(
  public.request_family_join(current_setting('test.invite_b')) ->> 'status',
  'pending',
  'after leaving their house a person may ask to join another'
);

set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000001';
select public.delete_family(current_setting('test.house_a')::uuid, 'Casa Alfa');

select lives_ok(
  $$select public.create_family('Casa Alfa Nova')$$,
  'after deleting their house a titular may create another'
);

set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000006';
select public.request_family_join(current_setting('test.invite_b'));

reset role;
select set_config('test.request_fabio', (select id::text from public.family_join_requests where requester_user_id = '7a000000-0000-4000-8000-000000000006' and status = 'pending'), true);
set local role authenticated;

set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000002';
select public.approve_family_join_request(current_setting('test.request_fabio')::uuid, 'member');

reset role;
select set_config('test.member_fabio', (select id::text from public.family_members where user_id = '7a000000-0000-4000-8000-000000000006'), true);
set local role authenticated;

select public.remove_family_member(current_setting('test.member_fabio')::uuid);

set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000006';
select public.request_family_join(current_setting('test.invite_b'));

reset role;
select set_config('test.request_fabio', (select id::text from public.family_join_requests where requester_user_id = '7a000000-0000-4000-8000-000000000006' and status = 'pending'), true);
set local role authenticated;

set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000002';
select public.approve_family_join_request(current_setting('test.request_fabio')::uuid, 'member');

reset role;

select is(
  (
    select count(*)::integer
    from public.family_access_decisions
    where subject_user_id = '7a000000-0000-4000-8000-000000000006'
      and acknowledged_at is null
  ),
  0,
  'entering a house again retires the removal the person never read'
);

set local role authenticated;
set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000006';
select public.leave_family(current_setting('test.house_b')::uuid);

select is(
  public.get_family_access_decision(),
  null,
  'leaving on purpose never resurfaces an old removal'
);

reset role;

alter table public.family_members disable trigger family_members_one_house_per_account;
insert into public.family_members (family_id, user_id, name, relationship, household_role, permission_role, tone)
values
  (current_setting('test.house_b')::uuid, '7a000000-0000-4000-8000-000000000008', 'Hugo', 'Amigo', 'adult', 'member', 'sky'),
  ((select id from public.families where name = 'Casa Eva'), '7a000000-0000-4000-8000-000000000008', 'Hugo', 'Amigo', 'adult', 'member', 'sky');
alter table public.family_members enable trigger family_members_one_house_per_account;

set local role authenticated;
set local request.jwt.claim.sub = '7a000000-0000-4000-8000-000000000008';

select lives_ok(
  $$select public.leave_family(current_setting('test.house_b')::uuid)$$,
  'an account left in two houses before the rule still leaves one'
);

select is(
  public.get_current_home_context() #>> '{family,name}',
  'Casa Eva',
  'and lands in the house it still belongs to'
);

reset role;

select * from finish();

rollback;
