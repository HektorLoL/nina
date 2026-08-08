create or replace function public.delete_task_section(
  target_family_id uuid,
  target_section_id text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if target_section_id = 'house-tasks' then
    raise exception 'default_task_section_cannot_be_deleted'
      using errcode = '22023';
  end if;

  if not public.is_family_member(target_family_id) then
    raise exception 'family_access_denied'
      using errcode = '42501';
  end if;

  update public.tasks
  set section_id = 'house-tasks'
  where family_id = target_family_id
    and section_id = target_section_id;

  delete from public.task_sections
  where family_id = target_family_id
    and id = target_section_id;

  if not found then
    raise exception 'task_section_not_found'
      using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.delete_task_section(uuid, text) from public;
grant execute on function public.delete_task_section(uuid, text) to authenticated;

alter table public.task_sections replica identity full;

do $$
begin
  alter publication supabase_realtime add table public.task_sections;
exception
  when duplicate_object then null;
end;
$$;
