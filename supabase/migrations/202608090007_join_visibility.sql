begin;

revoke all on table public.families from public, anon, authenticated;
grant select (
  id,
  name,
  created_by,
  created_at,
  updated_at,
  weekly_digest_enabled
) on table public.families to authenticated;

comment on column public.families.invite_code is
  'Household access in one string. Authenticated holds no column grant on it, so the owner-and-admin masking inside get_current_home_context is the only way a client ever sees it and a plain member cannot hand the house out. The column grant is also what keeps the realtime publication below safe, because a published row carries every column the subscriber may select.';

create or replace function public.bump_family_on_join_request()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  update public.families
  set updated_at = now()
  where id = new.family_id;

  return null;
end;
$$;

comment on function public.bump_family_on_join_request() is
  'family_join_requests has no client policy and never will, so the arrival and the review of a request ride out on the households own row instead. Without this the owner learns about a request only by opening the Casa tab, and the two people phone each other to coordinate a thing the app was built to coordinate.';

drop trigger if exists family_join_requests_bump_family on public.family_join_requests;
create trigger family_join_requests_bump_family
  after insert or update on public.family_join_requests
  for each row execute function public.bump_family_on_join_request();

revoke all on function public.bump_family_on_join_request()
  from public, anon, authenticated, service_role;

alter table public.families replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table public.families;
  exception
    when duplicate_object then null;
  end;
end;
$$;

create table if not exists public.family_access_decisions (
  id uuid primary key default gen_random_uuid(),
  family_id uuid references public.families(id) on delete set null,
  family_name text not null check (length(trim(family_name)) > 0),
  subject_user_id uuid not null references auth.users(id) on delete cascade,
  outcome text not null,
  decided_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  constraint family_access_decisions_acknowledged_after_decided
    check (acknowledged_at is null or acknowledged_at >= decided_at)
);

alter table public.family_access_decisions
  drop constraint if exists family_access_decisions_outcome_check;
alter table public.family_access_decisions
  add constraint family_access_decisions_outcome_check
  check (outcome in ('declined', 'removed'));

create index if not exists family_access_decisions_subject_unread_idx
  on public.family_access_decisions(subject_user_id, decided_at desc)
  where acknowledged_at is null;

alter table public.family_access_decisions enable row level security;
revoke all on table public.family_access_decisions from public, anon, authenticated;

comment on table public.family_access_decisions is
  'The terminal answer a person received about one home: declined, or removed. It exists because the previous behaviour was silence, and silence at this exact moment reads as a bug to the one household this product most wants to calm. The table deliberately has no reviewer column: family_join_requests already records who reviewed, and copying that here would let one adult hand the other a name to argue with.';

comment on column public.family_access_decisions.family_name is
  'Copied at decision time so the message still reads after the home is renamed or deleted, and so telling a person the answer never requires reading the household they no longer belong to.';

comment on column public.family_access_decisions.acknowledged_at is
  'A decision is delivered once. get_family_access_decision only returns unacknowledged rows and the client stamps this when the person dismisses the screen, so being declined is told and then let go instead of greeting them on every launch. The row itself is kept, never deleted.';

create or replace function public.get_family_access_decision()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  decision_payload jsonb;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select jsonb_build_object(
    'id', decisions.id,
    'family_name', decisions.family_name,
    'outcome', decisions.outcome,
    'decided_at', decisions.decided_at
  )
  into decision_payload
  from public.family_access_decisions as decisions
  where decisions.subject_user_id = current_user_id
    and decisions.acknowledged_at is null
    and not exists (
      select 1
      from public.family_members as members
      where members.family_id = decisions.family_id
        and members.user_id = current_user_id
    )
    and not exists (
      select 1
      from public.family_join_requests as requests
      where requests.family_id = decisions.family_id
        and requests.requester_user_id = current_user_id
        and requests.status = 'pending'
    )
  order by decisions.decided_at desc
  limit 1;

  return decision_payload;
end;
$$;

comment on function public.get_family_access_decision() is
  'The most recent unread terminal decision about the caller, and nothing else: only rows whose subject is auth.uid(), the household name but no other household fact, and never the person who decided. A live membership or a fresh pending request retires the decision, so nobody is told they were turned away by a home they are already back inside.';

revoke all on function public.get_family_access_decision()
  from public, anon, authenticated, service_role;
grant execute on function public.get_family_access_decision() to authenticated;

create or replace function public.acknowledge_family_access_decision(
  target_decision_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  update public.family_access_decisions
  set acknowledged_at = now()
  where id = target_decision_id
    and subject_user_id = auth.uid()
    and acknowledged_at is null;

  if not found then
    raise exception 'access_decision_acknowledge_denied' using errcode = '42501';
  end if;

  return jsonb_build_object('acknowledged', true);
end;
$$;

comment on function public.acknowledge_family_access_decision(uuid) is
  'Marks one decision as read by its own subject. An unknown id, another persons decision and an already-read decision all fail identically, so the call cannot be used to discover that a decision exists.';

revoke all on function public.acknowledge_family_access_decision(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.acknowledge_family_access_decision(uuid)
  to authenticated;

create or replace function public.decline_family_join_request(target_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  initial_family_id uuid;
  target_request public.family_join_requests%rowtype;
  target_family_name text;
begin
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

  if not public.can_manage_family(target_request.family_id) then
    raise exception 'family_management_denied' using errcode = '42501';
  end if;

  select families.name
  into target_family_name
  from public.families as families
  where families.id = target_request.family_id;

  update public.family_join_requests
  set
    status = 'declined',
    reviewed_by = current_user_id,
    reviewed_at = now()
  where id = target_request.id;

  insert into public.family_access_decisions (
    family_id,
    family_name,
    subject_user_id,
    outcome
  )
  values (
    target_request.family_id,
    target_family_name,
    target_request.requester_user_id,
    'declined'
  );

  return public.get_current_home_context();
end;
$$;

comment on function public.decline_family_join_request(uuid) is
  'Declines a request and leaves the requester an answer they can read, using the same family-first lock order as approval because the review now writes the households own row.';

revoke all on function public.decline_family_join_request(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.decline_family_join_request(uuid) to authenticated;

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
  target_family_name text;
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

  return public.get_current_home_context();
end;
$$;

comment on function public.remove_family_member(uuid) is
  'Removes a member under the family-first lock order, and leaves a claimed member a readable answer. An unclaimed child or pet profile raises no decision because there is nobody to tell.';

revoke all on function public.remove_family_member(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.remove_family_member(uuid) to authenticated;

commit;
