begin;

create or replace function public.request_family_join(invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  normalized_code text := lower(trim(invite_code));
  target_invite public.invites%rowtype;
  initial_family_id uuid;
  target_family public.families%rowtype;
  current_user_id uuid := auth.uid();
  current_profile public.profiles%rowtype;
  target_request public.family_join_requests%rowtype;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  -- Read only enough state to select the family-scoped serialization lock.
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

  -- Every join/approval path takes the family advisory lock before row locks.
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

  insert into public.family_join_requests (
    family_id,
    invite_token,
    requester_user_id,
    requester_name
  )
  values (
    target_family.id,
    target_invite.token,
    current_user_id,
    current_profile.display_name
  )
  on conflict (family_id, requester_user_id) where status = 'pending'
  do update set
    invite_token = excluded.invite_token,
    requester_name = excluded.requester_name,
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

create or replace function public.approve_family_join_request(
  target_request_id uuid,
  granted_permission_role text default 'member'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  initial_family_id uuid;
  manager_permission text;
  target_request public.family_join_requests%rowtype;
  target_profile public.profiles%rowtype;
  target_invite public.invites%rowtype;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  -- Read only enough state to select the same family lock as request_family_join.
  select family_id
  into initial_family_id
  from public.family_join_requests
  where id = target_request_id;

  if not found then
    raise exception 'join_request_not_pending' using errcode = 'P0002';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(initial_family_id::text, 0)
  );

  select *
  into target_request
  from public.family_join_requests
  where id = target_request_id
  for update;

  if not found
     or target_request.family_id <> initial_family_id
     or target_request.status <> 'pending' then
    raise exception 'join_request_not_pending' using errcode = 'P0002';
  end if;

  select permission_role
  into manager_permission
  from public.family_members
  where family_id = target_request.family_id
    and user_id = current_user_id;

  if coalesce(manager_permission, '') not in ('owner', 'admin') then
    raise exception 'family_management_denied' using errcode = '42501';
  end if;

  if coalesce(granted_permission_role, '') not in ('admin', 'member')
     or (granted_permission_role = 'admin' and manager_permission <> 'owner') then
    raise exception 'permission_role_denied' using errcode = '42501';
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
    granted_permission_role,
    'sky',
    'Participante desta casa.'
  )
  on conflict (family_id, user_id) where user_id is not null
  do update set
    permission_role = excluded.permission_role,
    updated_at = now();

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

drop function if exists public.update_family_member(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  date,
  text,
  text
);
create function public.update_family_member(
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
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  initial_family_id uuid;
  manager_permission text;
  target_member public.family_members%rowtype;
  requested_permission text := update_family_member.permission_role;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select family_id
  into initial_family_id
  from public.family_members
  where id = target_member_id;

  if not found then
    raise exception 'family_member_not_found' using errcode = 'P0002';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(initial_family_id::text, 0)
  );

  select *
  into target_member
  from public.family_members
  where id = target_member_id
  for update;

  if not found or target_member.family_id <> initial_family_id then
    raise exception 'family_member_not_found' using errcode = 'P0002';
  end if;

  select memberships.permission_role
  into manager_permission
  from public.family_members as memberships
  where memberships.family_id = target_member.family_id
    and memberships.user_id = current_user_id;

  if coalesce(manager_permission, '') not in ('owner', 'admin')
     and target_member.user_id is distinct from current_user_id then
    raise exception 'family_member_update_denied' using errcode = '42501';
  end if;

  if manager_permission = 'admin'
     and target_member.user_id is distinct from current_user_id
     and target_member.permission_role in ('owner', 'admin') then
    raise exception 'family_member_update_denied' using errcode = '42501';
  end if;

  if target_member.household_role = 'assistant'
     or household_role = 'assistant'
     or coalesce(household_role, '') not in ('adult', 'child', 'pet') then
    raise exception 'invalid_household_role' using errcode = '22023';
  end if;

  if target_member.user_id is not null and household_role <> 'adult' then
    raise exception 'claimed_member_must_be_adult' using errcode = '22023';
  end if;

  if coalesce(requested_permission, '') not in ('owner', 'admin', 'member') then
    raise exception 'invalid_permission_role' using errcode = '22023';
  end if;

  if requested_permission is distinct from target_member.permission_role then
    if manager_permission <> 'owner'
       or target_member.permission_role = 'owner'
       or requested_permission = 'owner' then
      raise exception 'permission_role_denied' using errcode = '42501';
    end if;
  end if;

  update public.family_members
  set
    name = case
      when user_id is null then coalesce(nullif(trim(member_name), ''), name)
      else name
    end,
    relationship = trim(update_family_member.relationship),
    household_role = case
      when user_id is null then update_family_member.household_role
      else 'adult'
    end,
    permission_role = requested_permission,
    tone = update_family_member.tone,
    memory_note = trim(update_family_member.memory_note),
    birth_date = update_family_member.birth_date,
    pet_species = case
      when update_family_member.household_role = 'pet' then trim(update_family_member.pet_species)
      else ''
    end,
    pet_breed = case
      when update_family_member.household_role = 'pet' then trim(update_family_member.pet_breed)
      else ''
    end
  where id = target_member_id;

  return public.get_current_home_context();
end;
$$;

create or replace function public.remove_family_member(target_member_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  initial_family_id uuid;
  manager_permission text;
  target_member public.family_members%rowtype;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select family_id
  into initial_family_id
  from public.family_members
  where id = target_member_id;

  if not found then
    raise exception 'family_member_not_found' using errcode = 'P0002';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(initial_family_id::text, 0)
  );

  select *
  into target_member
  from public.family_members
  where id = target_member_id
  for update;

  if not found or target_member.family_id <> initial_family_id then
    raise exception 'family_member_not_found' using errcode = 'P0002';
  end if;

  select permission_role
  into manager_permission
  from public.family_members
  where family_id = target_member.family_id
    and user_id = current_user_id;

  if coalesce(manager_permission, '') not in ('owner', 'admin')
     or target_member.household_role = 'assistant'
     or target_member.permission_role = 'owner'
     or target_member.user_id = current_user_id
     or (manager_permission = 'admin' and target_member.permission_role = 'admin') then
    raise exception 'family_member_remove_denied' using errcode = '42501';
  end if;

  delete from public.family_members
  where id = target_member.id;

  if target_member.user_id is not null then
    update public.profiles
    set active_family_id = null
    where id = target_member.user_id
      and active_family_id = target_member.family_id;
  end if;

  return public.get_current_home_context();
end;
$$;

comment on function public.request_family_join(text) is
  'Creates a pending family join request after taking the family advisory lock before row locks.';
comment on function public.approve_family_join_request(uuid, text) is
  'Approves a join request using the same family-first lock order as request creation.';

revoke all on function public.request_family_join(text) from public;
revoke all on function public.approve_family_join_request(uuid, text) from public;
revoke all on function public.update_family_member(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  date,
  text,
  text
) from public;
revoke all on function public.remove_family_member(uuid) from public;
grant execute on function public.request_family_join(text) to authenticated;
grant execute on function public.approve_family_join_request(uuid, text) to authenticated;
grant execute on function public.update_family_member(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  date,
  text,
  text
) to authenticated;
grant execute on function public.remove_family_member(uuid) to authenticated;

commit;
