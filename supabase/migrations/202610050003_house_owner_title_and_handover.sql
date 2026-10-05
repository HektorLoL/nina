begin;

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

  update public.profiles
  set active_family_id = target_family.id
  where id = current_user_id;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.create_family(text, text)
  from public, anon, authenticated, service_role;

update public.family_members
set relationship = ''
where relationship = 'Criador'
  and user_id is not null;

-- An offer names the member it was made to and the owner who made it; it is
-- void once that owner no longer holds the house, after seven days, or when
-- the member is gone.
create table if not exists private.family_ownership_offers (
  family_id uuid primary key references public.families (id) on delete cascade,
  member_id uuid not null references public.family_members (id) on delete cascade,
  offered_by uuid not null references auth.users (id) on delete cascade,
  offered_at timestamptz not null default now()
);

create index if not exists family_ownership_offers_member_id_fkey_idx
  on private.family_ownership_offers (member_id);
create index if not exists family_ownership_offers_offered_by_fkey_idx
  on private.family_ownership_offers (offered_by);

alter table private.family_ownership_offers enable row level security;
revoke all on table private.family_ownership_offers
  from public, anon, authenticated, service_role;

create or replace function private.live_ownership_offer(target_family_id uuid)
returns private.family_ownership_offers
language sql
stable
set search_path = pg_catalog, public, private
as $$
  select offers.*
  from private.family_ownership_offers as offers
  join public.family_members as receivers
    on receivers.id = offers.member_id
   and receivers.family_id = offers.family_id
   and receivers.user_id is not null
   and receivers.household_role = 'adult'
  join public.family_members as owners
    on owners.family_id = offers.family_id
   and owners.user_id = offers.offered_by
   and owners.permission_role = 'owner'
  where offers.family_id = target_family_id
    and offers.offered_at > now() - interval '7 days';
$$;

