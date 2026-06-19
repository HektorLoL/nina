alter table public.profiles
  add column if not exists active_family_id uuid references public.families(id) on delete set null,
  add column if not exists display_name_source text not null default 'auth'
    check (display_name_source in ('auth', 'user'));

create index if not exists profiles_active_family_id_idx
  on public.profiles(active_family_id);

create or replace function public.auth_user_display_name(target_user auth.users)
returns text
language sql
stable
set search_path = public, auth
as $$
  select coalesce(
    nullif(trim(target_user.raw_user_meta_data ->> 'display_name'), ''),
    nullif(trim(target_user.raw_user_meta_data ->> 'full_name'), ''),
    nullif(trim(target_user.raw_user_meta_data ->> 'name'), ''),
    nullif(
      initcap(
        replace(
          replace(split_part(coalesce(target_user.email, ''), '@', 1), '.', ' '),
          '_',
          ' '
        )
      ),
      ''
    ),
    'Família'
  );
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.profiles (
    id,
    display_name,
    display_name_source,
    email
  )
  values (
    new.id,
    public.auth_user_display_name(new),
    'auth',
    new.email
  )
  on conflict (id) do update
  set
    email = excluded.email,
    display_name = case
      when profiles.display_name_source = 'user' then profiles.display_name
      else excluded.display_name
    end,
    updated_at = now();

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert or update of email, raw_user_meta_data on auth.users
  for each row execute function public.handle_new_auth_user();

insert into public.profiles (
  id,
  display_name,
  display_name_source,
  email
)
select
  users.id,
  public.auth_user_display_name(users),
  'auth',
  users.email
from auth.users as users
on conflict (id) do update
set
  email = excluded.email,
  display_name = case
    when profiles.display_name_source = 'user' then profiles.display_name
    else excluded.display_name
  end,
  updated_at = now();

update public.profiles as profiles
set active_family_id = (
  select family_id
  from public.family_members
  where user_id = profiles.id
  order by created_at
  limit 1
)
where profiles.active_family_id is null
  and exists (
    select 1
    from public.family_members
    where user_id = profiles.id
  );

create or replace function public.enforce_family_member_limit()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  existing_count integer;
begin
  if new.household_role = 'assistant' then
    return new;
  end if;

  select count(*)
  into existing_count
  from public.family_members
  where family_id = new.family_id
    and household_role <> 'assistant'
    and (tg_op = 'INSERT' or id <> new.id);

  if existing_count >= 8 then
    raise exception 'family_member_limit_reached' using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists family_members_enforce_limit on public.family_members;
create trigger family_members_enforce_limit
  before insert or update of family_id, household_role on public.family_members
  for each row execute function public.enforce_family_member_limit();

create or replace function public.ensure_current_profile(display_name_hint text default null)
returns public.profiles
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  auth_user_record auth.users%rowtype;
  target_profile public.profiles%rowtype;
  normalized_hint text := nullif(trim(display_name_hint), '');
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select *
  into auth_user_record
  from auth.users
  where id = auth.uid();

  if not found then
    raise exception 'auth_user_not_found' using errcode = 'P0002';
  end if;

  insert into public.profiles (
    id,
    display_name,
    display_name_source,
    email
  )
  values (
    auth_user_record.id,
    coalesce(normalized_hint, public.auth_user_display_name(auth_user_record)),
    'auth',
    auth_user_record.email
  )
  on conflict (id) do update
  set
    email = excluded.email,
    display_name = case
      when profiles.display_name_source = 'user' then profiles.display_name
      else coalesce(normalized_hint, excluded.display_name)
    end,
    updated_at = now()
  returning * into target_profile;

  return target_profile;
end;
$$;

create or replace function public.get_current_home_context()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  current_profile public.profiles%rowtype;
  target_family public.families%rowtype;
  target_permission text;
  target_snapshot jsonb;
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
      'snapshot', null
    );
  end if;

  select data
  into target_snapshot
  from public.family_snapshots
  where family_id = target_family.id;

  return jsonb_build_object(
    'profile', to_jsonb(current_profile),
    'family', to_jsonb(target_family),
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
    'snapshot', target_snapshot
  );
end;
$$;

