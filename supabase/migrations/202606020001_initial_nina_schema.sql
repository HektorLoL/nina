create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  email text,
  sex text not null default 'notDetermined',
  household_role text not null default 'responsibleAdult',
  phone text not null default '',
  birthday_label text not null default '',
  availability_note text not null default '',
  communication_preference text not null default 'gentle',
  memory_note text not null default '',
  avatar jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  invite_code text not null unique check (length(trim(invite_code)) >= 4),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.family_members (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  relationship text not null default '',
  household_role text not null check (household_role in ('adult', 'child', 'pet', 'assistant')),
  permission_role text not null default 'member' check (permission_role in ('owner', 'admin', 'member')),
  tone text not null default 'mint',
  task_count integer not null default 0,
  memory_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index family_members_family_user_unique
  on public.family_members(family_id, user_id)
  where user_id is not null;

create table public.task_sections (
  family_id uuid not null references public.families(id) on delete cascade,
  id text not null,
  title text not null,
  symbol_name text not null default 'list.bullet.rectangle.fill',
  tone text not null default 'mint',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (family_id, id)
);

create table public.task_categories (
  family_id uuid not null references public.families(id) on delete cascade,
  id text not null,
  title text not null,
  symbol_name text not null default 'tag.fill',
  tone text not null default 'mint',
  is_custom boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (family_id, id)
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  section_id text not null default 'house-tasks',
  title text not null check (length(trim(title)) > 0),
  subtitle text not null default '',
  owner_member_id uuid references public.family_members(id) on delete set null,
  owner_label text not null default 'Casa',
  due_label text not null default 'Sem data',
  category_id text not null default 'home',
  category_snapshot jsonb not null default '{}'::jsonb,
  priority text not null default 'normal' check (priority in ('normal', 'high', 'urgent')),
  is_done boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_by_label text not null default 'Manual',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.shopping_items (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  amount text not null default '',
  owner_member_id uuid references public.family_members(id) on delete set null,
  owner_label text not null default 'Casa',
  is_checked boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.reminders (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  detail text not null default '',
  date_label text not null default '',
  symbol_name text not null default 'bell.fill',
  tone text not null default 'mint',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  sender text not null check (sender in ('user', 'nina')),
  text text not null,
  suggestion jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.memory_items (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  subject_member_id uuid references public.family_members(id) on delete cascade,
  title text not null,
  body text not null default '',
  source text not null default 'manual',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.household_insights (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  title text not null,
  message text not null default '',
  metric text not null default '',
  symbol_name text not null default 'chart.bar.fill',
  tone text not null default 'mint',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.family_snapshots (
  family_id uuid primary key references public.families(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.is_family_member(target_family_id uuid, target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select target_user_id is not null and exists (
    select 1
    from public.family_members
    where family_id = target_family_id
      and user_id = target_user_id
  );
$$;

create or replace function public.can_manage_family(target_family_id uuid, target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select target_user_id is not null and exists (
    select 1
    from public.family_members
    where family_id = target_family_id
      and user_id = target_user_id
      and permission_role in ('owner', 'admin')
  );
$$;

create or replace function public.is_family_creator(target_family_id uuid, target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select target_user_id is not null and exists (
    select 1
    from public.families
    where id = target_family_id
      and created_by = target_user_id
  );
$$;

create or replace function public.shares_family_with(other_user_id uuid, target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select target_user_id is not null
    and other_user_id is not null
    and exists (
      select 1
      from public.family_members mine
      join public.family_members theirs on theirs.family_id = mine.family_id
      where mine.user_id = target_user_id
        and theirs.user_id = other_user_id
    );
$$;

create or replace function public.join_family_by_invite(invite_code text, display_name text default null)
returns public.families
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized_code text := lower(trim(invite_code));
  target_family public.families%rowtype;
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select *
  into target_family
  from public.families
  where families.invite_code = normalized_code;

  if not found then
    raise exception 'invalid_invite_code' using errcode = 'P0001';
  end if;

  insert into public.family_members (
    family_id,
    user_id,
    name,
    relationship,
    household_role,
    permission_role,
    tone,
    memory_note
  )
  values (
    target_family.id,
    current_user_id,
    coalesce(nullif(trim(display_name), ''), 'Você'),
    'Você',
    'adult',
    'member',
    'sky',
    'Participante desta casa.'
  )
  on conflict (family_id, user_id) where user_id is not null
  do update set updated_at = now();

  return target_family;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger families_set_updated_at
  before update on public.families
  for each row execute function public.set_updated_at();

create trigger family_members_set_updated_at
  before update on public.family_members
  for each row execute function public.set_updated_at();

create trigger task_sections_set_updated_at
  before update on public.task_sections
  for each row execute function public.set_updated_at();

create trigger task_categories_set_updated_at
  before update on public.task_categories
  for each row execute function public.set_updated_at();

create trigger tasks_set_updated_at
  before update on public.tasks
  for each row execute function public.set_updated_at();

create trigger shopping_items_set_updated_at
  before update on public.shopping_items
  for each row execute function public.set_updated_at();

create trigger reminders_set_updated_at
  before update on public.reminders
  for each row execute function public.set_updated_at();

create trigger memory_items_set_updated_at
  before update on public.memory_items
  for each row execute function public.set_updated_at();

create trigger household_insights_set_updated_at
  before update on public.household_insights
  for each row execute function public.set_updated_at();

create trigger family_snapshots_set_updated_at
  before update on public.family_snapshots
  for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.task_sections enable row level security;
alter table public.task_categories enable row level security;
alter table public.tasks enable row level security;
alter table public.shopping_items enable row level security;
alter table public.reminders enable row level security;
alter table public.chat_messages enable row level security;
alter table public.memory_items enable row level security;
alter table public.household_insights enable row level security;
alter table public.family_snapshots enable row level security;

create policy "Profiles are visible to self and family"
  on public.profiles for select
  to authenticated
  using (id = (select auth.uid()) or public.shares_family_with(id));

create policy "Users can insert own profile"
  on public.profiles for insert
  to authenticated
  with check (id = (select auth.uid()));

create policy "Users can update own profile"
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy "Family members can view families"
  on public.families for select
  to authenticated
  using (public.is_family_member(id));

create policy "Authenticated users can create families"
  on public.families for insert
  to authenticated
  with check (created_by = (select auth.uid()));

create policy "Family managers can update families"
  on public.families for update
  to authenticated
  using (public.can_manage_family(id))
  with check (public.can_manage_family(id));

create policy "Family owners can delete families"
  on public.families for delete
  to authenticated
  using (public.can_manage_family(id));

create policy "Family members can view memberships"
  on public.family_members for select
  to authenticated
  using (public.is_family_member(family_id));

create policy "Creators can add their first membership"
  on public.family_members for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and public.is_family_creator(family_id)
  );

create policy "Family managers can add memberships"
  on public.family_members for insert
  to authenticated
  with check (public.can_manage_family(family_id));

create policy "Family managers and users can update memberships"
  on public.family_members for update
  to authenticated
  using (public.can_manage_family(family_id) or user_id = (select auth.uid()))
  with check (public.can_manage_family(family_id) or user_id = (select auth.uid()));

create policy "Family managers can delete memberships"
  on public.family_members for delete
  to authenticated
  using (public.can_manage_family(family_id));

create policy "Task sections are family scoped"
  on public.task_sections for all
  to authenticated
  using (public.is_family_member(family_id))
  with check (public.is_family_member(family_id));

create policy "Task categories are family scoped"
  on public.task_categories for all
  to authenticated
  using (public.is_family_member(family_id))
  with check (public.is_family_member(family_id));

create policy "Tasks are family scoped"
  on public.tasks for all
  to authenticated
  using (public.is_family_member(family_id))
  with check (public.is_family_member(family_id));

create policy "Shopping items are family scoped"
  on public.shopping_items for all
  to authenticated
  using (public.is_family_member(family_id))
  with check (public.is_family_member(family_id));

create policy "Reminders are family scoped"
  on public.reminders for all
  to authenticated
  using (public.is_family_member(family_id))
  with check (public.is_family_member(family_id));

create policy "Chat messages are family scoped"
  on public.chat_messages for all
  to authenticated
  using (public.is_family_member(family_id))
  with check (public.is_family_member(family_id));

create policy "Memory items are family scoped"
  on public.memory_items for all
  to authenticated
  using (public.is_family_member(family_id))
  with check (public.is_family_member(family_id));

create policy "Household insights are family scoped"
  on public.household_insights for all
  to authenticated
  using (public.is_family_member(family_id))
  with check (public.is_family_member(family_id));

create policy "Family snapshots are family scoped"
  on public.family_snapshots for all
  to authenticated
  using (public.is_family_member(family_id))
  with check (public.is_family_member(family_id));
