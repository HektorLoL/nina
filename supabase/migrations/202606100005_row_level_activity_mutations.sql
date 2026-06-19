revoke all
  on public.task_sections,
     public.task_categories,
     public.tasks,
     public.shopping_items,
     public.reminders,
     public.chat_messages,
     public.household_insights
  from public, anon;

grant select, insert, update, delete
  on public.task_sections,
     public.task_categories,
     public.tasks,
     public.shopping_items,
     public.reminders,
     public.chat_messages,
     public.household_insights
  to authenticated;

revoke all
  on public.family_snapshots
  from public, anon;

revoke insert, update, delete
  on public.family_snapshots
  from authenticated;

grant select
  on public.family_snapshots
  to authenticated;
