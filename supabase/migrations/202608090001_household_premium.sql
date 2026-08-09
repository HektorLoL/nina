begin;

alter table public.premium_subscriptions
  add column if not exists family_id uuid references public.families(id) on delete set null;

create index if not exists premium_subscriptions_family_active_idx
  on public.premium_subscriptions(family_id, is_active, expires_at desc);

comment on column public.premium_subscriptions.family_id is
  'Server-derived from the payer active home and their live membership. Never accepted from a client or Edge Function write.';

comment on policy "Users can read own premium subscriptions" on public.premium_subscriptions is
  'Deliberately not broadened to household members: the row carries the payer signed transaction, app account token and purchase identifiers. The household signal travels only through get_current_home_context.';

create or replace function public.resolve_premium_subscription_family()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  resolved_family_id uuid;
begin
  if new.user_id is null then
    new.family_id := null;
    return new;
  end if;

  select profiles.active_family_id
  into resolved_family_id
  from public.profiles
  where profiles.id = new.user_id;

  if resolved_family_id is not null
     and public.is_family_member(resolved_family_id, new.user_id) then
    new.family_id := resolved_family_id;
  else
    new.family_id := null;
  end if;

  return new;
end;
$$;

revoke all on function public.resolve_premium_subscription_family()
  from public, anon, authenticated, service_role;

drop trigger if exists premium_subscriptions_resolve_family on public.premium_subscriptions;
create trigger premium_subscriptions_resolve_family
  before insert or update on public.premium_subscriptions
  for each row execute function public.resolve_premium_subscription_family();

create or replace function public.resolve_premium_family_on_profile_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  update public.premium_subscriptions as subscriptions
  set family_id = new.active_family_id
  where subscriptions.user_id = new.id
    and subscriptions.family_id is distinct from new.active_family_id;

  return null;
end;
$$;

revoke all on function public.resolve_premium_family_on_profile_change()
  from public, anon, authenticated, service_role;

drop trigger if exists profiles_resolve_premium_family on public.profiles;
create trigger profiles_resolve_premium_family
  after update of active_family_id on public.profiles
  for each row execute function public.resolve_premium_family_on_profile_change();

create or replace function public.resolve_premium_family_on_membership_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if tg_op = 'DELETE' then
    if old.user_id is not null then
      update public.premium_subscriptions
      set family_id = null
      where premium_subscriptions.user_id = old.user_id
        and premium_subscriptions.family_id = old.family_id;
    end if;

    return null;
  end if;

  if new.user_id is not null then
    update public.premium_subscriptions as subscriptions
    set family_id = profiles.active_family_id
    from public.profiles
    where profiles.id = subscriptions.user_id
      and subscriptions.user_id = new.user_id
      and subscriptions.family_id is distinct from profiles.active_family_id;
  end if;

  return null;
end;
$$;

revoke all on function public.resolve_premium_family_on_membership_change()
  from public, anon, authenticated, service_role;

drop trigger if exists family_members_resolve_premium_family on public.family_members;
create trigger family_members_resolve_premium_family
  after insert or delete on public.family_members
  for each row execute function public.resolve_premium_family_on_membership_change();

update public.premium_subscriptions as subscriptions
set family_id = profiles.active_family_id
from public.profiles
where profiles.id = subscriptions.user_id;

create or replace function private.family_has_premium(target_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
  select target_family_id is not null and exists (
    select 1
    from public.premium_subscriptions
    where premium_subscriptions.family_id = target_family_id
      and premium_subscriptions.is_active
  );
$$;

revoke all on function private.family_has_premium(uuid)
  from public, anon, authenticated, service_role;

comment on function private.family_has_premium(uuid) is
  'Household premium signal for definer callers only. Answers whether the house is covered without exposing who paid or how.';

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
  household_premium jsonb;
  household_premium_status text;
  household_premium_expires_at timestamptz;
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
      'pending_join_requests', '[]'::jsonb,
      'premium', jsonb_build_object(
        'is_active', false,
        'status', 'inactive',
        'expires_at', null
      )
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
    'pending_join_requests', pending_requests,
    'premium', household_premium
  );
end;
$$;

revoke all on function public.get_current_home_context()
  from public, anon, authenticated, service_role;
grant execute on function public.get_current_home_context() to authenticated;

commit;