drop function if exists public.create_family(text, text, text);
create or replace function public.create_family(
  family_name text,
  invite_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
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

drop function if exists public.join_family_by_invite(text, text);
create or replace function public.join_family_by_invite(invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized_code text := lower(trim(invite_code));
  target_family public.families%rowtype;
  current_user_id uuid := auth.uid();
  current_profile public.profiles%rowtype;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select *
  into target_family
  from public.families
  where families.invite_code = normalized_code;

  if not found then
    raise exception 'invalid_invite_code' using errcode = 'P0001';
  end if;

  current_profile := public.ensure_current_profile(null);

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
    'Você',
    'adult',
    'member',
    'sky',
    'Participante desta casa.'
  )
  on conflict (family_id, user_id) where user_id is not null
  do update set updated_at = now();

  update public.profiles
  set active_family_id = target_family.id
  where id = current_user_id;

  return public.get_current_home_context();
end;
$$;

create or replace function public.activate_family(target_family_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_family_member(target_family_id) then
    raise exception 'family_access_denied' using errcode = '42501';
  end if;

  update public.profiles
  set active_family_id = target_family_id
  where id = auth.uid();

  return public.get_current_home_context();
end;
$$;

create or replace function public.update_family_settings(
  target_family_id uuid,
  family_name text,
  invite_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized_name text := trim(family_name);
  normalized_code text := lower(trim(invite_code));
begin
  if not public.can_manage_family(target_family_id) then
    raise exception 'family_management_denied' using errcode = '42501';
  end if;

  if normalized_name = '' or length(normalized_code) < 4 then
    raise exception 'invalid_family_settings' using errcode = '22023';
  end if;

  update public.families
  set
    name = normalized_name,
    invite_code = normalized_code
  where id = target_family_id;

  return public.get_current_home_context();
end;
$$;

create or replace function public.add_unclaimed_family_member(
  target_family_id uuid,
  member_name text,
  relationship text default '',
  household_role text default 'adult',
  tone text default 'mint',
  memory_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.can_manage_family(target_family_id) then
    raise exception 'family_management_denied' using errcode = '42501';
  end if;

  if nullif(trim(member_name), '') is null then
    raise exception 'member_name_required' using errcode = '22023';
  end if;

  if household_role not in ('adult', 'child', 'pet') then
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
    memory_note
  )
  values (
    target_family_id,
    null,
    trim(member_name),
    trim(relationship),
    household_role,
    'member',
    tone,
    trim(memory_note)
  );

  return public.get_current_home_context();
end;
$$;

create or replace function public.update_family_member(
  target_member_id uuid,
  member_name text,
  relationship text,
  household_role text,
  tone text,
  memory_note text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  target_member public.family_members%rowtype;
begin
  select *
  into target_member
  from public.family_members
  where id = target_member_id;

  if not found then
    raise exception 'family_member_not_found' using errcode = 'P0002';
  end if;

  if not public.can_manage_family(target_member.family_id)
     and target_member.user_id <> auth.uid() then
    raise exception 'family_member_update_denied' using errcode = '42501';
  end if;

  if household_role not in ('adult', 'child', 'pet', 'assistant') then
    raise exception 'invalid_household_role' using errcode = '22023';
  end if;

  update public.family_members
  set
    name = case
      when user_id is null then coalesce(nullif(trim(member_name), ''), name)
      else name
    end,
    relationship = trim(update_family_member.relationship),
    household_role = update_family_member.household_role,
    tone = update_family_member.tone,
    memory_note = trim(update_family_member.memory_note)
  where id = target_member_id;

  return public.get_current_home_context();
end;
$$;

drop policy if exists "Creators can add their first membership" on public.family_members;
drop policy if exists "Family managers can add memberships" on public.family_members;
drop policy if exists "Family managers and users can update memberships" on public.family_members;
drop policy if exists "Family managers can delete memberships" on public.family_members;

revoke insert, update, delete on public.family_members from authenticated;
revoke insert, update, delete on public.families from authenticated;
grant select on public.family_members to authenticated;
grant select on public.families to authenticated;

revoke all on function public.ensure_current_profile(text) from public;
revoke all on function public.get_current_home_context() from public;
revoke all on function public.create_family(text, text) from public;
revoke all on function public.join_family_by_invite(text) from public;
revoke all on function public.activate_family(uuid) from public;
revoke all on function public.update_family_settings(uuid, text, text) from public;
revoke all on function public.add_unclaimed_family_member(uuid, text, text, text, text, text) from public;
revoke all on function public.update_family_member(uuid, text, text, text, text, text) from public;

grant execute on function public.ensure_current_profile(text) to authenticated;
grant execute on function public.get_current_home_context() to authenticated;
grant execute on function public.create_family(text, text) to authenticated;
grant execute on function public.join_family_by_invite(text) to authenticated;
grant execute on function public.activate_family(uuid) to authenticated;
grant execute on function public.update_family_settings(uuid, text, text) to authenticated;
grant execute on function public.add_unclaimed_family_member(uuid, text, text, text, text, text) to authenticated;
grant execute on function public.update_family_member(uuid, text, text, text, text, text) to authenticated;
