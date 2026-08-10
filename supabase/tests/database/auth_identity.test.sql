begin;

create extension if not exists pgtap with schema extensions;

select plan(39);

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
    '10000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'owner@example.com',
    '{"full_name":"Owner Person"}'::jsonb,
    now(),
    now()
  ),
  (
    '10000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'member@example.com',
    '{"full_name":"Member Person"}'::jsonb,
    now(),
    now()
  ),
  (
    '10000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'outsider@example.com',
    '{"full_name":"Outside Person"}'::jsonb,
    now(),
    now()
  );

select is(
  (select display_name from public.profiles where id = '10000000-0000-0000-0000-000000000001'),
  'Owner Person',
  'auth user trigger creates a profile'
);

set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.ensure_current_profile('Apple Owner')$$,
  'authenticated user can ensure their profile'
);

select is(
  (select display_name from public.profiles where id = auth.uid()),
  'Apple Owner',
  'auth hint updates an auth-owned display name'
);

update public.profiles
set display_name = 'Chosen Name', display_name_source = 'user'
where id = auth.uid();

select lives_ok(
  $$select public.ensure_current_profile('Ignored Apple Name')$$,
  'profile ensure remains idempotent after a user edit'
);

select is(
  (select display_name from public.profiles where id = auth.uid()),
  'Chosen Name',
  'Apple metadata does not overwrite a user-edited display name'
);

select lives_ok(
  $$select public.create_family('Test Home')$$,
  'owner can create a family through the RPC'
);

select matches(
  public.get_current_home_context() #>> '{family,invite_code}',
  '^casa-[0-9a-f]{32}$',
  'family invites use a high-entropy server-generated code'
);

select throws_ok(
  $$select public.create_family('Unsafe Home', 'chosen-code')$$,
  '42501',
  null,
  'authenticated clients cannot choose an invite code'
);

select set_config(
  'test.family_id',
  (select active_family_id::text from public.profiles where id = auth.uid()),
  true
);

select set_config(
  'test.invite_code',
  public.get_current_home_context() #>> '{family,invite_code}',
  true
);

reset role;

select is(
  (
    select count(*)::integer
    from public.invites
    where family_id = current_setting('test.family_id')::uuid
  ),
  1,
  'family creation stores one invite row'
);

select is(
  (
    select token
    from public.invites
    where family_id = current_setting('test.family_id')::uuid
      and revoked_at is null
  ),
  current_setting('test.invite_code'),
  'the family compatibility code mirrors the current invite token'
);

select ok(
  (
    select expires_at > now()
    from public.invites
    where token = current_setting('test.invite_code')
  ),
  'new invites have a future expiration'
);

select is(
  (
    select max_uses
    from public.invites
    where token = current_setting('test.invite_code')
  ),
  7,
  'new invites default to seven uses'
);

select is(
  (
    select cardinality(accepted_by)
    from public.invites
    where token = current_setting('test.invite_code')
  ),
  0,
  'new invites start without acceptances'
);

set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';

select is(
  (
    select permission_role
    from public.family_members
    where user_id = auth.uid()
      and family_id = current_setting('test.family_id')::uuid
  ),
  'owner',
  'family creator receives owner permission'
);

select is(
  (select active_family_id from public.profiles where id = auth.uid()),
  current_setting('test.family_id')::uuid,
  'family creation selects the new active family'
);

select throws_ok(
  $$update public.family_members set permission_role = 'member' where user_id = auth.uid()$$,
  '42501',
  null,
  'authenticated clients cannot mutate membership permissions directly'
);

reset role;
set local role anon;

select is(
  public.get_family_invite_preview(current_setting('test.invite_code')) ->> 'valid',
  'true',
  'the public invite preview validates a current code'
);

select is(
  public.get_family_invite_preview(current_setting('test.invite_code')) ->> 'family_name',
  'Test Home',
  'the public invite preview exposes only the family-facing name'
);

reset role;

update public.invites
set expires_at = now() - interval '1 minute'
where token = current_setting('test.invite_code');

set local role anon;

select is(
  public.get_family_invite_preview(current_setting('test.invite_code')) ->> 'valid',
  'false',
  'expired invites are rejected by the public preview'
);

reset role;

update public.invites
set
  expires_at = now() + interval '7 days',
  max_uses = 1
where token = current_setting('test.invite_code');

set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000002';

select lives_ok(
  $$select public.request_family_join(current_setting('test.invite_code'))$$,
  'another authenticated user can request access by invite'
);

