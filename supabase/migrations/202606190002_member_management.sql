begin;

alter table public.family_members
  add column if not exists birth_date date,
  add column if not exists pet_species text not null default '',
  add column if not exists pet_breed text not null default '';

create or replace function public.enforce_family_people_limit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_people_count integer;
begin
  if new.household_role = 'assistant' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.family_id = new.family_id
     and old.household_role <> 'assistant' then
    return new;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.family_id::text, 0)
  );

  if tg_op = 'UPDATE' then
    select count(*)::integer
    into current_people_count
    from public.family_members
    where family_id = new.family_id
      and household_role <> 'assistant'
      and id <> old.id;
  else
    select count(*)::integer
    into current_people_count
    from public.family_members
    where family_id = new.family_id
      and household_role <> 'assistant';
  end if;

  if current_people_count >= 8 then
    raise exception 'family_member_limit_reached' using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists family_members_enforce_limit on public.family_members;
drop function if exists public.enforce_family_member_limit();
drop trigger if exists family_members_enforce_people_limit on public.family_members;
create trigger family_members_enforce_people_limit
  before insert or update of family_id, household_role on public.family_members
  for each row execute function public.enforce_family_people_limit();

revoke all on function public.enforce_family_people_limit() from public, anon, authenticated;

alter table public.family_members replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table public.family_members;
  exception
    when duplicate_object then null;
  end;
end;
$$;

create table public.family_join_requests (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  invite_token text references public.invites(token) on delete set null,
  requester_user_id uuid not null references auth.users(id) on delete cascade,
  requester_name text not null check (length(trim(requester_name)) > 0),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'declined', 'cancelled')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index family_join_requests_one_pending_per_family_user
  on public.family_join_requests(family_id, requester_user_id)
  where status = 'pending';

create index family_join_requests_family_status_created_idx
  on public.family_join_requests(family_id, status, created_at);

create index family_join_requests_requester_status_created_idx
  on public.family_join_requests(requester_user_id, status, created_at desc);

create trigger family_join_requests_set_updated_at
  before update on public.family_join_requests
  for each row execute function public.set_updated_at();

alter table public.family_join_requests enable row level security;
revoke all on table public.family_join_requests from public, anon, authenticated;

comment on table public.family_join_requests is
  'Server-managed requests to join a family. Clients access requests only through RPCs.';

