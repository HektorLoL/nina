begin;

alter table public.nina_ai_runs
  add column if not exists budget_month_start date;

update public.nina_ai_runs
set budget_month_start = date_trunc('month', created_at)::date
where budget_month_start is null;

alter table public.nina_ai_runs
  alter column budget_month_start set default private.current_month_start();

alter table public.nina_ai_runs
  alter column budget_month_start set not null;

comment on column public.nina_ai_runs.budget_month_start is
  'The budget month the run reserved against. Settlement releases and books here rather than recomputing the current month, so a run that crosses midnight on the last day of a month cannot strand its reservation in the month it left behind.';

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
  budget_cap bigint := 20000000;
  user_allowed boolean;
  family_allowed boolean;
  household_is_premium boolean;
  attachment_count integer;
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
    select public.claim_nina_chat_request(30, 3600) into user_allowed;
  else
    select public.claim_nina_chat_request(10, 86400) into user_allowed;
  end if;

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

comment on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date) is
  'The premium attachment gate and the tiered chat quota live here, not only in the Edge Function, so a direct RPC call cannot bypass either. The reserved budget month is pinned on the run so settlement cannot drift to another month.';

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

commit;
