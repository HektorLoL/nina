alter table public.tasks
  add column if not exists version bigint not null default 1;

create or replace function public.bump_task_version()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.version = old.version + 1;
  return new;
end;
$$;

drop trigger if exists tasks_bump_version on public.tasks;
create trigger tasks_bump_version
  before update on public.tasks
  for each row execute function public.bump_task_version();

alter table public.tasks replica identity full;
alter table public.shopping_items replica identity full;
alter table public.reminders replica identity full;
alter table public.chat_messages replica identity full;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'tasks',
    'shopping_items',
    'reminders',
    'chat_messages'
  ]
  loop
    begin
      execute format(
        'alter publication supabase_realtime add table public.%I',
        table_name
      );
    exception
      when duplicate_object then null;
    end;
  end loop;
end;
$$;
