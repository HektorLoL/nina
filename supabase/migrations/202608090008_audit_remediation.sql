begin;

-- These four were never revoked, so PUBLIC still holds execute and the subject
-- is an argument rather than auth.uid(). They are also the predicates every
-- content policy evaluates, and a policy expression runs as the invoking role,
-- so authenticated holds execute only through that same PUBLIC grant. Revoking
-- from PUBLIC without granting back to authenticated would deny every
-- signed-in read of every content table.
revoke all on function public.is_family_member(uuid, uuid) from public, anon;
grant execute on function public.is_family_member(uuid, uuid) to authenticated;

revoke all on function public.can_manage_family(uuid, uuid) from public, anon;
grant execute on function public.can_manage_family(uuid, uuid) to authenticated;

revoke all on function public.is_family_creator(uuid, uuid) from public, anon;
grant execute on function public.is_family_creator(uuid, uuid) to authenticated;

revoke all on function public.shares_family_with(uuid, uuid) from public, anon;
grant execute on function public.shares_family_with(uuid, uuid) to authenticated;

comment on function public.is_family_member(uuid, uuid) is
  'Row level security predicate. Authenticated keeps execute because every content policy evaluates it as the invoking role; anon must not, because the subject is an argument and an anonymous caller would be probing the household graph.';

comment on function public.can_manage_family(uuid, uuid) is
  'Row level security predicate. Authenticated keeps execute because every content policy evaluates it as the invoking role; anon must not, because the subject is an argument and an anonymous caller would be probing who administers a home.';

comment on function public.is_family_creator(uuid, uuid) is
  'Row level security predicate. Authenticated keeps execute because every content policy evaluates it as the invoking role; anon must not, because the subject is an argument and an anonymous caller would be probing who created a home.';

comment on function public.shares_family_with(uuid, uuid) is
  'Row level security predicate. Authenticated keeps execute because the profiles policy evaluates it as the invoking role; anon must not, because both subjects are arguments and an anonymous caller would be linking two user ids to one household.';