select set_config(
  'test.join_request_id',
  public.get_pending_family_join_request() ->> 'id',
  true
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';

select lives_ok(
  $$
    select public.approve_family_join_request(
      current_setting('test.join_request_id')::uuid,
      'member'
    )
  $$,
  'a family manager can approve the pending request'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000002';

select is(
  (
    select context ->> 'membership_verified'
    from (select public.get_current_home_context() as context) as result
  ),
  'true',
  'home context verifies backend membership'
);

select is(
  (
    select permission_role
    from public.family_members
    where user_id = auth.uid()
      and family_id = (select active_family_id from public.profiles where id = auth.uid())
  ),
  'member',
  'joined users receive member permission'
);

select is(
  (select active_family_id from public.profiles where id = auth.uid()),
  current_setting('test.family_id')::uuid,
  'joining selects the joined family'
);

select throws_ok(
  $$update public.family_members set permission_role = 'owner' where user_id = auth.uid()$$,
  '42501',
  null,
  'members cannot promote themselves'
);

update public.profiles
set display_name = 'Resolved Member', display_name_source = 'user'
where id = auth.uid();

select is(
  (
    select member ->> 'name'
    from jsonb_array_elements(public.get_current_home_context() -> 'members') as member
    where member ->> 'user_id' = auth.uid()::text
  ),
  'Resolved Member',
  'claimed member names resolve from the global profile'
);

reset role;

select is(
  (
    select cardinality(accepted_by)
    from public.invites
    where token = current_setting('test.invite_code')
  ),
  1,
  'accepting an invite records one use'
);

select ok(
  (
    select '10000000-0000-0000-0000-000000000002'::uuid = any(accepted_by)
    from public.invites
    where token = current_setting('test.invite_code')
  ),
  'accepted_by records the authenticated user'
);

set local role anon;

select is(
  public.get_family_invite_preview(current_setting('test.invite_code')) ->> 'valid',
  'false',
  'an invite at its maximum use count is no longer public'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000003';

select throws_ok(
  $$select public.join_family_by_invite(current_setting('test.invite_code'))$$,
  'P0001',
  'invalid_invite_code',
  'an invite at its maximum use count rejects another user'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.rotate_family_invite_code(current_setting('test.family_id')::uuid)$$,
  'family managers can rotate the invite code'
);

select isnt(
  public.get_current_home_context() #>> '{family,invite_code}',
  current_setting('test.invite_code'),
  'rotating an invite invalidates the previous code'
);

reset role;

select ok(
  (
    select revoked_at is not null
    from public.invites
    where token = current_setting('test.invite_code')
  ),
  'rotation records revocation on the previous invite'
);

select is(
  (
    select cardinality(accepted_by)
    from public.invites
    where family_id = current_setting('test.family_id')::uuid
      and revoked_at is null
  ),
  0,
  'rotation creates a fresh unused invite'
);

set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';

select lives_ok(
  $$
    do $block$
    declare
      member_number integer;
      target_family_id uuid;
    begin
      select id into target_family_id
      from public.families
      where id = current_setting('test.family_id')::uuid;

      for member_number in 1..6 loop
        perform public.add_unclaimed_family_member(
          target_family_id,
          'Pessoa ' || member_number,
          'Teste ' || member_number,
          'adult',
          'mint',
          ''
        );
      end loop;
    end
    $block$
  $$,
  'family manager can fill the remaining family slots'
);

select is(
  (
    select count(*)::integer
    from public.family_members
    where family_id = current_setting('test.family_id')::uuid
      and household_role <> 'assistant'
  ),
  8,
  'family limit counts eight people and excludes Nina'
);

select throws_ok(
  $$
    select public.add_unclaimed_family_member(
      current_setting('test.family_id')::uuid,
      'Pessoa extra',
      'Limite',
      'adult',
      'mint',
      ''
    )
  $$,
  '23514',
  'family_member_limit_reached',
  'the server rejects a ninth person'
);

select is(
  (
    select member ->> 'name'
    from jsonb_array_elements(public.get_current_home_context() -> 'members') as member
    where member ->> 'relationship' = 'Teste 1'
  ),
  'Pessoa 1',
  'unclaimed member names remain family-specific'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000003';

select is(
  (select count(*)::integer from public.families where id = current_setting('test.family_id')::uuid),
  0,
  'RLS hides a family from users without membership'
);

select * from finish();
rollback;
