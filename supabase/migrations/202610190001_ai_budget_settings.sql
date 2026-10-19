begin;

-- The caps live in one row the operator changes with one statement, never in
-- a function body, and every reservation reads that row.
create table if not exists private.nina_ai_budget_settings (
  singleton boolean primary key default true,
  interactive_cap_microusd bigint not null,
  insights_cap_microusd bigint not null,
  household_interactive_cap_microusd bigint not null,
  updated_at timestamptz not null default now()
);

alter table private.nina_ai_budget_settings
  drop constraint if exists nina_ai_budget_settings_singleton;
alter table private.nina_ai_budget_settings
  add constraint nina_ai_budget_settings_singleton check (singleton);

alter table private.nina_ai_budget_settings
  drop constraint if exists nina_ai_budget_settings_caps_not_negative;
alter table private.nina_ai_budget_settings
  add constraint nina_ai_budget_settings_caps_not_negative
  check (
    interactive_cap_microusd >= 0
    and insights_cap_microusd >= 0
    and household_interactive_cap_microusd >= 0
  );

-- One house can never hold more than a tenth of the shared conversation pool.
alter table private.nina_ai_budget_settings
  drop constraint if exists nina_ai_budget_settings_household_share;
alter table private.nina_ai_budget_settings
  add constraint nina_ai_budget_settings_household_share
  check (household_interactive_cap_microusd * 10 <= interactive_cap_microusd);

drop trigger if exists nina_ai_budget_settings_set_updated_at
  on private.nina_ai_budget_settings;
create trigger nina_ai_budget_settings_set_updated_at
  before update on private.nina_ai_budget_settings
  for each row execute function public.set_updated_at();

alter table private.nina_ai_budget_settings enable row level security;
revoke all on table private.nina_ai_budget_settings
  from public, anon, authenticated, service_role;

insert into private.nina_ai_budget_settings (
  singleton,
  interactive_cap_microusd,
  insights_cap_microusd,
  household_interactive_cap_microusd
)
values (true, 50000000, 10000000, 5000000)
on conflict (singleton) do update
set
  interactive_cap_microusd = excluded.interactive_cap_microusd,
  insights_cap_microusd = excluded.insights_cap_microusd,
  household_interactive_cap_microusd = excluded.household_interactive_cap_microusd;

-- Each house's share of the conversation pool is booked like the pool itself:
-- reserved before the model call, settled in the month it reserved in.
create table if not exists private.nina_ai_household_budget_months (
  family_id uuid not null references public.families(id) on delete cascade,
  month_start date not null,
  cap_microusd bigint not null,
  reserved_microusd bigint not null default 0,
  spent_microusd bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (family_id, month_start)
);

alter table private.nina_ai_household_budget_months
  drop constraint if exists nina_ai_household_budget_amounts_not_negative;
alter table private.nina_ai_household_budget_months
  add constraint nina_ai_household_budget_amounts_not_negative
  check (cap_microusd >= 0 and reserved_microusd >= 0 and spent_microusd >= 0);

alter table private.nina_ai_household_budget_months
  drop constraint if exists nina_ai_household_budget_within_cap;
alter table private.nina_ai_household_budget_months
  add constraint nina_ai_household_budget_within_cap
  check (reserved_microusd + spent_microusd <= cap_microusd);

drop trigger if exists nina_ai_household_budget_months_set_updated_at
  on private.nina_ai_household_budget_months;
create trigger nina_ai_household_budget_months_set_updated_at
  before update on private.nina_ai_household_budget_months
  for each row execute function public.set_updated_at();

alter table private.nina_ai_household_budget_months enable row level security;
revoke all on table private.nina_ai_household_budget_months
  from public, anon, authenticated, service_role;

update public.nina_ai_budget_months as months
set cap_microusd = case months.purpose
  when 'interactive' then settings.interactive_cap_microusd
  else settings.insights_cap_microusd
end
from private.nina_ai_budget_settings as settings
where settings.singleton
  and months.month_start = private.current_month_start();

