alter table public.tasks
  add column if not exists task_kind text not null default 'task';

alter table public.tasks
  drop constraint if exists tasks_task_kind_check;

alter table public.tasks
  add constraint tasks_task_kind_check
  check (task_kind in ('task', 'seed'));

create index if not exists tasks_family_open_seeds_idx
  on public.tasks(family_id, created_at desc)
  where task_kind = 'seed' and not is_done;
