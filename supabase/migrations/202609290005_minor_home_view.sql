begin;

-- A band, supervision settings and usage are shown only to that minor's own
-- live guardians; every other adult sees that the member is a minor and no more.
create or replace function private.member_access_json(
  target_member_id uuid,
  viewer_id uuid
)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public, private
as $$
declare
  target_row public.family_members%rowtype;
  settings private.minor_profiles%rowtype;
  viewer_link private.minor_guardianships%rowtype;
  minor_age record;
  policy private.age_policy%rowtype;
  claimed boolean;
  viewer_guards boolean;
  profile_consent boolean;
  supervision jsonb;
  shown_band text;
  shown_band_source text;
  sao_paulo_today date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  select * into target_row from public.family_members as members where members.id = target_member_id;
  if target_row.id is null or target_row.household_role not in ('child', 'teen') then
    return null;
  end if;

  claimed := target_row.user_id is not null;

  select *
  into viewer_link
  from private.minor_guardianships as links
  where links.member_id = target_row.id
    and links.guardian_user_id = viewer_id
    and links.ended_at is null
  order by links.created_at
  limit 1;
  viewer_guards := viewer_link.id is not null;

  profile_consent := private.has_live_minor_consent(
    target_row.id,
    case when claimed then 'account' else 'profile' end
  );

  select * into settings from private.minor_profiles as profiles where profiles.member_id = target_row.id;
  select * into policy from private.age_policy where singleton;

  if viewer_guards then
    if claimed then
      select * into minor_age from private.effective_age(target_row.user_id);
      shown_band := coalesce(minor_age.band, settings.declared_band);
      shown_band_source := coalesce(minor_age.band_source, 'guardian');
    else
      shown_band := settings.declared_band;
      shown_band_source := 'guardian';
    end if;

    supervision := jsonb_build_object(
      'band', shown_band,
      'band_source', shown_band_source,
      'nicknames', to_jsonb(coalesce(settings.nicknames, '{}'::text[])),
      'alerts_enabled', coalesce(settings.alerts_enabled, true),
      'quiet_start', coalesce(settings.quiet_start, 1260),
      'quiet_end', coalesce(settings.quiet_end, 420),
      'daily_limit_minutes', case
        when settings.member_id is null then 30
        else settings.daily_limit_minutes
      end,
      'usage_today_minutes', case
        when claimed then coalesce(
          (
            select usage.minutes::integer
            from private.minor_usage_days as usage
            where usage.member_id = target_row.id
              and usage.day = sao_paulo_today
          ),
          0
        )
      end,
      'usage_last_7_days', case
        when claimed then coalesce(
          (
            select jsonb_agg(
              jsonb_build_object('day', usage.day, 'minutes', usage.minutes)
              order by usage.day
            )
            from private.minor_usage_days as usage
            where usage.member_id = target_row.id
              and usage.day > sao_paulo_today - 7
              and usage.day <= sao_paulo_today
          ),
          '[]'::jsonb
        )
        else '[]'::jsonb
      end,
      'viewer_relationship', viewer_link.relationship
    );
  end if;

  return jsonb_build_object(
    'is_minor', true,
    'is_claimed', claimed,
    'guardian_names', private.guardian_names(target_row.id),
    'is_viewer_guardian', viewer_guards,
    'has_profile_consent', profile_consent,
    'has_health_consent', private.has_live_minor_consent(target_row.id, 'health'),
    'pending_deletion_at', case
      when not claimed and not profile_consent then policy.legacy_profile_deadline
    end,
    'supervision', supervision
  );
end;
$$;

