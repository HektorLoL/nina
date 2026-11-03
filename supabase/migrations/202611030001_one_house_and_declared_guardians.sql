begin;

-- The account lock sits after the family lock and before any row lock, so two houses never take the same person at once.
create or replace function private.lock_account(target_user_id uuid)
returns void
language sql
volatile
set search_path = pg_catalog
as $$
  select pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('account:' || target_user_id::text, 0)
  );
$$;

revoke all on function private.lock_account(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.claimed_house_elsewhere(
  target_user_id uuid,
  target_family_id uuid
)
returns boolean
language sql
stable
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.family_members as members
    where members.user_id = target_user_id
      and members.family_id is distinct from target_family_id
  );
$$;

revoke all on function private.claimed_house_elsewhere(uuid, uuid)
  from public, anon, authenticated, service_role;

-- One house per account: a second claimed row is refused, while rows left in two houses before this rule stay until the person leaves.
create or replace function private.enforce_one_house_per_account()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if new.user_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.user_id is not distinct from new.user_id
     and old.family_id = new.family_id then
    return new;
  end if;

  perform private.lock_account(new.user_id);

  if private.claimed_house_elsewhere(new.user_id, new.family_id) then
    raise exception 'family_membership_exists' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_one_house_per_account()
  from public, anon, authenticated, service_role;

drop trigger if exists family_members_one_house_per_account on public.family_members;
create trigger family_members_one_house_per_account
  before insert or update of user_id, family_id on public.family_members
  for each row execute function private.enforce_one_house_per_account();

-- Entering a house retires every unread removal or refusal, so a later departure never resurfaces an old one.
create or replace function private.retire_access_decisions_on_join()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  update public.family_access_decisions
  set acknowledged_at = greatest(now(), decided_at)
  where subject_user_id = new.user_id
    and acknowledged_at is null;

  return null;
end;
$$;

revoke all on function private.retire_access_decisions_on_join()
  from public, anon, authenticated, service_role;

drop trigger if exists family_members_retire_access_decisions on public.family_members;
create trigger family_members_retire_access_decisions
  after insert on public.family_members
  for each row
  when (new.user_id is not null)
  execute function private.retire_access_decisions_on_join();

