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
  set
    reserved_microusd = greatest(reserved_microusd - target_run.reserved_microusd, 0),
    spent_microusd = spent_microusd + greatest(actual_cost_microusd, 0)
  where month_start = private.current_month_start()
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

create or replace function public.fail_nina_ai_run(
  target_run_id uuid,
  failure_code text,
  request_latency_ms integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.record_failed_nina_ai_run(
    target_run_id,
    failure_code,
    0,
    0,
    0,
    0,
    0,
    request_latency_ms
  );
end;
$$;

revoke all on function public.record_failed_nina_ai_run(
  uuid,
  text,
  integer,
  integer,
  integer,
  integer,
  bigint,
  integer
) from public;
revoke all on function public.record_failed_nina_ai_run(
  uuid,
  text,
  integer,
  integer,
  integer,
  integer,
  bigint,
  integer
) from anon;
revoke all on function public.record_failed_nina_ai_run(
  uuid,
  text,
  integer,
  integer,
  integer,
  integer,
  bigint,
  integer
) from authenticated;
grant execute on function public.record_failed_nina_ai_run(
  uuid,
  text,
  integer,
  integer,
  integer,
  integer,
  bigint,
  integer
) to service_role;
