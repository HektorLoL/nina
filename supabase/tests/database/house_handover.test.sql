begin;

create extension if not exists pgtap with schema extensions;

select plan(35);

insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
values
  ('72000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'handover-owner@example.com', '{"full_name":"Handover Owner"}'::jsonb, now(), now()),
  ('72000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'handover-admin@example.com', '{"full_name":"Handover Admin"}'::jsonb, now(), now()),
  ('72000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'handover-member@example.com', '{"full_name":"Handover Member"}'::jsonb, now(), now()),
  ('72000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'handover-unknown@example.com', '{"full_name":"Handover Unknown"}'::jsonb, now(), now()),
  ('72000000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'handover-outsider@example.com', '{"full_name":"Handover Outsider"}'::jsonb, now(), now()),
  ('72000000-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'handover-sixth@example.com', '{"full_name":"Handover Sixth"}'::jsonb, now(), now());

-- The member who receives the house only declared an adult age; account 4 has no age row at all.
insert into private.account_age_status (user_id, status, assurance, recheck_after)
values ('72000000-0000-0000-0000-000000000003', 'adult', 'self_declared', now() + interval '180 days');

insert into private.account_age_status (user_id, status, assurance, recheck_after)
select users.id, 'adult', 'confirmed', now() + interval '180 days'
from auth.users as users
where users.id::text in (
  '72000000-0000-0000-0000-000000000001',
  '72000000-0000-0000-0000-000000000002',
  '72000000-0000-0000-0000-000000000005',
  '72000000-0000-0000-0000-000000000006'
);

set local role authenticated;
set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000005';
select public.create_family('Casa Vizinha');

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.create_family('Casa Para Passar')$$,
  'the owner creates the house'
);

select set_config(
  'test.handover_family_id',
  (select active_family_id::text from public.profiles where id = auth.uid()),
  true
);

reset role;

select is(
  (
    select relationship
    from public.family_members
    where family_id = current_setting('test.handover_family_id')::uuid
      and user_id = '72000000-0000-0000-0000-000000000001'
  ),
  '',
  'a new house names its owner by the role alone, with no relationship word'
);

insert into public.family_members (family_id, user_id, name, relationship, household_role, permission_role, tone)
values
  (current_setting('test.handover_family_id')::uuid, '72000000-0000-0000-0000-000000000002', 'Admin', 'Irmã', 'adult', 'admin', 'coral'),
  (current_setting('test.handover_family_id')::uuid, '72000000-0000-0000-0000-000000000003', 'Membro', 'Irmão', 'adult', 'member', 'sky'),
  (current_setting('test.handover_family_id')::uuid, '72000000-0000-0000-0000-000000000004', 'Antigo', 'Primo', 'adult', 'member', 'amber'),
  (current_setting('test.handover_family_id')::uuid, '72000000-0000-0000-0000-000000000006', 'Sexta', 'Prima', 'adult', 'member', 'sky'),
  (current_setting('test.handover_family_id')::uuid, null, 'Rex', 'Pet', 'pet', 'member', 'lavender');

update public.profiles
set active_family_id = current_setting('test.handover_family_id')::uuid
where id in (
  '72000000-0000-0000-0000-000000000002',
  '72000000-0000-0000-0000-000000000003',
  '72000000-0000-0000-0000-000000000004',
  '72000000-0000-0000-0000-000000000006'
);

create temporary table handover_members on commit drop as
select
  members.name,
  members.id
from public.family_members as members
where members.family_id = current_setting('test.handover_family_id')::uuid
union all
select 'Vizinho', members.id
from public.family_members as members
where members.user_id = '72000000-0000-0000-0000-000000000005';

grant select on handover_members to authenticated;

set local role authenticated;

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000003';
select throws_ok(
  $$select public.offer_family_ownership((select id from handover_members where name = 'Admin'))$$,
  '42501',
  'family_owner_transfer_denied',
  'a member cannot offer the house'
);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000002';
select throws_ok(
  $$select public.offer_family_ownership((select id from handover_members where name = 'Membro'))$$,
  '42501',
  'family_owner_transfer_denied',
  'an admin cannot offer the house'
);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000005';
select throws_ok(
  $$select public.offer_family_ownership((select id from handover_members where name = 'Membro'))$$,
  'P0002',
  'family_member_not_found',
  'someone outside the house learns nothing about its members'
);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000001';

select throws_ok(
  $$select public.offer_family_ownership((select id from handover_members where name = 'Vizinho'))$$,
  'P0002',
  'family_member_not_found',
  'the owner cannot reach a member of another house'
);

select throws_ok(
  $$
    select public.offer_family_ownership(
      (
        select id
        from public.family_members
        where family_id = current_setting('test.handover_family_id')::uuid
          and user_id = auth.uid()
      )
    )
  $$,
  '42501',
  'family_owner_transfer_denied',
  'the owner cannot offer the house to themselves'
);

select throws_ok(
  $$select public.offer_family_ownership((select id from handover_members where name = 'Nina'))$$,
  '42501',
  'family_owner_transfer_denied',
  'Nina never holds a house'
);

select throws_ok(
  $$select public.offer_family_ownership((select id from handover_members where name = 'Rex'))$$,
  '42501',
  'family_owner_transfer_denied',
  'a profile without an account never holds a house'
);

select lives_ok(
  $$select public.offer_family_ownership((select id from handover_members where name = 'Antigo'))$$,
  'an offer to anyone the list shows as an adult goes out, so it reveals nothing about their age'
);

select is(
  (public.get_current_home_context() #>> '{ownership_offer,member_id}')::uuid,
  (select id from handover_members where name = 'Antigo'),
  'the owner sees whom the house is offered to'
);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000004';
select throws_ok(
  $$select public.accept_family_ownership_offer(current_setting('test.handover_family_id')::uuid)$$,
  'P0001',
  'age_signal_required',
  'an account whose age was never read cannot take the house, and learns it about itself alone'
);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000003';
select throws_ok(
  $$select public.accept_family_ownership_offer(current_setting('test.handover_family_id')::uuid)$$,
  'P0002',
  'family_ownership_offer_not_found',
  'nobody accepts an offer made to someone else'
);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000001';
select lives_ok(
  $$select public.offer_family_ownership((select id from handover_members where name = 'Membro'))$$,
  'a new offer replaces the one before it'
);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000002';
select public.cancel_family_ownership_offer(current_setting('test.handover_family_id')::uuid);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000003';
select is(
  (public.get_current_home_context() #>> '{ownership_offer,member_id}')::uuid,
  (select id from handover_members where name = 'Membro'),
  'an admin cannot withdraw the owner''s offer, and the receiver sees it'
);

select lives_ok(
  $$select public.cancel_family_ownership_offer(current_setting('test.handover_family_id')::uuid)$$,
  'the receiver declines the offer'
);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000001';
select ok(
  public.get_current_home_context() -> 'ownership_offer' = 'null'::jsonb
    or public.get_current_home_context() -> 'ownership_offer' is null,
  'a declined offer is gone for the owner too'
);

select public.offer_family_ownership((select id from handover_members where name = 'Membro'));

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000003';
select lives_ok(
  $$select public.accept_family_ownership_offer(current_setting('test.handover_family_id')::uuid)$$,
  'an adult who declared their age accepts the house'
);

reset role;

select results_eq(
  $$
    select user_id::text, permission_role
    from public.family_members
    where family_id = current_setting('test.handover_family_id')::uuid
      and user_id::text in (
        '72000000-0000-0000-0000-000000000001',
        '72000000-0000-0000-0000-000000000002',
        '72000000-0000-0000-0000-000000000003'
      )
    order by user_id
  $$,
  $$
    values
      ('72000000-0000-0000-0000-000000000001', 'admin'),
      ('72000000-0000-0000-0000-000000000002', 'admin'),
      ('72000000-0000-0000-0000-000000000003', 'owner')
  $$,
  'the former owner stays as an admin and the new owner is the only owner'
);

select is(
  (select created_by::text from public.families where id = current_setting('test.handover_family_id')::uuid),
  '72000000-0000-0000-0000-000000000003',
  'the house records its new holder, so an account deletion hands it on from them'
);

select is(
  (select count(*)::integer from private.family_ownership_offers where family_id = current_setting('test.handover_family_id')::uuid),
  0,
  'an accepted offer is used up'
);

set local role authenticated;

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000003';
select throws_ok(
  $$select public.leave_family(current_setting('test.handover_family_id')::uuid)$$,
  'P0001',
  'family_owner_cannot_leave',
  'the new owner holds the house and cannot walk out of it'
);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000001';
select lives_ok(
  $$select public.leave_family(current_setting('test.handover_family_id')::uuid)$$,
  'the former owner may now leave the house'
);

select throws_ok(
  $$select public.offer_family_ownership((select id from handover_members where name = 'Admin'))$$,
  'P0002',
  'family_member_not_found',
  'someone who left cannot offer the house back'
);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000003';
select public.offer_family_ownership((select id from handover_members where name = 'Admin'));

reset role;
update private.family_ownership_offers
set offered_at = now() - interval '8 days'
where family_id = current_setting('test.handover_family_id')::uuid;
set local role authenticated;

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000002';
select throws_ok(
  $$select public.accept_family_ownership_offer(current_setting('test.handover_family_id')::uuid)$$,
  'P0002',
  'family_ownership_offer_not_found',
  'an offer older than seven days can no longer be accepted'
);

select ok(
  public.get_current_home_context() -> 'ownership_offer' = 'null'::jsonb
    or public.get_current_home_context() -> 'ownership_offer' is null,
  'an expired offer is not shown'
);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000003';
select lives_ok(
  $$select public.offer_family_ownership((select id from handover_members where name = 'Sexta'))$$,
  'the new owner offers the house in turn'
);

select lives_ok(
  $$select public.cancel_family_ownership_offer(current_setting('test.handover_family_id')::uuid)$$,
  'the owner withdraws the offer'
);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000006';
select ok(
  public.get_current_home_context() -> 'ownership_offer' = 'null'::jsonb
    or public.get_current_home_context() -> 'ownership_offer' is null,
  'a withdrawn offer is gone for the person it was made to'
);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000003';
select public.offer_family_ownership((select id from handover_members where name = 'Sexta'));

reset role;
update public.family_members
set permission_role = case user_id
  when '72000000-0000-0000-0000-000000000003' then 'admin'
  else 'owner'
end
where family_id = current_setting('test.handover_family_id')::uuid
  and user_id in ('72000000-0000-0000-0000-000000000002', '72000000-0000-0000-0000-000000000003');
set local role authenticated;

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000006';
select throws_ok(
  $$select public.accept_family_ownership_offer(current_setting('test.handover_family_id')::uuid)$$,
  'P0002',
  'family_ownership_offer_not_found',
  'an offer from someone who no longer holds the house cannot be accepted'
);

set local request.jwt.claim.sub = '72000000-0000-0000-0000-000000000002';
select public.offer_family_ownership((select id from handover_members where name = 'Sexta'));

select lives_ok(
  $$select public.remove_family_member((select id from handover_members where name = 'Sexta'))$$,
  'the owner takes the person the house was offered to out of it'
);

reset role;
select is(
  (select count(*)::integer from private.family_ownership_offers where family_id = current_setting('test.handover_family_id')::uuid),
  0,
  'removing the person it was offered to removes the offer'
);
set local role authenticated;

set local request.jwt.claim.sub = '';
select throws_ok(
  $$select public.accept_family_ownership_offer(current_setting('test.handover_family_id')::uuid)$$,
  '28000',
  'not_authenticated',
  'nobody takes a house without signing in'
);

reset role;

select ok(
  not has_function_privilege('anon', 'public.offer_family_ownership(uuid)', 'execute')
    and not has_function_privilege('service_role', 'public.offer_family_ownership(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.offer_family_ownership(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.accept_family_ownership_offer(uuid)', 'execute')
    and not has_function_privilege('service_role', 'public.accept_family_ownership_offer(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.accept_family_ownership_offer(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.cancel_family_ownership_offer(uuid)', 'execute')
    and not has_function_privilege('service_role', 'public.cancel_family_ownership_offer(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.cancel_family_ownership_offer(uuid)', 'execute'),
  'only a signed-in client offers, accepts or withdraws'
);

select ok(
  not has_table_privilege('authenticated', 'private.family_ownership_offers', 'select')
    and not has_table_privilege('service_role', 'private.family_ownership_offers', 'select'),
  'no API role reads the offers table'
);

select * from finish();
rollback;