-- A house names its owner through the permission role alone, never through the relationship.
create or replace function public.create_family(family_name text, invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  current_profile public.profiles%rowtype;
  normalized_name text := trim(family_name);
  normalized_invite_code text := lower(trim(invite_code));
  target_family public.families%rowtype;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform private.require_adult_account(current_user_id);
  perform private.lock_account(current_user_id);

  if private.claimed_house_elsewhere(current_user_id, null) then
    raise exception 'family_membership_exists' using errcode = 'P0001';
  end if;

  if normalized_name = '' then
    raise exception 'family_name_required' using errcode = '22023';
  end if;

  if length(normalized_invite_code) < 4 then
    raise exception 'invalid_invite_code' using errcode = '22023';
  end if;

  current_profile := public.ensure_current_profile(null);

  if exists (
    select 1
    from public.families
    where families.invite_code = normalized_invite_code
  ) then
    normalized_invite_code := normalized_invite_code
      || '-'
      || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
  end if;

  insert into public.families (name, invite_code, created_by)
  values (normalized_name, normalized_invite_code, current_user_id)
  returning * into target_family;

  insert into public.family_members (
    family_id,
    user_id,
    name,
    relationship,
    household_role,
    permission_role,
    tone,
    memory_note
  )
  values (
    target_family.id,
    current_user_id,
    current_profile.display_name,
    '',
    'adult',
    'owner',
    'sky',
    'Participante principal desta casa.'
  );

  insert into public.family_members (
    family_id,
    user_id,
    name,
    relationship,
    household_role,
    permission_role,
    tone,
    memory_note
  )
  values (
    target_family.id,
    null,
    'Nina',
    'IA da casa',
    'assistant',
    'member',
    'mint',
    'Aprende a dinâmica familiar e transforma lembranças soltas em organização.'
  );

  update public.family_join_requests
  set status = 'cancelled'
  where requester_user_id = current_user_id
    and status = 'pending';

  update public.profiles
  set active_family_id = target_family.id
  where id = current_user_id;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.create_family(text, text)
  from public, anon, authenticated, service_role;

create or replace function public.request_family_join(invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  normalized_code text := lower(trim(invite_code));
  target_invite public.invites%rowtype;
  initial_family_id uuid;
  target_family public.families%rowtype;
  current_user_id uuid := auth.uid();
  current_profile public.profiles%rowtype;
  target_request public.family_join_requests%rowtype;
  requester_age record;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select *
  into target_invite
  from public.invites
  where token = normalized_code;

  if not found then
    raise exception 'invalid_invite_code' using errcode = 'P0001';
  end if;

  initial_family_id := target_invite.family_id;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(initial_family_id::text, 0)
  );
  perform private.lock_account(current_user_id);

  select *
  into target_invite
  from public.invites
  where token = normalized_code
  for update;

  if not found
     or target_invite.family_id <> initial_family_id
     or target_invite.revoked_at is not null
     or target_invite.expires_at <= now()
     or cardinality(target_invite.accepted_by) >= target_invite.max_uses then
    raise exception 'invalid_invite_code' using errcode = 'P0001';
  end if;

  select *
  into target_family
  from public.families
  where id = target_invite.family_id;

  if not found then
    raise exception 'invalid_invite_code' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.family_members
    where family_id = target_family.id
      and user_id = current_user_id
  ) then
    update public.profiles
    set active_family_id = target_family.id
    where id = current_user_id;

    return jsonb_build_object(
      'status', 'member',
      'home_context', public.get_current_home_context(),
      'request', null
    );
  end if;

  if private.claimed_house_elsewhere(current_user_id, target_family.id) then
    raise exception 'family_membership_exists' using errcode = 'P0001';
  end if;

  if (
    select count(*)
    from public.family_members
    where family_id = target_family.id
      and household_role <> 'assistant'
  ) >= 8 then
    raise exception 'family_member_limit_reached' using errcode = '23514';
  end if;

  update public.family_join_requests
  set status = 'cancelled'
  where requester_user_id = current_user_id
    and status = 'pending'
    and family_id <> target_family.id;

  current_profile := public.ensure_current_profile(null);
  select * into requester_age from private.effective_age(current_user_id);

  insert into public.family_join_requests (
    family_id,
    invite_token,
    requester_user_id,
    requester_name,
    requester_age_status,
    requester_band
  )
  values (
    target_family.id,
    target_invite.token,
    current_user_id,
    current_profile.display_name,
    requester_age.status,
    case when requester_age.status = 'minor' then requester_age.band end
  )
  on conflict (family_id, requester_user_id) where status = 'pending'
  do update set
    invite_token = excluded.invite_token,
    requester_name = excluded.requester_name,
    requester_age_status = excluded.requester_age_status,
    requester_band = excluded.requester_band,
    updated_at = now()
  returning * into target_request;

  return jsonb_build_object(
    'status', 'pending',
    'home_context', null,
    'request', jsonb_build_object(
      'id', target_request.id,
      'family_id', target_request.family_id,
      'family_name', target_family.name,
      'requester_user_id', target_request.requester_user_id,
      'requester_name', target_request.requester_name,
      'status', target_request.status,
      'created_at', target_request.created_at,
      'reviewed_at', target_request.reviewed_at
    )
  );
end;
$$;

revoke all on function public.request_family_join(text)
  from public, anon, authenticated, service_role;
grant execute on function public.request_family_join(text) to authenticated;

