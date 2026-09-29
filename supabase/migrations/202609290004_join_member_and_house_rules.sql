begin;

-- can_manage_family is the one choke point for house powers, and it never
-- answers about anyone but the caller, so it cannot become an age oracle.
create or replace function public.can_manage_family(
  target_family_id uuid,
  target_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth, private
as $$
  select target_user_id is not null
    and (auth.uid() is null or target_user_id = auth.uid())
    and exists (
      select 1
      from public.family_members as members
      where members.family_id = target_family_id
        and members.user_id = target_user_id
        and members.permission_role in ('owner', 'admin')
    )
    and private.is_adult(target_user_id);
$$;

revoke all on function public.can_manage_family(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.can_manage_family(uuid, uuid) to authenticated;

create or replace function private.require_adult_account(target_user_id uuid)
returns void
language plpgsql
stable
set search_path = pg_catalog, private
as $$
declare
  ages record;
begin
  select * into ages from private.effective_age(target_user_id);
  if not ages.has_record and ages.status <> 'minor' then
    raise exception 'age_signal_required' using errcode = 'P0001';
  end if;
  if ages.status <> 'adult' then
    raise exception 'adult_account_required' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.require_adult_account(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.lock_family_member(target_member_id uuid)
returns public.family_members
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  initial_family_id uuid;
  locked public.family_members%rowtype;
begin
  select members.family_id
  into initial_family_id
  from public.family_members as members
  where members.id = target_member_id;

  if not found then
    return null;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(initial_family_id::text, 0)
  );

  select *
  into locked
  from public.family_members as members
  where members.id = target_member_id
  for update;

  if not found or locked.family_id <> initial_family_id then
    return null;
  end if;

  return locked;
end;
$$;

revoke all on function private.lock_family_member(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.is_acting_guardian(
  target_member_id uuid,
  target_user_id uuid
)
returns boolean
language sql
stable
set search_path = pg_catalog, private
as $$
  select private.is_live_guardian(target_member_id, target_user_id)
    and private.is_trusted_adult(target_user_id);
$$;

revoke all on function private.is_acting_guardian(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function private.start_guardianship(
  target_family_id uuid,
  target_member_id uuid,
  guardian_id uuid,
  guardian_relationship text
)
returns void
language plpgsql
set search_path = pg_catalog, public, private
as $$
declare
  policy private.age_policy%rowtype;
  guardian_age record;
begin
  select * into policy from private.age_policy where singleton;
  select * into guardian_age from private.effective_age(guardian_id);

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
    target_family_id,
    target_member_id,
    guardian_id,
    private.user_hash(guardian_id),
    guardian_relationship,
    policy.current_minor_consent_version,
    guardian_age.assurance
  )
  on conflict (member_id, guardian_user_id) where ended_at is null
  do update set relationship = excluded.relationship;
end;
$$;

revoke all on function private.start_guardianship(uuid, uuid, uuid, text)
  from public, anon, authenticated, service_role;

create or replace function private.record_minor_consent(
  target_family_id uuid,
  target_member_id uuid,
  guardian_id uuid,
  consent_purpose text
)
returns void
language plpgsql
set search_path = pg_catalog, public, private
as $$
declare
  guardian_hash text := private.user_hash(guardian_id);
  policy private.age_policy%rowtype;
begin
  select * into policy from private.age_policy where singleton;

  if exists (
    select 1
    from private.minor_data_consents as consents
    where consents.member_id = target_member_id
      and consents.purpose = consent_purpose
      and consents.guardian_user_hash = guardian_hash
      and consents.text_version = policy.current_minor_consent_version
      and consents.withdrawn_at is null
  ) then
    return;
  end if;

  insert into private.minor_data_consents (
    family_id,
    member_id,
    guardian_user_hash,
    purpose,
    text_version
  )
  values (
    target_family_id,
    target_member_id,
    guardian_hash,
    consent_purpose,
    policy.current_minor_consent_version
  );
end;
$$;

revoke all on function private.record_minor_consent(uuid, uuid, uuid, text)
  from public, anon, authenticated, service_role;

create or replace function private.close_minor_member(
  target_member_id uuid,
  close_reason text,
  closed_by uuid
)
returns void
language plpgsql
set search_path = pg_catalog, public, private
as $$
begin
  update private.minor_guardianships as links
  set
    ended_at = now(),
    end_reason = close_reason
  where links.member_id = target_member_id
    and links.ended_at is null;

  update private.minor_data_consents as consents
  set
    withdrawn_at = now(),
    withdrawn_by_hash = case
      when closed_by is null then null
      else private.user_hash(closed_by)
    end
  where consents.member_id = target_member_id
    and consents.withdrawn_at is null;
end;
$$;

revoke all on function private.close_minor_member(uuid, text, uuid)
  from public, anon, authenticated, service_role;

-- However a child or teen row goes, a house deletion's cascade included, its
-- guardianships end and its consents are withdrawn, so no proof stays open
-- for a profile that no longer exists.
create or replace function public.close_minor_member_on_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if old.household_role in ('child', 'teen')
     or exists (
       select 1
       from private.minor_guardianships as links
       where links.member_id = old.id
         and links.ended_at is null
     ) then
    if not exists (select 1 from public.families where families.id = old.family_id) then
      update private.minor_guardianships as links
      set family_id = null
      where links.member_id = old.id;

      update private.minor_data_consents as consents
      set family_id = null
      where consents.member_id = old.id;
    end if;

    perform private.close_minor_member(old.id, 'member_removed', null);
  end if;
  return old;
end;
$$;

revoke all on function public.close_minor_member_on_delete()
  from public, anon, authenticated, service_role;

drop trigger if exists family_members_close_minor on public.family_members;
create trigger family_members_close_minor
  before delete on public.family_members
  for each row execute function public.close_minor_member_on_delete();

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
    'Criador',
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

  update public.profiles
  set active_family_id = target_family.id
  where id = current_user_id;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.create_family(text, text)
  from public, anon, authenticated, service_role;

create or replace function public.create_family(family_name text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  invite_token text := public.generate_family_invite_code();
  context jsonb;
  target_family_id uuid;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  perform private.require_adult_account(current_user_id);

  context := public.create_family(family_name, invite_token);
  target_family_id := (context #>> '{family,id}')::uuid;

  insert into public.invites (
    token,
    family_id,
    expires_at,
    max_uses,
    created_by
  )
  values (
    invite_token,
    target_family_id,
    now() + interval '7 days',
    7,
    current_user_id
  );

  return context;
end;
$$;

revoke all on function public.create_family(text)
  from public, anon, authenticated, service_role;
grant execute on function public.create_family(text) to authenticated;

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

  if (
    select count(*)
    from public.family_members
    where family_id = target_family.id
      and household_role <> 'assistant'
  ) >= 8 then
    raise exception 'family_member_limit_reached' using errcode = '23514';
  end if;

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

drop function if exists public.approve_family_join_request(uuid, text);

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

  select requests.family_id
  into initial_family_id
  from public.family_join_requests as requests
  where requests.id = target_request_id;

  if not found then
    raise exception 'join_request_not_pending' using errcode = 'P0002';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(initial_family_id::text, 0)
  );

  select *
  into target_request
  from public.family_join_requests as requests
  where requests.id = target_request_id
  for update;

  if not found
     or target_request.family_id <> initial_family_id
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

drop function if exists public.add_unclaimed_family_member(
  uuid, text, text, text, text, text, date, text, text
);

-- Children and teens are created only through add_minor_profile, with a
-- declared guardian and a recorded consent; this path is for adults and pets.
create or replace function public.add_unclaimed_family_member(
  target_family_id uuid,
  member_name text,
  relationship text default '',
  household_role text default 'adult',
  tone text default 'mint',
  memory_note text default '',
  birth_date date default null,
  pet_species text default '',
  pet_breed text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
begin
  if not public.can_manage_family(target_family_id) then
    raise exception 'family_management_denied' using errcode = '42501';
  end if;

  if nullif(trim(member_name), '') is null then
    raise exception 'member_name_required' using errcode = '22023';
  end if;

  if coalesce(add_unclaimed_family_member.household_role, '') not in ('adult', 'pet') then
    raise exception 'invalid_household_role' using errcode = '22023';
  end if;

  insert into public.family_members (
    family_id,
    user_id,
    name,
    relationship,
    household_role,
    permission_role,
    tone,
    memory_note,
    birth_date,
    pet_species,
    pet_breed
  )
  values (
    target_family_id,
    null,
    trim(member_name),
    trim(add_unclaimed_family_member.relationship),
    add_unclaimed_family_member.household_role,
    'member',
    add_unclaimed_family_member.tone,
    trim(add_unclaimed_family_member.memory_note),
    add_unclaimed_family_member.birth_date,
    case
      when add_unclaimed_family_member.household_role = 'pet'
        then trim(add_unclaimed_family_member.pet_species)
      else ''
    end,
    case
      when add_unclaimed_family_member.household_role = 'pet'
        then trim(add_unclaimed_family_member.pet_breed)
      else ''
    end
  );

  return public.get_current_home_context();
end;
$$;

revoke all on function public.add_unclaimed_family_member(
  uuid, text, text, text, text, text, date, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.add_unclaimed_family_member(
  uuid, text, text, text, text, text, date, text, text
) to authenticated;

create or replace function public.update_family_member(
  target_member_id uuid,
  member_name text,
  relationship text,
  household_role text,
  permission_role text,
  tone text,
  memory_note text,
  birth_date date default null,
  pet_species text default '',
  pet_breed text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  manager_permission text;
  caller_manages boolean;
  caller_guards boolean;
  target_member public.family_members%rowtype;
  target_is_minor boolean;
  requested_permission text := update_family_member.permission_role;
  requested_role text := update_family_member.household_role;
  requested_birth_date date := update_family_member.birth_date;
  next_role text;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  target_member := private.lock_family_member(target_member_id);
  if target_member.id is null then
    raise exception 'family_member_not_found' using errcode = 'P0002';
  end if;

  select memberships.permission_role
  into manager_permission
  from public.family_members as memberships
  where memberships.family_id = target_member.family_id
    and memberships.user_id = current_user_id;

  caller_manages := public.can_manage_family(target_member.family_id);
  target_is_minor := target_member.household_role in ('child', 'teen');
  caller_guards := target_is_minor
    and private.is_acting_guardian(target_member.id, current_user_id);

  if not caller_manages
     and not caller_guards
     and not (
       target_member.user_id is not distinct from current_user_id
       and private.is_adult(current_user_id)
     ) then
    raise exception 'family_member_update_denied' using errcode = '42501';
  end if;

  if caller_manages
     and manager_permission = 'admin'
     and target_member.user_id is distinct from current_user_id
     and target_member.permission_role in ('owner', 'admin') then
    raise exception 'family_member_update_denied' using errcode = '42501';
  end if;

  if target_member.household_role = 'assistant' or requested_role = 'assistant' then
    raise exception 'invalid_household_role' using errcode = '22023';
  end if;

  if target_member.user_id is not null then
    next_role := target_member.household_role;
  elsif target_is_minor then
    if requested_role is distinct from target_member.household_role then
      raise exception 'invalid_household_role' using errcode = '22023';
    end if;
    next_role := target_member.household_role;
  else
    if coalesce(requested_role, '') not in ('adult', 'pet') then
      raise exception 'invalid_household_role' using errcode = '22023';
    end if;
    next_role := requested_role;
  end if;

  if coalesce(requested_permission, '') not in ('owner', 'admin', 'member') then
    raise exception 'invalid_permission_role' using errcode = '22023';
  end if;

  if next_role in ('child', 'teen') and requested_permission <> 'member' then
    raise exception 'minor_role_restricted' using errcode = '42501';
  end if;

  if requested_permission is distinct from target_member.permission_role then
    if manager_permission is distinct from 'owner'
       or not caller_manages
       or target_member.permission_role = 'owner'
       or requested_permission = 'owner' then
      raise exception 'permission_role_denied' using errcode = '42501';
    end if;
  end if;

  if next_role in ('child', 'teen') and requested_birth_date is not null then
    raise exception 'minor_birth_date_not_allowed' using errcode = '22023';
  end if;

  update public.family_members as members
  set
    name = case
      when members.user_id is null then coalesce(nullif(trim(member_name), ''), members.name)
      else members.name
    end,
    relationship = trim(update_family_member.relationship),
    household_role = next_role,
    permission_role = requested_permission,
    tone = update_family_member.tone,
    memory_note = trim(update_family_member.memory_note),
    birth_date = requested_birth_date,
    pet_species = case
      when next_role = 'pet' then trim(update_family_member.pet_species)
      else ''
    end,
    pet_breed = case
      when next_role = 'pet' then trim(update_family_member.pet_breed)
      else ''
    end
  where members.id = target_member_id;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.update_family_member(
  uuid, text, text, text, text, text, text, date, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.update_family_member(
  uuid, text, text, text, text, text, text, date, text, text
) to authenticated;

create or replace function public.remove_family_member(target_member_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  manager_permission text;
  caller_manages boolean;
  caller_guards boolean;
  target_member public.family_members%rowtype;
  target_family_name text;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  target_member := private.lock_family_member(target_member_id);
  if target_member.id is null then
    raise exception 'family_member_not_found' using errcode = 'P0002';
  end if;

  select members.permission_role
  into manager_permission
  from public.family_members as members
  where members.family_id = target_member.family_id
    and members.user_id = current_user_id;

  caller_manages := public.can_manage_family(target_member.family_id);
  caller_guards := target_member.household_role in ('child', 'teen')
    and private.is_acting_guardian(target_member.id, current_user_id);

  if target_member.household_role = 'assistant'
     or target_member.permission_role = 'owner'
     or target_member.user_id is not distinct from current_user_id
     or (
       not caller_guards
       and (
         not caller_manages
         or (manager_permission = 'admin' and target_member.permission_role = 'admin')
       )
     ) then
    raise exception 'family_member_remove_denied' using errcode = '42501';
  end if;

  select families.name
  into target_family_name
  from public.families as families
  where families.id = target_member.family_id;

  if target_member.household_role in ('child', 'teen') then
    perform private.close_minor_member(target_member.id, 'member_removed', current_user_id);
  end if;

  -- A guardianship never outlives the guardian's place in the ward's house.
  if target_member.user_id is not null then
    update private.minor_guardianships as links
    set
      ended_at = now(),
      end_reason = 'guardian_left'
    where links.guardian_user_id = target_member.user_id
      and links.ended_at is null
      and links.member_id in (
        select wards.id
        from public.family_members as wards
        where wards.family_id = target_member.family_id
      );

    update private.minor_data_consents as consents
    set
      withdrawn_at = now(),
      withdrawn_by_hash = private.user_hash(current_user_id)
    where consents.guardian_user_hash = private.user_hash(target_member.user_id)
      and consents.withdrawn_at is null
      and consents.member_id in (
        select wards.id
        from public.family_members as wards
        where wards.family_id = target_member.family_id
      );
  end if;

  delete from public.family_members
  where id = target_member.id;

  if target_member.user_id is not null then
    update public.profiles
    set active_family_id = null
    where id = target_member.user_id
      and active_family_id = target_member.family_id;

    insert into public.family_access_decisions (
      family_id,
      family_name,
      subject_user_id,
      outcome
    )
    values (
      target_member.family_id,
      target_family_name,
      target_member.user_id,
      'removed'
    );
  end if;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.remove_family_member(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.remove_family_member(uuid) to authenticated;

create or replace function public.add_minor_profile(
  target_family_id uuid,
  member_name text,
  minor_band text,
  guardian_relationship text,
  consent_version text,
  health_consent boolean default false,
  nicknames text[] default '{}',
  relationship text default '',
  tone text default 'mint'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  requested_band text := add_minor_profile.minor_band;
  requested_relationship text := add_minor_profile.guardian_relationship;
  requested_name text := nullif(trim(add_minor_profile.member_name), '');
  cleaned_nicknames text[];
  policy private.age_policy%rowtype;
  created_member_id uuid;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if not private.is_trusted_adult(current_user_id) then
    raise exception 'age_confirmation_required' using errcode = '42501';
  end if;

  if not public.is_adult_family_member(target_family_id) then
    raise exception 'family_not_found' using errcode = 'P0002';
  end if;

  if coalesce(requested_relationship, '') not in ('mae', 'pai', 'responsavel_legal') then
    raise exception 'guardian_declaration_required' using errcode = '22023';
  end if;

  select * into policy from private.age_policy where singleton;
  if add_minor_profile.consent_version is distinct from policy.current_minor_consent_version then
    raise exception 'minor_consent_outdated' using errcode = '22023';
  end if;

  if private.band_rank(requested_band) is null then
    raise exception 'invalid_minor_band' using errcode = '22023';
  end if;

  cleaned_nicknames := private.normalized_nicknames(add_minor_profile.nicknames);

  if requested_name is null then
    raise exception 'member_name_required' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target_family_id::text, 0)
  );

  insert into public.family_members (
    family_id,
    user_id,
    name,
    relationship,
    household_role,
    permission_role,
    tone,
    memory_note,
    birth_date
  )
  values (
    target_family_id,
    null,
    requested_name,
    trim(coalesce(add_minor_profile.relationship, '')),
    private.role_for_band(requested_band),
    'member',
    coalesce(add_minor_profile.tone, 'mint'),
    '',
    null
  )
  returning id into created_member_id;

  insert into private.minor_profiles (
    member_id,
    family_id,
    declared_band,
    nicknames
  )
  values (
    created_member_id,
    target_family_id,
    requested_band,
    cleaned_nicknames
  );

  perform private.start_guardianship(
    target_family_id,
    created_member_id,
    current_user_id,
    requested_relationship
  );
  perform private.record_minor_consent(
    target_family_id,
    created_member_id,
    current_user_id,
    'profile'
  );
  if coalesce(add_minor_profile.health_consent, false) then
    perform private.record_minor_consent(
      target_family_id,
      created_member_id,
      current_user_id,
      'health'
    );
  end if;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.add_minor_profile(
  uuid, text, text, text, text, boolean, text[], text, text
) from public, anon, authenticated, service_role;
grant execute on function public.add_minor_profile(
  uuid, text, text, text, text, boolean, text[], text, text
) to authenticated;

create or replace function public.declare_minor_guardianship(
  target_member_id uuid,
  guardian_relationship text,
  consent_version text,
  minor_band text default null,
  health_consent boolean default false,
  nicknames text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  requested_band text := declare_minor_guardianship.minor_band;
  requested_relationship text := declare_minor_guardianship.guardian_relationship;
  target_member public.family_members%rowtype;
  existing_profile private.minor_profiles%rowtype;
  policy private.age_policy%rowtype;
  cleaned_nicknames text[];
  next_band text;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if not private.is_trusted_adult(current_user_id) then
    raise exception 'age_confirmation_required' using errcode = '42501';
  end if;

  target_member := private.lock_family_member(target_member_id);
  if target_member.id is null
     or not public.is_adult_family_member(target_member.family_id) then
    raise exception 'family_member_not_found' using errcode = 'P0002';
  end if;

  if target_member.household_role not in ('child', 'teen') then
    raise exception 'not_a_minor_member' using errcode = '22023';
  end if;

  if coalesce(requested_relationship, '') not in ('mae', 'pai', 'responsavel_legal') then
    raise exception 'guardian_declaration_required' using errcode = '22023';
  end if;

  select * into policy from private.age_policy where singleton;
  if declare_minor_guardianship.consent_version is distinct from policy.current_minor_consent_version then
    raise exception 'minor_consent_outdated' using errcode = '22023';
  end if;

  if requested_band is not null and private.band_rank(requested_band) is null then
    raise exception 'invalid_minor_band' using errcode = '22023';
  end if;

  if declare_minor_guardianship.nicknames is not null then
    cleaned_nicknames := private.normalized_nicknames(declare_minor_guardianship.nicknames);
  end if;

  select *
  into existing_profile
  from private.minor_profiles as profiles
  where profiles.member_id = target_member.id
  for update;

  if existing_profile.member_id is null then
    if requested_band is null then
      raise exception 'invalid_minor_band' using errcode = '22023';
    end if;
    next_band := requested_band;

    insert into private.minor_profiles (
      member_id,
      family_id,
      declared_band,
      nicknames
    )
    values (
      target_member.id,
      target_member.family_id,
      next_band,
      coalesce(cleaned_nicknames, '{}')
    );
  else
    if requested_band is not null
       and private.band_rank(requested_band) > private.band_rank(existing_profile.declared_band) then
      raise exception 'invalid_minor_band' using errcode = '22023';
    end if;
    next_band := coalesce(requested_band, existing_profile.declared_band);

    update private.minor_profiles as profiles
    set
      declared_band = next_band,
      nicknames = coalesce(cleaned_nicknames, profiles.nicknames),
      updated_at = now()
    where profiles.member_id = target_member.id;
  end if;

  update public.family_members as members
  set
    household_role = case
      when members.user_id is null then private.role_for_band(next_band)
      else members.household_role
    end,
    updated_at = now()
  where members.id = target_member.id;

  perform private.start_guardianship(
    target_member.family_id,
    target_member.id,
    current_user_id,
    requested_relationship
  );
  perform private.record_minor_consent(
    target_member.family_id,
    target_member.id,
    current_user_id,
    case when target_member.user_id is null then 'profile' else 'account' end
  );
  if coalesce(declare_minor_guardianship.health_consent, false) then
    perform private.record_minor_consent(
      target_member.family_id,
      target_member.id,
      current_user_id,
      'health'
    );
  end if;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.declare_minor_guardianship(
  uuid, text, text, text, boolean, text[]
) from public, anon, authenticated, service_role;
grant execute on function public.declare_minor_guardianship(
  uuid, text, text, text, boolean, text[]
) to authenticated;

create or replace function public.set_minor_health_consent(
  target_member_id uuid,
  granted boolean,
  consent_version text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  target_member public.family_members%rowtype;
  policy private.age_policy%rowtype;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  target_member := private.lock_family_member(target_member_id);
  if target_member.id is null
     or granted is null
     or not private.is_acting_guardian(target_member.id, current_user_id) then
    raise exception 'guardian_access_denied' using errcode = '42501';
  end if;

  if granted then
    select * into policy from private.age_policy where singleton;
    if set_minor_health_consent.consent_version is distinct from policy.current_minor_consent_version then
      raise exception 'minor_consent_outdated' using errcode = '22023';
    end if;

    perform private.record_minor_consent(
      target_member.family_id,
      target_member.id,
      current_user_id,
      'health'
    );
  else
    update private.minor_data_consents as consents
    set
      withdrawn_at = now(),
      withdrawn_by_hash = private.user_hash(current_user_id)
    where consents.member_id = target_member.id
      and consents.purpose = 'health'
      and consents.withdrawn_at is null;

    -- Without a live health consent a minor's health reminders are not kept:
    -- their titles alone reveal health, so they are deleted, not moved.
    if not private.has_live_minor_consent(target_member.id, 'health') then
      delete from public.tasks
      where tasks.family_id = target_member.family_id
        and tasks.owner_member_id = target_member.id
        and tasks.category_id = 'health';
    end if;
  end if;

  update public.family_members as members
  set updated_at = now()
  where members.id = target_member.id;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.set_minor_health_consent(uuid, boolean, text)
  from public, anon, authenticated, service_role;
grant execute on function public.set_minor_health_consent(uuid, boolean, text)
  to authenticated;

create or replace function public.set_minor_supervision(
  target_member_id uuid,
  supervision jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  target_member public.family_members%rowtype;
  setting record;
  next_alerts boolean;
  next_quiet_start integer;
  next_quiet_end integer;
  next_limit integer;
  limit_given boolean := false;
  next_nicknames text[];
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  target_member := private.lock_family_member(target_member_id);
  if target_member.id is null
     or not private.is_acting_guardian(target_member.id, current_user_id)
     or not exists (
       select 1 from private.minor_profiles as profiles
       where profiles.member_id = target_member.id
     ) then
    raise exception 'guardian_access_denied' using errcode = '42501';
  end if;

  if supervision is null or jsonb_typeof(supervision) <> 'object' then
    raise exception 'invalid_supervision_settings' using errcode = '22023';
  end if;

  for setting in select key, value from jsonb_each(supervision) loop
    case setting.key
      when 'alerts_enabled' then
        if jsonb_typeof(setting.value) <> 'boolean' then
          raise exception 'invalid_supervision_settings' using errcode = '22023';
        end if;
        next_alerts := (setting.value #>> '{}')::boolean;
      when 'quiet_start', 'quiet_end' then
        if jsonb_typeof(setting.value) <> 'number'
           or (setting.value #>> '{}') !~ '^[0-9]{1,4}$'
           or (setting.value #>> '{}')::integer > 1439 then
          raise exception 'invalid_supervision_settings' using errcode = '22023';
        end if;
        if setting.key = 'quiet_start' then
          next_quiet_start := (setting.value #>> '{}')::integer;
        else
          next_quiet_end := (setting.value #>> '{}')::integer;
        end if;
      when 'daily_limit_minutes' then
        if jsonb_typeof(setting.value) = 'null' then
          next_limit := null;
        elsif jsonb_typeof(setting.value) = 'number'
          and (setting.value #>> '{}') in ('15', '30', '60') then
          next_limit := (setting.value #>> '{}')::integer;
        else
          raise exception 'invalid_supervision_settings' using errcode = '22023';
        end if;
        limit_given := true;
      when 'nicknames' then
        if jsonb_typeof(setting.value) <> 'array'
           or exists (
             select 1
             from jsonb_array_elements(setting.value) as entry(value)
             where jsonb_typeof(entry.value) <> 'string'
           ) then
          raise exception 'invalid_nicknames' using errcode = '22023';
        end if;
        next_nicknames := private.normalized_nicknames(
          array(select jsonb_array_elements_text(setting.value))
        );
      else
        raise exception 'invalid_supervision_settings' using errcode = '22023';
    end case;
  end loop;

  update private.minor_profiles as profiles
  set
    alerts_enabled = coalesce(next_alerts, profiles.alerts_enabled),
    quiet_start = coalesce(next_quiet_start, profiles.quiet_start),
    quiet_end = coalesce(next_quiet_end, profiles.quiet_end),
    daily_limit_minutes = case
      when limit_given then next_limit
      else profiles.daily_limit_minutes
    end,
    nicknames = coalesce(next_nicknames, profiles.nicknames),
    updated_at = now()
  where profiles.member_id = target_member.id;

  update public.family_members as members
  set updated_at = now()
  where members.id = target_member.id;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.set_minor_supervision(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.set_minor_supervision(uuid, jsonb) to authenticated;

create or replace function public.change_minor_band(
  target_member_id uuid,
  minor_band text,
  consent_version text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  requested_band text := change_minor_band.minor_band;
  target_member public.family_members%rowtype;
  existing_profile private.minor_profiles%rowtype;
  policy private.age_policy%rowtype;
  apple_record private.account_age_status%rowtype;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  target_member := private.lock_family_member(target_member_id);
  if target_member.id is null
     or not private.is_acting_guardian(target_member.id, current_user_id) then
    raise exception 'guardian_access_denied' using errcode = '42501';
  end if;

  select *
  into existing_profile
  from private.minor_profiles as profiles
  where profiles.member_id = target_member.id
  for update;

  if existing_profile.member_id is null or private.band_rank(requested_band) is null then
    raise exception 'invalid_minor_band' using errcode = '22023';
  end if;

  if private.band_rank(requested_band) > private.band_rank(existing_profile.declared_band) then
    select * into policy from private.age_policy where singleton;
    if change_minor_band.consent_version is distinct from policy.current_minor_consent_version then
      raise exception 'invalid_minor_band' using errcode = '22023';
    end if;

    if target_member.user_id is not null then
      select *
      into apple_record
      from private.account_age_status as ages
      where ages.user_id = target_member.user_id;

      -- A guardian may correct a claimed minor's band upward only as far as
      -- the band Apple itself reported, never past it.
      if apple_record.status is distinct from 'minor'
         or apple_record.household_marked
         or private.band_rank(requested_band) > private.band_rank(apple_record.minor_band) then
        raise exception 'invalid_minor_band' using errcode = '22023';
      end if;
    end if;
  end if;

  update private.minor_profiles as profiles
  set
    declared_band = requested_band,
    updated_at = now()
  where profiles.member_id = target_member.id;

  update public.family_members as members
  set
    household_role = case
      when members.user_id is null then private.role_for_band(requested_band)
      else members.household_role
    end,
    updated_at = now()
  where members.id = target_member.id;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.change_minor_band(uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.change_minor_band(uuid, text, text) to authenticated;

create or replace function public.end_minor_guardianship(target_member_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  caller_hash text;
  target_member public.family_members%rowtype;
  target_family_name text;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  target_member := private.lock_family_member(target_member_id);
  if target_member.id is null
     or not private.is_live_guardian(target_member.id, current_user_id) then
    raise exception 'guardian_access_denied' using errcode = '42501';
  end if;

  caller_hash := private.user_hash(current_user_id);

  update private.minor_guardianships as links
  set
    ended_at = now(),
    end_reason = 'guardian_withdrew'
  where links.member_id = target_member.id
    and links.guardian_user_id = current_user_id
    and links.ended_at is null;

  update private.minor_data_consents as consents
  set
    withdrawn_at = now(),
    withdrawn_by_hash = caller_hash
  where consents.member_id = target_member.id
    and consents.guardian_user_hash = caller_hash
    and consents.withdrawn_at is null;

  if not exists (
    select 1
    from private.minor_guardianships as links
    where links.member_id = target_member.id
      and links.ended_at is null
  ) then
    perform private.close_minor_member(target_member.id, 'guardian_withdrew', current_user_id);

    select families.name
    into target_family_name
    from public.families as families
    where families.id = target_member.family_id;

    delete from public.family_members
    where id = target_member.id;

    if target_member.user_id is not null then
      update public.profiles
      set active_family_id = null
      where id = target_member.user_id
        and active_family_id = target_member.family_id;

      insert into public.family_access_decisions (
        family_id,
        family_name,
        subject_user_id,
        outcome
      )
      values (
        target_member.family_id,
        target_family_name,
        target_member.user_id,
        'removed'
      );
    end if;
  else
    update public.family_members as members
    set updated_at = now()
    where members.id = target_member.id;
  end if;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.end_minor_guardianship(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.end_minor_guardianship(uuid) to authenticated;

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
  target_family_name text;
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

  for target_membership in
    select family_members.family_id
    from public.family_members
    where family_members.user_id = target_user_id
    order by family_members.family_id
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(target_membership.family_id::text, 0)
    );

    select families.created_by, families.name
    into family_created_by, target_family_name
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
        insert into public.family_access_decisions (
          family_id,
          family_name,
          subject_user_id,
          outcome
        )
        select
          members.family_id,
          target_family_name,
          members.user_id,
          'removed'
        from public.family_members as members
        where members.family_id = target_membership.family_id
          and members.user_id is not null
          and members.user_id <> target_user_id;

        delete from public.families
        where families.id = target_membership.family_id;
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
      delete from public.families
      where families.id = orphan_family.id;
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

commit;
