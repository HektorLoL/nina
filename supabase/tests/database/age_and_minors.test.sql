begin;

create extension if not exists pgtap with schema extensions;

select plan(177);

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

insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
values
  ('a1000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'olga@example.com', '{"full_name":"Olga Guardiã"}', now(), now()),
  ('a1000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'davi@example.com', '{"full_name":"Davi Declarado"}', now(), now()),
  ('a1000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'pedro@example.com', '{"full_name":"Pedro Menor"}', now(), now()),
  ('a1000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'ursula@example.com', '{"full_name":"Ursula Sem Idade"}', now(), now()),
  ('a1000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'ana@example.com', '{"full_name":"Ana Adulta"}', now(), now()),
  ('a1000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'otto@example.com', '{"full_name":"Otto Fora"}', now(), now()),
  ('a1000000-0000-4000-8000-000000000008', 'authenticated', 'authenticated', 'rita@example.com', '{"full_name":"Rita Catraca"}', now(), now()),
  ('a1000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', 'zeca@example.com', '{"full_name":"Zeca Legado"}', now(), now()),
  ('a1000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated', 'mini@example.com', '{"full_name":"Mini Pedido"}', now(), now());

insert into private.account_age_status (user_id, status, minor_band, assurance, minor_since, recheck_after)
values
  ('a1000000-0000-4000-8000-000000000001', 'adult', null, 'confirmed', null, now() + interval '180 days'),
  ('a1000000-0000-4000-8000-000000000002', 'adult', null, 'self_declared', null, now() + interval '180 days'),
  ('a1000000-0000-4000-8000-000000000003', 'minor', '12_15', 'self_declared', now(), now() + interval '30 days'),
  ('a1000000-0000-4000-8000-000000000005', 'adult', null, 'confirmed', null, now() + interval '180 days'),
  ('a1000000-0000-4000-8000-000000000006', 'adult', null, 'confirmed', null, now() + interval '180 days'),
  ('a1000000-0000-4000-8000-000000000008', 'adult', null, 'confirmed', null, now() + interval '180 days'),
  ('a1000000-0000-4000-8000-00000000000b', 'minor', 'under_12', 'guardian_declared', now(), now() + interval '30 days');

-- The private schema is reachable by no API role.
select ok(
  not has_schema_privilege('anon', 'private', 'usage')
    and not has_schema_privilege('authenticated', 'private', 'usage')
    and not has_schema_privilege('service_role', 'private', 'usage'),
  'no API role holds usage on the private schema'
);

select is(
  (
    select count(*)::integer
    from pg_class
    where relnamespace = 'private'::regnamespace
      and relkind = 'r'
      and relname in (
        'account_age_status', 'age_policy', 'age_signal_challenges', 'app_attest_keys',
        'pseudonym_salt', 'nina_ai_blocks', 'minor_profiles', 'minor_guardianships',
        'minor_data_consents', 'account_terms_acceptances', 'minor_acknowledgements',
        'minor_usage_days', 'nina_reply_reports', 'child_safety_holds',
        'child_safety_preserved_accounts'
      )
      and relrowsecurity
  ),
  15,
  'every new private table has row level security on'
);

select ok(
  not has_function_privilege('authenticated', 'public.record_age_signal(uuid,text,text,text,boolean)', 'execute')
    and has_function_privilege('service_role', 'public.record_age_signal(uuid,text,text,text,boolean)', 'execute'),
  'only the server key records an age signal'
);

select is(
  (select count(*)::integer from pg_proc where proname = 'get_my_age_status' and pronargs > 0),
  0,
  'get_my_age_status takes no argument, so it can only ever answer about the caller'
);

select ok(
  not has_function_privilege('service_role', 'private.operator_set_age_status(uuid,text,text,boolean,text)', 'execute')
    and not has_function_privilege('authenticated', 'private.operator_lift_ai_block(uuid,text)', 'execute')
    and not has_function_privilege('service_role', 'private.age_assurance_distribution()', 'execute'),
  'the operator functions are revoked from every API role'
);

select ok(
  (select trusted_assurances = '{confirmed,operator}' from private.age_policy),
  'only Apple-confirmed and operator-set adults are trusted by default'
);

select throws_ok(
  $$update private.age_policy set trusted_assurances = '{self_declared}'$$,
  '23514',
  null,
  'the policy can never stop trusting the two proven assurances'
);

select is(
  (
    select count(*)::integer
    from public.nina_ai_consents as consents
    cross join private.age_policy as policy
    where consents.revoked_at is null
      and (consents.policy_version <> policy.current_policy_version or consents.transfer_consented_at is null)
  ),
  0,
  'no live AI consent stands on an older policy text or without the transfer consent'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000004';

select is(
  public.get_my_age_status() ->> 'status',
  'unknown',
  'an account with no age record is unknown'
);

select is(
  public.get_my_age_status() ->> 'recorded_at',
  null,
  'an account that never shared an age has no recorded signal'
);

select throws_ok(
  $$select public.create_family('Casa Sem Idade')$$,
  'P0001',
  'age_signal_required',
  'an account with no age record cannot create a house'
);

select is(
  public.get_current_home_context() ->> 'viewer_kind',
  'minor',
  'an account of unknown age receives the minor shape'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000003';

select throws_ok(
  $$select public.create_family('Casa do Pedro')$$,
  '42501',
  'adult_account_required',
  'a minor cannot create a house'
);

select is(
  public.get_my_age_status() ->> 'band',
  '12_15',
  'a minor reads their own band'
);

select is(
  public.get_my_age_status() ->> 'trusted_adult',
  'false',
  'a minor is never a trusted adult'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000002';

select ok(
  (public.get_my_age_status() ->> 'status') = 'adult'
    and (public.get_my_age_status() ->> 'trusted_adult') = 'false'
    and (public.get_my_age_status() ->> 'may_use_ai') = 'false',
  'a self-declared adult is an adult for the house but never trusted'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select public.create_family('Casa das Idades')$$,
  'a trusted adult creates a house'
);

select set_config('test.family', (select active_family_id::text from public.profiles where id = auth.uid()), true);
select set_config('test.invite', public.get_current_home_context() #>> '{family,invite_code}', true);

select is(
  public.get_current_home_context() ->> 'viewer_kind',
  'adult',
  'an adult receives the adult shape'
);

select is(
  public.record_terms_acceptance() #>> '{terms,accepted_current}',
  'true',
  'an adult accepts the current terms once'
);

reset role;
set local role authenticated;

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000004';
select lives_ok($$select public.request_family_join(current_setting('test.invite'))$$, 'a person of unknown age can ask to join');
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000003';
select lives_ok($$select public.request_family_join(current_setting('test.invite'))$$, 'a minor can ask to join');
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000002';
select lives_ok($$select public.request_family_join(current_setting('test.invite'))$$, 'a self-declared adult can ask to join');
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000005';
select lives_ok($$select public.request_family_join(current_setting('test.invite'))$$, 'a confirmed adult can ask to join');
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000008';
select lives_ok($$select public.request_family_join(current_setting('test.invite'))$$, 'another confirmed adult can ask to join');

reset role;

select is(
  (
    select requester_age_status || ':' || coalesce(requester_band, '-')
    from public.family_join_requests
    where requester_user_id = 'a1000000-0000-4000-8000-000000000003'
  ),
  'minor:12_15',
  'a join request keeps a snapshot of the requester age'
);

select set_config('test.request_minor', (select id::text from public.family_join_requests where requester_user_id = 'a1000000-0000-4000-8000-000000000003'), true);
select set_config('test.request_unknown', (select id::text from public.family_join_requests where requester_user_id = 'a1000000-0000-4000-8000-000000000004'), true);
select set_config('test.request_declared', (select id::text from public.family_join_requests where requester_user_id = 'a1000000-0000-4000-8000-000000000002'), true);
select set_config('test.request_ana', (select id::text from public.family_join_requests where requester_user_id = 'a1000000-0000-4000-8000-000000000005'), true);
select set_config('test.request_rita', (select id::text from public.family_join_requests where requester_user_id = 'a1000000-0000-4000-8000-000000000008'), true);

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select is(
  (
    select request ->> 'requester_age'
    from jsonb_array_elements(public.get_current_home_context() -> 'pending_join_requests') as request
    where request ->> 'id' = current_setting('test.request_unknown')
  ),
  'unknown',
  'the approval card reads the requester age live'
);

select lives_ok($$select public.approve_family_join_request(current_setting('test.request_declared')::uuid, 'admin')$$, 'the owner approves a self-declared adult as administrator');
select lives_ok($$select public.approve_family_join_request(current_setting('test.request_ana')::uuid, 'member')$$, 'the owner approves a confirmed adult');
select lives_ok($$select public.approve_family_join_request(current_setting('test.request_rita')::uuid, 'admin')$$, 'the owner approves another confirmed adult as administrator');

select throws_ok(
  $$select public.approve_family_join_request(current_setting('test.request_minor')::uuid, 'member')$$,
  'P0001',
  'join_request_age_changed',
  'an adult-style approval of a minor is refused so the card refreshes'
);

select throws_ok(
  $$select public.approve_family_join_request(current_setting('test.request_minor')::uuid, 'member', 'mae', '12_15', false, '2026-09-29')$$,
  '22023',
  'guardian_declaration_required',
  'approving a minor without the guardian declaration is refused'
);

select throws_ok(
  $$select public.approve_family_join_request(current_setting('test.request_minor')::uuid, 'member', 'mae', '12_15', true, '2026-06-01')$$,
  '22023',
  'minor_consent_outdated',
  'approving a minor on an older consent text is refused'
);

select throws_ok(
  $$select public.approve_family_join_request(current_setting('test.request_minor')::uuid, 'member', 'mae', '16_17', true, '2026-09-29')$$,
  '22023',
  'invalid_minor_band',
  'a guardian cannot declare a minor older than the band Apple reported'
);

select throws_ok(
  $$select public.approve_family_join_request(current_setting('test.request_minor')::uuid, 'admin', 'mae', '12_15', true, '2026-09-29')$$,
  '42501',
  'minor_role_restricted',
  'a minor is never approved as administrator'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000002';

select throws_ok(
  $$select public.approve_family_join_request(current_setting('test.request_minor')::uuid, 'member', 'pai', '12_15', true, '2026-09-29')$$,
  '42501',
  'age_confirmation_required',
  'a self-declared administrator cannot approve a minor'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select public.approve_family_join_request(current_setting('test.request_minor')::uuid, 'member', 'mae', '12_15', true, '2026-09-29', false, array['Pedrinho'])$$,
  'a trusted owner approves a minor as their guardian'
);

reset role;

select set_config('test.member_minor', (select id::text from public.family_members where user_id = 'a1000000-0000-4000-8000-000000000003'), true);

select ok(
  exists (select 1 from public.family_members where id = current_setting('test.member_minor')::uuid and household_role = 'teen' and permission_role = 'member')
    and exists (select 1 from private.minor_profiles where member_id = current_setting('test.member_minor')::uuid and declared_band = '12_15' and nicknames = array['Pedrinho'])
    and exists (select 1 from private.minor_guardianships where member_id = current_setting('test.member_minor')::uuid and guardian_user_id = 'a1000000-0000-4000-8000-000000000001' and ended_at is null)
    and exists (select 1 from private.minor_data_consents where member_id = current_setting('test.member_minor')::uuid and purpose = 'account' and withdrawn_at is null)
    and exists (select 1 from private.account_terms_acceptances where user_id = 'a1000000-0000-4000-8000-000000000003' and accepted_by = 'guardian'),
  'approving a minor writes the member, the profile, the guardianship, the consent and the acceptance together'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select public.approve_family_join_request(current_setting('test.request_unknown')::uuid, 'member', 'responsavel_legal', 'under_12', true, '2026-09-29')$$,
  'a trusted owner approves a person of unknown age as a minor'
);

reset role;

select ok(
  exists (
    select 1 from private.account_age_status
    where user_id = 'a1000000-0000-4000-8000-000000000004'
      and status = 'minor' and minor_band = 'under_12'
      and assurance = 'guardian_declared' and household_marked
  )
  and exists (
    select 1 from public.family_members
    where user_id = 'a1000000-0000-4000-8000-000000000004' and household_role = 'child'
  ),
  'an unknown requester approved as a minor is household-marked with the declared band'
);

select set_config('test.member_unknown', (select id::text from public.family_members where user_id = 'a1000000-0000-4000-8000-000000000004'), true);
select set_config('test.member_owner', (select id::text from public.family_members where user_id = 'a1000000-0000-4000-8000-000000000001'), true);
select set_config('test.member_ana', (select id::text from public.family_members where user_id = 'a1000000-0000-4000-8000-000000000005'), true);
select set_config('test.member_davi', (select id::text from public.family_members where user_id = 'a1000000-0000-4000-8000-000000000002'), true);

insert into public.tasks (id, family_id, title, subtitle, owner_member_id, category_id)
values
  ('a3000000-0000-4000-8000-000000000001', current_setting('test.family')::uuid, 'Levar a mochila', 'BOLETO-SECRETO 23793.38128', current_setting('test.member_minor')::uuid, 'school'),
  ('a3000000-0000-4000-8000-000000000002', current_setting('test.family')::uuid, 'Pagar a luz', 'Vence dia 12', current_setting('test.member_owner')::uuid, 'bills'),
  ('a3000000-0000-4000-8000-000000000003', current_setting('test.family')::uuid, 'Consertar a pia', '', current_setting('test.member_davi')::uuid, 'home'),
  ('a3000000-0000-4000-8000-000000000004', current_setting('test.family')::uuid, 'Comprar tinta', '', current_setting('test.member_ana')::uuid, 'home'),
  ('a3000000-0000-4000-8000-000000000005', current_setting('test.family')::uuid, 'Lixo', '', null, 'home'),
  ('a3000000-0000-4000-8000-000000000006', current_setting('test.family')::uuid, 'Varrer', '', current_setting('test.member_owner')::uuid, 'home');

insert into public.shopping_items (family_id, title) values (current_setting('test.family')::uuid, 'Cerveja');
insert into public.memory_items (family_id, title, visibility) values (current_setting('test.family')::uuid, 'Memória da casa', 'shared');
insert into public.household_insights (family_id, title) values (current_setting('test.family')::uuid, 'Resumo');
insert into public.family_snapshots (family_id, data) values (current_setting('test.family')::uuid, '{}');

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000003';

select is(
  (
    (select count(*) from public.families)
    + (select count(*) from public.family_members)
    + (select count(*) from public.family_snapshots)
    + (select count(*) from public.household_insights)
    + (select count(*) from public.memory_items)
    + (select count(*) from public.nina_proposals)
    + (select count(*) from public.nina_threads)
    + (select count(*) from public.chat_messages)
    + (select count(*) from public.shopping_items)
    + (select count(*) from public.task_categories)
    + (select count(*) from public.task_sections)
    + (select count(*) from public.tasks)
    + (select count(*) from public.premium_subscriptions)
    + (select count(*) from public.premium_subscription_transactions)
  )::integer,
  0,
  'a minor member reads no row from any household table'
);

select is(
  (select count(*)::integer from public.profiles),
  1,
  'a minor still reads their own profile row, and only that one'
);

select is(
  pg_temp.affected_rows($$update public.tasks set title = 'Mudado' where id = 'a3000000-0000-4000-8000-000000000001'$$),
  0,
  'a minor cannot update even their own task directly'
);

select is(
  pg_temp.affected_rows($$delete from public.tasks where family_id = current_setting('test.family')::uuid$$),
  0,
  'a minor deletes nothing from the house'
);

select throws_ok(
  $$insert into public.tasks (family_id, title) values (current_setting('test.family')::uuid, 'Tarefa do menor')$$,
  '42501',
  null,
  'a minor writes no task'
);

select ok(
  (public.get_current_home_context() -> 'family') = 'null'::jsonb
    and jsonb_array_length(public.get_current_home_context() -> 'members') = 0
    and public.get_current_home_context()::text not like '%subtitle%'
    and public.get_current_home_context()::text not like '%BOLETO%',
  'the minor projection of the home context carries no house, no member and no detail line'
);

select is(
  public.get_minor_home_view() #>> '{viewer,state}',
  'active',
  'a minor with a guardian reaches the active view'
);

select is(
  jsonb_array_length(public.get_minor_home_view() -> 'tasks'),
  1,
  'a minor sees only their own task'
);

select ok(
  public.get_minor_home_view()::text not like '%BOLETO%'
    and public.get_minor_home_view()::text not like '%subtitle%'
    and not jsonb_path_exists(public.get_minor_home_view(), 'strict $.**.band'),
  'the minor view carries no detail line and no band'
);

select is(
  public.get_minor_home_view() #>> '{viewer,first_name}',
  'Pedro',
  'the minor view greets by first name'
);

select ok(
  (public.get_minor_home_view() #>> '{viewer,needs_acknowledgement}')::boolean
    and public.get_minor_home_view() #>> '{viewer,acknowledgement_kind}' = 'entendi',
  'a minor under sixteen is shown the Entendi welcome first'
);

select throws_ok(
  $$select public.acknowledge_minor_terms('aceitar', '2026-09-29')$$,
  '22023',
  'invalid_acknowledgement',
  'a minor under sixteen cannot accept the terms themselves'
);

select throws_ok(
  $$select public.acknowledge_minor_terms('entendi', '2026-06-01')$$,
  '22023',
  'minor_consent_outdated',
  'an acknowledgement of an older text is refused'
);

select is(
  public.acknowledge_minor_terms('entendi', '2026-09-29') #>> '{viewer,needs_acknowledgement}',
  'false',
  'an Entendi is recorded once as informed'
);

select throws_ok(
  $$select public.set_minor_task_done('a3000000-0000-4000-8000-000000000002', 1, true)$$,
  'P0002',
  'task_not_found',
  'a minor cannot mark another member''s task'
);

select throws_ok(
  $$select public.set_minor_task_done('a3000000-0000-4000-8000-000000000001', 99, true)$$,
  'P0001',
  'task_version_conflict',
  'a stale version is refused so the house''s version stands'
);

select throws_ok(
  $$select public.set_minor_task_done('a3000000-0000-4000-8000-000000000001', 1, true, now() + interval '1 day')$$,
  '22023',
  'invalid_next_due_at',
  'a one-off task takes no next date'
);

select lives_ok(
  $$select public.set_minor_task_done('a3000000-0000-4000-8000-000000000001', 1, true)$$,
  'a minor marks their own task done'
);

select is(
  public.record_minor_usage((now() at time zone 'America/Sao_Paulo')::date, 12) ->> 'usage_today_minutes',
  '12',
  'a minor records minutes of use for today'
);

select is(
  public.record_minor_usage((now() at time zone 'America/Sao_Paulo')::date, 5) ->> 'usage_today_minutes',
  '12',
  'recorded minutes never go down in a day'
);

select throws_ok(
  $$select public.record_minor_usage((now() at time zone 'America/Sao_Paulo')::date - 3, 5)$$,
  '22023',
  'invalid_usage',
  'minutes for a day outside the window are refused'
);

update public.profiles set email = 'pedro@example.com', phone = '11999999999', memory_note = 'nota' where id = auth.uid();

select ok(
  (select email is null and phone = '' and memory_note = '' from public.profiles where id = auth.uid()),
  'a minor profile never keeps an email or optional personal fields'
);

reset role;

select ok(
  (select is_done and title = 'Levar a mochila' and subtitle = 'BOLETO-SECRETO 23793.38128' and version = 2 from public.tasks where id = 'a3000000-0000-4000-8000-000000000001'),
  'marking done changes nothing on the task but done and its version'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select public.update_family_member(current_setting('test.member_minor')::uuid, 'Pedro', 'Filho', 'adult', 'member', 'sky', '')$$,
  'a guardian edits a minor''s row'
);

select is(
  (select household_role from public.family_members where id = current_setting('test.member_minor')::uuid),
  'teen',
  'no client ever sets a claimed member''s household role'
);

select throws_ok(
  $$select public.update_family_member(current_setting('test.member_minor')::uuid, 'Pedro', 'Filho', 'teen', 'admin', 'sky', '')$$,
  '42501',
  'minor_role_restricted',
  'a minor is never made administrator'
);

select throws_ok(
  $$select public.add_unclaimed_family_member(current_setting('test.family')::uuid, 'Bebê', 'Filha', 'child')$$,
  '22023',
  'invalid_household_role',
  'a child profile never skips the guardian declaration'
);

select lives_ok(
  $$select public.add_unclaimed_family_member(current_setting('test.family')::uuid, 'Tia Nair', 'Tia', 'adult')$$,
  'an adult profile without an account is still added the old way'
);

select lives_ok(
  $$select public.add_minor_profile(current_setting('test.family')::uuid, 'Bia', 'under_12', 'pai', '2026-09-29', false, array['Bibi'])$$,
  'a trusted adult creates a child profile with a declaration and a consent'
);

reset role;

select set_config('test.member_bia', (select id::text from public.family_members where name = 'Bia' and family_id = current_setting('test.family')::uuid), true);

select throws_ok(
  $$insert into public.family_members (family_id, name, household_role, birth_date) values (current_setting('test.family')::uuid, 'Com Data', 'child', '2019-01-01')$$,
  '23514',
  null,
  'a child or teen row never stores a birth date'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000002';

select throws_ok(
  $$select public.add_minor_profile(current_setting('test.family')::uuid, 'Caio', '12_15', 'pai', '2026-09-29')$$,
  '42501',
  'age_confirmation_required',
  'a self-declared adult cannot create a child profile'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000005';

select throws_ok(
  $$select public.set_minor_supervision(current_setting('test.member_bia')::uuid, '{"daily_limit_minutes": 15}')$$,
  '42501',
  'guardian_access_denied',
  'an adult who is not the guardian cannot change supervision'
);

select ok(
  (
    select member -> 'access' ->> 'supervision' is null
      and (member -> 'access' ->> 'is_minor')::boolean
    from jsonb_array_elements(public.get_current_home_context() -> 'members') as member
    where member ->> 'id' = current_setting('test.member_bia')
  ),
  'an adult who is not the guardian sees a minor but never their band or supervision'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select public.set_minor_supervision(current_setting('test.member_bia')::uuid, '{"daily_limit_minutes": 15, "quiet_start": 1200}')$$,
  'the guardian sets a daily limit and quiet hours'
);

select throws_ok(
  $$select public.set_minor_supervision(current_setting('test.member_bia')::uuid, '{"bedtime": 1}')$$,
  '22023',
  'invalid_supervision_settings',
  'an unknown supervision key is refused'
);

select is(
  (
    select member #>> '{access,supervision,daily_limit_minutes}'
    from jsonb_array_elements(public.get_current_home_context() -> 'members') as member
    where member ->> 'id' = current_setting('test.member_bia')
  ),
  '15',
  'the guardian reads the supervision they set'
);

select throws_ok(
  $$select public.change_minor_band(current_setting('test.member_bia')::uuid, '12_15')$$,
  '22023',
  'invalid_minor_band',
  'an older band needs the consent text again'
);

select lives_ok(
  $$select public.change_minor_band(current_setting('test.member_bia')::uuid, '12_15', '2026-09-29')$$,
  'a guardian corrects an unclaimed profile to an older band with the consent text'
);

select is(
  (select household_role from public.family_members where id = current_setting('test.member_bia')::uuid),
  'teen',
  'the role follows the band'
);

select throws_ok(
  $$insert into public.tasks (family_id, title, owner_member_id, category_id) values (current_setting('test.family')::uuid, 'Vacina', current_setting('test.member_bia')::uuid, 'health')$$,
  'P0001',
  'minor_health_consent_required',
  'a health task for a minor needs the separate health consent'
);

select lives_ok(
  $$select public.set_minor_health_consent(current_setting('test.member_bia')::uuid, true, '2026-09-29')$$,
  'the guardian grants the health consent'
);

select lives_ok(
  $$insert into public.tasks (family_id, title, owner_member_id, category_id) values (current_setting('test.family')::uuid, 'Vacina', current_setting('test.member_bia')::uuid, 'health')$$,
  'with the health consent the health task is accepted'
);

reset role;

insert into public.nina_proposals (id, family_id, owner_user_id, kind, title, payload)
values (
  'a4000000-0000-4000-8000-000000000001',
  current_setting('test.family')::uuid,
  'a1000000-0000-4000-8000-000000000001',
  'task',
  'Dar o remédio',
  '{"title":"Dar o remédio","owner":"Pedro Menor","category":"health"}'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select throws_ok(
  $$select public.resolve_nina_proposal('a4000000-0000-4000-8000-000000000001', 'accept')$$,
  'P0001',
  'minor_health_consent_required',
  'confirming a proposal cannot create a minor''s health task without the consent'
);

select lives_ok(
  $$select public.end_minor_guardianship(current_setting('test.member_bia')::uuid)$$,
  'the last guardian withdraws'
);

reset role;

select ok(
  not exists (select 1 from public.family_members where id = current_setting('test.member_bia')::uuid)
    and exists (select 1 from public.tasks where title = 'Vacina' and owner_member_id is null and owner_label = 'Casa'),
  'the last guardian withdrawing deletes the profile and returns its tasks to the house'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select throws_ok(
  $$select public.record_nina_ai_consent('2026-06-16', true, true)$$,
  '42501',
  'nina_consent_outdated',
  'a consent to an older policy text is refused'
);

select throws_ok(
  $$select public.record_nina_ai_consent('2026-09-29', true)$$,
  '42501',
  'nina_transfer_consent_required',
  'an older build that omits the transfer consent is refused'
);

select is(
  public.record_nina_ai_consent('2026-09-29', true, true) #>> '{ai_consent,is_current}',
  'true',
  'a trusted adult consents at the current version with the transfer'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000005';

select is(
  public.record_nina_ai_consent('2026-09-29', true, true) #>> '{ai_consent,is_current}',
  'true',
  'a second trusted adult consents'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000002';

select throws_ok(
  $$select public.record_nina_ai_consent('2026-09-29', true, true)$$,
  '42501',
  'age_confirmation_required',
  'a self-declared adult cannot consent to AI'
);

select throws_ok(
  $$select public.begin_nina_chat_run(current_setting('test.family')::uuid, gen_random_uuid(), 'Oi', '[]', 'gpt-6-luna', 1000, '2026-09-23')$$,
  '42501',
  'age_confirmation_required',
  'a self-declared adult cannot start a chat run'
);

reset role;

insert into private.nina_ai_blocks (user_id, reason_code) values ('a1000000-0000-4000-8000-000000000001', 'operator');

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select throws_ok(
  $$select public.begin_nina_chat_run(current_setting('test.family')::uuid, gen_random_uuid(), 'Oi', '[]', 'gpt-6-luna', 1000, '2026-09-23')$$,
  '42501',
  'nina_ai_blocked',
  'a blocked adult cannot start a chat run'
);

reset role;

delete from private.nina_ai_blocks where user_id = 'a1000000-0000-4000-8000-000000000001';
update public.nina_ai_consents set policy_version = '2026-06-16' where user_id = 'a1000000-0000-4000-8000-000000000005' and revoked_at is null;

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000005';

select throws_ok(
  $$select public.begin_nina_chat_run(current_setting('test.family')::uuid, gen_random_uuid(), 'Oi', '[]', 'gpt-6-luna', 1000, '2026-09-23')$$,
  '42501',
  'nina_consent_outdated',
  'a live consent on an older policy text does not authorize a run'
);

reset role;

update public.nina_ai_consents set policy_version = '2026-09-29', transfer_consented_at = null where user_id = 'a1000000-0000-4000-8000-000000000005' and revoked_at is null;

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000005';

select throws_ok(
  $$select public.begin_nina_chat_run(current_setting('test.family')::uuid, gen_random_uuid(), 'Oi', '[]', 'gpt-6-luna', 1000, '2026-09-23')$$,
  '42501',
  'nina_transfer_consent_required',
  'a live consent without the transfer consent does not authorize a run'
);

reset role;

update public.nina_ai_consents set transfer_consented_at = now() where user_id = 'a1000000-0000-4000-8000-000000000005' and revoked_at is null;

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select set_config('test.run', (public.begin_nina_chat_run(current_setting('test.family')::uuid, 'a5000000-0000-4000-8000-000000000001', 'Oi Nina', '[]', 'gpt-6-luna', 1000, '2026-09-23') ->> 'run_id'), true)$$,
  'a trusted adult with a current consent starts a chat run'
);

reset role;

select ok(
  (
    select not (keys ?| array['Pedro Menor', 'Ursula Sem Idade', 'Davi Declarado', 'Tia Nair'])
      and keys ? 'Olga Guardiã'
      and keys ? 'Ana Adulta'
    from (
      select jsonb_object_keys_array as keys
      from (
        select coalesce(jsonb_agg(key), '[]'::jsonb) as jsonb_object_keys_array
        from jsonb_object_keys(private.nina_weekly_metrics(current_setting('test.family')::uuid) -> 'open_tasks_by_owner') as key
      ) as collected
    ) as owners
  ),
  'the weekly metrics key only consenting carriers, never a minor, an unclaimed adult or an adult who did not consent'
);

insert into public.premium_subscriptions (original_transaction_id, user_id, product_id, environment, status, is_active, transaction_id, expires_at, signed_transaction_info)
values ('age-original', 'a1000000-0000-4000-8000-000000000001', 'com.heitor.nina.premium.monthly', 'Sandbox', 'active', true, 'age-transaction', now() + interval '30 days', 'signed-example');

set local role service_role;

select ok(
  exists (
    select 1 from jsonb_array_elements(public.get_nina_weekly_candidates()) as candidate(metrics)
    where candidate.metrics ->> 'family_id' = current_setting('test.family')
  ),
  'a covered household with two consenting carriers is a weekly candidate'
);

select ok(
  (
    select jsonb_agg(entry ->> 'alias_kind' order by entry ->> 'name')
    from jsonb_array_elements(public.get_nina_model_roster(current_setting('test.family')::uuid, 'a1000000-0000-4000-8000-000000000001')) as entry
    where entry ->> 'name' in ('Pedro Menor', 'Ursula Sem Idade', 'Davi Declarado', 'Tia Nair', 'Olga Guardiã', 'Ana Adulta')
  ) = '["none", "adult", "none", "teen", "adult", "child"]'::jsonb,
  'the model roster aliases minors and every adult who is not a consenting carrier'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000005';

select is(
  public.record_nina_ai_consent('2026-09-29', false) #>> '{ai_consent,last_revoke_reason}',
  'withdrawn',
  'a withdrawal is recorded with its reason'
);

reset role;
set local role service_role;
set local request.jwt.claim.sub = '';

select ok(
  not exists (
    select 1 from jsonb_array_elements(public.get_nina_weekly_candidates()) as candidate(metrics)
    where candidate.metrics ->> 'family_id' = current_setting('test.family')
  ),
  'with fewer than two consenting carriers the house gets no insight'
);

select lives_ok(
  $$select public.complete_nina_chat_run(current_setting('test.run')::uuid, 'a5000000-0000-4000-8000-000000000002', 'Anotado.', '[]', 1, 0, 1, 0, 1, 10)$$,
  'the server completes the run'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select throws_ok(
  $$select public.report_nina_reply('a5000000-0000-4000-8000-000000000002', 'rude')$$,
  '22023',
  'invalid_report_reason',
  'a report needs one of the four reasons'
);

select is(
  public.report_nina_reply('a5000000-0000-4000-8000-000000000002', 'inappropriate') ->> 'reported',
  'true',
  'an adult reports a reply in their own thread'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000005';

select throws_ok(
  $$select public.report_nina_reply('a5000000-0000-4000-8000-000000000002', 'other')$$,
  'P0002',
  'nina_message_not_found',
  'nobody reports a reply from another adult''s thread'
);

reset role;

select is(
  (select count(*)::integer from public.chat_messages where id in ('a5000000-0000-4000-8000-000000000001', 'a5000000-0000-4000-8000-000000000002') and held_for_review_until > now() + interval '89 days'),
  2,
  'a report holds the reply and the message that caused it for review'
);

set local role service_role;

select lives_ok(
  $$select public.hold_nina_chat_run_for_child_safety(current_setting('test.run')::uuid)$$,
  'the server seals a run for child safety'
);

reset role;

select ok(
  (select text = 'Mensagem não enviada.' from public.chat_messages where id = 'a5000000-0000-4000-8000-000000000001')
    and (select content = 'Oi Nina' from private.child_safety_holds where run_id = current_setting('test.run')::uuid)
    and exists (select 1 from private.nina_ai_blocks where user_id = 'a1000000-0000-4000-8000-000000000001' and reason_code = 'child_safety_hold' and lifted_at is null),
  'a held message leaves normal storage, is sealed for reporting, and blocks the conversation'
);

select ok(
  not has_table_privilege('service_role', 'private.child_safety_holds', 'select'),
  'no API role can read a held message'
);

delete from private.nina_ai_blocks where user_id = 'a1000000-0000-4000-8000-000000000001';
update public.family_members set birth_date = '1990-05-05' where id = current_setting('test.member_ana')::uuid;

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select ok(
  public.export_account_data()::text not like '%1990-05-05%'
    and jsonb_array_length(public.export_account_data() -> 'memberships') = 1
    and (public.export_account_data() ->> 'schema_version') = '1',
  'an account export carries only the caller''s own data, never another member''s birth date'
);

select is(
  public.export_minor_data(current_setting('test.member_minor')::uuid) ->> 'schema_version',
  '1',
  'a live guardian exports the minor''s data'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000005';

select throws_ok(
  $$select public.export_minor_data(current_setting('test.member_minor')::uuid)$$,
  '42501',
  'guardian_access_denied',
  'an adult who is not the guardian cannot export a minor''s data'
);

reset role;
set local role service_role;

select is(
  public.authorize_guardian_account_deletion('a1000000-0000-4000-8000-000000000001', current_setting('test.member_minor')::uuid),
  'a1000000-0000-4000-8000-000000000003'::uuid,
  'a live guardian may delete the ward''s account'
);

select throws_ok(
  $$select public.authorize_guardian_account_deletion('a1000000-0000-4000-8000-000000000005', current_setting('test.member_minor')::uuid)$$,
  '42501',
  'guardian_access_denied',
  'nobody else may delete a minor''s account'
);

select ok(
  public.premium_buyer_is_eligible('a1000000-0000-4000-8000-000000000001')
    and not public.premium_buyer_is_eligible('a1000000-0000-4000-8000-000000000002')
    and not public.premium_buyer_is_eligible('a1000000-0000-4000-8000-000000000003'),
  'only an adult the server lets use AI may start a new subscription'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000008';

select is(
  public.record_nina_ai_consent('2026-09-29', true, true) #>> '{ai_consent,is_granted}',
  'true',
  'a third adult consents before the ratchet'
);

reset role;
set local role service_role;
set local request.jwt.claim.sub = '';

select is(
  public.record_age_signal('a1000000-0000-4000-8000-000000000008', 'minor', '12_15', 'self_declared', false) ->> 'photo_cleanup_required',
  'true',
  'a move from adult to minor applies at once and asks for photo cleanup'
);

reset role;

select ok(
  (select revoke_reason = 'age_status' from public.nina_ai_consents where user_id = 'a1000000-0000-4000-8000-000000000008' order by accepted_at desc limit 1)
    and (select permission_role = 'member' and household_role = 'teen' from public.family_members where user_id = 'a1000000-0000-4000-8000-000000000008' and family_id = current_setting('test.family')::uuid),
  'the ratchet withdraws the live AI consent and drops the administrator seat'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000008';

select ok(
  not public.can_manage_family(current_setting('test.family')::uuid)
    and not public.current_user_is_adult(),
  'a former administrator who is now a minor manages nothing'
);

select ok(
  not public.can_manage_family(current_setting('test.family')::uuid, 'a1000000-0000-4000-8000-000000000001'),
  'can_manage_family never answers about anyone but the caller'
);

reset role;
set local role service_role;

select throws_ok(
  $$select public.record_age_signal('a1000000-0000-4000-8000-000000000008', 'adult', null, 'self_declared', false)$$,
  '22023',
  'age_signal_rejected',
  'a minor becomes an adult only on an Apple-confirmed signal'
);

select is(
  public.record_age_signal('a1000000-0000-4000-8000-00000000000a', 'adult', null, 'self_declared', false) ->> 'status',
  'adult',
  'an account that never was a minor may become a self-declared adult'
);

select is(
  public.record_age_signal('a1000000-0000-4000-8000-000000000003', 'adult', null, 'confirmed', false) ->> 'status',
  'adult',
  'an Apple-confirmed signal releases a minor into adulthood'
);

reset role;

select ok(
  (select end_reason = 'reached_majority' from private.minor_guardianships where member_id = current_setting('test.member_minor')::uuid)
    and not exists (select 1 from private.minor_profiles where member_id = current_setting('test.member_minor')::uuid)
    and (select household_role = 'adult' from public.family_members where id = current_setting('test.member_minor')::uuid),
  'reaching majority ends the guardianship, drops the minor profile and makes the row an adult'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000003';

select is(
  public.get_my_age_status() #>> '{terms,reached_majority}',
  'true',
  'a new adult is asked to accept the terms as their own'
);

select is(
  public.get_my_age_status() #> '{terms,former_guardian_names}',
  '["Olga Guardiã"]'::jsonb,
  'the majority notice names the guardian who no longer follows the account'
);

select is(
  public.record_terms_acceptance() #>> '{terms,reached_majority}',
  'false',
  'accepting the terms closes the majority notice'
);

reset role;
set local role service_role;

select is(
  length(public.issue_age_signal_challenge('a1000000-0000-4000-8000-000000000006') ->> 'challenge'),
  43,
  'a challenge is 32 random bytes in unpadded base64url'
);

select set_config('test.challenge', public.issue_age_signal_challenge('a1000000-0000-4000-8000-000000000006') ->> 'challenge', true);

select ok(
  public.consume_age_signal_challenge('a1000000-0000-4000-8000-000000000006', current_setting('test.challenge'))
    and not public.consume_age_signal_challenge('a1000000-0000-4000-8000-000000000006', current_setting('test.challenge'))
    and not public.consume_age_signal_challenge('a1000000-0000-4000-8000-000000000005', current_setting('test.challenge')),
  'a challenge is single use and bound to its account'
);

select lives_ok(
  $$select public.register_app_attest_key('a1000000-0000-4000-8000-000000000006', 'key-otto', 'MFkwEwYHKoZIzj0CAQ', 'production')$$,
  'the server stores an attested key'
);

select ok(
  public.advance_app_attest_counter('key-otto', 1)
    and not public.advance_app_attest_counter('key-otto', 1)
    and public.advance_app_attest_counter('key-otto', 2),
  'an assertion counter only ever moves forward'
);

select throws_ok(
  $$select public.register_app_attest_key('a1000000-0000-4000-8000-000000000005', 'key-otto', 'MFkwEwYHKoZIzj0CAQ', 'production')$$,
  '22023',
  'app_attest_invalid',
  'a device key is never moved to another account'
);

select throws_ok(
  $sql$do $issue$ begin for attempt in 1..20 loop perform public.issue_age_signal_challenge('a1000000-0000-4000-8000-000000000006'); end loop; end $issue$$sql$,
  'P0001',
  'rate_limited',
  'more than twenty challenges in an hour are refused'
);

reset role;

insert into public.families (id, name, invite_code, created_by)
values ('a2000000-0000-4000-8000-00000000000f', 'Casa Antiga', 'casa-99999999999999999999999999999999', 'a1000000-0000-4000-8000-000000000006');

insert into public.family_join_requests (family_id, requester_user_id, requester_name, created_at)
values
  ('a2000000-0000-4000-8000-00000000000f', 'a1000000-0000-4000-8000-00000000000b', 'Mini Pedido', now() - interval '8 days'),
  ('a2000000-0000-4000-8000-00000000000f', 'a1000000-0000-4000-8000-000000000005', 'Ana Adulta', now() - interval '8 days');

insert into private.minor_usage_days (member_id, day, minutes)
values (current_setting('test.member_unknown')::uuid, (now() at time zone 'America/Sao_Paulo')::date - 40, 10);

set local role service_role;
select lives_ok($$select public.run_nina_retention()$$, 'retention runs');
reset role;

select ok(
  not exists (select 1 from public.family_join_requests where requester_user_id = 'a1000000-0000-4000-8000-00000000000b')
    and exists (select 1 from public.family_join_requests where requester_user_id = 'a1000000-0000-4000-8000-000000000005' and family_id = 'a2000000-0000-4000-8000-00000000000f'),
  'retention deletes a minor''s pending request after seven days and keeps an adult''s'
);

select is(
  (select count(*)::integer from private.minor_usage_days where member_id = current_setting('test.member_unknown')::uuid and day < (now() at time zone 'America/Sao_Paulo')::date - 30),
  0,
  'retention keeps usage minutes for thirty days only'
);

set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000004';

select is(
  public.get_minor_home_view() #>> '{viewer,state}',
  'active',
  'a household-marked minor with a guardian reaches the active view'
);

select is(
  public.get_minor_home_view() #>> '{viewer,acknowledgement_kind}',
  'entendi',
  'a household-marked child is shown the Entendi welcome'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-00000000000b';

select is(
  public.get_minor_home_view() #>> '{viewer,state}',
  'no_home',
  'a minor without a house sees the no-home state'
);

set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select throws_ok(
  $$select public.get_minor_home_view()$$,
  '42501',
  'minor_account_required',
  'an adult has no minor view'
);

reset role;

-- The model roster lists every name a member is known by, so a profile
-- rename cannot leave the name the house registered unaliased.
insert into public.profiles (id, display_name, display_name_source)
values ('a1000000-0000-4000-8000-000000000004', 'Ursa', 'user')
on conflict (id) do update set display_name = excluded.display_name;

set local role service_role;

select is(
  (
    select entry -> 'names'
    from jsonb_array_elements(public.get_nina_model_roster(current_setting('test.family')::uuid, 'a1000000-0000-4000-8000-000000000001')) as entry
    where entry ->> 'member_id' = current_setting('test.member_unknown')
  ),
  '["Ursa", "Ursula Sem Idade"]'::jsonb,
  'the roster carries both the profile name and the name the house registered'
);

reset role;

-- A declined share is not a minor record; only a minor status is.
insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
values
  ('b1000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'gilda@example.com', '{"full_name":"Gilda Dona"}', now(), now()),
  ('b1000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'hugo@example.com', '{"full_name":"Hugo Guardião"}', now(), now()),
  ('b1000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'iara@example.com', '{"full_name":"Iara Menor"}', now(), now()),
  ('b1000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'vera@example.com', '{"full_name":"Vera Recusa"}', now(), now()),
  ('b1000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'caio@example.com', '{"full_name":"Caio Menor"}', now(), now()),
  ('b1000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'lara@example.com', '{"full_name":"Lara Adulta"}', now(), now()),
  ('b1000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'hugo-again@example.com', '{"full_name":"Hugo De Novo"}', now(), now());

insert into private.account_age_status (user_id, status, minor_band, assurance, minor_since, recheck_after)
values
  ('b1000000-0000-4000-8000-000000000001', 'adult', null, 'confirmed', null, now() + interval '180 days'),
  ('b1000000-0000-4000-8000-000000000002', 'adult', null, 'confirmed', null, now() + interval '180 days'),
  ('b1000000-0000-4000-8000-000000000003', 'minor', '12_15', 'self_declared', now(), now() + interval '30 days'),
  ('b1000000-0000-4000-8000-000000000005', 'minor', '16_17', 'self_declared', now(), now() + interval '30 days'),
  ('b1000000-0000-4000-8000-000000000006', 'adult', null, 'confirmed', null, now() + interval '180 days');

set local role service_role;

select is(
  public.record_age_signal('b1000000-0000-4000-8000-000000000004', 'adult', null, 'self_declared', false) ->> 'status',
  'adult',
  'a first share records a self-declared adult'
);

select is(
  public.record_age_signal('b1000000-0000-4000-8000-000000000004', 'unknown', null, 'none', false) ->> 'status',
  'unknown',
  'declining a later share moves the adult to unknown at once'
);

select is(
  public.record_age_signal('b1000000-0000-4000-8000-000000000004', 'adult', null, 'self_declared', false) ->> 'status',
  'adult',
  'an adult who once declined may self-declare again, because declining is not a minor record'
);

select is(
  public.record_age_signal('b1000000-0000-4000-8000-000000000005', 'unknown', null, 'none', false) ->> 'status',
  'unknown',
  'a minor who declines a share reads as unknown'
);

select throws_ok(
  $$select public.record_age_signal('b1000000-0000-4000-8000-000000000005', 'adult', null, 'self_declared', false)$$,
  '22023',
  'age_signal_rejected',
  'a minor who declined once still needs an Apple-confirmed signal to become an adult'
);

reset role;

-- Guardianship lives inside the house: removing the guardian ends it.
set local role authenticated;
set local request.jwt.claim.sub = 'b1000000-0000-4000-8000-000000000001';

select lives_ok($$select public.create_family('Casa Nova')$$, 'a trusted adult creates a second house');
select set_config('test.family2', (select active_family_id::text from public.profiles where id = auth.uid()), true);
select set_config('test.invite2', public.get_current_home_context() #>> '{family,invite_code}', true);

set local request.jwt.claim.sub = 'b1000000-0000-4000-8000-000000000002';
select lives_ok($$select public.request_family_join(current_setting('test.invite2'))$$, 'a trusted adult asks to join the second house');
set local request.jwt.claim.sub = 'b1000000-0000-4000-8000-000000000003';
select lives_ok($$select public.request_family_join(current_setting('test.invite2'))$$, 'a minor asks to join the second house');
set local request.jwt.claim.sub = 'b1000000-0000-4000-8000-000000000006';
select lives_ok($$select public.request_family_join(current_setting('test.invite2'))$$, 'another trusted adult asks to join the second house');

reset role;

select set_config('test.request_hugo', (select id::text from public.family_join_requests where requester_user_id = 'b1000000-0000-4000-8000-000000000002'), true);
select set_config('test.request_iara', (select id::text from public.family_join_requests where requester_user_id = 'b1000000-0000-4000-8000-000000000003'), true);
select set_config('test.request_lara', (select id::text from public.family_join_requests where requester_user_id = 'b1000000-0000-4000-8000-000000000006'), true);

set local role authenticated;
set local request.jwt.claim.sub = 'b1000000-0000-4000-8000-000000000001';

select lives_ok($$select public.approve_family_join_request(current_setting('test.request_hugo')::uuid, 'admin')$$, 'the owner approves a guardian-to-be as administrator');
select lives_ok($$select public.approve_family_join_request(current_setting('test.request_lara')::uuid, 'member')$$, 'the owner approves a second adult');

set local request.jwt.claim.sub = 'b1000000-0000-4000-8000-000000000002';

select lives_ok(
  $$select public.approve_family_join_request(current_setting('test.request_iara')::uuid, 'member', 'pai', '12_15', true, '2026-09-29')$$,
  'a trusted administrator approves a minor as their guardian'
);

reset role;

select set_config('test.member_iara', (select id::text from public.family_members where user_id = 'b1000000-0000-4000-8000-000000000003'), true);
select set_config('test.member_hugo', (select id::text from public.family_members where user_id = 'b1000000-0000-4000-8000-000000000002'), true);

set local role authenticated;
set local request.jwt.claim.sub = 'b1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select public.remove_family_member(current_setting('test.member_hugo')::uuid)$$,
  'the owner removes an adult who guards a minor'
);

reset role;

select ok(
  (
    select end_reason = 'guardian_left'
    from private.minor_guardianships
    where member_id = current_setting('test.member_iara')::uuid
      and guardian_user_id = 'b1000000-0000-4000-8000-000000000002'
  )
  and not exists (
    select 1
    from private.minor_data_consents
    where member_id = current_setting('test.member_iara')::uuid
      and guardian_user_hash = private.user_hash('b1000000-0000-4000-8000-000000000002')
      and withdrawn_at is null
  ),
  'removing a guardian from the house ends the guardianship and withdraws the consents they gave'
);

set local role authenticated;
set local request.jwt.claim.sub = 'b1000000-0000-4000-8000-000000000002';

select throws_ok(
  $$select public.export_minor_data(current_setting('test.member_iara')::uuid)$$,
  '42501',
  'guardian_access_denied',
  'a removed guardian cannot export the ward''s data'
);

select throws_ok(
  $$select public.set_minor_supervision(current_setting('test.member_iara')::uuid, '{"daily_limit_minutes": 15}')$$,
  '42501',
  'guardian_access_denied',
  'a removed guardian cannot change the ward''s supervision'
);

select throws_ok(
  $$select public.remove_family_member(current_setting('test.member_iara')::uuid)$$,
  '42501',
  'family_member_remove_denied',
  'a removed guardian cannot take the ward out of the house'
);

reset role;
set local role service_role;

select throws_ok(
  $$select public.authorize_guardian_account_deletion('b1000000-0000-4000-8000-000000000002', current_setting('test.member_iara')::uuid)$$,
  '42501',
  'guardian_access_denied',
  'a removed guardian cannot delete the ward''s account'
);

reset role;

insert into private.minor_guardianships (family_id, member_id, guardian_user_id, guardian_user_hash, relationship, consent_text_version, guardian_assurance)
values (
  current_setting('test.family2')::uuid,
  current_setting('test.member_iara')::uuid,
  'b1000000-0000-4000-8000-000000000002',
  private.user_hash('b1000000-0000-4000-8000-000000000002'),
  'pai',
  '2026-09-29',
  'confirmed'
);

select ok(
  not private.is_live_guardian(current_setting('test.member_iara')::uuid, 'b1000000-0000-4000-8000-000000000002'),
  'a live link alone never makes someone outside the house a guardian'
);

delete from private.minor_guardianships
where member_id = current_setting('test.member_iara')::uuid
  and guardian_user_id = 'b1000000-0000-4000-8000-000000000002'
  and ended_at is null;

set local role authenticated;
set local request.jwt.claim.sub = 'b1000000-0000-4000-8000-000000000003';

select is(
  public.get_minor_home_view() #>> '{viewer,state}',
  'no_guardian',
  'a ward whose only guardian left the house reads the no-guardian state'
);

select is(
  public.get_my_age_status() ->> 'needs_name',
  'true',
  'a minor whose only name came from the sign-in is asked for one'
);

reset role;

insert into public.profiles (id, display_name, display_name_source)
values ('b1000000-0000-4000-8000-000000000003', 'Iara', 'user')
on conflict (id) do update
set display_name = excluded.display_name, display_name_source = excluded.display_name_source;

set local role authenticated;
set local request.jwt.claim.sub = 'b1000000-0000-4000-8000-000000000003';

select is(
  public.get_my_age_status() ->> 'needs_name',
  'false',
  'a minor who typed a name is not asked again'
);

-- Withdrawing a child's health consent deletes the child's health reminders.
set local request.jwt.claim.sub = 'b1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select public.add_minor_profile(current_setting('test.family2')::uuid, 'Nino', 'under_12', 'mae', '2026-09-29', true)$$,
  'a trusted owner registers a child with the health consent'
);

reset role;

select set_config('test.member_nino', (select id::text from public.family_members where family_id = current_setting('test.family2')::uuid and name = 'Nino'), true);

insert into public.tasks (family_id, title, owner_member_id, category_id)
values
  (current_setting('test.family2')::uuid, 'Xarope do Nino', current_setting('test.member_nino')::uuid, 'health'),
  (current_setting('test.family2')::uuid, 'Mochila do Nino', current_setting('test.member_nino')::uuid, 'school');

set local role authenticated;
set local request.jwt.claim.sub = 'b1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select public.set_minor_health_consent(current_setting('test.member_nino')::uuid, false, null)$$,
  'the guardian withdraws the health consent'
);

reset role;

select ok(
  not exists (
    select 1 from public.tasks
    where owner_member_id = current_setting('test.member_nino')::uuid
      and category_id = 'health'
  )
  and exists (
    select 1 from public.tasks
    where owner_member_id = current_setting('test.member_nino')::uuid
      and category_id = 'school'
  ),
  'withdrawing a child''s health consent deletes the health reminders and keeps the rest'
);

-- A guardian who deletes their account withdraws every consent they gave.
set local role service_role;

select lives_ok(
  $$select public.prepare_account_deletion('b1000000-0000-4000-8000-000000000001')$$,
  'the only guardian of a child profile deletes their account'
);

reset role;

select ok(
  not private.has_live_minor_consent(current_setting('test.member_nino')::uuid, 'profile')
    and not exists (
      select 1 from private.minor_data_consents
      where guardian_user_hash = private.user_hash('b1000000-0000-4000-8000-000000000001')
        and withdrawn_at is null
    )
    and exists (
      select 1 from public.family_members
      where family_id = current_setting('test.family2')::uuid
        and user_id = 'b1000000-0000-4000-8000-000000000006'
        and permission_role = 'owner'
    ),
  'a deleted guardian''s consents read as withdrawn while the house passes to the next adult'
);

-- Deleting a house closes every proof it held open and keeps it as proof.
set local role authenticated;
set local request.jwt.claim.sub = 'b1000000-0000-4000-8000-000000000006';

select lives_ok(
  $$select public.add_minor_profile(current_setting('test.family2')::uuid, 'Tito', '12_15', 'responsavel_legal', '2026-09-29')$$,
  'the new owner registers a teen'
);

reset role;

select set_config('test.links2', (select string_agg(id::text, ',') from private.minor_guardianships where family_id = current_setting('test.family2')::uuid and ended_at is null), true);
select set_config('test.consents2', (select string_agg(id::text, ',') from private.minor_data_consents where family_id = current_setting('test.family2')::uuid and withdrawn_at is null), true);

delete from public.families where id = current_setting('test.family2')::uuid;

select ok(
  (select count(*) from private.minor_guardianships where id = any(string_to_array(current_setting('test.links2'), ',')::uuid[])) > 0
    and not exists (select 1 from private.minor_guardianships where id = any(string_to_array(current_setting('test.links2'), ',')::uuid[]) and ended_at is null)
    and (select count(*) from private.minor_data_consents where id = any(string_to_array(current_setting('test.consents2'), ',')::uuid[])) > 0
    and not exists (select 1 from private.minor_data_consents where id = any(string_to_array(current_setting('test.consents2'), ',')::uuid[]) and withdrawn_at is null),
  'deleting a house ends every guardianship and withdraws every consent it held, and keeps them as proof'
);

-- An account tied to an open hold outlives its own deletion, sealed.
insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
values ('apple-subject-hugo', 'b1000000-0000-4000-8000-000000000002', '{"sub":"apple-subject-hugo"}', 'apple', now(), now());

insert into private.child_safety_holds (id, user_id, content)
values ('b4000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000002', 'conteúdo retido');

set local role service_role;

select lives_ok(
  $$select public.prepare_account_deletion('b1000000-0000-4000-8000-000000000002')$$,
  'an account with an open hold is prepared for deletion'
);

reset role;

delete from auth.users where id = 'b1000000-0000-4000-8000-000000000002';

select ok(
  exists (
    select 1 from private.child_safety_holds
    where id = 'b4000000-0000-4000-8000-000000000001'
      and user_id = 'b1000000-0000-4000-8000-000000000002'
  )
  and exists (
    select 1 from private.child_safety_preserved_accounts
    where hold_id = 'b4000000-0000-4000-8000-000000000001'
      and user_id = 'b1000000-0000-4000-8000-000000000002'
      and apple_subject = 'apple-subject-hugo'
      and email = 'hugo@example.com'
  ),
  'deleting an account with an open hold keeps the hold''s account id and the preserved identifiers'
);

insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
values ('apple-subject-hugo', 'b1000000-0000-4000-8000-000000000007', '{"sub":"apple-subject-hugo"}', 'apple', now(), now());

select ok(
  private.ai_blocked('b1000000-0000-4000-8000-000000000007'),
  'signing in again with the same Apple ID does not clear a child-safety block'
);

update private.child_safety_holds
set content = '', deleted_at = now()
where id = 'b4000000-0000-4000-8000-000000000001';

set local role service_role;
select lives_ok($$select public.run_nina_retention()$$, 'retention runs after a false positive is cleared');
reset role;

select ok(
  not exists (select 1 from private.child_safety_preserved_accounts where hold_id = 'b4000000-0000-4000-8000-000000000001')
    and not private.ai_blocked('b1000000-0000-4000-8000-000000000007'),
  'a false positive keeps no preserved account and blocks nobody'
);

-- A refused message keeps only the neutral marker on the server.
set local role authenticated;
set local request.jwt.claim.sub = 'a1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select set_config('test.refused_run', (public.begin_nina_chat_run(current_setting('test.family')::uuid, 'a5000000-0000-4000-8000-000000000009', 'Texto recusado', '[]', 'gpt-6-luna', 1000, '2026-09-23') ->> 'run_id'), true)$$,
  'a trusted adult starts a run that moderation will refuse'
);

reset role;
set local role service_role;

select lives_ok(
  $$select public.redact_refused_nina_message(current_setting('test.refused_run')::uuid)$$,
  'the server redacts the refused message'
);

reset role;

select is(
  (select text from public.chat_messages where id = 'a5000000-0000-4000-8000-000000000009'),
  'Mensagem não enviada.',
  'a refused message keeps only the neutral marker'
);

select ok(
  not has_function_privilege('authenticated', 'public.redact_refused_nina_message(uuid)', 'execute'),
  'only the server redacts a refused message'
);

select * from finish();

rollback;