-- A minor or an unknown requester enters only through one atomic approval by a
-- trusted owner or administrator who declares being their guardian: the
-- member row, the guardianship, the consent and the acceptance land together.
create or replace function public.approve_family_join_request(
  target_request_id uuid,
  granted_permission_role text default 'member',
  guardian_relationship text default null,
  minor_band text default null,
  guardian_declared boolean default false,
  consent_version text default null,
  health_consent boolean default false,
  nicknames text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  requested_permission text := approve_family_join_request.granted_permission_role;
  requested_relationship text := approve_family_join_request.guardian_relationship;
  requested_band text := approve_family_join_request.minor_band;
  requested_declaration boolean := coalesce(approve_family_join_request.guardian_declared, false);
  requested_consent_version text := approve_family_join_request.consent_version;
  requested_health boolean := coalesce(approve_family_join_request.health_consent, false);
  requested_nicknames text[] := approve_family_join_request.nicknames;
  guardian_arguments_present boolean;
  cleaned_nicknames text[];
  initial_family_id uuid;
  initial_requester_id uuid;
  manager_permission text;
  target_request public.family_join_requests%rowtype;
  target_profile public.profiles%rowtype;
  target_invite public.invites%rowtype;
  requester_age record;
  policy private.age_policy%rowtype;
  approved_member_id uuid;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select requests.family_id, requests.requester_user_id
  into initial_family_id, initial_requester_id
  from public.family_join_requests as requests
  where requests.id = target_request_id;

  if not found then
    raise exception 'join_request_not_pending' using errcode = 'P0002';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(initial_family_id::text, 0)
  );
  perform private.lock_account(initial_requester_id);

  select *
  into target_request
  from public.family_join_requests as requests
  where requests.id = target_request_id
  for update;

  if not found
     or target_request.family_id <> initial_family_id
     or target_request.requester_user_id <> initial_requester_id
     or target_request.status <> 'pending' then
    raise exception 'join_request_not_pending' using errcode = 'P0002';
  end if;

  select members.permission_role
  into manager_permission
  from public.family_members as members
  where members.family_id = target_request.family_id
    and members.user_id = current_user_id;

  select * into requester_age from private.effective_age(target_request.requester_user_id);
  select * into policy from private.age_policy where singleton;

  guardian_arguments_present := requested_relationship is not null
    or requested_band is not null
    or requested_declaration
    or requested_consent_version is not null
    or requested_health
    or coalesce(cardinality(requested_nicknames), 0) > 0;

  if requester_age.status = 'adult' then
    if not public.can_manage_family(target_request.family_id) then
      raise exception 'family_management_denied' using errcode = '42501';
    end if;

    if guardian_arguments_present then
      raise exception 'join_request_age_changed' using errcode = 'P0001';
    end if;

    if coalesce(requested_permission, '') not in ('admin', 'member')
       or (requested_permission = 'admin' and manager_permission <> 'owner') then
      raise exception 'permission_role_denied' using errcode = '42501';
    end if;
  else
    if coalesce(manager_permission, '') not in ('owner', 'admin') then
      raise exception 'family_management_denied' using errcode = '42501';
    end if;

    if not guardian_arguments_present then
      raise exception 'join_request_age_changed' using errcode = 'P0001';
    end if;

    if not private.is_trusted_adult(current_user_id) then
      raise exception 'age_confirmation_required' using errcode = '42501';
    end if;

    if not requested_declaration
       or coalesce(requested_relationship, '') not in ('mae', 'pai', 'responsavel_legal') then
      raise exception 'guardian_declaration_required' using errcode = '22023';
    end if;

    if requested_consent_version is distinct from policy.current_minor_consent_version then
      raise exception 'minor_consent_outdated' using errcode = '22023';
    end if;

    if private.band_rank(requested_band) is null
       or (
         requester_age.status = 'minor'
         and private.band_rank(requested_band) > private.band_rank(requester_age.band)
       ) then
      raise exception 'invalid_minor_band' using errcode = '22023';
    end if;

    if coalesce(requested_permission, 'member') <> 'member' then
      raise exception 'minor_role_restricted' using errcode = '42501';
    end if;

    cleaned_nicknames := private.normalized_nicknames(requested_nicknames);
  end if;

  -- A requester who meanwhile joined or created another house reads as a request that no longer holds, never as that house.
  if private.claimed_house_elsewhere(target_request.requester_user_id, target_request.family_id) then
    raise exception 'join_request_not_pending' using errcode = 'P0002';
  end if;

  if target_request.invite_token is not null then
    select *
    into target_invite
    from public.invites
    where token = target_request.invite_token
    for update;

    if found
       and not (target_request.requester_user_id = any(target_invite.accepted_by)) then
      if cardinality(target_invite.accepted_by) >= target_invite.max_uses then
        raise exception 'invite_use_limit_reached' using errcode = '23514';
      end if;

      update public.invites
      set accepted_by = array_append(accepted_by, target_request.requester_user_id)
      where token = target_invite.token;
    end if;
  end if;

  select *
  into target_profile
  from public.profiles
  where id = target_request.requester_user_id;

  if requester_age.status = 'adult' then
    insert into public.family_members (
      family_id,
      user_id,
      name,
      relationship,
      household_role,
      permission_role,
      tone,
      memory_note
    )
    values (
      target_request.family_id,
      target_request.requester_user_id,
      coalesce(target_profile.display_name, target_request.requester_name),
      'Participante',
      'adult',
      requested_permission,
      'sky',
      'Participante desta casa.'
    )
    on conflict (family_id, user_id) where user_id is not null
    do update set
      permission_role = excluded.permission_role,
      updated_at = now();
  else
    if requester_age.status = 'unknown' then
      insert into private.account_age_status (
        user_id,
        status,
        minor_band,
        assurance,
        parental_controls_active,
        household_marked,
        minor_since,
        recorded_at,
        recheck_after
      )
      values (
        target_request.requester_user_id,
        'minor',
        requested_band,
        'guardian_declared',
        false,
        true,
        now(),
        now(),
        now() + interval '30 days'
      )
      on conflict (user_id) do update
      set
        status = 'minor',
        minor_band = excluded.minor_band,
        assurance = 'guardian_declared',
        household_marked = true,
        minor_since = coalesce(account_age_status.minor_since, now()),
        recheck_after = excluded.recheck_after;

      perform private.apply_protective_age_effects(target_request.requester_user_id);
    end if;

    insert into public.family_members (
      family_id,
      user_id,
      name,
      relationship,
      household_role,
      permission_role,
      tone,
      memory_note
    )
    values (
      target_request.family_id,
      target_request.requester_user_id,
      coalesce(target_profile.display_name, target_request.requester_name),
      'Participante',
      private.role_for_band(requested_band),
      'member',
      'sky',
      ''
    )
    on conflict (family_id, user_id) where user_id is not null
    do update set
      permission_role = 'member',
      updated_at = now()
    returning id into approved_member_id;

    insert into private.minor_profiles (
      member_id,
      family_id,
      declared_band,
      nicknames
    )
    values (
      approved_member_id,
      target_request.family_id,
      requested_band,
      cleaned_nicknames
    )
    on conflict (member_id) do update
    set
      declared_band = excluded.declared_band,
      nicknames = excluded.nicknames,
      updated_at = now();

    update public.family_members as members
    set household_role = private.role_for_band(requested_band)
    where members.id = approved_member_id;

    perform private.start_guardianship(
      target_request.family_id,
      approved_member_id,
      current_user_id,
      requested_relationship
    );
    perform private.record_minor_consent(
      target_request.family_id,
      approved_member_id,
      current_user_id,
      'account'
    );
    if requested_health then
      perform private.record_minor_consent(
        target_request.family_id,
        approved_member_id,
        current_user_id,
        'health'
      );
    end if;

    insert into private.account_terms_acceptances (
      user_id,
      user_hash,
      terms_version,
      policy_version,
      accepted_by,
      guardian_user_hash
    )
    values (
      target_request.requester_user_id,
      private.user_hash(target_request.requester_user_id),
      policy.current_terms_version,
      policy.current_policy_version,
      'guardian',
      private.user_hash(current_user_id)
    );
  end if;

  update public.family_join_requests
  set
    status = 'approved',
    reviewed_by = current_user_id,
    reviewed_at = now()
  where id = target_request.id;

  update public.profiles
  set active_family_id = target_request.family_id
  where id = target_request.requester_user_id
    and active_family_id is null;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.approve_family_join_request(
  uuid, text, text, text, boolean, text, boolean, text[]
) from public, anon, authenticated, service_role;
grant execute on function public.approve_family_join_request(
  uuid, text, text, text, boolean, text, boolean, text[]
) to authenticated;

