begin;

create extension if not exists pgtap with schema extensions;

select plan(47);

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
    'manager-owner@example.com',
    '{"full_name":"Manager Owner"}'::jsonb,
    now(),
    now()
  ),
  (
    '61000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'manager-candidate@example.com',
    '{"full_name":"Manager Candidate"}'::jsonb,
    now(),
    now()
  ),
  (
    '61000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'manager-outsider@example.com',
    '{"full_name":"Manager Outsider"}'::jsonb,
    now(),
    now()
  );

set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.create_family('Casa Gerenciada')$$,
  'owner creates the managed family'
);

select set_config(
  'test.member_management_family_id',
  (select active_family_id::text from public.profiles where id = auth.uid()),
  true
);

select set_config(
  'test.member_management_invite',
  (
    select invite_code
    from public.families
    where id = current_setting('test.member_management_family_id')::uuid
  ),
  true
);

select lives_ok(
  $$
    select public.add_unclaimed_family_member(
      current_setting('test.member_management_family_id')::uuid,
      'Lia',
      'Filha',
      'child',
      'amber',
      'Estuda pela manhã.',
      '2018-04-12'::date,
      '',
      ''
    )
  $$,
  'manager creates a child profile'
);

select lives_ok(
  $$
    select public.add_unclaimed_family_member(
      current_setting('test.member_management_family_id')::uuid,
      'Pingo',
      'Pet',
      'pet',
      'lavender',
      'Ração duas vezes ao dia.',
      '2022-09-01'::date,
      'Cachorro',
      'Vira-lata'
    )
  $$,
  'manager creates a pet profile'
);

select is(
  (
    select birth_date
    from public.family_members
    where family_id = current_setting('test.member_management_family_id')::uuid
      and name = 'Lia'
  ),
  '2018-04-12'::date,
  'child profile stores a birth date'
);

