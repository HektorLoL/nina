begin;

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table private.nina_maintenance_config (
  singleton boolean primary key default true check (singleton),
  project_url text,
  shared_secret text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into private.nina_maintenance_config (
  singleton,
  project_url,
  shared_secret
)
values (
  true,
  coalesce(
    nullif(current_setting('app.settings.api_url', true), ''),
    'https://apemftmlsjocvifbptum.supabase.co'
  ),
  encode(extensions.gen_random_bytes(32), 'hex')
)
on conflict (singleton) do nothing;

create table public.nina_threads (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  visibility text not null default 'private'
    check (visibility in ('private', 'legacy_shared')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index nina_threads_private_owner_unique
  on public.nina_threads(family_id, owner_user_id)
  where visibility = 'private';

create trigger nina_threads_set_updated_at
  before update on public.nina_threads
  for each row execute function public.set_updated_at();

alter table public.chat_messages
  add column if not exists thread_id uuid references public.nina_threads(id) on delete cascade,
  add column if not exists run_id uuid,
  add column if not exists retained_until timestamptz;

update public.chat_messages
set retained_until = created_at + interval '30 days'
where retained_until is null;

create index chat_messages_private_thread_created_idx
  on public.chat_messages(thread_id, created_at);

alter table public.tasks
  add column if not exists due_at timestamptz;

alter table public.reminders
  add column if not exists due_at timestamptz;

create table public.nina_ai_budget_months (
  month_start date not null,
  purpose text not null check (purpose in ('interactive', 'insights')),
  cap_microusd bigint not null check (cap_microusd >= 0),
  reserved_microusd bigint not null default 0 check (reserved_microusd >= 0),
  spent_microusd bigint not null default 0 check (spent_microusd >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (month_start, purpose),
  constraint nina_ai_budget_within_cap
    check (reserved_microusd + spent_microusd <= cap_microusd)
);

create trigger nina_ai_budget_months_set_updated_at
  before update on public.nina_ai_budget_months
  for each row execute function public.set_updated_at();

create table public.nina_ai_family_rate_limits (
  family_id uuid not null references public.families(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (family_id)
);

create trigger nina_ai_family_rate_limits_set_updated_at
  before update on public.nina_ai_family_rate_limits
  for each row execute function public.set_updated_at();

create table public.nina_ai_runs (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  thread_id uuid references public.nina_threads(id) on delete set null,
  request_message_id uuid unique references public.chat_messages(id) on delete set null,
  response_message_id uuid unique references public.chat_messages(id) on delete set null,
  purpose text not null check (purpose in ('interactive', 'insights')),
  model text not null,
  status text not null default 'reserved'
    check (status in ('reserved', 'running', 'completed', 'failed', 'rejected')),
  pricing_version date not null,
  reserved_microusd bigint not null default 0 check (reserved_microusd >= 0),
  actual_microusd bigint check (actual_microusd is null or actual_microusd >= 0),
  input_tokens integer check (input_tokens is null or input_tokens >= 0),
  cached_input_tokens integer check (cached_input_tokens is null or cached_input_tokens >= 0),
  output_tokens integer check (output_tokens is null or output_tokens >= 0),
  reasoning_tokens integer check (reasoning_tokens is null or reasoning_tokens >= 0),
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index nina_ai_runs_family_created_idx
  on public.nina_ai_runs(family_id, created_at desc);

create trigger nina_ai_runs_set_updated_at
  before update on public.nina_ai_runs
  for each row execute function public.set_updated_at();

alter table public.chat_messages
  add constraint chat_messages_run_id_fkey
  foreign key (run_id) references public.nina_ai_runs(id) on delete set null;

alter table public.memory_items
  add column if not exists visibility text not null default 'shared'
    check (visibility in ('private', 'shared')),
  add column if not exists owner_user_id uuid references auth.users(id) on delete cascade,
  add column if not exists status text not null default 'confirmed'
    check (status in ('pending', 'confirmed', 'dismissed')),
  add column if not exists confidence numeric(4, 3)
    check (confidence is null or confidence between 0 and 1),
  add column if not exists source_run_id uuid references public.nina_ai_runs(id) on delete set null,
  add column if not exists deduplication_key text,
  add column if not exists confirmed_at timestamptz,
  add column if not exists confirmed_by uuid references auth.users(id) on delete set null;

update public.memory_items
set
  visibility = 'shared',
  status = 'confirmed',
  confirmed_at = coalesce(confirmed_at, created_at),
  confirmed_by = coalesce(confirmed_by, created_by)
where status = 'confirmed';

create unique index memory_items_owner_dedup_unique
  on public.memory_items(family_id, owner_user_id, visibility, deduplication_key)
  where status = 'confirmed' and deduplication_key is not null;

create table public.nina_proposals (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  thread_id uuid references public.nina_threads(id) on delete cascade,
  run_id uuid references public.nina_ai_runs(id) on delete set null,
  assistant_message_id uuid references public.chat_messages(id) on delete set null,
  kind text not null check (kind in ('task', 'reminder', 'shopping', 'memory')),
  state text not null default 'pending'
    check (state in ('pending', 'accepted', 'rejected')),
  title text not null check (length(trim(title)) > 0),
  detail text not null default '',
  action_title text not null default 'Confirmar',
  payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(payload) = 'object'),
  allowed_memory_visibilities text[] not null default array[]::text[],
  resolved_payload jsonb,
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index nina_proposals_owner_state_created_idx
  on public.nina_proposals(owner_user_id, state, created_at desc);

create trigger nina_proposals_set_updated_at
  before update on public.nina_proposals
  for each row execute function public.set_updated_at();

alter table public.household_insights
  add column if not exists period_start date,
  add column if not exists period_end date,
  add column if not exists source_run_id uuid references public.nina_ai_runs(id) on delete set null,
  add column if not exists expires_at timestamptz;

update public.household_insights
set expires_at = coalesce(expires_at, created_at + interval '90 days')
where expires_at is null;

create unique index household_insights_weekly_unique
  on public.household_insights(family_id, period_start, title)
  where period_start is not null;

alter table public.nina_threads enable row level security;
alter table public.nina_ai_budget_months enable row level security;
alter table public.nina_ai_family_rate_limits enable row level security;
alter table public.nina_ai_runs enable row level security;
alter table public.nina_proposals enable row level security;

drop policy if exists "Chat messages are family scoped" on public.chat_messages;
drop policy if exists "Memory items are family scoped" on public.memory_items;

create policy "Nina threads are owner scoped"
  on public.nina_threads for select
  to authenticated
  using (
    owner_user_id = (select auth.uid())
    and public.is_family_member(family_id)
  );

create policy "Private Nina messages are owner scoped"
  on public.chat_messages for select
  to authenticated
  using (
    (
      thread_id is null
      and public.is_family_member(family_id)
    )
    or exists (
      select 1
      from public.nina_threads
      where nina_threads.id = chat_messages.thread_id
        and nina_threads.owner_user_id = (select auth.uid())
        and public.is_family_member(nina_threads.family_id)
    )
  );

create policy "Legacy chat messages remain family writable"
  on public.chat_messages for all
  to authenticated
  using (
    thread_id is null
    and public.is_family_member(family_id)
  )
  with check (
    thread_id is null
    and public.is_family_member(family_id)
  );

create policy "Confirmed Nina memories respect visibility"
  on public.memory_items for select
  to authenticated
  using (
    status = 'confirmed'
    and public.is_family_member(family_id)
    and (
      visibility = 'shared'
      or owner_user_id = (select auth.uid())
    )
  );

create policy "Memory owners can update confirmed memories"
  on public.memory_items for update
  to authenticated
  using (
    owner_user_id = (select auth.uid())
    and public.is_family_member(family_id)
  )
  with check (
    owner_user_id = (select auth.uid())
    and public.is_family_member(family_id)
    and status = 'confirmed'
  );

create policy "Memory owners can delete confirmed memories"
  on public.memory_items for delete
  to authenticated
  using (
    owner_user_id = (select auth.uid())
    and public.is_family_member(family_id)
  );

create policy "Nina proposals are owner readable"
  on public.nina_proposals for select
  to authenticated
  using (
    owner_user_id = (select auth.uid())
    and public.is_family_member(family_id)
  );

revoke all
  on public.nina_threads,
     public.nina_ai_budget_months,
     public.nina_ai_family_rate_limits,
     public.nina_ai_runs,
     public.nina_proposals
  from public, anon, authenticated;

grant select on public.nina_threads, public.nina_proposals to authenticated;
grant select, update, delete on public.memory_items to authenticated;

create or replace function private.current_month_start()
returns date
language sql
stable
set search_path = pg_catalog
as $$
  select date_trunc('month', now())::date;
$$;

create or replace function private.claim_nina_family_request(
  target_family_id uuid,
  max_requests integer default 100,
  window_seconds integer default 86400
)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_count integer;
begin
  if auth.uid() is null
     or max_requests < 1
     or window_seconds < 1
     or not public.is_family_member(target_family_id) then
    return false;
  end if;

  insert into public.nina_ai_family_rate_limits (
    family_id,
    window_started_at,
    request_count
  )
  values (
    target_family_id,
    now(),
    1
  )
  on conflict (family_id) do update
  set
    window_started_at = case
      when now() >= nina_ai_family_rate_limits.window_started_at + make_interval(secs => window_seconds)
        then now()
      else nina_ai_family_rate_limits.window_started_at
    end,
    request_count = case
      when now() >= nina_ai_family_rate_limits.window_started_at + make_interval(secs => window_seconds)
        then 1
      else least(nina_ai_family_rate_limits.request_count + 1, max_requests + 1)
    end
  returning request_count into current_count;

  return current_count <= max_requests;
end;
$$;

create or replace function public.begin_nina_chat_run(
  target_family_id uuid,
  client_message_id uuid,
  message_text text,
  attachment_metadata jsonb,
  requested_model text,
  reserved_cost_microusd bigint,
  pricing_version date
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  target_thread_id uuid;
  target_run public.nina_ai_runs%rowtype;
  current_month date := private.current_month_start();
  budget_cap bigint := 20000000;
  user_allowed boolean;
  family_allowed boolean;
  normalized_text text := trim(message_text);
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if reserved_cost_microusd < 0 or reserved_cost_microusd > 250000 then
    raise exception 'invalid_cost_reservation' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.family_members
    where family_id = target_family_id
      and user_id = current_user_id
      and household_role = 'adult'
  ) then
    raise exception 'nina_adult_access_required' using errcode = '42501';
  end if;

  select *
  into target_run
  from public.nina_ai_runs
  where request_message_id = client_message_id;

  if found then
    if target_run.family_id <> target_family_id
       or target_run.user_id <> current_user_id then
      raise exception 'message_id_conflict' using errcode = '23505';
    end if;

    return jsonb_build_object(
      'idempotent', true,
      'run_id', target_run.id,
      'thread_id', target_run.thread_id,
      'status', target_run.status
    );
  end if;

  select public.claim_nina_chat_request(30, 3600) into user_allowed;
  select private.claim_nina_family_request(target_family_id, 100, 86400) into family_allowed;

  if not user_allowed or not family_allowed then
    raise exception 'nina_rate_limited' using errcode = 'P0001';
  end if;

  insert into public.nina_ai_budget_months (
    month_start,
    purpose,
    cap_microusd
  )
  values (
    current_month,
    'interactive',
    budget_cap
  )
  on conflict (month_start, purpose) do nothing;

  update public.nina_ai_budget_months
  set reserved_microusd = reserved_microusd + reserved_cost_microusd
  where month_start = current_month
    and purpose = 'interactive'
    and spent_microusd + reserved_microusd + reserved_cost_microusd <= cap_microusd;

  if not found then
    raise exception 'nina_budget_exceeded' using errcode = 'P0001';
  end if;

  insert into public.nina_threads (
    family_id,
    owner_user_id,
    visibility
  )
  values (
    target_family_id,
    current_user_id,
    'private'
  )
  on conflict (family_id, owner_user_id) where visibility = 'private'
  do update set updated_at = now()
  returning id into target_thread_id;

  insert into public.chat_messages (
    id,
    family_id,
    thread_id,
    sender,
    text,
    attachments,
    created_by,
    retained_until
  )
  values (
    client_message_id,
    target_family_id,
    target_thread_id,
    'user',
    normalized_text,
    coalesce(attachment_metadata, '[]'::jsonb),
    current_user_id,
    now() + interval '30 days'
  );

  insert into public.nina_ai_runs (
    family_id,
    user_id,
    thread_id,
    request_message_id,
    purpose,
    model,
    status,
    pricing_version,
    reserved_microusd
  )
  values (
    target_family_id,
    current_user_id,
    target_thread_id,
    client_message_id,
    'interactive',
    requested_model,
    'running',
    pricing_version,
    reserved_cost_microusd
  )
  returning * into target_run;

  update public.chat_messages
  set run_id = target_run.id
  where id = client_message_id;

  return jsonb_build_object(
    'idempotent', false,
    'run_id', target_run.id,
    'thread_id', target_thread_id,
    'status', target_run.status
  );
end;
$$;

create or replace function public.complete_nina_chat_run(
  target_run_id uuid,
  assistant_message_id uuid,
  assistant_reply text,
  proposals jsonb,
  usage_input_tokens integer,
  usage_cached_input_tokens integer,
  usage_output_tokens integer,
  usage_reasoning_tokens integer,
  actual_cost_microusd bigint,
  request_latency_ms integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare
  target_run public.nina_ai_runs%rowtype;
  proposal jsonb;
begin
  select *
  into target_run
  from public.nina_ai_runs
  where id = target_run_id
  for update;

  if not found then
    raise exception 'nina_run_not_found' using errcode = 'P0002';
  end if;

  if target_run.status = 'completed' then
    return public.get_nina_chat_result(target_run_id);
  end if;

  if target_run.status not in ('reserved', 'running') then
    raise exception 'nina_run_not_completable' using errcode = 'P0001';
  end if;

  insert into public.chat_messages (
    id,
    family_id,
    thread_id,
    run_id,
    sender,
    text,
    attachments,
    retained_until
  )
  values (
    assistant_message_id,
    target_run.family_id,
    target_run.thread_id,
    target_run.id,
    'nina',
    trim(assistant_reply),
    '[]'::jsonb,
    now() + interval '30 days'
  );

  if jsonb_typeof(coalesce(proposals, '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_nina_proposals' using errcode = '22023';
  end if;

  for proposal in
    select value
    from jsonb_array_elements(coalesce(proposals, '[]'::jsonb))
    limit 3
  loop
    insert into public.nina_proposals (
      id,
      family_id,
      owner_user_id,
      thread_id,
      run_id,
      assistant_message_id,
      kind,
      title,
      detail,
      action_title,
      payload,
      allowed_memory_visibilities
    )
    values (
      coalesce((proposal ->> 'id')::uuid, gen_random_uuid()),
      target_run.family_id,
      target_run.user_id,
      target_run.thread_id,
      target_run.id,
      assistant_message_id,
      proposal ->> 'kind',
      proposal ->> 'title',
      coalesce(proposal ->> 'detail', ''),
      coalesce(proposal ->> 'action_title', 'Confirmar'),
      coalesce(proposal -> 'payload', '{}'::jsonb),
      case
        when proposal ->> 'kind' = 'memory'
          then array['private', 'shared']::text[]
        else array[]::text[]
      end
    );
  end loop;

  update public.nina_ai_budget_months
  set
    reserved_microusd = greatest(reserved_microusd - target_run.reserved_microusd, 0),
    spent_microusd = spent_microusd + greatest(actual_cost_microusd, 0)
  where month_start = private.current_month_start()
    and purpose = target_run.purpose;

  update public.nina_ai_runs
  set
    response_message_id = assistant_message_id,
    status = 'completed',
    actual_microusd = greatest(actual_cost_microusd, 0),
    input_tokens = greatest(usage_input_tokens, 0),
    cached_input_tokens = greatest(usage_cached_input_tokens, 0),
    output_tokens = greatest(usage_output_tokens, 0),
    reasoning_tokens = greatest(usage_reasoning_tokens, 0),
    latency_ms = greatest(request_latency_ms, 0),
    completed_at = now()
  where id = target_run.id;

  return public.get_nina_chat_result(target_run.id);
end;
$$;

create or replace function public.fail_nina_ai_run(
  target_run_id uuid,
  failure_code text,
  request_latency_ms integer default null
)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  target_run public.nina_ai_runs%rowtype;
begin
  select *
  into target_run
  from public.nina_ai_runs
  where id = target_run_id
  for update;

  if not found or target_run.status not in ('reserved', 'running') then
    return;
  end if;

  update public.nina_ai_budget_months
  set reserved_microusd = greatest(reserved_microusd - target_run.reserved_microusd, 0)
  where month_start = private.current_month_start()
    and purpose = target_run.purpose;

  update public.nina_ai_runs
  set
    status = 'failed',
    error_code = left(coalesce(failure_code, 'unknown_error'), 120),
    latency_ms = case
      when request_latency_ms is null then latency_ms
      else greatest(request_latency_ms, 0)
    end,
    completed_at = now()
  where id = target_run.id;
end;
$$;

create or replace function public.get_nina_chat_result(target_run_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  target_run public.nina_ai_runs%rowtype;
  target_reply text;
  target_message_id uuid;
  proposal_rows jsonb;
begin
  select *
  into target_run
  from public.nina_ai_runs
  where id = target_run_id;

  if not found then
    raise exception 'nina_run_not_found' using errcode = 'P0002';
  end if;

  if auth.uid() is not null
     and target_run.user_id <> auth.uid() then
    raise exception 'nina_run_access_denied' using errcode = '42501';
  end if;

  select id, text
  into target_message_id, target_reply
  from public.chat_messages
  where id = target_run.response_message_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', nina_proposals.id,
        'kind', nina_proposals.kind,
        'state', nina_proposals.state,
        'title', nina_proposals.title,
        'detail', nina_proposals.detail,
        'action_title', nina_proposals.action_title,
        'payload', nina_proposals.payload,
        'allowed_memory_visibilities', nina_proposals.allowed_memory_visibilities,
        'resolved_payload', nina_proposals.resolved_payload
      )
      order by nina_proposals.created_at
    ),
    '[]'::jsonb
  )
  into proposal_rows
  from public.nina_proposals
  where run_id = target_run.id;

  return jsonb_build_object(
    'version', 2,
    'run_id', target_run.id,
    'thread_id', target_run.thread_id,
    'status', target_run.status,
    'reply', target_reply,
    'assistant_message_id', target_message_id,
    'proposals', proposal_rows
  );
end;
$$;

create or replace function public.get_current_nina_state(target_family_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  target_thread_id uuid;
begin
  if current_user_id is null
     or not public.is_family_member(target_family_id) then
    raise exception 'family_access_denied' using errcode = '42501';
  end if;

  select id
  into target_thread_id
  from public.nina_threads
  where family_id = target_family_id
    and owner_user_id = current_user_id
    and visibility = 'private';

  return jsonb_build_object(
    'thread', case
      when target_thread_id is null then null
      else jsonb_build_object(
        'id', target_thread_id,
        'family_id', target_family_id,
        'owner_user_id', current_user_id
      )
    end,
    'messages', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', messages.id,
            'sender', messages.sender,
            'text', messages.text,
            'suggestion', messages.suggestion,
            'attachments', messages.attachments,
            'created_at', messages.created_at,
            'proposals', coalesce(
              (
                select jsonb_agg(
                  jsonb_build_object(
                    'id', proposals.id,
                    'kind', proposals.kind,
                    'state', proposals.state,
                    'title', proposals.title,
                    'detail', proposals.detail,
                    'action_title', proposals.action_title,
                    'payload', proposals.payload,
                    'allowed_memory_visibilities', proposals.allowed_memory_visibilities,
                    'resolved_payload', proposals.resolved_payload
                  )
                  order by proposals.created_at
                )
                from public.nina_proposals as proposals
                where proposals.assistant_message_id = messages.id
              ),
              '[]'::jsonb
            )
          )
          order by messages.created_at
        )
        from public.chat_messages as messages
        where messages.thread_id = target_thread_id
      ),
      '[]'::jsonb
    ),
    'memories', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', memories.id,
            'family_id', memories.family_id,
            'owner_user_id', memories.owner_user_id,
            'title', memories.title,
            'body', memories.body,
            'visibility', memories.visibility,
            'confidence', memories.confidence,
            'created_at', memories.created_at,
            'updated_at', memories.updated_at
          )
          order by memories.updated_at desc
        )
        from public.memory_items as memories
        where memories.family_id = target_family_id
          and memories.status = 'confirmed'
          and (
            memories.visibility = 'shared'
            or memories.owner_user_id = current_user_id
          )
      ),
      '[]'::jsonb
    )
  );