-- A house that already spent past its share this month keeps what it spent on
-- record and reserves nothing more until the month turns.
insert into private.nina_ai_household_budget_months (
  family_id,
  month_start,
  cap_microusd,
  reserved_microusd,
  spent_microusd
)
select
  usage.family_id,
  usage.month_start,
  greatest(settings.household_interactive_cap_microusd, usage.reserved + usage.spent),
  usage.reserved,
  usage.spent
from (
  select
    runs.family_id,
    runs.budget_month_start as month_start,
    coalesce(
      sum(runs.reserved_microusd) filter (where runs.status in ('reserved', 'running')),
      0
    ) as reserved,
    coalesce(
      sum(coalesce(runs.actual_microusd, 0)) filter (where runs.status in ('completed', 'failed')),
      0
    ) as spent
  from public.nina_ai_runs as runs
  where runs.purpose = 'interactive'
    and runs.budget_month_start = private.current_month_start()
  group by runs.family_id, runs.budget_month_start
) as usage
cross join private.nina_ai_budget_settings as settings
where settings.singleton
on conflict (family_id, month_start) do nothing;

revoke all on function private.current_month_start()
  from public, anon, authenticated, service_role;
revoke all on function private.invoke_nina_maintenance()
  from public, anon, authenticated, service_role;

-- The weekly insight always describes the last whole Monday-to-Sunday week in
-- São Paulo, so every day of a week names the same week.
create or replace function private.nina_insight_period_start(reference timestamptz)
returns date
language sql
stable
set search_path = pg_catalog
as $$
  select (date_trunc('week', reference at time zone 'America/Sao_Paulo'))::date - 7;
$$;

revoke all on function private.nina_insight_period_start(timestamptz)
  from public, anon, authenticated, service_role;

-- A covered household's adults each get 50 messages a day, counted in the same
-- daily window as the free tier's 10, so the limit people read is the one kept.
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
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  target_thread_id uuid;
  target_run public.nina_ai_runs%rowtype;
  current_month date := private.current_month_start();
  budget_cap bigint;
  household_cap bigint;
  user_allowed boolean;
  family_allowed boolean;
  household_is_premium boolean;
  attachment_count integer;
  normalized_text text := trim(message_text);
  policy private.age_policy%rowtype;
  live_consent public.nina_ai_consents%rowtype;
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

  if not private.may_use_ai(current_user_id) then
    raise exception 'age_confirmation_required' using errcode = '42501';
  end if;

  if private.ai_blocked(current_user_id) then
    raise exception 'nina_ai_blocked' using errcode = '42501';
  end if;

  select *
  into live_consent
  from public.nina_ai_consents as consents
  where consents.family_id = target_family_id
    and consents.user_id = current_user_id
    and consents.revoked_at is null;

  if live_consent.id is null then
    raise exception 'nina_ai_consent_required' using errcode = '42501';
  end if;

  select * into policy from private.age_policy where singleton;
  if live_consent.policy_version is distinct from policy.current_policy_version then
    raise exception 'nina_consent_outdated' using errcode = '42501';
  end if;

  if live_consent.transfer_consented_at is null then
    raise exception 'nina_transfer_consent_required' using errcode = '42501';
  end if;

  household_is_premium := private.family_has_premium(target_family_id);

  attachment_count := case
    when jsonb_typeof(coalesce(attachment_metadata, '[]'::jsonb)) = 'array'
      then jsonb_array_length(coalesce(attachment_metadata, '[]'::jsonb))
    else 0
  end;

  if attachment_count > 0 and not household_is_premium then
    raise exception 'nina_attachments_require_premium' using errcode = 'P0001';
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

  if household_is_premium then
    select public.claim_nina_chat_request(50, 86400) into user_allowed;
  else
    select public.claim_nina_chat_request(10, 86400) into user_allowed;
  end if;

  select private.claim_nina_family_request(target_family_id, 100, 86400) into family_allowed;

  if not user_allowed or not family_allowed then
    raise exception 'nina_rate_limited' using errcode = 'P0001';
  end if;

  select
    settings.interactive_cap_microusd,
    settings.household_interactive_cap_microusd
  into budget_cap, household_cap
  from private.nina_ai_budget_settings as settings
  where settings.singleton;

  if not found then
    raise exception 'nina_budget_exceeded' using errcode = 'P0001';
  end if;

  -- A house past its share reads the same refusal as a spent pool, which every
  -- shipped build already shows as a paused conversation.
  insert into private.nina_ai_household_budget_months (
    family_id,
    month_start,
    cap_microusd
  )
  values (
    target_family_id,
    current_month,
    household_cap
  )
  on conflict (family_id, month_start) do nothing;

  update private.nina_ai_household_budget_months
  set
    cap_microusd = household_cap,
    reserved_microusd = reserved_microusd + reserved_cost_microusd
  where family_id = target_family_id
    and month_start = current_month
    and spent_microusd + reserved_microusd + reserved_cost_microusd <= household_cap;

  if not found then
    raise exception 'nina_budget_exceeded' using errcode = 'P0001';
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
  set
    cap_microusd = budget_cap,
    reserved_microusd = reserved_microusd + reserved_cost_microusd
  where month_start = current_month
    and purpose = 'interactive'
    and spent_microusd + reserved_microusd + reserved_cost_microusd <= budget_cap;

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
    reserved_microusd,
    budget_month_start
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
    reserved_cost_microusd,
    current_month
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