revoke all on function private.member_access_json(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function private.ai_consent_json(
  target_family_id uuid,
  target_user_id uuid
)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public, private
as $$
declare
  policy private.age_policy%rowtype;
  live_consent public.nina_ai_consents%rowtype;
  last_reason text;
begin
  select * into policy from private.age_policy where singleton;

  if target_family_id is not null then
    select *
    into live_consent
    from public.nina_ai_consents as consents
    where consents.family_id = target_family_id
      and consents.user_id = target_user_id
      and consents.revoked_at is null
    order by consents.accepted_at desc
    limit 1;

    if live_consent.id is null then
      select consents.revoke_reason
      into last_reason
      from public.nina_ai_consents as consents
      where consents.family_id = target_family_id
        and consents.user_id = target_user_id
        and consents.revoked_at is not null
      order by consents.revoked_at desc, consents.accepted_at desc
      limit 1;
    end if;
  end if;

  return jsonb_build_object(
    'is_granted', live_consent.id is not null,
    'policy_version', live_consent.policy_version,
    'accepted_at', live_consent.accepted_at,
    'transfer_consented', live_consent.transfer_consented_at is not null,
    'is_current', live_consent.id is not null
      and live_consent.policy_version = policy.current_policy_version
      and live_consent.transfer_consented_at is not null,
    'current_policy_version', policy.current_policy_version,
    'last_revoke_reason', last_reason
  );
end;
$$;

revoke all on function private.ai_consent_json(uuid, uuid)
  from public, anon, authenticated, service_role;

-- A caller who is not an adult receives the shape an older build reads as "no
-- house", so an outdated app can never show a minor the household.
create or replace function public.get_current_home_context()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  current_profile public.profiles%rowtype;
  viewer_age jsonb;
  target_family public.families%rowtype;
  target_permission text;
  target_snapshot jsonb;
  active_invite jsonb;
  pending_requests jsonb := '[]'::jsonb;
  remaining_member_slots integer := 0;
  household_premium jsonb;
  household_premium_status text;
  household_premium_expires_at timestamptz;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  current_profile := public.ensure_current_profile(null);
  viewer_age := private.age_status_json(current_user_id);

  if viewer_age ->> 'status' is distinct from 'adult' then
    return jsonb_build_object(
      'viewer_kind', 'minor',
      'viewer_age', viewer_age,
      'profile', jsonb_build_object(
        'id', current_profile.id,
        'display_name', current_profile.display_name
      ),
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
      'ai_consent', private.ai_consent_json(null, current_user_id)
    );
  end if;

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
      'viewer_kind', 'adult',
      'viewer_age', viewer_age,
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
      'ai_consent', private.ai_consent_json(null, current_user_id)
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
          'reviewed_at', requests.reviewed_at,
          'requester_age', requester_ages.status,
          'requester_band', case
            when requester_ages.status = 'minor' then requester_ages.band
          end
        )
        order by requests.created_at
      ),
      '[]'::jsonb
    )
    into pending_requests
    from public.family_join_requests as requests
    left join public.profiles as requester_profiles
      on requester_profiles.id = requests.requester_user_id
    cross join lateral private.effective_age(requests.requester_user_id) as requester_ages
    where requests.family_id = target_family.id
      and requests.status = 'pending';
  end if;

  return jsonb_build_object(
    'viewer_kind', 'adult',
    'viewer_age', viewer_age,
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
            'birth_date', case
              when members.household_role in ('child', 'teen') then null
              else members.birth_date
            end,
            'pet_species', members.pet_species,
            'pet_breed', members.pet_breed,
            'identity_state', case
              when members.user_id is null then 'unclaimed'
              else 'claimed'
            end,
            'created_at', members.created_at,
            'access', private.member_access_json(members.id, current_user_id)
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
    'ai_consent', private.ai_consent_json(target_family.id, current_user_id)
  );
end;
$$;

revoke all on function public.get_current_home_context()
  from public, anon, authenticated, service_role;
grant execute on function public.get_current_home_context() to authenticated;

create or replace function private.minor_membership(target_user_id uuid)
returns public.family_members
language sql
stable
set search_path = pg_catalog, public
as $$
  select members.*
  from public.family_members as members
  left join public.profiles as profiles on profiles.id = target_user_id
  where members.user_id = target_user_id
  order by
    case when members.family_id = profiles.active_family_id then 0 else 1 end,
    members.created_at,
    members.id
  limit 1;
$$;

revoke all on function private.minor_membership(uuid)
  from public, anon, authenticated, service_role;