end;
$$;

create or replace function public.resolve_nina_proposal(
  target_proposal_id uuid,
  decision text,
  edited_payload jsonb default '{}'::jsonb,
  memory_visibility text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  target_proposal public.nina_proposals%rowtype;
  final_payload jsonb;
  final_title text;
  final_detail text;
  final_owner text;
  final_due_label text;
  final_due_at timestamptz;
  final_category text;
  final_symbol text;
  final_visibility text;
  created_id uuid;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if decision not in ('accept', 'reject') then
    raise exception 'invalid_proposal_decision' using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(edited_payload, '{}'::jsonb)) <> 'object' then
    raise exception 'invalid_proposal_payload' using errcode = '22023';
  end if;

  select *
  into target_proposal
  from public.nina_proposals
  where id = target_proposal_id
  for update;

  if not found then
    raise exception 'nina_proposal_not_found' using errcode = 'P0002';
  end if;

  if target_proposal.owner_user_id <> current_user_id
     or not public.is_family_member(target_proposal.family_id) then
    raise exception 'nina_proposal_access_denied' using errcode = '42501';
  end if;

  if target_proposal.state <> 'pending' then
    return jsonb_build_object(
      'id', target_proposal.id,
      'state', target_proposal.state,
      'resolved_payload', target_proposal.resolved_payload
    );
  end if;

  if decision = 'reject' then
    update public.nina_proposals
    set
      state = 'rejected',
      resolved_at = now(),
      resolved_by = current_user_id,
      resolved_payload = '{}'::jsonb
    where id = target_proposal.id;

    return jsonb_build_object(
      'id', target_proposal.id,
      'state', 'rejected',
      'resolved_payload', '{}'::jsonb
    );
  end if;

  final_payload := target_proposal.payload || coalesce(edited_payload, '{}'::jsonb);
  final_title := coalesce(
    nullif(trim(final_payload ->> 'title'), ''),
    target_proposal.title
  );
  final_detail := coalesce(final_payload ->> 'detail', target_proposal.detail, '');
  final_owner := coalesce(nullif(trim(final_payload ->> 'owner'), ''), 'Casa');
  final_due_label := coalesce(nullif(trim(final_payload ->> 'due_label'), ''), 'Sem data');
  final_category := coalesce(nullif(trim(final_payload ->> 'category'), ''), 'home');
  final_symbol := coalesce(nullif(trim(final_payload ->> 'symbol_name'), ''), 'sparkles');
  final_due_at := case
    when nullif(final_payload ->> 'due_at', '') is null then null
    else (final_payload ->> 'due_at')::timestamptz
  end;

  case target_proposal.kind
    when 'task' then
      insert into public.tasks (
        family_id,
        title,
        subtitle,
        owner_label,
        due_label,
        due_at,
        category_id,
        created_by,
        created_by_label
      )
      values (
        target_proposal.family_id,
        final_title,
        final_detail,
        final_owner,
        final_due_label,
        final_due_at,
        final_category,
        current_user_id,
        'Nina'
      )
      returning id into created_id;
    when 'reminder' then
      insert into public.reminders (
        family_id,
        title,
        detail,
        date_label,
        due_at,
        symbol_name,
        tone,
        created_by
      )
      values (
        target_proposal.family_id,
        final_title,
        final_detail,
        final_due_label,
        final_due_at,
        final_symbol,
        'amber',
        current_user_id
      )
      returning id into created_id;
    when 'shopping' then
      insert into public.shopping_items (
        family_id,
        title,
        amount,
        owner_label,
        created_by
      )
      values (
        target_proposal.family_id,
        final_title,
        coalesce(final_payload ->> 'amount', ''),
        final_owner,
        current_user_id
      )
      returning id into created_id;
    when 'memory' then
      final_visibility := coalesce(memory_visibility, final_payload ->> 'visibility', 'private');
      if final_visibility not in ('private', 'shared') then
        raise exception 'invalid_memory_visibility' using errcode = '22023';
      end if;

      insert into public.memory_items (
        family_id,
        title,
        body,
        source,
        created_by,
        owner_user_id,
        visibility,
        status,
        confidence,
        source_run_id,
        deduplication_key,
        confirmed_at,
        confirmed_by
      )
      values (
        target_proposal.family_id,
        final_title,
        final_detail,
        'nina',
        current_user_id,
        current_user_id,
        final_visibility,
        'confirmed',
        coalesce((final_payload ->> 'confidence')::numeric, 0.7),
        target_proposal.run_id,
        nullif(final_payload ->> 'deduplication_key', ''),
        now(),
        current_user_id
      )
      on conflict (
        family_id,
        owner_user_id,
        visibility,
        deduplication_key
      )
      where status = 'confirmed' and deduplication_key is not null
      do update set
        title = excluded.title,
        body = excluded.body,
        confidence = greatest(memory_items.confidence, excluded.confidence),
        source_run_id = excluded.source_run_id,
        confirmed_at = now(),
        confirmed_by = excluded.confirmed_by
      returning id into created_id;
  end case;

  final_payload := final_payload || jsonb_build_object(
    'created_id', created_id,
    'memory_visibility', final_visibility
  );

  update public.nina_proposals
  set
    state = 'accepted',
    resolved_at = now(),
    resolved_by = current_user_id,
    resolved_payload = final_payload
  where id = target_proposal.id;

  return jsonb_build_object(
    'id', target_proposal.id,
    'state', 'accepted',
    'resolved_payload', final_payload
  );