revoke all on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date)
  from public, anon, authenticated, service_role;
grant execute on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date)
  to authenticated;

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
set search_path = pg_catalog, public, private
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

  update private.nina_ai_household_budget_months
  set
    reserved_microusd = greatest(reserved_microusd - target_run.reserved_microusd, 0),
    spent_microusd = spent_microusd + greatest(actual_cost_microusd, 0)
  where target_run.purpose = 'interactive'
    and family_id = target_run.family_id
    and month_start = target_run.budget_month_start;

  update public.nina_ai_budget_months
  set
    reserved_microusd = greatest(reserved_microusd - target_run.reserved_microusd, 0),
    spent_microusd = spent_microusd + greatest(actual_cost_microusd, 0)
  where month_start = target_run.budget_month_start
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

revoke all on function public.complete_nina_chat_run(uuid, uuid, text, jsonb, integer, integer, integer, integer, bigint, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.complete_nina_chat_run(uuid, uuid, text, jsonb, integer, integer, integer, integer, bigint, integer)
  to service_role;

create or replace function public.record_failed_nina_ai_run(
  target_run_id uuid,
  failure_code text,
  usage_input_tokens integer default 0,
  usage_cached_input_tokens integer default 0,
  usage_output_tokens integer default 0,
  usage_reasoning_tokens integer default 0,
  actual_cost_microusd bigint default 0,
  request_latency_ms integer default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
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

  update private.nina_ai_household_budget_months
  set
    reserved_microusd = greatest(reserved_microusd - target_run.reserved_microusd, 0),
    spent_microusd = spent_microusd + greatest(actual_cost_microusd, 0)
  where target_run.purpose = 'interactive'
    and family_id = target_run.family_id
    and month_start = target_run.budget_month_start;

  update public.nina_ai_budget_months
  set
    reserved_microusd = greatest(reserved_microusd - target_run.reserved_microusd, 0),
    spent_microusd = spent_microusd + greatest(actual_cost_microusd, 0)
  where month_start = target_run.budget_month_start
    and purpose = target_run.purpose;

  update public.nina_ai_runs
  set
    status = 'failed',
    error_code = left(coalesce(failure_code, 'unknown_error'), 120),
    actual_microusd = greatest(actual_cost_microusd, 0),
    input_tokens = greatest(usage_input_tokens, 0),
    cached_input_tokens = greatest(usage_cached_input_tokens, 0),
    output_tokens = greatest(usage_output_tokens, 0),
    reasoning_tokens = greatest(usage_reasoning_tokens, 0),
    latency_ms = case
      when request_latency_ms is null then latency_ms
      else greatest(request_latency_ms, 0)
    end,
    completed_at = now()
  where id = target_run.id;
end;
$$;

revoke all on function public.record_failed_nina_ai_run(uuid, text, integer, integer, integer, integer, bigint, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.record_failed_nina_ai_run(uuid, text, integer, integer, integer, integer, bigint, integer)
  to service_role;

create or replace function public.reserve_nina_insight_run(
  target_family_id uuid,
  requested_model text,
  reserved_cost_microusd bigint,
  pricing_version date
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  current_month date := private.current_month_start();
  budget_cap bigint;
  target_run_id uuid;
begin
  if reserved_cost_microusd < 0 or reserved_cost_microusd > 1000000 then
    raise exception 'invalid_cost_reservation' using errcode = '22023';
  end if;

  select settings.insights_cap_microusd
  into budget_cap
  from private.nina_ai_budget_settings as settings
  where settings.singleton;

  if not found then
    raise exception 'nina_budget_exceeded' using errcode = 'P0001';
  end if;

  insert into public.nina_ai_budget_months (
    month_start,
    purpose,
    cap_microusd
  )
  values (
    current_month,
    'insights',
    budget_cap
  )
  on conflict (month_start, purpose) do nothing;

  update public.nina_ai_budget_months
  set
    cap_microusd = budget_cap,
    reserved_microusd = reserved_microusd + reserved_cost_microusd
  where month_start = current_month
    and purpose = 'insights'
    and spent_microusd + reserved_microusd + reserved_cost_microusd <= budget_cap;

  if not found then
    raise exception 'nina_budget_exceeded' using errcode = 'P0001';
  end if;

  insert into public.nina_ai_runs (
    family_id,
    purpose,
    model,
    status,
    pricing_version,
    reserved_microusd,
    budget_month_start
  )
  values (
    target_family_id,
    'insights',
    requested_model,
    'running',
    pricing_version,
    reserved_cost_microusd,
    current_month
  )
  returning id into target_run_id;

  return target_run_id;
end;
$$;

revoke all on function public.reserve_nina_insight_run(uuid, text, bigint, date)
  from public, anon, authenticated, service_role;
grant execute on function public.reserve_nina_insight_run(uuid, text, bigint, date)
  to service_role;

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
set search_path = pg_catalog, public, private
as $$
declare
  target_run public.nina_ai_runs%rowtype;
  insight jsonb;
  insight_period_start date;
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

  -- The week is the one the run was reserved for, so a run that finishes on
  -- another day still lands on the week its candidate was chosen for.
  insight_period_start := private.nina_insight_period_start(target_run.created_at);

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
      insight_period_start,
      insight_period_start + 6,
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
  where month_start = target_run.budget_month_start
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

revoke all on function public.complete_nina_insight_run(uuid, jsonb, integer, integer, integer, integer, bigint, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.complete_nina_insight_run(uuid, jsonb, integer, integer, integer, integer, bigint, integer)
  to service_role;

-- A run whose house disappears books its whole reservation as spent, so the
-- month's cap never shrinks for a reservation nothing will settle.
create or replace function private.settle_household_ai_runs(target_family_id uuid)
returns void
language plpgsql
set search_path = pg_catalog, public, private
as $$
declare
  open_run_ids uuid[];
  house_share record;
  pool_share record;
begin
  select coalesce(array_agg(open_runs.id order by open_runs.id), '{}'::uuid[])
  into open_run_ids
  from (
    select runs.id
    from public.nina_ai_runs as runs
    where runs.family_id = target_family_id
      and runs.status in ('reserved', 'running')
    order by runs.id
    for update
  ) as open_runs;

  -- House shares are booked before any pool row and pool rows in month order, as a turn and every other settle take them, so none waits on another in a circle.
  for house_share in
    select
      runs.budget_month_start,
      sum(runs.reserved_microusd)::bigint as reserved_microusd
    from public.nina_ai_runs as runs
    where runs.id = any(open_run_ids)
      and runs.purpose = 'interactive'
    group by runs.budget_month_start
    order by runs.budget_month_start
  loop
    update private.nina_ai_household_budget_months as months
    set
      reserved_microusd = greatest(months.reserved_microusd - house_share.reserved_microusd, 0),
      spent_microusd = months.spent_microusd
        + least(house_share.reserved_microusd, months.reserved_microusd)
    where months.family_id = target_family_id
      and months.month_start = house_share.budget_month_start;
  end loop;

  for pool_share in
    select
      runs.budget_month_start,
      runs.purpose,
      sum(runs.reserved_microusd)::bigint as reserved_microusd
    from public.nina_ai_runs as runs
    where runs.id = any(open_run_ids)
    group by runs.budget_month_start, runs.purpose
    order by runs.budget_month_start, runs.purpose
  loop
    update public.nina_ai_budget_months as months
    set
      reserved_microusd = greatest(months.reserved_microusd - pool_share.reserved_microusd, 0),
      spent_microusd = months.spent_microusd
        + least(pool_share.reserved_microusd, months.reserved_microusd)
    where months.month_start = pool_share.budget_month_start
      and months.purpose = pool_share.purpose;
  end loop;

  update public.nina_ai_runs as runs
  set
    status = 'failed',
    error_code = 'family_deleted',
    actual_microusd = runs.reserved_microusd,
    completed_at = now()
  where runs.id = any(open_run_ids);
end;
$$;

revoke all on function private.settle_household_ai_runs(uuid)
  from public, anon, authenticated, service_role;

-- A run nothing settled within fifteen minutes never will be, so its whole
-- reservation is booked as spent: what the provider charged for it is unknown.
create or replace function private.settle_abandoned_ai_runs()
returns integer
language plpgsql
set search_path = pg_catalog, public, private
as $$
declare
  abandoned_run_ids uuid[];
  house_share record;
  pool_share record;
  settled_runs integer;
begin
  select coalesce(array_agg(abandoned_runs.id order by abandoned_runs.id), '{}'::uuid[])
  into abandoned_run_ids
  from (
    select runs.id
    from public.nina_ai_runs as runs
    where runs.status in ('reserved', 'running')
      and runs.created_at < now() - interval '15 minutes'
    order by runs.id
    for update skip locked
  ) as abandoned_runs;

  -- House shares are booked before any pool row and pool rows in month order, as a turn and every other settle take them, so none waits on another in a circle.
  for house_share in
    select
      runs.family_id,
      runs.budget_month_start,
      sum(runs.reserved_microusd)::bigint as reserved_microusd
    from public.nina_ai_runs as runs
    where runs.id = any(abandoned_run_ids)
      and runs.purpose = 'interactive'
    group by runs.family_id, runs.budget_month_start
    order by runs.family_id, runs.budget_month_start
  loop
    update private.nina_ai_household_budget_months as months
    set
      reserved_microusd = greatest(months.reserved_microusd - house_share.reserved_microusd, 0),
      spent_microusd = months.spent_microusd
        + least(house_share.reserved_microusd, months.reserved_microusd)
    where months.family_id = house_share.family_id
      and months.month_start = house_share.budget_month_start;
  end loop;

  for pool_share in
    select
      runs.budget_month_start,
      runs.purpose,
      sum(runs.reserved_microusd)::bigint as reserved_microusd
    from public.nina_ai_runs as runs
    where runs.id = any(abandoned_run_ids)
    group by runs.budget_month_start, runs.purpose
    order by runs.budget_month_start, runs.purpose
  loop
    update public.nina_ai_budget_months as months
    set
      reserved_microusd = greatest(months.reserved_microusd - pool_share.reserved_microusd, 0),
      spent_microusd = months.spent_microusd
        + least(pool_share.reserved_microusd, months.reserved_microusd)
    where months.month_start = pool_share.budget_month_start
      and months.purpose = pool_share.purpose;
  end loop;

  update public.nina_ai_runs as runs
  set
    status = 'failed',
    error_code = 'run_abandoned',
    actual_microusd = runs.reserved_microusd,
    completed_at = now()
  where runs.id = any(abandoned_run_ids);
  get diagnostics settled_runs = row_count;

  return settled_runs;
end;
$$;

revoke all on function private.settle_abandoned_ai_runs()
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
      week.period_start,
      week.period_start + 6 as period_end,
      week.period_start::timestamp at time zone 'America/Sao_Paulo' as starts_at,
      (week.period_start + 7)::timestamp at time zone 'America/Sao_Paulo' as ends_at
    from (
      select private.nina_insight_period_start(now()) as period_start
    ) as week
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
      count(*) filter (
        where created_at >= bounds.starts_at
          and created_at < bounds.ends_at
      )::integer as tasks_created,
      count(*) filter (
        where is_done
          and completed_at >= bounds.starts_at
          and completed_at < bounds.ends_at
      )::integer as tasks_completed,
      count(*) filter (where not is_done)::integer as tasks_open,
      count(*) filter (
        where created_at >= bounds.starts_at
          and created_at < bounds.ends_at
          and due_at is not null
      )::integer as scheduled_task_events
    from counted_tasks
    cross join bounds
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
          and created_at >= bounds.starts_at
          and created_at < bounds.ends_at
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
          and confirmed_at >= bounds.starts_at
          and confirmed_at < bounds.ends_at
      ) as shared_memory_events
    from bounds
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
-- portrait of one person, so the house gets no insight that week. Houses not
-- yet tried this week come first, then the house longest without an insight,
-- so a nightly cap delays a house and never skips it for good.
create or replace function public.get_nina_weekly_candidates()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select coalesce(
    jsonb_agg(
      candidate.metrics
      order by
        candidate.attempts_this_week,
        candidate.last_period_start nulls first,
        candidate.family_id
    ),
    '[]'::jsonb
  )
  from (
    select
      families.id as family_id,
      private.nina_weekly_metrics(families.id) as metrics,
      (
        select count(*)
        from public.nina_ai_runs as runs
        where runs.family_id = families.id
          and runs.purpose = 'insights'
          and runs.created_at >= week.attempts_since
      ) as attempts_this_week,
      (
        select max(insights.period_start)
        from public.household_insights as insights
        where insights.family_id = families.id
      ) as last_period_start
    from public.families
    cross join (
      select
        bounds.period_start,
        (bounds.period_start + 7)::timestamp at time zone 'America/Sao_Paulo' as attempts_since
      from (
        select private.nina_insight_period_start(now()) as period_start
      ) as bounds
    ) as week
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
          and household_insights.period_start = week.period_start
      )
  ) as candidate;
$$;

revoke all on function public.get_nina_weekly_candidates()
  from public, anon, authenticated, service_role;
grant execute on function public.get_nina_weekly_candidates() to service_role;

create or replace function public.run_nina_retention()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  abandoned_runs integer;
  deleted_messages integer;
  deleted_proposals integer;
  deleted_runs integer;
  deleted_insights integer;
  archived_tasks integer;
  deleted_challenges integer;
  deleted_attest_keys integer;
  deleted_minor_requests integer;
  deleted_usage_days integer;
  deleted_reports integer;
  deleted_blocks integer;
  deleted_preserved_accounts integer;
  deleted_consent_proofs integer := 0;
  deleted_legacy_profiles integer := 0;
  proof_rows integer;
  legacy_deadline timestamptz;
begin
  -- Abandoned runs are settled before old runs are deleted, so no reservation
  -- is ever deleted with the run that held it.
  abandoned_runs := private.settle_abandoned_ai_runs();

  update public.nina_proposals
  set
    state = 'rejected',
    resolved_at = now(),
    resolved_payload = jsonb_build_object('reason', 'expired')
  where state = 'pending'
    and created_at < now() - interval '30 days';

  -- A reported reply is held for review, and never for more than ninety days.
  delete from public.chat_messages
  where coalesce(retained_until, created_at + interval '30 days') < now()
    and (
      held_for_review_until is null
      or held_for_review_until < now()
      or held_for_review_until > now() + interval '90 days'
    );
  get diagnostics deleted_messages = row_count;

  -- Words a deleted house left on a report are kept no longer than the reply itself could be.
  update private.nina_reply_reports
  set
    reply_text = null,
    request_text = null
  where created_at < now() - interval '90 days'
    and (reply_text is not null or request_text is not null);

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

  -- Thirty days sits well clear of the fortnight the weekly insight can read
  -- back, so bounding the list can never starve the metric it is measured from.
  update public.tasks
  set archived_at = now()
  where archived_at is null
    and is_done
    and completed_at < now() - interval '30 days';
  get diagnostics archived_tasks = row_count;

  delete from private.age_signal_challenges
  where created_at < now() - interval '1 day';
  get diagnostics deleted_challenges = row_count;

  delete from private.app_attest_keys
  where coalesce(last_used_at, created_at) < now() - interval '400 days';
  get diagnostics deleted_attest_keys = row_count;

  delete from public.family_join_requests as requests
  where requests.status = 'pending'
    and requests.created_at < now() - interval '7 days'
    and not private.is_adult(requests.requester_user_id);
  get diagnostics deleted_minor_requests = row_count;

  delete from private.minor_usage_days
  where day < (now() at time zone 'America/Sao_Paulo')::date - 30;
  get diagnostics deleted_usage_days = row_count;

  delete from private.nina_reply_reports
  where reviewed_at < now() - interval '6 months';
  get diagnostics deleted_reports = row_count;

  delete from private.nina_ai_blocks
  where lifted_at < now() - interval '1 year';
  get diagnostics deleted_blocks = row_count;

  delete from private.child_safety_preserved_accounts as preserved
  using private.child_safety_holds as holds
  where holds.id = preserved.hold_id
    and not private.child_safety_hold_is_preserved(holds);
  get diagnostics deleted_preserved_accounts = row_count;

  delete from private.minor_guardianships
  where ended_at < now() - interval '5 years';
  get diagnostics proof_rows = row_count;
  deleted_consent_proofs := deleted_consent_proofs + proof_rows;

  delete from private.minor_data_consents
  where withdrawn_at < now() - interval '5 years';
  get diagnostics proof_rows = row_count;
  deleted_consent_proofs := deleted_consent_proofs + proof_rows;

  delete from private.account_terms_acceptances
  where user_id is null
    and accepted_at < now() - interval '5 years';
  get diagnostics proof_rows = row_count;
  deleted_consent_proofs := deleted_consent_proofs + proof_rows;

  select policy.legacy_profile_deadline
  into legacy_deadline
  from private.age_policy as policy
  where policy.singleton;

  if legacy_deadline is not null and legacy_deadline < now() then
    delete from public.family_members as members
    where members.user_id is null
      and members.household_role in ('child', 'teen')
      and not private.has_live_minor_consent(members.id, 'profile')
      and not exists (
        select 1
        from private.minor_guardianships as links
        where links.member_id = members.id
          and links.ended_at is null
      );
    get diagnostics deleted_legacy_profiles = row_count;
  end if;

  return jsonb_build_object(
    'abandoned_runs', abandoned_runs,
    'messages', deleted_messages,
    'proposals', deleted_proposals,
    'runs', deleted_runs,
    'insights', deleted_insights,
    'archived_tasks', archived_tasks,
    'age_challenges', deleted_challenges,
    'app_attest_keys', deleted_attest_keys,
    'minor_join_requests', deleted_minor_requests,
    'minor_usage_days', deleted_usage_days,
    'reply_reports', deleted_reports,
    'ai_blocks', deleted_blocks,
    'preserved_accounts', deleted_preserved_accounts,
    'consent_proofs', deleted_consent_proofs,
    'legacy_minor_profiles', deleted_legacy_profiles
  );
end;
$$;

revoke all on function public.run_nina_retention()
  from public, anon, authenticated, service_role;
grant execute on function public.run_nina_retention() to service_role;

commit;
