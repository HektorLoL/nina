begin;

-- A predicate whose subject is an argument answers only inside SECURITY DEFINER
-- code, which runs as its owner, so no client can ask it about somebody else.
revoke all on function public.can_manage_family(uuid, uuid)
  from public, anon, authenticated, service_role;

revoke all on function public.is_family_creator(uuid, uuid)
  from public, anon, authenticated, service_role;

revoke all on function public.is_family_member(uuid, uuid)
  from public, anon, authenticated, service_role;

-- The profiles policy evaluates this as the signed-in role, so it keeps its
-- grant and answers only about the caller, never about two other people.
create or replace function public.shares_family_with(
  other_user_id uuid,
  target_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
  select target_user_id is not null
    and other_user_id is not null
    and (auth.uid() is null or target_user_id = auth.uid())
    and exists (
      select 1
      from public.family_members as mine
      join public.family_members as theirs
        on theirs.family_id = mine.family_id
      where mine.user_id = target_user_id
        and theirs.user_id = other_user_id
    );
$$;

revoke all on function public.shares_family_with(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.shares_family_with(uuid, uuid) to authenticated;

comment on function public.can_manage_family(uuid, uuid) is
  'House-power check for SECURITY DEFINER code only. No API role executes it: it reads age status, and its subject is an argument.';

comment on function public.is_family_creator(uuid, uuid) is
  'Creator check for SECURITY DEFINER code only. No API role executes it, because its subject is an argument.';

comment on function public.is_family_member(uuid, uuid) is
  'Membership check for SECURITY DEFINER code only. No API role executes it, because its subject is an argument. Household policies use is_adult_family_member.';

comment on function public.shares_family_with(uuid, uuid) is
  'Profiles policy predicate. Authenticated executes it because the policy runs as the invoking role; it answers only when its subject is the caller.';

commit;