end;
$$;

create or replace function public.update_nina_memory(
  target_memory_id uuid,
  memory_title text,
  memory_body text,
  memory_visibility text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  updated_memory public.memory_items%rowtype;
begin
  if memory_visibility not in ('private', 'shared') then
    raise exception 'invalid_memory_visibility' using errcode = '22023';
  end if;

  update public.memory_items
  set
    title = coalesce(nullif(trim(memory_title), ''), title),
    body = trim(memory_body),
    visibility = memory_visibility,
    deduplication_key = null
  where id = target_memory_id
    and owner_user_id = current_user_id
    and status = 'confirmed'
    and public.is_family_member(family_id)
  returning * into updated_memory;

  if not found then
    raise exception 'nina_memory_not_found' using errcode = 'P0002';
  end if;

  return to_jsonb(updated_memory);
end;
$$;

create or replace function public.delete_nina_memory(target_memory_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  delete from public.memory_items
  where id = target_memory_id
    and owner_user_id = auth.uid()
    and public.is_family_member(family_id);

  if not found then
    raise exception 'nina_memory_not_found' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.delete_current_nina_chat_history(target_family_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  target_thread_id uuid;
begin
  select id
  into target_thread_id
  from public.nina_threads
  where family_id = target_family_id
    and owner_user_id = current_user_id
    and visibility = 'private';

  if target_thread_id is null then
    return;
  end if;

  delete from public.nina_proposals
  where thread_id = target_thread_id;

  delete from public.chat_messages
  where thread_id = target_thread_id;
end;
$$;

create or replace function private.nina_weekly_metrics(target_family_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
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
      count(*) filter (where not is_done)::integer as tasks_open
    from public.tasks
    where family_id = target_family_id
  ),
  owner_metrics as (
    select coalesce(
      jsonb_object_agg(owner_label, owner_count),
      '{}'::jsonb
    ) as open_tasks_by_owner
    from (
      select
        coalesce(nullif(trim(owner_label), ''), 'Casa') as owner_label,
        count(*)::integer as owner_count
      from public.tasks
      where family_id = target_family_id
        and not is_done
      group by coalesce(nullif(trim(owner_label), ''), 'Casa')
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
        from public.reminders
        where family_id = target_family_id
          and created_at >= now() - interval '7 days'
      ) as reminder_events,
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
    'reminder_events', other_metrics.reminder_events,
    'shared_memory_events', other_metrics.shared_memory_events,
    'relevant_event_count',
      task_metrics.tasks_created
      + task_metrics.tasks_completed
      + other_metrics.shopping_events
      + other_metrics.reminder_events
      + other_metrics.shared_memory_events
  )
  from bounds, task_metrics, owner_metrics, other_metrics;
$$;

create or replace function public.get_nina_weekly_candidates()
returns jsonb
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce(
    jsonb_agg(candidate.metrics),
    '[]'::jsonb
  )
  from (
    select private.nina_weekly_metrics(families.id) as metrics
    from public.families
    where (
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

create or replace function public.reserve_nina_insight_run(
  target_family_id uuid,
  requested_model text,
  reserved_cost_microusd bigint,
  pricing_version date
)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  current_month date := private.current_month_start();
  target_run_id uuid;
begin
  if reserved_cost_microusd < 0 or reserved_cost_microusd > 1000000 then
    raise exception 'invalid_cost_reservation' using errcode = '22023';
  end if;

  insert into public.nina_ai_budget_months (
    month_start,
    purpose,
    cap_microusd
  )
  values (
    current_month,
    'insights',
    5000000
  )
  on conflict (month_start, purpose) do nothing;

  update public.nina_ai_budget_months
  set reserved_microusd = reserved_microusd + reserved_cost_microusd
  where month_start = current_month
    and purpose = 'insights'
    and spent_microusd + reserved_microusd + reserved_cost_microusd <= cap_microusd;

  if not found then
    raise exception 'nina_budget_exceeded' using errcode = 'P0001';
  end if;

  insert into public.nina_ai_runs (
    family_id,
    purpose,
    model,
    status,
    pricing_version,
    reserved_microusd
  )
  values (
    target_family_id,
    'insights',
    requested_model,
    'running',
    pricing_version,
    reserved_cost_microusd
  )
  returning id into target_run_id;

  return target_run_id;
end;
$$;

create or replace function public.complete_nina_insight_run(
  target_run_id uuid,
  insight_rows jsonb,
  usage_input_tokens integer,
  usage_cached_input_tokens integer,
  usage_output_tokens integer,
  usage_reasoning_tokens integer,
  actual_cost_microusd bigint,
  request_latency_ms integer
)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  target_run public.nina_ai_runs%rowtype;
  insight jsonb;
begin
  select *
  into target_run
  from public.nina_ai_runs
  where id = target_run_id
    and purpose = 'insights'
  for update;

  if not found or target_run.status = 'completed' then
    return;
  end if;

  for insight in
    select value from jsonb_array_elements(coalesce(insight_rows, '[]'::jsonb))
    limit 4
  loop
    insert into public.household_insights (
      family_id,
      title,
      message,
      metric,
      symbol_name,
      tone,
      period_start,
      period_end,
      source_run_id,
      expires_at
    )
    values (
      target_run.family_id,
      insight ->> 'title',
      insight ->> 'message',
      insight ->> 'metric',
      coalesce(insight ->> 'symbol_name', 'chart.bar.fill'),
      coalesce(insight ->> 'tone', 'mint'),
      current_date - 7,
      current_date,
      target_run.id,
      now() + interval '90 days'
    )
    on conflict (family_id, period_start, title)
      where period_start is not null
    do update set
      message = excluded.message,
      metric = excluded.metric,
      symbol_name = excluded.symbol_name,
      tone = excluded.tone,
      source_run_id = excluded.source_run_id,
      expires_at = excluded.expires_at,
      updated_at = now();
  end loop;

  update public.nina_ai_budget_months
  set
    reserved_microusd = greatest(reserved_microusd - target_run.reserved_microusd, 0),
    spent_microusd = spent_microusd + greatest(actual_cost_microusd, 0)
  where month_start = private.current_month_start()
    and purpose = 'insights';

  update public.nina_ai_runs
  set
    status = 'completed',
    actual_microusd = greatest(actual_cost_microusd, 0),
    input_tokens = greatest(usage_input_tokens, 0),
    cached_input_tokens = greatest(usage_cached_input_tokens, 0),
    output_tokens = greatest(usage_output_tokens, 0),
    reasoning_tokens = greatest(usage_reasoning_tokens, 0),
    latency_ms = greatest(request_latency_ms, 0),
    completed_at = now()
  where id = target_run.id;
end;
$$;

create or replace function public.run_nina_retention()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_messages integer;
  deleted_proposals integer;
  deleted_runs integer;
  deleted_insights integer;
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

  return jsonb_build_object(
    'messages', deleted_messages,
    'proposals', deleted_proposals,
    'runs', deleted_runs,
    'insights', deleted_insights
  );
end;
$$;

create or replace function public.verify_nina_maintenance_secret(
  candidate_secret text
)
returns boolean
language sql
stable
security definer
set search_path = private
as $$
  select exists (
    select 1
    from private.nina_maintenance_config
    where singleton
      and length(candidate_secret) >= 32
      and shared_secret = candidate_secret
  );
$$;

create or replace function private.invoke_nina_maintenance()
returns void
language plpgsql
security definer
set search_path = public, private, vault, net
as $$
declare
  project_url text;
  maintenance_secret text;
begin
  select
    nina_maintenance_config.project_url,
    nina_maintenance_config.shared_secret
  into
    project_url,
    maintenance_secret
  from private.nina_maintenance_config
  where singleton;

  if project_url is null then
    select decrypted_secret
    into project_url
    from vault.decrypted_secrets
    where name = 'nina_project_url'
    limit 1;
  end if;

  if project_url is null or maintenance_secret is null then
    return;
  end if;

  perform net.http_post(
    url := rtrim(project_url, '/') || '/functions/v1/nina-maintenance',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Nina-Maintenance-Secret', maintenance_secret
    ),
    body := '{}'::jsonb
  );
end;
$$;

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'nina-daily-maintenance'
  ) then
    perform cron.unschedule('nina-daily-maintenance');
  end if;

  perform cron.schedule(
    'nina-daily-maintenance',
    '15 6 * * *',
    'select private.invoke_nina_maintenance()'
  );
end;
$$;

revoke all on function private.claim_nina_family_request(uuid, integer, integer) from public;
revoke all on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date) from public;
revoke all on function public.complete_nina_chat_run(uuid, uuid, text, jsonb, integer, integer, integer, integer, bigint, integer) from public;
revoke all on function public.fail_nina_ai_run(uuid, text, integer) from public;
revoke all on function public.get_nina_chat_result(uuid) from public;
revoke all on function public.get_current_nina_state(uuid) from public;
revoke all on function public.resolve_nina_proposal(uuid, text, jsonb, text) from public;
revoke all on function public.update_nina_memory(uuid, text, text, text) from public;
revoke all on function public.delete_nina_memory(uuid) from public;
revoke all on function public.delete_current_nina_chat_history(uuid) from public;
revoke all on function public.get_nina_weekly_candidates() from public;
revoke all on function public.reserve_nina_insight_run(uuid, text, bigint, date) from public;
revoke all on function public.complete_nina_insight_run(uuid, jsonb, integer, integer, integer, integer, bigint, integer) from public;
revoke all on function public.run_nina_retention() from public;
revoke all on function public.verify_nina_maintenance_secret(text) from public;

grant execute on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date) to authenticated;
grant execute on function public.get_nina_chat_result(uuid) to authenticated;
grant execute on function public.get_current_nina_state(uuid) to authenticated;
grant execute on function public.resolve_nina_proposal(uuid, text, jsonb, text) to authenticated;
grant execute on function public.update_nina_memory(uuid, text, text, text) to authenticated;
grant execute on function public.delete_nina_memory(uuid) to authenticated;
grant execute on function public.delete_current_nina_chat_history(uuid) to authenticated;

grant execute on function public.complete_nina_chat_run(uuid, uuid, text, jsonb, integer, integer, integer, integer, bigint, integer) to service_role;
grant execute on function public.fail_nina_ai_run(uuid, text, integer) to service_role;
grant execute on function public.get_nina_weekly_candidates() to service_role;
grant execute on function public.reserve_nina_insight_run(uuid, text, bigint, date) to service_role;
grant execute on function public.complete_nina_insight_run(uuid, jsonb, integer, integer, integer, integer, bigint, integer) to service_role;
grant execute on function public.run_nina_retention() to service_role;
grant execute on function public.verify_nina_maintenance_secret(text) to service_role;
grant select, update on table public.nina_ai_runs to service_role;

commit;