-- Acting for a minor never follows the policy row: any adult, confirmed, operator-set or self-declared, without active parental controls is trusted.
create or replace function private.is_trusted_adult(target_user_id uuid)
returns boolean
language sql
stable
set search_path = pg_catalog, private
as $$
  select coalesce(
    (
      select ages.status = 'adult'
        and not ages.parental_controls_active
        and ages.assurance in ('confirmed', 'operator', 'self_declared')
      from private.effective_age(target_user_id) as ages
    ),
    false
  );
$$;

revoke all on function private.is_trusted_adult(uuid)
  from public, anon, authenticated, service_role;

-- The majority screen shows once: an acceptance of their own after the guardianship ended answers it, whatever the Terms version.
create or replace function private.age_status_json(target_user_id uuid)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public, private
as $$
declare
  ages record;
  policy private.age_policy%rowtype;
  names jsonb;
  former_names jsonb;
  accepted_current boolean;
  reached_majority boolean;
begin
  select * into ages from private.effective_age(target_user_id);
  select * into policy from private.age_policy where singleton;

  select coalesce(jsonb_agg(distinct guardian.name), '[]'::jsonb)
  into names
  from public.family_members as wards
  cross join lateral jsonb_array_elements_text(private.guardian_names(wards.id)) as guardian(name)
  where wards.user_id = target_user_id;

  select coalesce(jsonb_agg(distinct former.guardian_name), '[]'::jsonb)
  into former_names
  from (
    select coalesce(
      nullif(trim(guardian_profiles.display_name), ''),
      nullif(trim(guardian_members.name), ''),
      'Responsável'
    ) as guardian_name
    from private.minor_guardianships as links
    join public.family_members as wards on wards.id = links.member_id
    left join public.family_members as guardian_members
      on guardian_members.family_id = wards.family_id
     and guardian_members.user_id = links.guardian_user_id
    left join public.profiles as guardian_profiles
      on guardian_profiles.id = links.guardian_user_id
    where wards.user_id = target_user_id
      and links.end_reason = 'reached_majority'
      and links.guardian_user_id is not null
  ) as former;

  select exists (
    select 1
    from private.account_terms_acceptances as acceptances
    where acceptances.user_id = target_user_id
      and acceptances.terms_version = policy.current_terms_version
  )
  into accepted_current;

  select ages.status = 'adult'
    and exists (
      select 1
      from private.minor_guardianships as links
      join public.family_members as wards on wards.id = links.member_id
      where wards.user_id = target_user_id
        and links.end_reason = 'reached_majority'
    )
    and not exists (
      select 1
      from private.account_terms_acceptances as acceptances
      where acceptances.user_id = target_user_id
        and acceptances.accepted_by = 'self'
        and acceptances.accepted_at >= coalesce(
          (
            select max(links.ended_at)
            from private.minor_guardianships as links
            join public.family_members as wards on wards.id = links.member_id
            where wards.user_id = target_user_id
              and links.end_reason = 'reached_majority'
          ),
          '-infinity'::timestamptz
        )
    )
  into reached_majority;

  return jsonb_build_object(
    'status', ages.status,
    'band', case when ages.status = 'minor' then ages.band end,
    'band_source', case when ages.status = 'minor' then ages.band_source end,
    'assurance', ages.assurance,
    'parental_controls_active', ages.parental_controls_active,
    'household_marked', ages.household_marked,
    'trusted_adult', private.is_trusted_adult(target_user_id),
    'may_use_ai', private.may_use_ai(target_user_id),
    'may_buy_premium', private.may_use_ai(target_user_id),
    'ai_blocked', private.ai_blocked(target_user_id),
    'recorded_at', case
      when not ages.has_record
        or (ages.household_marked and ages.assurance = 'guardian_declared') then null
      else ages.recorded_at
    end,
    'recheck_after', ages.recheck_after,
    'guardian_names', names,
    'needs_name', ages.status <> 'adult'
      and coalesce(
        (
          select profiles.display_name_source = 'auth'
          from public.profiles
          where profiles.id = target_user_id
        ),
        true
      ),
    'terms', jsonb_build_object(
      'current_terms_version', policy.current_terms_version,
      'current_policy_version', policy.current_policy_version,
      'current_minor_consent_version', policy.current_minor_consent_version,
      'accepted_current', accepted_current,
      'reached_majority', coalesce(reached_majority, false),
      'former_guardian_names', case
        when coalesce(reached_majority, false) then former_names
        else '[]'::jsonb
      end
    )
  );