create or replace function public.get_current_home_context()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  current_profile public.profiles%rowtype;
  target_family public.families%rowtype;
  target_permission text;
  target_snapshot jsonb;
  active_invite jsonb;
  pending_requests jsonb := '[]'::jsonb;
  remaining_member_slots integer := 0;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  current_profile := public.ensure_current_profile(null);

  if current_profile.active_family_id is not null then
    select families.*
    into target_family
    from public.families as families
    join public.family_members as membership
      on membership.family_id = families.id
     and membership.user_id = current_user_id
    where families.id = current_profile.active_family_id;

    if found then
      select membership.permission_role
      into target_permission
      from public.family_members as membership
      where membership.family_id = target_family.id
        and membership.user_id = current_user_id;
    end if;
  end if;

  if target_family.id is null then
    select families.*
    into target_family
    from public.family_members as membership
    join public.families as families on families.id = membership.family_id
    where membership.user_id = current_user_id
    order by membership.created_at
    limit 1;

    if target_family.id is not null then
      select membership.permission_role
      into target_permission
      from public.family_members as membership
      where membership.family_id = target_family.id
        and membership.user_id = current_user_id;

      update public.profiles
      set active_family_id = target_family.id
      where id = current_user_id;
      current_profile.active_family_id := target_family.id;
    end if;
  end if;

  if target_family.id is null then
    return jsonb_build_object(
      'profile', to_jsonb(current_profile),
      'family', null,
      'members', '[]'::jsonb,
      'permission_role', null,
      'membership_verified', false,
      'snapshot', null,
      'active_invite', null,
      'pending_join_requests', '[]'::jsonb
    );
  end if;

  select greatest(8 - count(*)::integer, 0)
  into remaining_member_slots
  from public.family_members
  where family_id = target_family.id
    and household_role <> 'assistant';

  select data
  into target_snapshot
  from public.family_snapshots
  where family_id = target_family.id;

  if target_permission in ('owner', 'admin') then
    select jsonb_build_object(
      'code', invites.token,
      'status', case
        when invites.revoked_at is not null then 'revoked'
        when invites.expires_at <= now() then 'expired'
        when remaining_member_slots = 0
          or cardinality(invites.accepted_by) >= invites.max_uses then 'exhausted'
        else 'active'
      end,
      'expires_at', invites.expires_at,
      'max_uses', invites.max_uses,
      'uses', cardinality(invites.accepted_by),
      'uses_remaining', greatest(
        least(
          invites.max_uses - cardinality(invites.accepted_by),
          remaining_member_slots
        ),
        0
      )
    )
    into active_invite
    from public.invites
    where invites.family_id = target_family.id
      and invites.revoked_at is null
    order by invites.created_at desc
    limit 1;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', requests.id,
          'family_id', requests.family_id,
          'family_name', target_family.name,
          'requester_user_id', requests.requester_user_id,
          'requester_name', coalesce(requester_profiles.display_name, requests.requester_name),
          'status', requests.status,
          'created_at', requests.created_at,
          'reviewed_at', requests.reviewed_at
        )
        order by requests.created_at
      ),
      '[]'::jsonb
    )
    into pending_requests
    from public.family_join_requests as requests
    left join public.profiles as requester_profiles
      on requester_profiles.id = requests.requester_user_id
    where requests.family_id = target_family.id
      and requests.status = 'pending';
  end if;

  return jsonb_build_object(
    'profile', to_jsonb(current_profile),
    'family', jsonb_build_object(
      'id', target_family.id,
      'name', target_family.name,
      'invite_code', case
        when target_permission in ('owner', 'admin') then target_family.invite_code
        else ''
      end,
      'created_by', target_family.created_by,
      'created_at', target_family.created_at,
      'updated_at', target_family.updated_at
    ),
    'members', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', members.id,
            'family_id', members.family_id,
            'user_id', members.user_id,
            'name', case
              when members.user_id is null then members.name
              else coalesce(member_profiles.display_name, members.name)
            end,
            'relationship', members.relationship,
            'household_role', members.household_role,
            'permission_role', members.permission_role,
            'tone', members.tone,
            'task_count', members.task_count,
            'memory_note', members.memory_note,
            'birth_date', members.birth_date,
            'pet_species', members.pet_species,
            'pet_breed', members.pet_breed,
            'identity_state', case
              when members.user_id is null then 'unclaimed'
              else 'claimed'
            end,
            'created_at', members.created_at
          )
          order by
            case when members.household_role = 'assistant' then 1 else 0 end,
            members.created_at
        )
        from public.family_members as members
        left join public.profiles as member_profiles on member_profiles.id = members.user_id
        where members.family_id = target_family.id
      ),
      '[]'::jsonb
    ),
    'permission_role', target_permission,
    'membership_verified', true,
    'snapshot', target_snapshot,
    'active_invite', active_invite,
    'pending_join_requests', pending_requests
  );
end;
$$;

create or replace function public.get_family_invite_preview(invite_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_code text := lower(trim(invite_code));
  target_name text;
  target_expires_at timestamptz;
  uses_remaining integer;
begin
  if length(normalized_code) < 12 or length(normalized_code) > 96 then
    return jsonb_build_object('valid', false);
  end if;

  select
    families.name,
    invites.expires_at,
    greatest(
      least(
        invites.max_uses - cardinality(invites.accepted_by),
        8 - (
          select count(*)::integer
          from public.family_members
          where family_id = families.id
            and household_role <> 'assistant'
        )
      ),
      0
    )
  into
    target_name,
    target_expires_at,
    uses_remaining
  from public.invites
  join public.families on families.id = invites.family_id
  where invites.token = normalized_code
    and invites.revoked_at is null
    and invites.expires_at > now()
    and cardinality(invites.accepted_by) < invites.max_uses
    and (
      select count(*)
      from public.family_members
      where family_id = families.id
        and household_role <> 'assistant'
    ) < 8;

  if not found then
    return jsonb_build_object('valid', false);
  end if;

  return jsonb_build_object(
    'valid', true,
    'family_name', target_name,
    'expires_at', target_expires_at,
    'uses_remaining', uses_remaining
  );
end;
$$;

create or replace function public.get_pending_family_join_request()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  request_payload jsonb;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select jsonb_build_object(
    'id', requests.id,
    'family_id', requests.family_id,
    'family_name', families.name,
    'requester_user_id', requests.requester_user_id,
    'requester_name', requests.requester_name,
    'status', requests.status,
    'created_at', requests.created_at,
    'reviewed_at', requests.reviewed_at
  )
  into request_payload
  from public.family_join_requests as requests
  join public.families on families.id = requests.family_id
  where requests.requester_user_id = current_user_id
    and requests.status = 'pending'
  order by requests.created_at desc
  limit 1;

  return request_payload;
end;
$$;

create or replace function public.request_family_join(invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  normalized_code text := lower(trim(invite_code));
  target_invite public.invites%rowtype;
  target_family public.families%rowtype;
  current_user_id uuid := auth.uid();
  current_profile public.profiles%rowtype;
  target_request public.family_join_requests%rowtype;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select *
  into target_invite
  from public.invites
  where token = normalized_code
  for update;

  if not found
     or target_invite.revoked_at is not null
     or target_invite.expires_at <= now()
     or cardinality(target_invite.accepted_by) >= target_invite.max_uses then
    raise exception 'invalid_invite_code' using errcode = 'P0001';
  end if;

  select *
  into target_family
  from public.families
  where id = target_invite.family_id;

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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target_family.id::text, 0)
  );

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
  manager_permission text;
  target_request public.family_join_requests%rowtype;
  target_profile public.profiles%rowtype;
  target_invite public.invites%rowtype;
