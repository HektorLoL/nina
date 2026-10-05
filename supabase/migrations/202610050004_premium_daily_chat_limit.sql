begin;

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
  budget_cap bigint := 20000000;
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

revoke all on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date)
  from public, anon, authenticated, service_role;
grant execute on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date)
  to authenticated;

comment on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date) is
  'The age, block, consent, premium attachment and quota gates live here, not only in the Edge Function, so a direct RPC call cannot bypass any of them. The reserved budget month is pinned on the run so settlement cannot drift to another month.';

commit;