-- A minor sees only their own tasks, reduced to title, time and glyph; a task's
-- detail line, other people's work, shopping, members and memories never
-- appear here.
create or replace function public.get_minor_home_view()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  ages record;
  membership public.family_members%rowtype;
  settings private.minor_profiles%rowtype;
  household public.families%rowtype;
  policy private.age_policy%rowtype;
  viewer_state text;
  profile_name text;
  sao_paulo_today date := (now() at time zone 'America/Sao_Paulo')::date;
  day_start timestamptz := ((now() at time zone 'America/Sao_Paulo')::date)::timestamp
    at time zone 'America/Sao_Paulo';
  acknowledgement text;
  needs_ack boolean := false;
  visible_tasks jsonb := '[]'::jsonb;
  guardians jsonb := '[]'::jsonb;
  usage_today integer := 0;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into ages from private.effective_age(current_user_id);
  if ages.status = 'adult' then
    raise exception 'minor_account_required' using errcode = '42501';
  end if;

  select * into policy from private.age_policy where singleton;
  select profiles.display_name into profile_name from public.profiles where profiles.id = current_user_id;
  membership := private.minor_membership(current_user_id);

  if membership.id is null then
    viewer_state := 'no_home';
  elsif ages.status <> 'minor' then
    viewer_state := 'age_required';
  elsif not exists (
    select 1
    from private.minor_guardianships as links
    where links.member_id = membership.id
      and links.ended_at is null
  ) then
    viewer_state := 'no_guardian';
  else
    viewer_state := 'active';
  end if;

  if membership.id is not null then
    select * into household from public.families as families where families.id = membership.family_id;
    guardians := private.guardian_names(membership.id);
    select * into settings from private.minor_profiles as profiles where profiles.member_id = membership.id;
    select coalesce(usage.minutes, 0)
    into usage_today
    from private.minor_usage_days as usage
    where usage.member_id = membership.id
      and usage.day = sao_paulo_today;
    usage_today := coalesce(usage_today, 0);
  end if;

  if ages.status = 'minor' then
    acknowledgement := case when ages.band = '16_17' then 'aceitar' else 'entendi' end;
  end if;

  if viewer_state = 'active' then
    needs_ack := case acknowledgement
      when 'aceitar' then not exists (
        select 1
        from private.account_terms_acceptances as acceptances
        where acceptances.user_id = current_user_id
          and acceptances.accepted_by = 'self_with_guardian'
          and acceptances.terms_version = policy.current_terms_version
      )
      else not exists (
        select 1
        from private.minor_acknowledgements as acknowledgements
        where acknowledgements.user_id = current_user_id
          and acknowledgements.kind = 'entendi'
          and acknowledgements.text_version = policy.current_terms_version
      )
    end;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', owned.id,
          'task_kind', owned.task_kind,
          'title', owned.title,
          'due_at', owned.due_at,
          'due_label', owned.due_label,
          'category_id', owned.category_id,
          'recurrence_rule', owned.recurrence_rule,
          'remind_offset_minutes', owned.remind_offset_minutes,
          'is_done', owned.is_done,
          'completed_at', owned.completed_at,
          'version', owned.version
        )
        order by owned.due_at nulls last, owned.created_at, owned.id
      ),
      '[]'::jsonb
    )
    into visible_tasks
    from (
      select tasks.*
      from public.tasks
      where tasks.family_id = membership.family_id
        and tasks.owner_member_id = membership.id
        and tasks.archived_at is null
        and (not tasks.is_done or tasks.completed_at >= day_start)
      order by tasks.due_at nulls last, tasks.created_at, tasks.id
      limit 100
    ) as owned;
  end if;

  return jsonb_build_object(
    'viewer', jsonb_build_object(
      'member_id', membership.id,
      'first_name', split_part(
        trim(coalesce(membership.name, profile_name, '')),
        ' ',
        1
      ),
      'guardian_names', guardians,
      'state', viewer_state,
      'supervision', jsonb_build_object(
        'alerts_enabled', case
          when viewer_state in ('no_home', 'age_required') or settings.member_id is null then true
          else settings.alerts_enabled
        end,
        'quiet_start', case
          when viewer_state in ('no_home', 'age_required') or settings.member_id is null then 1260
          else settings.quiet_start
        end,
        'quiet_end', case
          when viewer_state in ('no_home', 'age_required') or settings.member_id is null then 420
          else settings.quiet_end
        end,
        'daily_limit_minutes', case
          when viewer_state in ('no_home', 'age_required') or settings.member_id is null then 30
          else settings.daily_limit_minutes
        end
      ),
      'usage_today_minutes', usage_today,
      'needs_acknowledgement', needs_ack,
      'acknowledgement_kind', acknowledgement
    ),
    'family', case
      when household.id is null then null
      else jsonb_build_object('id', household.id, 'name', household.name)
    end,
    'tasks', visible_tasks,
    'server_time', now()
  );
