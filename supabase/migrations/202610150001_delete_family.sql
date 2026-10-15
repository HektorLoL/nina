begin;

alter table public.family_access_decisions
  add column if not exists house_deleted boolean not null default false;

comment on column public.family_access_decisions.house_deleted is
  'True when the whole house was deleted rather than the person removed from it. The outcome stays removed or declined, so a build that predates this column still reads a removal as a removal and never as a refused request.';

alter table private.nina_reply_reports
  add column if not exists reply_text text,
  add column if not exists request_text text;

comment on column private.nina_reply_reports.reply_text is
  'The reported reply, copied only when its house is deleted inside the review window; retention clears it ninety days after the report, as it would the reply.';
comment on column private.nina_reply_reports.request_text is
  'The message that asked for the reported reply, copied and cleared with reply_text.';

-- A deleted house withdraws its AI consents and never erases them, so each
-- adult's grant, transfer consent and withdrawal stays demonstrable.
alter table public.nina_ai_consents
  alter column family_id drop not null;
alter table public.nina_ai_consents
  drop constraint if exists nina_ai_consents_family_id_fkey;
alter table public.nina_ai_consents
  add constraint nina_ai_consents_family_id_fkey
  foreign key (family_id) references public.families(id) on delete set null;

alter table public.nina_ai_consents
  drop constraint if exists nina_ai_consents_revoke_reason_check;
alter table public.nina_ai_consents
  add constraint nina_ai_consents_revoke_reason_check
  check (
    revoke_reason is null
    or revoke_reason in ('withdrawn', 'superseded', 'policy_changed', 'age_status', 'house_deleted')
  );

comment on column public.nina_ai_consents.family_id is
  'The house the grant was given in. Null once that house was deleted; the grant was withdrawn with revoke_reason house_deleted first and stays as proof.';