-- Cover is a fact about time, not a stored flag. is_active only ever changes
-- when an App Store notification arrives, and nothing re-reads the expiry
-- afterwards, so an unconfigured or failing notification URL would leave a
-- refunded or long-expired subscription granting the household unlimited
-- attachments, the thirty per hour tier and the paid weekly digest forever.
create or replace function private.family_has_premium(target_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
  select target_family_id is not null and exists (
    select 1
    from public.premium_subscriptions as subscriptions
    where subscriptions.family_id = target_family_id
      and subscriptions.is_active
      and subscriptions.revoked_at is null
      and (
        subscriptions.expires_at is null
        or subscriptions.expires_at > now()
        or (
          subscriptions.grace_period_expires_at is not null
          and subscriptions.grace_period_expires_at > now()
        )
      )
  );
$$;

revoke all on function private.family_has_premium(uuid)
  from public, anon, authenticated, service_role;

comment on function private.family_has_premium(uuid) is
  'Household premium signal for definer callers only. Answers whether the house is covered without exposing who paid or how. Cover requires liveness and not merely the stored flag: a refunded row never counts, and an expired row counts only while its Apple grace period is still running, so a missing renewal notification expires cover on its own.';

-- The payer own view and the household view must never disagree about cover,
-- so the same liveness predicate decides is_active here and picks which row to
-- report. status and expires_at stay as recorded, because they describe the
-- purchase rather than the entitlement.
create or replace function public.get_current_premium_status()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
  with owned_subscriptions as (
    select
      subscriptions.*,
      (
        subscriptions.is_active
        and subscriptions.revoked_at is null
        and (
          subscriptions.expires_at is null
          or subscriptions.expires_at > now()
          or (
            subscriptions.grace_period_expires_at is not null
            and subscriptions.grace_period_expires_at > now()
          )
        )
      ) as is_live
    from public.premium_subscriptions as subscriptions
    where subscriptions.user_id = auth.uid()
  ),
  latest_subscription as (
    select *
    from owned_subscriptions
    order by
      is_live desc,
      is_active desc,
      expires_at desc nulls last,
      last_verified_at desc,
      updated_at desc
    limit 1
  )
  select coalesce(
    (
      select jsonb_build_object(
        'is_active', latest_subscription.is_live,
        'status', latest_subscription.status,
        'product_id', latest_subscription.product_id,
        'expires_at', latest_subscription.expires_at,
        'will_renew', latest_subscription.will_renew,
        'environment', latest_subscription.environment,
        'original_transaction_id', latest_subscription.original_transaction_id,
        'latest_transaction_id', latest_subscription.transaction_id,
        'last_verified_at', latest_subscription.last_verified_at
      )
      from latest_subscription
    ),
    jsonb_build_object(
      'is_active', false,
      'status', 'inactive',
      'product_id', null,
      'expires_at', null,
      'will_renew', null,
      'environment', null,
      'original_transaction_id', null,
      'latest_transaction_id', null,
      'last_verified_at', null
    )
  );
$$;

revoke all on function public.get_current_premium_status()
  from public, anon, authenticated, service_role;
grant execute on function public.get_current_premium_status() to authenticated;

comment on function public.get_current_premium_status() is
  'The payer own entitlement. is_active is the same liveness test the household signal applies, so a device can never be told it is covered while the home it pays for is not.';

-- The row remembered when a window opened but not how long it was meant to
-- last, and the roll condition used whatever length the current call happened
-- to pass. One message sent through a premium household, whose window is an
-- hour, therefore reset the daily window of a free household and handed the
-- same adult a fresh free allowance every hour.
alter table public.nina_chat_rate_limits
  add column if not exists window_length_seconds integer not null default 3600;

alter table public.nina_chat_rate_limits
  drop constraint if exists nina_chat_rate_limits_window_length_check;

alter table public.nina_chat_rate_limits
  add constraint nina_chat_rate_limits_window_length_check
  check (window_length_seconds >= 1);

comment on column public.nina_chat_rate_limits.window_length_seconds is
  'The length of the window that is currently open. A claim rolls the window only once the longer of the stored and requested lengths has elapsed, so a short tier can never shorten a long one mid-flight. The name deliberately differs from the window_seconds argument so no reference inside the claim can be ambiguous.';

create or replace function public.claim_nina_chat_request(
  max_requests integer default 30,
  window_seconds integer default 3600
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  requested_window_seconds integer := window_seconds;
  current_count integer;
begin
  if current_user_id is null
     or max_requests < 1
     or requested_window_seconds < 1 then
    return false;
  end if;

  insert into public.nina_chat_rate_limits (
    user_id,
    window_started_at,
    window_length_seconds,
    request_count
  )
  values (
    current_user_id,
    now(),
    requested_window_seconds,
    1
  )
  on conflict (user_id) do update
  set
    window_started_at = case
      when now() >= nina_chat_rate_limits.window_started_at
        + make_interval(
            secs => greatest(
              nina_chat_rate_limits.window_length_seconds,
              excluded.window_length_seconds
            )
          )
        then now()
      else nina_chat_rate_limits.window_started_at
    end,
    window_length_seconds = case
      when now() >= nina_chat_rate_limits.window_started_at
        + make_interval(
            secs => greatest(
              nina_chat_rate_limits.window_length_seconds,
              excluded.window_length_seconds
            )
          )
        then excluded.window_length_seconds
      else greatest(
        nina_chat_rate_limits.window_length_seconds,
        excluded.window_length_seconds
      )
    end,
    request_count = case
      when now() >= nina_chat_rate_limits.window_started_at
        + make_interval(
            secs => greatest(
              nina_chat_rate_limits.window_length_seconds,
              excluded.window_length_seconds
            )
          )
        then 1
      else least(nina_chat_rate_limits.request_count + 1, max_requests + 1)
    end
  returning request_count into current_count;

  return current_count <= max_requests;
end;
$$;

revoke all on function public.claim_nina_chat_request(integer, integer)
  from public, anon, authenticated, service_role;

comment on function public.claim_nina_chat_request(integer, integer) is
  'Per-adult chat quota, reachable only from begin_nina_chat_run. One person can belong to households on different tiers and they share this row, so the open window always runs for the longest length any tier has claimed under it. Fail closed is deliberate: a short window must never shorten a long one.';

commit;