end;
$$;

revoke all on function private.age_status_json(uuid)
  from public, anon, authenticated, service_role;

-- A failed turn hides the person's line and never deletes it: the hold's sealing and the preservation copy still read it.
create or replace function public.get_current_nina_state(target_family_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  target_thread_id uuid;
begin
  if current_user_id is null
     or not public.is_adult_family_member(target_family_id) then
    raise exception 'family_access_denied' using errcode = '42501';
  end if;

  select id
  into target_thread_id
  from public.nina_threads
  where family_id = target_family_id
    and owner_user_id = current_user_id
    and visibility = 'private';

  return jsonb_build_object(
    'thread', case
      when target_thread_id is null then null
      else jsonb_build_object(
        'id', target_thread_id,
        'family_id', target_family_id,
        'owner_user_id', current_user_id
      )
    end,
    'messages', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', messages.id,
            'sender', messages.sender,
            'text', messages.text,
            'suggestion', messages.suggestion,
            'attachments', messages.attachments,
            'created_at', messages.created_at,
            'proposals', coalesce(
              (
                select jsonb_agg(
                  jsonb_build_object(
                    'id', proposals.id,
                    'kind', proposals.kind,
                    'state', proposals.state,
                    'title', proposals.title,
                    'detail', proposals.detail,
                    'action_title', proposals.action_title,
                    'payload', proposals.payload,
                    'allowed_memory_visibilities', proposals.allowed_memory_visibilities,
                    'resolved_payload', proposals.resolved_payload
                  )
                  order by proposals.created_at
                )
                from public.nina_proposals as proposals
                where proposals.assistant_message_id = messages.id
              ),
              '[]'::jsonb
            )
          )
          order by messages.created_at
        )
        from public.chat_messages as messages
        where messages.thread_id = target_thread_id
          and not (
            messages.sender = 'user'
            and messages.text <> 'Mensagem não enviada.'
            and exists (
              select 1
              from public.nina_ai_runs as runs
              where runs.request_message_id = messages.id
                and runs.status = 'failed'
            )
          )
      ),
      '[]'::jsonb
    ),
    'memories', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', memories.id,
            'family_id', memories.family_id,
            'owner_user_id', memories.owner_user_id,
            'title', memories.title,
            'body', memories.body,
            'visibility', memories.visibility,
            'confidence', memories.confidence,
            'created_at', memories.created_at,
            'updated_at', memories.updated_at
          )
          order by memories.updated_at desc
        )
        from public.memory_items as memories
        where memories.family_id = target_family_id
          and memories.status = 'confirmed'
          and (
            memories.visibility = 'shared'
            or memories.owner_user_id = current_user_id
          )
      ),
      '[]'::jsonb
    )
  );
end;
$$;

revoke all on function public.get_current_nina_state(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_current_nina_state(uuid) to authenticated;

-- A person holds one pending request at a time and none while in a house; no membership is touched here.
update public.family_join_requests as requests
set status = 'cancelled'
where requests.status = 'pending'
  and (
    exists (
      select 1
      from public.family_members as members
      where members.user_id = requests.requester_user_id
    )
    or exists (
      select 1
      from public.family_join_requests as newer
      where newer.requester_user_id = requests.requester_user_id
        and newer.status = 'pending'
        and (newer.created_at, newer.id) > (requests.created_at, requests.id)
    )
  );

commit;
