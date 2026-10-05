begin;

-- Leaving runs the cleanup a removal runs: a guardianship never outlives the
-- guardian's place in the ward's house, and the leaver's tasks fall back to the
-- house through the owner_member_id foreign key.
create or replace function public.leave_family(target_family_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  caller_member_id uuid;
  leaving_member public.family_members%rowtype;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select members.id
  into caller_member_id
  from public.family_members as members
  where members.family_id = target_family_id
    and members.user_id = current_user_id;

  if caller_member_id is null then
    raise exception 'family_not_found' using errcode = 'P0002';
  end if;

  leaving_member := private.lock_family_member(caller_member_id);
  if leaving_member.id is null
     or leaving_member.family_id is distinct from target_family_id
     or leaving_member.user_id is distinct from current_user_id then
    raise exception 'family_not_found' using errcode = 'P0002';
  end if;

  -- The owner holds the house; without a successor, leaving would orphan it.
  if leaving_member.permission_role = 'owner' then
    raise exception 'family_owner_cannot_leave' using errcode = 'P0001';
  end if;

  -- A child or teen leaves only through a guardian, never on their own.
  if leaving_member.household_role is distinct from 'adult' then
    raise exception 'family_leave_denied' using errcode = '42501';
  end if;

  update private.minor_guardianships as links
  set
    ended_at = now(),
    end_reason = 'guardian_left'
  where links.guardian_user_id = current_user_id
    and links.ended_at is null
    and links.member_id in (
      select wards.id
      from public.family_members as wards
      where wards.family_id = target_family_id
    );

  update private.minor_data_consents as consents
  set
    withdrawn_at = now(),
    withdrawn_by_hash = private.user_hash(current_user_id)
  where consents.guardian_user_hash = private.user_hash(current_user_id)
    and consents.withdrawn_at is null
    and consents.member_id in (
      select wards.id
      from public.family_members as wards
      where wards.family_id = target_family_id
    );

  delete from public.family_members
  where id = leaving_member.id;

  update public.profiles
  set active_family_id = null
  where id = current_user_id
    and active_family_id = target_family_id;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.leave_family(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.leave_family(uuid) to authenticated;

commit;