end;
$$;

revoke all on function public.get_minor_home_view()
  from public, anon, authenticated, service_role;
grant execute on function public.get_minor_home_view() to authenticated;

-- A minor changes nothing on a task but whether it is done and, for a
-- repeating task, which occurrence is next; the house's version always wins.
create or replace function public.set_minor_task_done(
  target_task_id uuid,
  expected_version integer,
  mark_done boolean,
  next_due_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  requested_next_due timestamptz := set_minor_task_done.next_due_at;
  initial_family_id uuid;
  task_owner_member_id uuid;
  target_task public.tasks%rowtype;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if private.is_adult(current_user_id) then
    raise exception 'minor_account_required' using errcode = '42501';
  end if;

  select tasks.family_id, tasks.owner_member_id
  into initial_family_id, task_owner_member_id
  from public.tasks
  join public.family_members as members
    on members.id = tasks.owner_member_id
   and members.family_id = tasks.family_id
  where tasks.id = target_task_id
    and members.user_id = current_user_id;

  if not found then
    raise exception 'task_not_found' using errcode = 'P0002';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(initial_family_id::text, 0)
  );

  select *
  into target_task
  from public.tasks
  where tasks.id = target_task_id
  for update;

  if not found
     or target_task.family_id <> initial_family_id
     or target_task.owner_member_id is distinct from task_owner_member_id
     or target_task.archived_at is not null then
    raise exception 'task_not_found' using errcode = 'P0002';
  end if;

  if not exists (
    select 1
    from private.minor_guardianships as links
    where links.member_id = task_owner_member_id
      and links.ended_at is null
  ) then
    raise exception 'guardian_required' using errcode = 'P0001';
  end if;

  if mark_done is null
     or expected_version is null
     or target_task.version <> expected_version then
    raise exception 'task_version_conflict' using errcode = 'P0001';
  end if;

  if target_task.recurrence_rule = 'none' then
    if requested_next_due is not null then
      raise exception 'invalid_next_due_at' using errcode = '22023';
    end if;

    update public.tasks
    set is_done = mark_done
    where tasks.id = target_task.id;
  else
    if requested_next_due is null
       or (
         mark_done
         and not (
           requested_next_due > coalesce(target_task.due_at, now() - interval '1 day')
           and requested_next_due <= now() + interval '400 days'
         )
       )
       or (
         not mark_done
         and not (
           target_task.due_at is not null
           and requested_next_due < target_task.due_at
           and requested_next_due >= target_task.due_at - interval '400 days'
         )
       ) then
      raise exception 'invalid_next_due_at' using errcode = '22023';
    end if;

    update public.tasks
    set
      is_done = false,
      due_at = requested_next_due
    where tasks.id = target_task.id;
  end if;

  return public.get_minor_home_view();
end;
$$;

