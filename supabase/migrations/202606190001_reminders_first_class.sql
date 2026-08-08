alter table public.reminders
  add column if not exists recurrence_rule text not null default 'none',
  add column if not exists snoozed_until timestamptz;

alter table public.reminders
  drop constraint if exists reminders_recurrence_rule_check;

alter table public.reminders
  add constraint reminders_recurrence_rule_check
  check (recurrence_rule in ('none', 'daily', 'weekly', 'monthly', 'yearly'));

create index if not exists reminders_family_due_at_idx
  on public.reminders(family_id, due_at)
  where due_at is not null;

create index if not exists reminders_family_snoozed_until_idx
  on public.reminders(family_id, snoozed_until)
  where snoozed_until is not null;