-- A copy taken while the account still lives (its house deleted first) is
-- merged with every later one, so the account's own deletion still adds what
-- it joined and wrote afterwards.
create or replace function private.preserve_child_safety_account(target_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog, public, auth, private
as $$
begin
  insert into private.child_safety_preserved_accounts as preserved (
    hold_id,
    user_id,
    apple_subject,
    email,
    account_created_at,
    last_sign_in_at,
    memberships,
    messages,
    memories
  )
  select
    holds.id,
    users.id,
    (
      select identities.provider_id
      from auth.identities
      where identities.user_id = users.id
        and identities.provider = 'apple'
      order by identities.created_at
      limit 1
    ),
    users.email,
    users.created_at,
    users.last_sign_in_at,
    coalesce(
      (
        select jsonb_agg(to_jsonb(members) order by members.created_at, members.id)
        from public.family_members as members
        where members.user_id = users.id
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(to_jsonb(messages) order by messages.created_at, messages.id)
        from public.chat_messages as messages
        where messages.created_by = users.id
           or messages.thread_id in (
             select threads.id
             from public.nina_threads as threads
             where threads.owner_user_id = users.id
           )
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(to_jsonb(memories) order by memories.created_at, memories.id)
        from public.memory_items as memories
        where memories.owner_user_id = users.id
           or memories.created_by = users.id
      ),
      '[]'::jsonb
    )
  from private.child_safety_holds as holds
  join auth.users on users.id = holds.user_id
  where holds.user_id = target_user_id
    and private.child_safety_hold_is_preserved(holds)
  on conflict (hold_id) do update
  set
    apple_subject = coalesce(excluded.apple_subject, preserved.apple_subject),
    email = coalesce(excluded.email, preserved.email),
    account_created_at = coalesce(preserved.account_created_at, excluded.account_created_at),
    last_sign_in_at = greatest(preserved.last_sign_in_at, excluded.last_sign_in_at),
    memberships = (
      select coalesce(
        jsonb_agg(kept.item order by kept.item ->> 'created_at', kept.item ->> 'id'),
        '[]'::jsonb
      )
      from (
        select distinct elements.item
        from jsonb_array_elements(preserved.memberships || excluded.memberships)
          as elements(item)
      ) as kept
    ),
    messages = (
      select coalesce(
        jsonb_agg(kept.item order by kept.item ->> 'created_at', kept.item ->> 'id'),
        '[]'::jsonb
      )
      from (
        select distinct elements.item
        from jsonb_array_elements(preserved.messages || excluded.messages)
          as elements(item)
      ) as kept
    ),
    memories = (
      select coalesce(
        jsonb_agg(kept.item order by kept.item ->> 'created_at', kept.item ->> 'id'),
        '[]'::jsonb
      )
      from (
        select distinct elements.item
        from jsonb_array_elements(preserved.memories || excluded.memories)
          as elements(item)
      ) as kept
    );
end;
$$;

revoke all on function private.preserve_child_safety_account(uuid)
  from public, anon, authenticated, service_role;

-- A run whose house disappears books its whole reservation as spent, so the
-- month's cap never shrinks for a reservation nothing will settle.
create or replace function private.settle_household_ai_runs(target_family_id uuid)
returns void
language plpgsql
set search_path = pg_catalog, public, private
as $$
declare
  open_run record;
begin
  for open_run in
    select runs.id, runs.purpose, runs.budget_month_start, runs.reserved_microusd
    from public.nina_ai_runs as runs
    where runs.family_id = target_family_id
      and runs.status in ('reserved', 'running')
    order by runs.id
    for update
  loop
    update public.nina_ai_budget_months as months
    set
      reserved_microusd = greatest(months.reserved_microusd - open_run.reserved_microusd, 0),
      spent_microusd = months.spent_microusd
        + least(open_run.reserved_microusd, months.reserved_microusd)
    where months.month_start = open_run.budget_month_start
      and months.purpose = open_run.purpose;

    update public.nina_ai_runs
    set
      status = 'failed',
      error_code = 'family_deleted',
      actual_microusd = open_run.reserved_microusd,
      completed_at = now()
    where id = open_run.id;
  end loop;
end;
$$;

revoke all on function private.settle_household_ai_runs(uuid)
  from public, anon, authenticated, service_role;

-- The one way a house is deleted. Every person it held, and everyone waiting
-- to enter, is told, which also starts a minor account's thirty days from now.
create or replace function private.delete_household(
  target_family_id uuid,
  deleting_user_id uuid
)
returns void
language plpgsql
set search_path = pg_catalog, public, auth, private
as $$
declare
  household_name text;
  claimed record;
begin
  select families.name
  into household_name
  from public.families
  where families.id = target_family_id;

  if not found then
    return;
  end if;

  -- A removal or a departure leaves the person's chat and memories in the house, so whoever wrote here is copied, not only its members.
  for claimed in
    select people.user_id
    from (
      select members.user_id
      from public.family_members as members
      where members.family_id = target_family_id
      union
      select threads.owner_user_id
      from public.nina_threads as threads
      where threads.family_id = target_family_id
      union
      select messages.created_by
      from public.chat_messages as messages
      where messages.family_id = target_family_id
      union
      select memories.owner_user_id
      from public.memory_items as memories
      where memories.family_id = target_family_id
      union
      select memories.created_by
      from public.memory_items as memories
      where memories.family_id = target_family_id
    ) as people
    where people.user_id is not null
    order by people.user_id
  loop
    perform private.preserve_child_safety_account(claimed.user_id);
  end loop;

  perform private.settle_household_ai_runs(target_family_id);

  insert into public.family_access_decisions (
    family_id,
    family_name,
    subject_user_id,
    outcome,
    house_deleted
  )
  select
    members.family_id,
    household_name,
    members.user_id,
    'removed',
    true
  from public.family_members as members
  where members.family_id = target_family_id
    and members.user_id is not null
    and members.user_id is distinct from deleting_user_id;

  insert into public.family_access_decisions (
    family_id,
    family_name,
    subject_user_id,
    outcome,
    house_deleted
  )
  select
    requests.family_id,
    household_name,
    requests.requester_user_id,
    'declined',
    true
  from public.family_join_requests as requests
  where requests.family_id = target_family_id
    and requests.status = 'pending'
    and requests.requester_user_id is distinct from deleting_user_id
    and not exists (
      select 1
      from public.family_members as members
      where members.family_id = target_family_id
        and members.user_id = requests.requester_user_id
    );

  update public.profiles
  set active_family_id = null
  where profiles.active_family_id = target_family_id;

  update public.nina_ai_consents as consents
  set
    revoked_at = greatest(now(), consents.accepted_at),
    revoke_reason = 'house_deleted'
  where consents.family_id = target_family_id
    and consents.revoked_at is null;

  -- A reply another adult reported outlives the house for its review: only that reporter erases it early.
  update private.nina_reply_reports as reports
  set
    reply_text = coalesce(reports.reply_text, replies.text),
    request_text = coalesce(
      reports.request_text,
      (
        select requests.text
        from public.nina_ai_runs as runs
        join public.chat_messages as requests on requests.id = runs.request_message_id
        where runs.id = replies.run_id
      )
    )
  from public.chat_messages as replies
  where reports.message_id = replies.id
    and replies.family_id = target_family_id
    and replies.held_for_review_until > now()
    and reports.reporter_user_id is distinct from deleting_user_id;

  delete from public.families
  where families.id = target_family_id;
end;
$$;

revoke all on function private.delete_household(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.get_family_access_decision()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  decision_payload jsonb;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select jsonb_build_object(
    'id', decisions.id,
    'family_name', decisions.family_name,
    'outcome', decisions.outcome,
    'decided_at', decisions.decided_at,
    'house_deleted', decisions.house_deleted
  )
  into decision_payload
  from public.family_access_decisions as decisions
  where decisions.subject_user_id = current_user_id
    and decisions.acknowledged_at is null
    and not exists (
      select 1
      from public.family_members as members
      where members.family_id = decisions.family_id
        and members.user_id = current_user_id
    )
    and not exists (
      select 1
      from public.family_join_requests as requests
      where requests.family_id = decisions.family_id
        and requests.requester_user_id = current_user_id
        and requests.status = 'pending'
    )
  order by decisions.decided_at desc
  limit 1;

  return decision_payload;
end;
$$;

comment on function public.get_family_access_decision() is
  'The most recent unread terminal decision about the caller, and nothing else: only rows whose subject is auth.uid(), the household name but no other household fact, and never the person who decided. A live membership or a fresh pending request retires the decision, so nobody is told they were turned away by a home they are already back inside.';

revoke all on function public.get_family_access_decision()
  from public, anon, authenticated, service_role;
grant execute on function public.get_family_access_decision() to authenticated;

create or replace function public.prepare_account_deletion(target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  target_membership record;
  orphan_family record;
  family_created_by uuid;
  replacement_user_id uuid;
  target_permission_role text;
  shared_families_preserved integer := 0;
  solo_families_deleted integer := 0;
begin
  if target_user_id is null then
    raise exception 'account_deletion_user_required' using errcode = '22023';
  end if;

  perform private.preserve_child_safety_account(target_user_id);

  update private.minor_guardianships as links
  set
    ended_at = now(),
    end_reason = 'account_deleted'
  where links.ended_at is null
    and (
      links.guardian_user_id = target_user_id
      or links.member_id in (
        select members.id
        from public.family_members as members
        where members.user_id = target_user_id
      )
    );

  update private.minor_data_consents as consents
  set withdrawn_at = now()
  where consents.withdrawn_at is null
    and consents.member_id in (
      select members.id
      from public.family_members as members
      where members.user_id = target_user_id
    );

  update private.minor_data_consents as consents
  set
    withdrawn_at = now(),
    withdrawn_by_hash = consents.guardian_user_hash
  where consents.withdrawn_at is null
    and consents.guardian_user_hash = private.user_hash(target_user_id);

  delete from public.nina_proposals
  where owner_user_id = target_user_id;

  delete from public.nina_threads
  where owner_user_id = target_user_id;

  delete from public.memory_items
  where owner_user_id = target_user_id
     or created_by = target_user_id;

  delete from public.chat_messages
  where created_by = target_user_id;

  -- The words a deleted house left on this person's reports go with the account, as the messages would have.
  update private.nina_reply_reports
  set
    reply_text = null,
    request_text = null
  where reporter_user_id = target_user_id
    and (reply_text is not null or request_text is not null);

  for target_membership in
    select family_members.family_id
    from public.family_members
    where family_members.user_id = target_user_id
    order by family_members.family_id
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(target_membership.family_id::text, 0)
    );

    select families.created_by
    into family_created_by
    from public.families
    where families.id = target_membership.family_id
    for update;

    if not found then
      continue;
    end if;

    perform family_members.id
    from public.family_members
    where family_members.family_id = target_membership.family_id
    order by family_members.id
    for update;

    select family_members.permission_role
    into target_permission_role
    from public.family_members
    where family_members.family_id = target_membership.family_id
      and family_members.user_id = target_user_id;

    if not found then
      continue;
    end if;

    -- A house is only ever handed to an adult; with no adult left it is
    -- deleted rather than left to minors.
    select family_members.user_id
    into replacement_user_id
    from public.family_members
    where family_members.family_id = target_membership.family_id
      and family_members.user_id is not null
      and family_members.user_id <> target_user_id
      and family_members.household_role = 'adult'
      and private.is_adult(family_members.user_id)
    order by
      case family_members.permission_role
        when 'owner' then 0
        when 'admin' then 1
        else 2
      end,
      family_members.created_at,
      family_members.id
    limit 1;

    if replacement_user_id is null then
      if family_created_by = target_user_id then
        perform private.delete_household(target_membership.family_id, target_user_id);
        solo_families_deleted := solo_families_deleted + 1;
      else
        delete from public.family_members
        where family_members.family_id = target_membership.family_id
          and family_members.user_id = target_user_id;
      end if;
      continue;
    end if;

    update public.families
    set created_by = replacement_user_id
    where families.id = target_membership.family_id
      and families.created_by = target_user_id;

    if target_permission_role = 'owner'
       and not exists (
         select 1
         from public.family_members
         where family_members.family_id = target_membership.family_id
           and family_members.user_id <> target_user_id
           and family_members.user_id is not null
           and family_members.permission_role = 'owner'
       ) then
      update public.family_members
      set permission_role = 'owner'
      where family_members.family_id = target_membership.family_id
        and family_members.user_id = replacement_user_id;
    end if;

    delete from public.family_members
    where family_members.family_id = target_membership.family_id
      and family_members.user_id = target_user_id;

    shared_families_preserved := shared_families_preserved + 1;
  end loop;

  for orphan_family in
    select families.id
    from public.families
    where families.created_by = target_user_id
    order by families.id
    for update
  loop
    select family_members.user_id
    into replacement_user_id
    from public.family_members
    where family_members.family_id = orphan_family.id
      and family_members.user_id is not null
      and family_members.user_id <> target_user_id
      and family_members.household_role = 'adult'
      and private.is_adult(family_members.user_id)
    order by
      case family_members.permission_role
        when 'owner' then 0
        when 'admin' then 1
        else 2
      end,
      family_members.created_at,
      family_members.id
    limit 1;

    if replacement_user_id is null then
      perform private.delete_household(orphan_family.id, target_user_id);
      solo_families_deleted := solo_families_deleted + 1;
    else
      update public.families
      set created_by = replacement_user_id
      where families.id = orphan_family.id;

      if not exists (
        select 1
        from public.family_members
        where family_members.family_id = orphan_family.id
          and family_members.permission_role = 'owner'
          and family_members.user_id is not null
          and family_members.user_id <> target_user_id
      ) then
        update public.family_members
        set permission_role = 'owner'
        where family_members.family_id = orphan_family.id
          and family_members.user_id = replacement_user_id;
      end if;

      shared_families_preserved := shared_families_preserved + 1;
    end if;
  end loop;

  update public.invites
  set
    created_by = families.created_by,
    accepted_by = array_remove(invites.accepted_by, target_user_id),
    revoked_at = case
      when invites.created_by = target_user_id
        then coalesce(invites.revoked_at, now())
      else invites.revoked_at
    end
  from public.families
  where families.id = invites.family_id
    and (
      invites.created_by = target_user_id
      or target_user_id = any(invites.accepted_by)
    );

  delete from public.family_members
  where family_members.user_id = target_user_id;

  update public.profiles
  set active_family_id = null
  where profiles.id = target_user_id;

  return jsonb_build_object(
    'prepared', true,
    'shared_families_preserved', shared_families_preserved,
    'solo_families_deleted', solo_families_deleted
  );
end;
$$;

revoke all on function public.prepare_account_deletion(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.prepare_account_deletion(uuid) to service_role;

create or replace function public.run_nina_retention()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  deleted_messages integer;
  deleted_proposals integer;
  deleted_runs integer;
  deleted_insights integer;
  archived_tasks integer;
  deleted_challenges integer;
  deleted_attest_keys integer;
  deleted_minor_requests integer;
  deleted_usage_days integer;
  deleted_reports integer;
  deleted_blocks integer;
  deleted_preserved_accounts integer;
  deleted_consent_proofs integer := 0;
  deleted_legacy_profiles integer := 0;
  proof_rows integer;
  legacy_deadline timestamptz;
begin
  update public.nina_proposals
  set
    state = 'rejected',
    resolved_at = now(),
    resolved_payload = jsonb_build_object('reason', 'expired')
  where state = 'pending'
    and created_at < now() - interval '30 days';

  -- A reported reply is held for review, and never for more than ninety days.
  delete from public.chat_messages
  where coalesce(retained_until, created_at + interval '30 days') < now()
    and (
      held_for_review_until is null
      or held_for_review_until < now()
      or held_for_review_until > now() + interval '90 days'
    );
  get diagnostics deleted_messages = row_count;

  -- Words a deleted house left on a report are kept no longer than the reply itself could be.
  update private.nina_reply_reports
  set
    reply_text = null,
    request_text = null
  where created_at < now() - interval '90 days'
    and (reply_text is not null or request_text is not null);

  delete from public.nina_proposals
  where state <> 'pending'
    and resolved_at < now() - interval '30 days';
  get diagnostics deleted_proposals = row_count;

  delete from public.nina_ai_runs
  where created_at < now() - interval '90 days';
  get diagnostics deleted_runs = row_count;

  delete from public.household_insights
  where coalesce(expires_at, created_at + interval '90 days') < now();
  get diagnostics deleted_insights = row_count;

  -- Thirty days sits well clear of the seven the weekly insight reads back, so
  -- bounding the list can never starve the metric it is measured from.
  update public.tasks
  set archived_at = now()
  where archived_at is null
    and is_done
    and completed_at < now() - interval '30 days';
  get diagnostics archived_tasks = row_count;

  delete from private.age_signal_challenges
  where created_at < now() - interval '1 day';
  get diagnostics deleted_challenges = row_count;

  delete from private.app_attest_keys
  where coalesce(last_used_at, created_at) < now() - interval '400 days';
  get diagnostics deleted_attest_keys = row_count;

  delete from public.family_join_requests as requests
  where requests.status = 'pending'
    and requests.created_at < now() - interval '7 days'
    and not private.is_adult(requests.requester_user_id);
  get diagnostics deleted_minor_requests = row_count;

  delete from private.minor_usage_days
  where day < (now() at time zone 'America/Sao_Paulo')::date - 30;
  get diagnostics deleted_usage_days = row_count;

  delete from private.nina_reply_reports
  where reviewed_at < now() - interval '6 months';
  get diagnostics deleted_reports = row_count;

  delete from private.nina_ai_blocks
  where lifted_at < now() - interval '1 year';
  get diagnostics deleted_blocks = row_count;

  delete from private.child_safety_preserved_accounts as preserved
  using private.child_safety_holds as holds
  where holds.id = preserved.hold_id
    and not private.child_safety_hold_is_preserved(holds);
  get diagnostics deleted_preserved_accounts = row_count;

  delete from private.minor_guardianships
  where ended_at < now() - interval '5 years';
  get diagnostics proof_rows = row_count;
  deleted_consent_proofs := deleted_consent_proofs + proof_rows;

  delete from private.minor_data_consents
  where withdrawn_at < now() - interval '5 years';
  get diagnostics proof_rows = row_count;
  deleted_consent_proofs := deleted_consent_proofs + proof_rows;

  delete from private.account_terms_acceptances
  where user_id is null
    and accepted_at < now() - interval '5 years';
  get diagnostics proof_rows = row_count;
  deleted_consent_proofs := deleted_consent_proofs + proof_rows;

  select policy.legacy_profile_deadline
  into legacy_deadline
  from private.age_policy as policy
  where policy.singleton;

  if legacy_deadline is not null and legacy_deadline < now() then
    delete from public.family_members as members
    where members.user_id is null
      and members.household_role in ('child', 'teen')
      and not private.has_live_minor_consent(members.id, 'profile')
      and not exists (
        select 1
        from private.minor_guardianships as links
        where links.member_id = members.id
          and links.ended_at is null
      );
    get diagnostics deleted_legacy_profiles = row_count;
  end if;

  return jsonb_build_object(
    'messages', deleted_messages,
    'proposals', deleted_proposals,
    'runs', deleted_runs,
    'insights', deleted_insights,
    'archived_tasks', archived_tasks,
    'age_challenges', deleted_challenges,
    'app_attest_keys', deleted_attest_keys,
    'minor_join_requests', deleted_minor_requests,
    'minor_usage_days', deleted_usage_days,
    'reply_reports', deleted_reports,
    'ai_blocks', deleted_blocks,
    'preserved_accounts', deleted_preserved_accounts,
    'consent_proofs', deleted_consent_proofs,
    'legacy_minor_profiles', deleted_legacy_profiles
  );
end;
$$;

revoke all on function public.run_nina_retention()
  from public, anon, authenticated, service_role;
grant execute on function public.run_nina_retention() to service_role;

-- Only the titular deletes a house, and only while an adult today: an admin
-- never deletes over the titular, and a titular who became a minor keeps the
-- role on the row but none of its powers. The name the person confirmed must
-- still be the house's name, so a house renamed meanwhile is never deleted
-- on a confirmation given for another name.
create or replace function public.delete_family(
  target_family_id uuid,
  confirmed_family_name text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  caller_member public.family_members%rowtype;
  household_name text;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.family_members as members
    where members.family_id = target_family_id
      and members.user_id = current_user_id
  ) then
    raise exception 'family_not_found' using errcode = 'P0002';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target_family_id::text, 0)
  );

  -- Open runs are locked before the house row, the order a finishing run takes them in.
  perform private.settle_household_ai_runs(target_family_id);

  select families.name
  into household_name
  from public.families
  where families.id = target_family_id
  for update;

  if not found then
    raise exception 'family_not_found' using errcode = 'P0002';
  end if;

  perform members.id
  from public.family_members as members
  where members.family_id = target_family_id
  order by members.id
  for update;

  select *
  into caller_member
  from public.family_members as members
  where members.family_id = target_family_id
    and members.user_id = current_user_id;

  if not found then
    raise exception 'family_not_found' using errcode = 'P0002';
  end if;

  if caller_member.permission_role is distinct from 'owner'
     or not public.can_manage_family(target_family_id) then
    raise exception 'family_delete_denied' using errcode = '42501';
  end if;

  if lower(btrim(coalesce(confirmed_family_name, ''))) <> lower(btrim(household_name)) then
    raise exception 'family_delete_name_mismatch' using errcode = '22023';
  end if;

  perform private.delete_household(target_family_id, current_user_id);

  return public.get_current_home_context();
end;
$$;

revoke all on function public.delete_family(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.delete_family(uuid, text) to authenticated;

commit;