begin
  select *
  into target_request
  from public.family_join_requests
  where id = target_request_id
  for update;

  if not found or target_request.status <> 'pending' then
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

create or replace function public.decline_family_join_request(target_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  target_request public.family_join_requests%rowtype;
begin
  select *
  into target_request
  from public.family_join_requests
  where id = target_request_id
  for update;

  if not found or target_request.status <> 'pending' then
    raise exception 'join_request_not_pending' using errcode = 'P0002';
  end if;

  if not public.can_manage_family(target_request.family_id) then
    raise exception 'family_management_denied' using errcode = '42501';
  end if;

  update public.family_join_requests
  set
    status = 'declined',
    reviewed_by = current_user_id,
    reviewed_at = now()
  where id = target_request.id;

  return public.get_current_home_context();
end;
$$;

create or replace function public.cancel_family_join_request(target_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  update public.family_join_requests
  set status = 'cancelled'
  where id = target_request_id
    and requester_user_id = auth.uid()
    and status = 'pending';

  if not found then
    raise exception 'join_request_cancel_denied' using errcode = '42501';
  end if;

  return jsonb_build_object('cancelled', true);
end;
$$;

drop function if exists public.add_unclaimed_family_member(uuid, text, text, text, text, text);
create function public.add_unclaimed_family_member(
  target_family_id uuid,
  member_name text,
  relationship text default '',
  household_role text default 'child',
  tone text default 'mint',
  memory_note text default '',
  birth_date date default null,
  pet_species text default '',
  pet_breed text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.can_manage_family(target_family_id) then
    raise exception 'family_management_denied' using errcode = '42501';
  end if;

  if nullif(trim(member_name), '') is null then
    raise exception 'member_name_required' using errcode = '22023';
  end if;

  if coalesce(household_role, '') not in ('adult', 'child', 'pet') then
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
    trim(relationship),
    household_role,
    'member',
    tone,
    trim(memory_note),
    add_unclaimed_family_member.birth_date,
    case when household_role = 'pet' then trim(pet_species) else '' end,
    case when household_role = 'pet' then trim(pet_breed) else '' end
  );

  return public.get_current_home_context();
end;
$$;

drop function if exists public.update_family_member(uuid, text, text, text, text, text);
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
  manager_permission text;
  target_member public.family_members%rowtype;
  requested_permission text := update_family_member.permission_role;
begin
  select *
  into target_member
  from public.family_members
  where id = target_member_id
  for update;

  if not found then
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
     or household_role not in ('adult', 'child', 'pet') then
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
  manager_permission text;
  target_member public.family_members%rowtype;
begin
  select *
  into target_member
  from public.family_members
  where id = target_member_id
  for update;

  if not found then
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

create or replace function public.join_family_by_invite(invite_code text)
returns jsonb
language sql
security definer
set search_path = pg_catalog, public, auth
as $$
  select public.request_family_join(invite_code);
$$;

revoke all on function public.get_pending_family_join_request() from public;
revoke all on function public.request_family_join(text) from public;
revoke all on function public.approve_family_join_request(uuid, text) from public;
revoke all on function public.decline_family_join_request(uuid) from public;
revoke all on function public.cancel_family_join_request(uuid) from public;
revoke all on function public.add_unclaimed_family_member(uuid, text, text, text, text, text, date, text, text) from public;
revoke all on function public.update_family_member(uuid, text, text, text, text, text, text, date, text, text) from public;
revoke all on function public.remove_family_member(uuid) from public;
revoke all on function public.join_family_by_invite(text) from public;

grant execute on function public.get_pending_family_join_request() to authenticated;
grant execute on function public.request_family_join(text) to authenticated;
grant execute on function public.approve_family_join_request(uuid, text) to authenticated;
grant execute on function public.decline_family_join_request(uuid) to authenticated;
grant execute on function public.cancel_family_join_request(uuid) to authenticated;
grant execute on function public.add_unclaimed_family_member(uuid, text, text, text, text, text, date, text, text) to authenticated;
grant execute on function public.update_family_member(uuid, text, text, text, text, text, text, date, text, text) to authenticated;
grant execute on function public.remove_family_member(uuid) to authenticated;
grant execute on function public.join_family_by_invite(text) to authenticated;

commit;
