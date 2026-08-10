begin;

alter table public.tasks
  add column if not exists completed_at timestamptz,
  add column if not exists archived_at timestamptz;

comment on column public.tasks.completed_at is
  'When the task actually became done. Decided by the is_done transition alone and never accepted from a client write, so a long-finished task that gets edited does not read as work done this week.';

comment on column public.tasks.archived_at is
  'When retention moved the task out of the active list. Household history belongs to the family, so a finished task leaves the list by being stamped here and never by being deleted.';

create or replace function public.stamp_task_completion()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'INSERT' then
    if not new.is_done then
      new.completed_at := null;
    elsif new.completed_at is null then
      new.completed_at := now();
    end if;

    return new;
  end if;

  if new.is_done and not old.is_done then
    new.completed_at := now();
  elsif old.is_done and not new.is_done then
    -- Re-opening returns a task to the household, so it must not stay archived
    -- and invisible to every client.
    new.completed_at := null;
    new.archived_at := null;
  else
    new.completed_at := old.completed_at;
  end if;

  return new;
end;
$$;

comment on function public.stamp_task_completion() is
  'Only a genuine is_done transition writes completed_at, and a later write cannot move it. A recurring task rolls due_at forward without flipping is_done, so it is never stamped, and a client cannot forge the timestamp that decides when retention archives the row.';

drop trigger if exists tasks_stamp_completion on public.tasks;
create trigger tasks_stamp_completion
  before insert or update on public.tasks
  for each row execute function public.stamp_task_completion();

revoke all on function public.stamp_task_completion()
  from public, anon, authenticated, service_role;

-- The real completion moment was never recorded, so the last write to a done
-- row is the closest evidence there is. The timestamp, version and completion
-- triggers stay off so the backfill neither overwrites the evidence it reads
-- nor reports seven weeks of history as activity from today.
alter table public.tasks disable trigger tasks_set_updated_at;
alter table public.tasks disable trigger tasks_bump_version;
alter table public.tasks disable trigger tasks_stamp_completion;

update public.tasks
set completed_at = updated_at
where is_done
  and completed_at is null;

alter table public.tasks enable trigger tasks_stamp_completion;
alter table public.tasks enable trigger tasks_bump_version;
alter table public.tasks enable trigger tasks_set_updated_at;

create index if not exists tasks_family_unarchived_idx
  on public.tasks(family_id, archived_at)
  where archived_at is null;

create or replace function public.run_nina_retention()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  deleted_messages integer;
  deleted_proposals integer;
  deleted_runs integer;
  deleted_insights integer;
  archived_tasks integer;
begin
  update public.nina_proposals
  set
    state = 'rejected',
    resolved_at = now(),
    resolved_payload = jsonb_build_object('reason', 'expired')
  where state = 'pending'
    and created_at < now() - interval '30 days';

  delete from public.chat_messages
  where coalesce(retained_until, created_at + interval '30 days') < now();
  get diagnostics deleted_messages = row_count;

  delete from public.nina_proposals
  where state <> 'pending'
    and resolved_at < now() - interval '30 days';
  get diagnostics deleted_proposals = row_count;

  delete from public.nina_ai_runs
  where created_at < now() - interval '90 days';
  get diagnostics deleted_runs = row_count;

  delete from public.household_insights
  where coalesce(expires_at, created_at + interval '90 days') < now();
  get diagnostics deleted_insights = row_count;

  -- Thirty days sits well clear of the seven the weekly insight reads back, so
  -- bounding the list can never starve the metric it is measured from.
  update public.tasks
  set archived_at = now()
  where archived_at is null
    and is_done
    and completed_at < now() - interval '30 days';
  get diagnostics archived_tasks = row_count;

  return jsonb_build_object(
    'messages', deleted_messages,
    'proposals', deleted_proposals,
    'runs', deleted_runs,
    'insights', deleted_insights,
    'archived_tasks', archived_tasks
  );
end;
$$;

comment on function public.run_nina_retention() is
  'Daily retention. Every step here deletes except the task step, which archives: chat, proposals and operational logs are byproducts of running Nina, while a finished task is household history the family may still want to read back.';

revoke all on function public.run_nina_retention()
  from public, anon, authenticated, service_role;
grant execute on function public.run_nina_retention() to service_role;

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
        where is_done
          and completed_at >= now() - interval '7 days'
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
  'Workload is counted per member id and only then given a display name, so a rename no longer splits one person into two buckets and a departed member no longer holds one. Two members sharing a name are separated by relationship, because a single merged bucket would show a couple a number that belongs to someone else. Completions are counted from completed_at, so editing or archiving a long-finished task never books it as work done this week.';

revoke all on function private.nina_weekly_metrics(uuid)
  from public, anon, authenticated, service_role;

commit;
