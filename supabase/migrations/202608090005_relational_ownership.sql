begin;

create index if not exists tasks_family_owner_member_open_idx
  on public.tasks(family_id, owner_member_id)
  where not is_done;

create index if not exists shopping_items_family_owner_member_open_idx
  on public.shopping_items(family_id, owner_member_id)
  where not is_checked;

create index if not exists tasks_owner_member_idx
  on public.tasks(owner_member_id)
  where owner_member_id is not null;

create index if not exists shopping_items_owner_member_idx
  on public.shopping_items(owner_member_id)
  where owner_member_id is not null;

create or replace function public.sync_owner_member_label()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  is_update boolean := tg_op = 'UPDATE';
  pointer_changed boolean := true;
  label_changed boolean := true;
  previous_member_id uuid;
  bound_name text;
  matched_member_id uuid;
  matched_name text;
begin
  if is_update then
    previous_member_id := old.owner_member_id;
    pointer_changed := new.owner_member_id is distinct from old.owner_member_id;
    label_changed := new.owner_label is distinct from old.owner_label;

    if not pointer_changed
       and not label_changed
       and new.family_id is not distinct from old.family_id then
      return new;
    end if;
  end if;

  if new.owner_member_id is not null then
    select members.name
    into bound_name
    from public.family_members as members
    where members.id = new.owner_member_id
      and members.family_id = new.family_id
      and members.household_role <> 'assistant';

    -- A row may only name a person who belongs to its own household, so a
    -- forged owner_member_id cannot pull another family's member name across.
    if bound_name is null then
      raise exception 'owner_member_not_assignable' using errcode = '42501';
    end if;

    if pointer_changed or lower(trim(new.owner_label)) = lower(trim(bound_name)) then
      new.owner_label := bound_name;
      return new;
    end if;

    -- A write that moves the label alone is a reassignment by name, so the
    -- stale pointer is dropped and resolved again rather than overruling it.
    new.owner_member_id := null;
  elsif previous_member_id is not null and not label_changed then
    new.owner_label := 'Casa';
  end if;

  new.owner_label := coalesce(nullif(trim(new.owner_label), ''), 'Casa');

  if lower(new.owner_label) <> 'casa' then
    select
      case when count(*) = 1 then (array_agg(members.id))[1] end,
      case when count(*) = 1 then (array_agg(members.name))[1] end
    into matched_member_id, matched_name
    from public.family_members as members
    where members.family_id = new.family_id
      and members.household_role <> 'assistant'
      and lower(trim(members.name)) = lower(new.owner_label);

    if matched_member_id is not null then
      new.owner_member_id := matched_member_id;
      new.owner_label := matched_name;
    end if;
  end if;

  return new;
end;
$$;

comment on function public.sync_owner_member_label() is
  'Keeps owner_label a pure display cache of owner_member_id, in both directions: a written pointer decides the label, and a label written alone reassigns the pointer. An ambiguous name matches nobody, because attributing work to the wrong person is worse than leaving it unattributed. Clearing the pointer, including the on-delete-set-null a removed member triggers, returns the row to Casa rather than leaving a departed name stamped on it.';

drop trigger if exists tasks_sync_owner_label on public.tasks;
create trigger tasks_sync_owner_label
  before insert or update on public.tasks
  for each row execute function public.sync_owner_member_label();

drop trigger if exists shopping_items_sync_owner_label on public.shopping_items;
create trigger shopping_items_sync_owner_label
  before insert or update on public.shopping_items
  for each row execute function public.sync_owner_member_label();

create or replace function public.propagate_family_member_name()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  update public.tasks
  set owner_label = new.name
  where family_id = new.family_id
    and owner_member_id = new.id
    and owner_label is distinct from new.name;

  update public.shopping_items
  set owner_label = new.name
  where family_id = new.family_id
    and owner_member_id = new.id
    and owner_label is distinct from new.name;

  return null;
end;
$$;

comment on function public.propagate_family_member_name() is
  'A rename must reach every row that points at the member, or the display cache diverges and one person renders as two. The write also bumps the task version so realtime hands the corrected chip to every phone.';

drop trigger if exists family_members_propagate_name on public.family_members;
create trigger family_members_propagate_name
  after update of name on public.family_members
  for each row
  when (old.name is distinct from new.name)
  execute function public.propagate_family_member_name();

revoke all on function public.sync_owner_member_label()
  from public, anon, authenticated, service_role;
revoke all on function public.propagate_family_member_name()
  from public, anon, authenticated, service_role;

comment on column public.tasks.owner_member_id is
  'The assignment. Null means the house owns the task, which is the only unattributed state and is never a person.';

comment on column public.tasks.owner_label is
  'Display cache of the assigned member name, maintained by trigger. Never the source of truth: write owner_member_id and let the label follow.';

