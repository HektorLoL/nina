begin;

-- A carrier is a claimed adult of the house who holds a live consent at the
-- current version, with the transfer consent, and whom the server lets use AI.
create or replace function private.is_ai_carrier(
  target_family_id uuid,
  target_user_id uuid
)
returns boolean
language sql
stable
set search_path = pg_catalog, public, private
as $$
  select target_user_id is not null
    and exists (
      select 1
      from public.family_members as members
      where members.family_id = target_family_id
        and members.user_id = target_user_id
        and members.household_role = 'adult'
    )
    and exists (
      select 1
      from public.nina_ai_consents as consents
      cross join private.age_policy as policy
      where policy.singleton
        and consents.family_id = target_family_id
        and consents.user_id = target_user_id
        and consents.revoked_at is null
        and consents.transfer_consented_at is not null
        and consents.policy_version = policy.current_policy_version
    )
    and private.may_use_ai(target_user_id)
    and not private.ai_blocked(target_user_id);
$$;

revoke all on function private.is_ai_carrier(uuid, uuid)
  from public, anon, authenticated, service_role;

-- The weekly insight is keyed only by consenting adult carriers and pets; the
-- work of children, teens, adults who did not consent and unclaimed adults is
-- left out together with the people themselves.
create or replace function private.nina_weekly_metrics(target_family_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  with bounds as (
    select
      (current_date - 7) as period_start,
      current_date as period_end
  ),
  keyed_people as (
    select
      people.id,
      case
        when count(*) over (partition by people.name) = 1 then people.name
        else people.name
          || ' · '
          || coalesce(
               nullif(trim(people.relationship), ''),
               (
                 row_number() over (
                   partition by people.name
                   order by people.created_at, people.id
                 )
               )::text
             )
      end as display_key
    from (
      select
        members.id,
        case
          when members.user_id is null then members.name
          else coalesce(member_profiles.display_name, members.name)
        end as name,
        members.relationship,
        members.created_at
      from public.family_members as members
      left join public.profiles as member_profiles
        on member_profiles.id = members.user_id
      where members.family_id = target_family_id
        and (
          members.household_role = 'pet'
          or (
            members.household_role = 'adult'
            and members.user_id is not null
            and private.is_ai_carrier(target_family_id, members.user_id)
          )
        )
    ) as people
  ),
  counted_tasks as (
    select tasks.*
    from public.tasks
    where tasks.family_id = target_family_id
      and (
        tasks.owner_member_id is null
        or tasks.owner_member_id in (select keyed_people.id from keyed_people)
      )
  ),
  task_metrics as (
    select
      count(*) filter (where created_at >= now() - interval '7 days')::integer as tasks_created,
      count(*) filter (
        where is_done
          and completed_at >= now() - interval '7 days'
      )::integer as tasks_completed,
      count(*) filter (where not is_done)::integer as tasks_open,
      count(*) filter (
        where created_at >= now() - interval '7 days'
          and due_at is not null
      )::integer as scheduled_task_events
    from counted_tasks
  ),
  owner_metrics as (
    select coalesce(
      jsonb_object_agg(open_counts.display_key, open_counts.owner_count),
      '{}'::jsonb
    ) as open_tasks_by_owner
    from (
      select
        coalesce(keyed_people.display_key, 'Casa') as display_key,
        count(*)::integer as owner_count
      from counted_tasks as open_tasks
      left join keyed_people
        on keyed_people.id = open_tasks.owner_member_id
      where not open_tasks.is_done
      group by 1
    ) as open_counts
  ),
  other_metrics as (
    select
      (
        select count(*)::integer
        from public.shopping_items
        where family_id = target_family_id
          and created_at >= now() - interval '7 days'
          and (
            owner_member_id is null
            or owner_member_id in (select keyed_people.id from keyed_people)
          )
      ) as shopping_events,
      (
        select count(*)::integer
        from public.memory_items
        where family_id = target_family_id
          and visibility = 'shared'
          and status = 'confirmed'
          and confirmed_at >= now() - interval '7 days'
      ) as shared_memory_events
  )
  select jsonb_build_object(
    'family_id', target_family_id,
    'period_start', bounds.period_start,
    'period_end', bounds.period_end,
    'tasks_created', task_metrics.tasks_created,
    'tasks_completed', task_metrics.tasks_completed,
    'tasks_open', task_metrics.tasks_open,
    'open_tasks_by_owner', owner_metrics.open_tasks_by_owner,
    'shopping_events', other_metrics.shopping_events,
    'reminder_events', task_metrics.scheduled_task_events,
    'shared_memory_events', other_metrics.shared_memory_events,
    'relevant_event_count',
      task_metrics.tasks_created
      + task_metrics.tasks_completed
      + other_metrics.shopping_events
      + other_metrics.shared_memory_events
  )
  from bounds, task_metrics, owner_metrics, other_metrics;
$$;

revoke all on function private.nina_weekly_metrics(uuid)
  from public, anon, authenticated, service_role;

-- With fewer than two consenting carriers a household comparison is a
-- portrait of one person, so the house gets no insight that week.
create or replace function public.get_nina_weekly_candidates()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select coalesce(
    jsonb_agg(candidate.metrics),
    '[]'::jsonb
  )
  from (
    select private.nina_weekly_metrics(families.id) as metrics
    from public.families
    where families.weekly_digest_enabled
      and private.family_has_premium(families.id)
      and (
        select count(*)
        from public.family_members as members
        where members.family_id = families.id
          and members.user_id is not null
          and members.household_role = 'adult'
          and private.is_ai_carrier(families.id, members.user_id)
      ) >= 2
      and (
        private.nina_weekly_metrics(families.id) ->> 'relevant_event_count'
      )::integer >= 5
      and not exists (
        select 1
        from public.household_insights
        where household_insights.family_id = families.id
          and household_insights.period_start = current_date - 7
      )
  ) as candidate;
$$;

revoke all on function public.get_nina_weekly_candidates()
  from public, anon, authenticated, service_role;
grant execute on function public.get_nina_weekly_candidates() to service_role;

comment on function public.get_nina_weekly_candidates() is
  'The weekly insight ships carrier display names to a model, so a household with fewer than two claimed adults holding a live, current, transfer-consented consent is never a candidate.';

-- The roster tells nina-chat and nina-maintenance which names must be swapped
-- for a code before any string leaves the server: every minor, every person of
-- unknown age, and every adult other than the requester who is not a carrier.
-- Every name a member is known by is listed, because the house's registered
-- name and owner labels can outlive a later profile rename.
create or replace function public.get_nina_model_roster(
  target_family_id uuid,
  requesting_user_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'member_id', roster.id,
        'name', roster.display_name,
        'names', to_jsonb(roster.known_names),
        'household_role', roster.household_role,
        'alias_kind', roster.alias_kind,
        'nicknames', to_jsonb(roster.nicknames),
        'created_at', roster.created_at
      )
      order by roster.created_at, roster.id
    ),
    '[]'::jsonb
  )
  from (
    select
      members.id,
      members.household_role,
      members.created_at,
      case
        when members.user_id is null then members.name
        else coalesce(member_profiles.display_name, members.name)
      end as display_name,
      array(
        select distinct trim(known.name)
        from unnest(array[members.name, member_profiles.display_name]) as known(name)
        where nullif(trim(known.name), '') is not null
        order by 1
      ) as known_names,
      case
        when members.household_role in ('pet', 'assistant') then 'none'
        when members.user_id is null and members.household_role = 'child' then 'child'
        when members.user_id is null and members.household_role = 'teen' then 'teen'
        when members.user_id is null then 'adult'
        when ages.status = 'minor' and ages.band = 'under_12' then 'child'
        when ages.status = 'minor' then 'teen'
        when ages.status <> 'adult' then 'person'
        when requesting_user_id is not null and members.user_id = requesting_user_id then 'none'
        when private.is_ai_carrier(target_family_id, members.user_id) then 'none'
        else 'adult'
      end as alias_kind,
      case
        when members.household_role in ('child', 'teen') or ages.status is distinct from 'adult'
          then coalesce(settings.nicknames, '{}'::text[])
        else '{}'::text[]
      end as nicknames
    from public.family_members as members
    left join public.profiles as member_profiles
      on member_profiles.id = members.user_id
    left join private.minor_profiles as settings
      on settings.member_id = members.id
    left join lateral private.effective_age(members.user_id) as ages
      on members.user_id is not null
    where members.family_id = target_family_id
  ) as roster;
$$;

revoke all on function public.get_nina_model_roster(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_nina_model_roster(uuid, uuid) to service_role;

commit;
