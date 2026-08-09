begin;

create table if not exists public.nina_ai_consents (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  policy_version text not null
    check (
      policy_version = trim(policy_version)
      and length(policy_version) between 1 and 40
    ),
  accepted_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint nina_ai_consents_revoked_after_accepted
    check (revoked_at is null or revoked_at >= accepted_at)
);

create unique index if not exists nina_ai_consents_one_live_per_member
  on public.nina_ai_consents(family_id, user_id)
  where revoked_at is null;

create index if not exists nina_ai_consents_user_accepted_at_idx
  on public.nina_ai_consents(user_id, accepted_at desc);

alter table public.nina_ai_consents enable row level security;
revoke all on table public.nina_ai_consents from public, anon, authenticated;

comment on table public.nina_ai_consents is
  'Server-side record of the LGPD legal basis for Nina AI processing. Rows are never deleted: a withdrawal stamps revoked_at and a later consent inserts a new row, so the grant and withdrawal history stays demonstrable. Clients reach it only through record_nina_ai_consent and get_current_home_context.';

comment on column public.nina_ai_consents.revoked_at is
  'When this grant stopped being the live one, whether the person withdrew it or accepted a newer policy version. Null means the grant is live and is the only thing that authorizes an AI run.';

create or replace function public.record_nina_ai_consent(
  policy_version text,
  granted boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  preferred_family_id uuid;
  target_family_id uuid;
  normalized_version text := trim(coalesce(policy_version, ''));
  live_version text;
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

  if not exists (
    select 1
    from public.family_members
    where family_id = target_family_id
      and user_id = current_user_id
      and household_role = 'adult'
  ) then
    raise exception 'nina_adult_access_required' using errcode = '42501';
  end if;

  if granted then
    select consents.policy_version
    into live_version
    from public.nina_ai_consents as consents
    where consents.family_id = target_family_id
      and consents.user_id = current_user_id
      and consents.revoked_at is null;

    if live_version is distinct from normalized_version then
      update public.nina_ai_consents as consents
      set revoked_at = now()
      where consents.family_id = target_family_id
        and consents.user_id = current_user_id
        and consents.revoked_at is null;

      insert into public.nina_ai_consents (
        family_id,
        user_id,
        policy_version
      )
      values (
        target_family_id,
        current_user_id,
        normalized_version
      )
      on conflict (family_id, user_id) where revoked_at is null do nothing;
    end if;
  else
    update public.nina_ai_consents as consents
    set revoked_at = now()
    where consents.family_id = target_family_id
      and consents.user_id = current_user_id
      and consents.revoked_at is null;
  end if;

  return public.get_current_home_context();
end;
$$;

comment on function public.record_nina_ai_consent(text, boolean) is
  'Records or withdraws one adult consent to Nina AI processing. Only the person themselves can call it, and only for a home where they are an adult, so nobody consents on behalf of a child, a pet profile or the household.';

revoke all on function public.record_nina_ai_consent(text, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.record_nina_ai_consent(text, boolean) to authenticated;

create or replace function public.get_current_home_context()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  current_profile public.profiles%rowtype;
  target_family public.families%rowtype;
  target_permission text;
  target_snapshot jsonb;
  active_invite jsonb;
  pending_requests jsonb := '[]'::jsonb;
  remaining_member_slots integer := 0;
  household_premium jsonb;
  household_premium_status text;
  household_premium_expires_at timestamptz;
  caller_ai_consent jsonb;
  caller_consent_version text;
  caller_consent_accepted_at timestamptz;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  current_profile := public.ensure_current_profile(null);

  if current_profile.active_family_id is not null then
    select families.*
    into target_family
    from public.families as families
    join public.family_members as membership
      on membership.family_id = families.id
     and membership.user_id = current_user_id
    where families.id = current_profile.active_family_id;

    if found then
      select membership.permission_role
      into target_permission
      from public.family_members as membership
      where membership.family_id = target_family.id
        and membership.user_id = current_user_id;
    end if;
  end if;

  if target_family.id is null then
    select families.*
    into target_family
    from public.family_members as membership
    join public.families as families on families.id = membership.family_id
    where membership.user_id = current_user_id
    order by membership.created_at
    limit 1;

    if target_family.id is not null then
      select membership.permission_role
      into target_permission
      from public.family_members as membership
      where membership.family_id = target_family.id
        and membership.user_id = current_user_id;

      update public.profiles
      set active_family_id = target_family.id
      where id = current_user_id;
      current_profile.active_family_id := target_family.id;
    end if;
  end if;

  if target_family.id is null then
    return jsonb_build_object(
      'profile', to_jsonb(current_profile),
      'family', null,
      'members', '[]'::jsonb,
      'permission_role', null,
      'membership_verified', false,
      'snapshot', null,
      'active_invite', null,
      'pending_join_requests', '[]'::jsonb,
      'premium', jsonb_build_object(
        'is_active', false,
        'status', 'inactive',
        'expires_at', null
      ),
      'ai_consent', jsonb_build_object(
        'is_granted', false,
        'policy_version', null,
        'accepted_at', null
      )
    );
  end if;

  select greatest(8 - count(*)::integer, 0)
  into remaining_member_slots
  from public.family_members
  where family_id = target_family.id
    and household_role <> 'assistant';

  select data
  into target_snapshot
  from public.family_snapshots
  where family_id = target_family.id;

  select
    subscriptions.status,
    subscriptions.expires_at
  into household_premium_status, household_premium_expires_at
  from public.premium_subscriptions as subscriptions
  where subscriptions.family_id = target_family.id
  order by
    subscriptions.is_active desc,
    subscriptions.expires_at desc nulls last,
    subscriptions.last_verified_at desc,
    subscriptions.updated_at desc
  limit 1;

  household_premium := jsonb_build_object(
    'is_active', private.family_has_premium(target_family.id),
    'status', coalesce(household_premium_status, 'inactive'),
    'expires_at', household_premium_expires_at
  );

  select
    consents.policy_version,
    consents.accepted_at
  into caller_consent_version, caller_consent_accepted_at
  from public.nina_ai_consents as consents
  where consents.family_id = target_family.id
    and consents.user_id = current_user_id
    and consents.revoked_at is null;

  caller_ai_consent := jsonb_build_object(
    'is_granted', caller_consent_version is not null,
    'policy_version', caller_consent_version,
    'accepted_at', caller_consent_accepted_at
  );

  if target_permission in ('owner', 'admin') then
    select jsonb_build_object(
      'code', invites.token,
      'status', case
        when invites.revoked_at is not null then 'revoked'
        when invites.expires_at <= now() then 'expired'
        when remaining_member_slots = 0
          or cardinality(invites.accepted_by) >= invites.max_uses then 'exhausted'
        else 'active'
      end,
      'expires_at', invites.expires_at,
      'max_uses', invites.max_uses,
      'uses', cardinality(invites.accepted_by),
      'uses_remaining', greatest(
        least(
          invites.max_uses - cardinality(invites.accepted_by),
          remaining_member_slots
        ),
        0
      )
    )
    into active_invite
    from public.invites
    where invites.family_id = target_family.id
      and invites.revoked_at is null
    order by invites.created_at desc
    limit 1;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', requests.id,
          'family_id', requests.family_id,
          'family_name', target_family.name,
          'requester_user_id', requests.requester_user_id,
          'requester_name', coalesce(requester_profiles.display_name, requests.requester_name),
          'status', requests.status,
          'created_at', requests.created_at,
          'reviewed_at', requests.reviewed_at
        )
        order by requests.created_at
      ),
      '[]'::jsonb
    )
    into pending_requests
    from public.family_join_requests as requests
    left join public.profiles as requester_profiles
      on requester_profiles.id = requests.requester_user_id
    where requests.family_id = target_family.id
      and requests.status = 'pending';
  end if;

  return jsonb_build_object(
    'profile', to_jsonb(current_profile),
    'family', jsonb_build_object(
      'id', target_family.id,
      'name', target_family.name,
      'invite_code', case
        when target_permission in ('owner', 'admin') then target_family.invite_code
        else ''
      end,
      'created_by', target_family.created_by,
      'created_at', target_family.created_at,
      'updated_at', target_family.updated_at,
      'weekly_digest_enabled', target_family.weekly_digest_enabled
    ),
    'members', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', members.id,
            'family_id', members.family_id,
            'user_id', members.user_id,
            'name', case
              when members.user_id is null then members.name
              else coalesce(member_profiles.display_name, members.name)
            end,
            'relationship', members.relationship,
            'household_role', members.household_role,
            'permission_role', members.permission_role,
            'tone', members.tone,
            'task_count', members.task_count,
            'memory_note', members.memory_note,
            'birth_date', members.birth_date,
            'pet_species', members.pet_species,
            'pet_breed', members.pet_breed,
            'identity_state', case
              when members.user_id is null then 'unclaimed'
              else 'claimed'
            end,
            'created_at', members.created_at
          )
          order by
            case when members.household_role = 'assistant' then 1 else 0 end,
            members.created_at
        )
        from public.family_members as members
        left join public.profiles as member_profiles on member_profiles.id = members.user_id
        where members.family_id = target_family.id
      ),
      '[]'::jsonb
    ),
    'permission_role', target_permission,
    'membership_verified', true,
    'snapshot', target_snapshot,
    'active_invite', active_invite,
    'pending_join_requests', pending_requests,
    'premium', household_premium,
    'ai_consent', caller_ai_consent
  );