revoke all on function private.live_ownership_offer(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.ownership_offer_json(target_family_id uuid)
returns jsonb
language sql
stable
set search_path = pg_catalog, public, private
as $$
  select jsonb_build_object(
    'member_id', offers.member_id,
    'offered_by', offers.offered_by,
    'offered_at', offers.offered_at,
    'expires_at', offers.offered_at + interval '7 days'
  )
  from private.live_ownership_offer(target_family_id) as offers
  where offers.family_id is not null;
$$;

revoke all on function private.ownership_offer_json(uuid)
  from public, anon, authenticated, service_role;

-- The owner may offer the house to any member the list shows as an adult with
-- an account; only the receiver's own acceptance reads their age, so neither
-- answer tells the owner anything about the other person.
create or replace function public.offer_family_ownership(target_member_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  target_member public.family_members%rowtype;
  owner_member public.family_members%rowtype;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  target_member := private.lock_family_member(target_member_id);
  if target_member.id is null then
    raise exception 'family_member_not_found' using errcode = 'P0002';
  end if;

  select *
  into owner_member
  from public.family_members as members
  where members.family_id = target_member.family_id
    and members.user_id = current_user_id
  for update;

  if not found then
    raise exception 'family_member_not_found' using errcode = 'P0002';
  end if;

  if owner_member.permission_role is distinct from 'owner'
     or not public.can_manage_family(target_member.family_id)
     or target_member.id = owner_member.id
     or target_member.user_id is null
     or target_member.household_role is distinct from 'adult' then
    raise exception 'family_owner_transfer_denied' using errcode = '42501';
  end if;

  delete from private.family_ownership_offers
  where offered_at <= now() - interval '7 days';

  insert into private.family_ownership_offers (family_id, member_id, offered_by, offered_at)
  values (target_member.family_id, target_member.id, current_user_id, now())
  on conflict (family_id) do update
  set
    member_id = excluded.member_id,
    offered_by = excluded.offered_by,
    offered_at = excluded.offered_at;

  update public.families
  set updated_at = now()
  where id = target_member.family_id;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.offer_family_ownership(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.offer_family_ownership(uuid) to authenticated;

-- The owner withdraws an offer and the receiver declines one through the same door.
create or replace function public.cancel_family_ownership_offer(target_family_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  caller_member public.family_members%rowtype;
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

  select *
  into caller_member
  from public.family_members as members
  where members.family_id = target_family_id
    and members.user_id = current_user_id;

  if not found then
    raise exception 'family_not_found' using errcode = 'P0002';
  end if;

  delete from private.family_ownership_offers as offers
  where offers.offered_at <= now() - interval '7 days';

  delete from private.family_ownership_offers as offers
  where offers.family_id = target_family_id
    and (
      offers.member_id = caller_member.id
      or (offers.offered_by = current_user_id and caller_member.permission_role = 'owner')
    );

  if found then
    update public.families
    set updated_at = now()
    where id = target_family_id;
  end if;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.cancel_family_ownership_offer(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.cancel_family_ownership_offer(uuid) to authenticated;

-- Accepting reads only the caller's own age; the former owner stays as an
-- admin and families.created_by follows, so a later deletion hands the house
-- on from the new owner.
create or replace function public.accept_family_ownership_offer(target_family_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  caller_member public.family_members%rowtype;
  owner_member public.family_members%rowtype;
  offer private.family_ownership_offers%rowtype;
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

  perform families.id
  from public.families
  where families.id = target_family_id
  for no key update;

  select *
  into caller_member
  from public.family_members as members
  where members.family_id = target_family_id
    and members.user_id = current_user_id
  for update;

  if not found then
    raise exception 'family_not_found' using errcode = 'P0002';
  end if;

  select *
  into offer
  from private.live_ownership_offer(target_family_id) as offers
  where offers.member_id = caller_member.id;

  if offer.family_id is null then
    raise exception 'family_ownership_offer_not_found' using errcode = 'P0002';
  end if;

  perform private.require_adult_account(current_user_id);

  select *
  into owner_member
  from public.family_members as members
  where members.family_id = target_family_id
    and members.user_id = offer.offered_by
    and members.permission_role = 'owner'
  for update;

  if not found then
    raise exception 'family_ownership_offer_not_found' using errcode = 'P0002';
  end if;

  update public.family_members
  set permission_role = 'admin'
  where id = owner_member.id;

  update public.family_members
  set permission_role = 'owner'
  where id = caller_member.id;

  update public.families
  set created_by = current_user_id,
      updated_at = now()
  where id = target_family_id;

  delete from private.family_ownership_offers
  where family_id = target_family_id;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.accept_family_ownership_offer(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.accept_family_ownership_offer(uuid) to authenticated;

create or replace function public.get_current_home_context()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  current_profile public.profiles%rowtype;
  viewer_age jsonb;
  target_family public.families%rowtype;
  target_permission text;
  target_snapshot jsonb;
  active_invite jsonb;
  pending_requests jsonb := '[]'::jsonb;
  remaining_member_slots integer := 0;
  household_premium jsonb;
  household_premium_status text;
  household_premium_expires_at timestamptz;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  current_profile := public.ensure_current_profile(null);
  viewer_age := private.age_status_json(current_user_id);

  if viewer_age ->> 'status' is distinct from 'adult' then
    return jsonb_build_object(
      'viewer_kind', 'minor',
      'viewer_age', viewer_age,
      'profile', jsonb_build_object(
        'id', current_profile.id,
        'display_name', current_profile.display_name
      ),
      'family', null,
      'members', '[]'::jsonb,
      'permission_role', null,
      'membership_verified', false,
      'snapshot', null,
      'active_invite', null,
      'pending_join_requests', '[]'::jsonb,
      'premium', jsonb_build_object(
        'is_active', false,
        'status', 'inactive',
        'expires_at', null
      ),
      'ai_consent', private.ai_consent_json(null, current_user_id)
    );
  end if;

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
      'viewer_kind', 'adult',
      'viewer_age', viewer_age,
      'profile', to_jsonb(current_profile),
      'family', null,
      'members', '[]'::jsonb,
      'permission_role', null,
      'membership_verified', false,
      'snapshot', null,
      'active_invite', null,
      'pending_join_requests', '[]'::jsonb,
      'premium', jsonb_build_object(
        'is_active', false,
        'status', 'inactive',
        'expires_at', null
      ),
      'ai_consent', private.ai_consent_json(null, current_user_id)
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

  select
    subscriptions.status,
    subscriptions.expires_at
  into household_premium_status, household_premium_expires_at
  from public.premium_subscriptions as subscriptions
  where subscriptions.family_id = target_family.id
  order by
    subscriptions.is_active desc,
    subscriptions.expires_at desc nulls last,
    subscriptions.last_verified_at desc,
    subscriptions.updated_at desc
  limit 1;

  household_premium := jsonb_build_object(
    'is_active', private.family_has_premium(target_family.id),
    'status', coalesce(household_premium_status, 'inactive'),
    'expires_at', household_premium_expires_at
  );

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
          'reviewed_at', requests.reviewed_at,
          'requester_age', requester_ages.status,
          'requester_band', case
            when requester_ages.status = 'minor' then requester_ages.band
          end
        )
        order by requests.created_at
      ),
      '[]'::jsonb
    )
    into pending_requests
    from public.family_join_requests as requests
    left join public.profiles as requester_profiles
      on requester_profiles.id = requests.requester_user_id
    cross join lateral private.effective_age(requests.requester_user_id) as requester_ages
    where requests.family_id = target_family.id
      and requests.status = 'pending';
  end if;

  return jsonb_build_object(
    'viewer_kind', 'adult',
    'viewer_age', viewer_age,
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
      'updated_at', target_family.updated_at,
      'weekly_digest_enabled', target_family.weekly_digest_enabled
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
            'birth_date', case
              when members.household_role in ('child', 'teen') then null
              else members.birth_date
            end,
            'pet_species', members.pet_species,
            'pet_breed', members.pet_breed,
            'identity_state', case
              when members.user_id is null then 'unclaimed'
              else 'claimed'
            end,
            'created_at', members.created_at,
            'access', private.member_access_json(members.id, current_user_id)
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
    'pending_join_requests', pending_requests,
    'premium', household_premium,
    'ai_consent', private.ai_consent_json(target_family.id, current_user_id),
    'ownership_offer', private.ownership_offer_json(target_family.id)
  );
end;
$$;

revoke all on function public.get_current_home_context()
  from public, anon, authenticated, service_role;
grant execute on function public.get_current_home_context() to authenticated;

commit;