revoke all on function public.set_minor_task_done(uuid, integer, boolean, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.set_minor_task_done(uuid, integer, boolean, timestamptz)
  to authenticated;

create or replace function public.record_minor_usage(
  usage_day date,
  usage_minutes integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  ages record;
  membership public.family_members%rowtype;
  sao_paulo_today date := (now() at time zone 'America/Sao_Paulo')::date;
  today_minutes integer;
  limit_minutes integer;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into ages from private.effective_age(current_user_id);
  membership := private.minor_membership(current_user_id);

  if ages.status <> 'minor'
     or membership.id is null
     or not exists (
       select 1 from private.minor_profiles as profiles
       where profiles.member_id = membership.id
     ) then
    raise exception 'minor_account_required' using errcode = '42501';
  end if;

  if usage_day is null
     or usage_minutes is null
     or usage_day < sao_paulo_today - 1
     or usage_day > sao_paulo_today + 1
     or usage_minutes < 0
     or usage_minutes > 1440 then
    raise exception 'invalid_usage' using errcode = '22023';
  end if;

  insert into private.minor_usage_days (member_id, day, minutes)
  values (membership.id, usage_day, usage_minutes)
  on conflict (member_id, day) do update
  set minutes = greatest(minor_usage_days.minutes, excluded.minutes);

  select usage.minutes
  into today_minutes
  from private.minor_usage_days as usage
  where usage.member_id = membership.id
    and usage.day = sao_paulo_today;

  select profiles.daily_limit_minutes
  into limit_minutes
  from private.minor_profiles as profiles
  where profiles.member_id = membership.id;

  return jsonb_build_object(
    'usage_today_minutes', coalesce(today_minutes, 0),
    'daily_limit_minutes', limit_minutes
  );
end;
$$;

revoke all on function public.record_minor_usage(date, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.record_minor_usage(date, integer) to authenticated;

create or replace function public.acknowledge_minor_terms(
  acknowledgement_kind text,
  text_version text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  ages record;
  policy private.age_policy%rowtype;
  membership public.family_members%rowtype;
  guardian_hash text;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into ages from private.effective_age(current_user_id);
  if ages.status = 'adult' then
    raise exception 'minor_account_required' using errcode = '42501';
  end if;

  if ages.status <> 'minor'
     or acknowledgement_kind is null
     or (acknowledgement_kind = 'entendi' and ages.band not in ('under_12', '12_15'))
     or (acknowledgement_kind = 'aceitar' and ages.band <> '16_17')
     or acknowledgement_kind not in ('entendi', 'aceitar') then
    raise exception 'invalid_acknowledgement' using errcode = '22023';
  end if;

  select * into policy from private.age_policy where singleton;
  if acknowledge_minor_terms.text_version is distinct from policy.current_terms_version then
    raise exception 'minor_consent_outdated' using errcode = '22023';
  end if;

  if acknowledgement_kind = 'entendi' then
    insert into private.minor_acknowledgements (user_id, kind, text_version)
    values (current_user_id, 'entendi', policy.current_terms_version)
    on conflict on constraint minor_acknowledgements_pkey do nothing;
  else
    membership := private.minor_membership(current_user_id);

    select links.guardian_user_hash
    into guardian_hash
    from private.minor_guardianships as links
    where links.member_id = membership.id
      and links.ended_at is null
    order by links.created_at
    limit 1;

    if not exists (
      select 1
      from private.account_terms_acceptances as acceptances
      where acceptances.user_id = current_user_id
        and acceptances.accepted_by = 'self_with_guardian'
        and acceptances.terms_version = policy.current_terms_version
    ) then
      insert into private.account_terms_acceptances (
        user_id,
        user_hash,
        terms_version,
        policy_version,
        accepted_by,
        guardian_user_hash
      )
      values (
        current_user_id,
        private.user_hash(current_user_id),
        policy.current_terms_version,
        policy.current_policy_version,
        'self_with_guardian',
        guardian_hash
      );
    end if;

    insert into private.minor_acknowledgements (user_id, kind, text_version)
    values (current_user_id, 'aceitar', policy.current_terms_version)
    on conflict on constraint minor_acknowledgements_pkey do nothing;
  end if;

  return public.get_minor_home_view();
end;
$$;

revoke all on function public.acknowledge_minor_terms(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.acknowledge_minor_terms(text, text) to authenticated;

commit;
