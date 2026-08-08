begin;

create or replace function public.prepare_account_deletion(target_user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, auth
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

    select family_members.user_id
    into replacement_user_id
    from public.family_members
    where family_members.family_id = target_membership.family_id
      and family_members.user_id is not null
      and family_members.user_id <> target_user_id
      and family_members.household_role <> 'assistant'
    order by
      case
        when family_members.household_role = 'adult'
          and family_members.permission_role = 'owner' then 0
        when family_members.household_role = 'adult'
          and family_members.permission_role = 'admin' then 1
        when family_members.household_role = 'adult' then 2
        else 3
      end,
      family_members.created_at,
      family_members.id
    limit 1;

    if replacement_user_id is null then
      if family_created_by = target_user_id then
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

  -- Repair legacy/inconsistent creator rows even if the user's membership was
  -- already removed by an earlier idempotent attempt.
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
      and family_members.household_role <> 'assistant'
    order by
      case
        when family_members.household_role = 'adult'
          and family_members.permission_role = 'owner' then 0
        when family_members.household_role = 'adult'
          and family_members.permission_role = 'admin' then 1
        when family_members.household_role = 'adult' then 2
        else 3
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
  from public, anon, authenticated;
grant execute on function public.prepare_account_deletion(uuid)
  to service_role;

comment on function public.prepare_account_deletion(uuid) is
  'Atomically removes private account content and transfers or deletes homes before Auth deletion. Service-only and idempotent.';

create or replace function public.prepare_account_deletion_before_auth_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  perform public.prepare_account_deletion(old.id);
  return old;
end;
$$;

revoke all on function public.prepare_account_deletion_before_auth_delete()
  from public, anon, authenticated, service_role;

drop trigger if exists prepare_account_deletion_before_auth_delete
  on auth.users;
create trigger prepare_account_deletion_before_auth_delete
  before delete on auth.users
  for each row execute function public.prepare_account_deletion_before_auth_delete();

comment on function public.prepare_account_deletion_before_auth_delete() is
  'Closes races by repeating idempotent account preparation inside the Auth user deletion transaction.';

commit;