comment on column public.shopping_items.owner_member_id is
  'The assignment. Null means the house owns the item, which is the only unattributed state and is never a person.';

comment on column public.shopping_items.owner_label is
  'Display cache of the assigned member name, maintained by trigger. Never the source of truth: write owner_member_id and let the label follow.';

-- The backfill must not read as a week of activity, so the timestamp and
-- version triggers stay off while historical rows gain their pointer.
alter table public.tasks disable trigger tasks_set_updated_at;
alter table public.tasks disable trigger tasks_bump_version;
alter table public.shopping_items disable trigger shopping_items_set_updated_at;

with matched as (
  select
    task_rows.id as row_id,
    candidates.member_id,
    candidates.member_name
  from public.tasks as task_rows
  cross join lateral (
    select
      case when count(*) = 1 then (array_agg(members.id))[1] end as member_id,
      case when count(*) = 1 then (array_agg(members.name))[1] end as member_name
    from public.family_members as members
    where members.family_id = task_rows.family_id
      and members.household_role <> 'assistant'
      and lower(trim(members.name)) = lower(trim(task_rows.owner_label))
  ) as candidates
  where task_rows.owner_member_id is null
    and lower(trim(task_rows.owner_label)) not in ('', 'casa')
)
update public.tasks
set
  owner_member_id = matched.member_id,
  owner_label = matched.member_name
from matched
where tasks.id = matched.row_id
  and matched.member_id is not null;

with matched as (
  select
    item_rows.id as row_id,
    candidates.member_id,
    candidates.member_name
  from public.shopping_items as item_rows
  cross join lateral (
    select
      case when count(*) = 1 then (array_agg(members.id))[1] end as member_id,
      case when count(*) = 1 then (array_agg(members.name))[1] end as member_name
    from public.family_members as members
    where members.family_id = item_rows.family_id
      and members.household_role <> 'assistant'
      and lower(trim(members.name)) = lower(trim(item_rows.owner_label))
  ) as candidates
  where item_rows.owner_member_id is null
    and lower(trim(item_rows.owner_label)) not in ('', 'casa')
)
update public.shopping_items
set
  owner_member_id = matched.member_id,
  owner_label = matched.member_name
from matched
where shopping_items.id = matched.row_id
  and matched.member_id is not null;

alter table public.shopping_items enable trigger shopping_items_set_updated_at;
alter table public.tasks enable trigger tasks_bump_version;
alter table public.tasks enable trigger tasks_set_updated_at;

create or replace function private.nina_weekly_metrics(target_family_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with bounds as (
    select
      (current_date - 7) as period_start,
      current_date as period_end
  ),
  task_metrics as (
    select
      count(*) filter (where created_at >= now() - interval '7 days')::integer as tasks_created,
      count(*) filter (
        where updated_at >= now() - interval '7 days'
          and is_done
      )::integer as tasks_completed,
      count(*) filter (where not is_done)::integer as tasks_open,
      count(*) filter (
        where created_at >= now() - interval '7 days'
          and due_at is not null
      )::integer as scheduled_task_events
    from public.tasks
    where family_id = target_family_id
  ),
  household_people as (
    select
      members.id,
      case
        when count(*) over (partition by members.name) = 1 then members.name
        else members.name
          || ' · '
          || coalesce(
               nullif(trim(members.relationship), ''),
               (
                 row_number() over (
                   partition by members.name
                   order by members.created_at, members.id
                 )
               )::text
             )
      end as display_key
    from public.family_members as members
    where members.family_id = target_family_id
      and members.household_role <> 'assistant'
  ),
  owner_metrics as (
    select coalesce(
      jsonb_object_agg(open_counts.display_key, open_counts.owner_count),
      '{}'::jsonb
    ) as open_tasks_by_owner
    from (
      select
        keyed.display_key,
        count(*)::integer as owner_count
      from (
        select coalesce(
          household_people.display_key,
          nullif(trim(open_tasks.owner_label), ''),
          'Casa'
        ) as display_key
        from public.tasks as open_tasks
        left join household_people
          on household_people.id = open_tasks.owner_member_id
        where open_tasks.family_id = target_family_id
          and not open_tasks.is_done
      ) as keyed
      group by keyed.display_key
    ) as open_counts
  ),
  other_metrics as (
    select
      (
        select count(*)::integer
        from public.shopping_items
        where family_id = target_family_id
          and created_at >= now() - interval '7 days'
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

comment on function private.nina_weekly_metrics(uuid) is
  'Workload is counted per member id and only then given a display name, so a rename no longer splits one person into two buckets and a departed member no longer holds one. Two members sharing a name are separated by relationship, because a single merged bucket would show a couple a number that belongs to someone else.';

revoke all on function private.nina_weekly_metrics(uuid)
  from public, anon, authenticated, service_role;

commit;