select is(
  (
    select pet_species || ' · ' || pet_breed
    from public.family_members
    where family_id = current_setting('test.member_management_family_id')::uuid
      and name = 'Pingo'
  ),
  'Cachorro · Vira-lata',
  'pet profile stores species and breed'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000002';

select lives_ok(
  $$select public.request_family_join(current_setting('test.member_management_invite'))$$,
  'candidate submits a join request'
);

select is(
  public.get_pending_family_join_request() ->> 'status',
  'pending',
  'join request remains pending before approval'
);

select is(
  (
    select count(*)::integer
    from public.family_members
    where family_id = current_setting('test.member_management_family_id')::uuid
      and user_id = auth.uid()
  ),
  0,
  'requesting access does not create membership'
);

select set_config(
  'test.member_management_request_id',
  public.get_pending_family_join_request() ->> 'id',
  true
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select lives_ok(
  $$
    select public.approve_family_join_request(
      current_setting('test.member_management_request_id')::uuid,
      'admin'
    )
  $$,
  'owner can approve a request as admin'
);

select is(
  (
    select permission_role
    from public.family_members
    where family_id = current_setting('test.member_management_family_id')::uuid
      and user_id = '61000000-0000-0000-0000-000000000002'
  ),
  'admin',
  'approved candidate receives the selected permission'
);

select set_config(
  'test.member_management_candidate_member_id',
  (
    select id::text
    from public.family_members
    where family_id = current_setting('test.member_management_family_id')::uuid
      and user_id = '61000000-0000-0000-0000-000000000002'
  ),
  true
);

select lives_ok(
  $$
    select public.update_family_member(
      current_setting('test.member_management_candidate_member_id')::uuid,
      'Ignored',
      'Irmã',
      'adult',
      'member',
      'sky',
      'Ajuda com compras.',
      null,
      '',
      ''
    )
  $$,
  'owner can change an admin back to member'
);

select is(
  (
    select permission_role
    from public.family_members
    where id = current_setting('test.member_management_candidate_member_id')::uuid
  ),
  'member',
  'permission role change is persisted'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000002';

select throws_ok(
  $$
    select public.update_family_member(
      current_setting('test.member_management_candidate_member_id')::uuid,
      'Ignored',
      'Irmã',
      'adult',
      'owner',
      'sky',
      '',
      null,
      '',
      ''
    )
  $$,
  '42501',
  'permission_role_denied',
  'members cannot promote themselves'
);

select throws_ok(
  $$
    select public.remove_family_member(
      (
        select id
        from public.family_members
        where family_id = current_setting('test.member_management_family_id')::uuid
          and permission_role = 'owner'
      )
    )
  $$,
  '42501',
  'family_member_remove_denied',
  'members cannot remove the owner'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000003';

select throws_ok(
  $$
    select public.update_family_member(
      current_setting('test.member_management_candidate_member_id')::uuid,
      'Comprometido',
      '',
      'adult',
      'member',
      'coral',
      '',
      null,
      '',
      ''
    )
  $$,
  '42501',
  'family_member_update_denied',
  'an outsider cannot update a leaked member identifier'
);

select throws_ok(
  $$
    select public.remove_family_member(
      current_setting('test.member_management_candidate_member_id')::uuid
    )
  $$,
  '42501',
  'family_member_remove_denied',
  'an outsider cannot remove a leaked member identifier'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select lives_ok(
  $$
    select public.remove_family_member(
      current_setting('test.member_management_candidate_member_id')::uuid
    )
  $$,
  'owner can remove a non-owner member'
);

select is(
  (
    select count(*)::integer
    from public.family_members
    where id = current_setting('test.member_management_candidate_member_id')::uuid
  ),
  0,
  'removed membership no longer exists'
);

select is(
  (
    select active_family_id
    from public.profiles
    where id = '61000000-0000-0000-0000-000000000002'
  ),
  null::uuid,
  'removing a member clears the matching active family'
);

select public.add_unclaimed_family_member(
  current_setting('test.member_management_family_id')::uuid,
  'Marina',
  'Mãe',
  'adult',
  'sky',
  '',
  null,
  '',
  ''
);

select public.add_unclaimed_family_member(
  current_setting('test.member_management_family_id')::uuid,
  'Marina',
  'Prima',
  'adult',
  'lavender',
  '',
  null,
  '',
  ''
);

select set_config(
  'test.member_management_first_marina',
  (
    select id::text
    from public.family_members
    where family_id = current_setting('test.member_management_family_id')::uuid
      and name = 'Marina'
      and relationship = 'Mãe'
  ),
  true
);

select set_config(
  'test.member_management_second_marina',
  (
    select id::text
    from public.family_members
    where family_id = current_setting('test.member_management_family_id')::uuid
      and name = 'Marina'
      and relationship = 'Prima'
  ),
  true
);

insert into public.tasks (id, family_id, title, owner_member_id)
values
  (
    '69000000-0000-0000-0000-000000000001',
    current_setting('test.member_management_family_id')::uuid,
    'Levar a Lia na escola',
    current_setting('test.member_management_first_marina')::uuid
  ),
  (
    '69000000-0000-0000-0000-000000000002',
    current_setting('test.member_management_family_id')::uuid,
    'Marcar o pediatra',
    current_setting('test.member_management_first_marina')::uuid
  ),
  (
    '69000000-0000-0000-0000-000000000003',
    current_setting('test.member_management_family_id')::uuid,
    'Comprar ração do Pingo',
    current_setting('test.member_management_second_marina')::uuid
  ),
  (
    '69000000-0000-0000-0000-000000000004',
    current_setting('test.member_management_family_id')::uuid,
    'Pagar o condomínio',
    null
  );

insert into public.shopping_items (id, family_id, title, owner_member_id)
values (
  '69000000-0000-0000-0000-000000000005',
  current_setting('test.member_management_family_id')::uuid,
  'Arroz',
  current_setting('test.member_management_first_marina')::uuid
);

select is(
  (
    select owner_label
    from public.tasks
    where id = '69000000-0000-0000-0000-000000000001'
  ),
  'Marina',
  'assigning a member stamps the display label from the member row'
);

update public.tasks
set owner_label = 'Lia'
where id = '69000000-0000-0000-0000-000000000004';

select is(
  (
    select owner_member_id
    from public.tasks
    where id = '69000000-0000-0000-0000-000000000004'
  ),
  (
    select id
    from public.family_members
    where family_id = current_setting('test.member_management_family_id')::uuid
      and name = 'Lia'
  ),
  'naming an unambiguous member in the label binds the task to that member'
);

update public.tasks
set owner_label = 'Casa'
where id = '69000000-0000-0000-0000-000000000004';

select is(
  (
    select owner_member_id
    from public.tasks
    where id = '69000000-0000-0000-0000-000000000004'
  ),
  null::uuid,
  'returning a task to Casa releases the member it pointed at'
);

select throws_ok(
  $$
    update public.tasks
    set owner_member_id = (
      select id
      from public.family_members
      where family_id = current_setting('test.member_management_family_id')::uuid
        and household_role = 'assistant'
    )
    where id = '69000000-0000-0000-0000-000000000003'
  $$,
  '42501',
  'owner_member_not_assignable',
  'household work cannot be assigned to the assistant'
);

reset role;

select is(
  (
    private.nina_weekly_metrics(
      current_setting('test.member_management_family_id')::uuid
    ) -> 'open_tasks_by_owner' ->> 'Marina · Mãe'
  )::integer,
  2,
  'two members sharing a name keep separate workload buckets'
);

select is(
  (
    private.nina_weekly_metrics(
      current_setting('test.member_management_family_id')::uuid
    ) -> 'open_tasks_by_owner' ->> 'Marina · Prima'
  )::integer,
  1,
  'the second member sharing the name keeps her own workload bucket'
);

select is(
  (
    private.nina_weekly_metrics(
      current_setting('test.member_management_family_id')::uuid
    ) -> 'open_tasks_by_owner' ->> 'Marina'
  ),
  null::text,
  'a shared first name never collapses two people into one bucket'
);

select is(
  (
    private.nina_weekly_metrics(
      current_setting('test.member_management_family_id')::uuid
    ) -> 'open_tasks_by_owner' ->> 'Casa'
  )::integer,
  1,
  'unowned household work keeps its own Casa bucket'
);

set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select public.update_family_member(
  current_setting('test.member_management_first_marina')::uuid,
  'Marina Castello',
  'Mãe',
  'adult',
  'member',
  'sky',
  '',
  null,
  '',
  ''
);

select is(
  (
    select owner_member_id
    from public.tasks
    where id = '69000000-0000-0000-0000-000000000001'
  ),
  current_setting('test.member_management_first_marina')::uuid,
  'a rename does not orphan the attribution of an owned task'
);

select is(
  (
    select owner_label
    from public.tasks
    where id = '69000000-0000-0000-0000-000000000001'
  ),
  'Marina Castello',
  'a rename refreshes the task display label'
);

select is(
  (
    select owner_label
    from public.shopping_items
    where id = '69000000-0000-0000-0000-000000000005'
  ),
  'Marina Castello',
  'a rename refreshes the shopping display label'
);

reset role;

select is(
  (
    private.nina_weekly_metrics(
      current_setting('test.member_management_family_id')::uuid
    ) -> 'open_tasks_by_owner' ->> 'Marina Castello'
  )::integer,
  2,
  'a rename keeps one member in one workload bucket instead of splitting her in two'
);

select is(
  (
    private.nina_weekly_metrics(
      current_setting('test.member_management_family_id')::uuid
    ) -> 'open_tasks_by_owner' ->> 'Marina'
  )::integer,
  1,
  'the former name only carries the work of the member who still answers to it'
);

set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select public.remove_family_member(
  current_setting('test.member_management_first_marina')::uuid
);

select is(
  (
    select owner_member_id
    from public.tasks
    where id = '69000000-0000-0000-0000-000000000001'
  ),
  null::uuid,
  'removing a member clears the attribution on their old tasks'
);

select is(
  (
    select owner_label
    from public.tasks
    where id = '69000000-0000-0000-0000-000000000001'
  ),
  'Casa',
  'a removed member name is not left stamped on their old tasks'
);

select is(
  (
    select owner_label
    from public.shopping_items
    where id = '69000000-0000-0000-0000-000000000005'
  ),
  'Casa',
  'a removed member name is not left stamped on their old shopping items'
);

reset role;

select is(
  (
    private.nina_weekly_metrics(
      current_setting('test.member_management_family_id')::uuid
    ) -> 'open_tasks_by_owner' ->> 'Marina Castello'
  ),
  null::text,
  'a removed member no longer holds a workload bucket'
);

select is(
  (
    private.nina_weekly_metrics(
      current_setting('test.member_management_family_id')::uuid
    ) -> 'open_tasks_by_owner' ->> 'Casa'
  )::integer,
  3,
  'work left by a removed member returns to the house instead of naming a person'
);

set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select public.remove_family_member(
  current_setting('test.member_management_second_marina')::uuid
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000003';

select lives_ok(
  $$select public.request_family_join(current_setting('test.member_management_invite'))$$,
  'another candidate can request access'
);

select lives_ok(
  $$
    select public.cancel_family_join_request(
      (public.get_pending_family_join_request() ->> 'id')::uuid
    )
  $$,
  'requester can cancel their own pending request'
);

select lives_ok(
  $$select public.request_family_join(current_setting('test.member_management_invite'))$$,
  'requester can submit a new request after cancelling'
);

select set_config(
  'test.member_management_capacity_request_id',
  public.get_pending_family_join_request() ->> 'id',
  true
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select lives_ok(
  $$
    do $capacity$
    begin
      for profile_number in 1..5 loop
        perform public.add_unclaimed_family_member(
          current_setting('test.member_management_family_id')::uuid,
          'Perfil ' || profile_number,
          'Dependente',
          'child',
          'mint',
          '',
          null,
          '',
          ''
        );
      end loop;
    end
    $capacity$
  $$,
  'owner can fill the remaining household capacity'
);

select throws_ok(
  $$
    select public.add_unclaimed_family_member(
      current_setting('test.member_management_family_id')::uuid,
      'Perfil excedente',
      'Dependente',
      'child',
      'mint',
      '',
      null,
      '',
      ''
    )
  $$,
  '23514',
  'family_member_limit_reached',
  'profile creation cannot exceed eight people'
);

reset role;
set local role anon;

select is(
  public.get_family_invite_preview(current_setting('test.member_management_invite')) ->> 'valid',
  'false',
  'a full household is not advertised as joinable'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000003';

select throws_ok(
  $$select public.request_family_join(current_setting('test.member_management_invite'))$$,
  '23514',
  'family_member_limit_reached',
  'a full household rejects new join requests'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '61000000-0000-0000-0000-000000000001';

select throws_ok(
  $$
    select public.approve_family_join_request(
      current_setting('test.member_management_capacity_request_id')::uuid,
      'member'
    )
  $$,
  '23514',
  'family_member_limit_reached',
  'join approval cannot exceed eight people'
);

reset role;

select ok(
  position(
    'pg_advisory_xact_lock' in lower(
      pg_get_functiondef('public.request_family_join(text)'::regprocedure)
    )
  ) < position(
    'for update' in lower(
      pg_get_functiondef('public.request_family_join(text)'::regprocedure)
    )
  ),
  'join requests take the family advisory lock before row locks'
);

select ok(
  position(
    'pg_advisory_xact_lock' in lower(
      pg_get_functiondef(
        'public.approve_family_join_request(uuid,text)'::regprocedure
      )
    )
  ) < position(
    'for update' in lower(
      pg_get_functiondef(
        'public.approve_family_join_request(uuid,text)'::regprocedure
      )
    )
  ),
  'join approvals use the same family-first lock order'
);

select * from finish();
rollback;
