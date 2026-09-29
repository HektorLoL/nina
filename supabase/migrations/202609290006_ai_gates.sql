begin;

-- Every consent given before this migration was given on text that said the model
-- provider keeps nothing. It is withdrawn, never deleted, so the history stays
-- demonstrable and every adult accepts the corrected text again.
update public.nina_ai_consents
set
  revoked_at = greatest(now(), accepted_at),
  revoke_reason = 'policy_changed'
where revoked_at is null;

drop function if exists public.record_nina_ai_consent(text, boolean);

-- A grant counts only at the current policy version, with its own separate
-- consent to the transfer abroad, from an adult the server may let use AI.
create or replace function public.record_nina_ai_consent(
  policy_version text,
  granted boolean,
  transfer_consented boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  preferred_family_id uuid;
  target_family_id uuid;
  normalized_version text := trim(coalesce(record_nina_ai_consent.policy_version, ''));
  policy private.age_policy%rowtype;
  live_consent public.nina_ai_consents%rowtype;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if granted is null
     or (granted and (normalized_version = '' or length(normalized_version) > 40)) then
    raise exception 'invalid_nina_ai_consent' using errcode = '22023';
  end if;

  select profiles.active_family_id
  into preferred_family_id
  from public.profiles as profiles
  where profiles.id = current_user_id;

  select membership.family_id
  into target_family_id
  from public.family_members as membership
  where membership.user_id = current_user_id
  order by
    case when membership.family_id = preferred_family_id then 0 else 1 end,
    membership.created_at
  limit 1;

  if target_family_id is null then
    raise exception 'family_not_found' using errcode = 'P0002';
  end if;

  if granted then
    if not exists (
      select 1
      from public.family_members as members
      where members.family_id = target_family_id
        and members.user_id = current_user_id
        and members.household_role = 'adult'
    ) then
      raise exception 'nina_adult_access_required' using errcode = '42501';
    end if;

    if not private.may_use_ai(current_user_id) then
      raise exception 'age_confirmation_required' using errcode = '42501';
    end if;

    if private.ai_blocked(current_user_id) then
      raise exception 'nina_ai_blocked' using errcode = '42501';
    end if;

    select * into policy from private.age_policy where singleton;
    if normalized_version is distinct from policy.current_policy_version then
      raise exception 'nina_consent_outdated' using errcode = '42501';
    end if;

    if not coalesce(transfer_consented, false) then
      raise exception 'nina_transfer_consent_required' using errcode = '42501';
    end if;

    select *
    into live_consent
    from public.nina_ai_consents as consents
    where consents.family_id = target_family_id
      and consents.user_id = current_user_id
      and consents.revoked_at is null
    for update;

    if live_consent.id is null
       or live_consent.policy_version is distinct from normalized_version
       or live_consent.transfer_consented_at is null then
      update public.nina_ai_consents as consents
      set
        revoked_at = greatest(now(), consents.accepted_at),
        revoke_reason = 'superseded'
      where consents.family_id = target_family_id
        and consents.user_id = current_user_id
        and consents.revoked_at is null;

      insert into public.nina_ai_consents (
        family_id,
        user_id,
        policy_version,
        transfer_consented_at
      )
      values (
        target_family_id,
        current_user_id,
        normalized_version,
        now()
      );
    end if;
  else
    update public.nina_ai_consents as consents
    set
      revoked_at = greatest(now(), consents.accepted_at),
      revoke_reason = 'withdrawn'
    where consents.family_id = target_family_id
      and consents.user_id = current_user_id
      and consents.revoked_at is null;
  end if;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.record_nina_ai_consent(text, boolean, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.record_nina_ai_consent(text, boolean, boolean)
  to authenticated;

comment on function public.record_nina_ai_consent(text, boolean, boolean) is
  'Records or withdraws one adult consent to Nina AI processing. A two-argument call from an older build omits the transfer consent and is refused, which is the fail-closed outcome by design.';

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

revoke all on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date)
  from public, anon, authenticated, service_role;
grant execute on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date)
  to authenticated;

comment on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date) is
  'The age, block, consent, premium attachment and quota gates live here, not only in the Edge Function, so a direct RPC call cannot bypass any of them. The reserved budget month is pinned on the run so settlement cannot drift to another month.';

-- A new purchase needs the same assurance the chat needs; a renewal or restore
-- of an original already recorded for the account is always honored.
create or replace function public.premium_buyer_is_eligible(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select target_user_id is not null and private.may_use_ai(target_user_id);
$$;

revoke all on function public.premium_buyer_is_eligible(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.premium_buyer_is_eligible(uuid) to service_role;

commit;