end;
$$;

comment on function public.get_current_home_context() is
  'The one household snapshot every mutation RPC returns. The ai_consent block is the caller own live consent, so a device renders the recorded fact instead of a local guess that a reinstall would erase.';

revoke all on function public.get_current_home_context()
  from public, anon, authenticated, service_role;
grant execute on function public.get_current_home_context() to authenticated;

create or replace function public.get_nina_weekly_candidates()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select coalesce(
    jsonb_agg(candidate.metrics),
    '[]'::jsonb
  )
  from (
    select private.nina_weekly_metrics(families.id) as metrics
    from public.families
    where families.weekly_digest_enabled
      and private.family_has_premium(families.id)
      and exists (
        select 1
        from public.nina_ai_consents as consents
        join public.family_members as members
          on members.family_id = consents.family_id
         and members.user_id = consents.user_id
        where consents.family_id = families.id
          and consents.revoked_at is null
          and members.household_role = 'adult'
      )
      and (
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

comment on function public.get_nina_weekly_candidates() is
  'The weekly insight ships member display names to a model, so a household with no live consent from an adult who still belongs to it is never a candidate.';

revoke all on function public.get_nina_weekly_candidates()
  from public, anon, authenticated, service_role;
grant execute on function public.get_nina_weekly_candidates() to service_role;

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

  if not exists (
    select 1
    from public.nina_ai_consents as consents
    where consents.family_id = target_family_id
      and consents.user_id = current_user_id
      and consents.revoked_at is null
  ) then
    raise exception 'nina_ai_consent_required' using errcode = '42501';
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
  'The consent gate, the premium attachment gate and the tiered chat quota live here, not only in the Edge Function, so a direct RPC call cannot bypass any of them. The reserved budget month is pinned on the run so settlement cannot drift to another month.';

revoke all on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date)
  from public, anon, authenticated, service_role;
grant execute on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date)
  to authenticated;

commit;
