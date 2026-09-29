begin;

alter table public.nina_ai_consents
  add column if not exists transfer_consented_at timestamptz;
alter table public.nina_ai_consents
  add column if not exists revoke_reason text;

alter table public.nina_ai_consents
  drop constraint if exists nina_ai_consents_revoke_reason_check;
alter table public.nina_ai_consents
  add constraint nina_ai_consents_revoke_reason_check
  check (
    revoke_reason is null
    or revoke_reason in ('withdrawn', 'superseded', 'policy_changed', 'age_status')
  );

alter table public.family_join_requests
  add column if not exists requester_age_status text;
alter table public.family_join_requests
  add column if not exists requester_band text;

alter table public.family_join_requests
  drop constraint if exists family_join_requests_requester_age_status_check;
alter table public.family_join_requests
  add constraint family_join_requests_requester_age_status_check
  check (
    requester_age_status is null
    or requester_age_status in ('adult', 'minor', 'unknown')
  );

alter table public.family_join_requests
  drop constraint if exists family_join_requests_requester_band_check;
alter table public.family_join_requests
  add constraint family_join_requests_requester_band_check
  check (
    requester_band is null
    or requester_band in ('under_12', '12_15', '16_17')
  );

update public.family_members
set birth_date = null
where household_role = 'child'
  and birth_date is not null;

update public.family_members
set permission_role = 'member'
where household_role = 'child'
  and permission_role <> 'member';

update public.family_members
set household_role = 'adult'
where user_id is not null
  and household_role not in ('adult', 'child');

alter table public.family_members
  drop constraint if exists family_members_household_role_check;
alter table public.family_members
  add constraint family_members_household_role_check
  check (household_role in ('adult', 'teen', 'child', 'pet', 'assistant'));

alter table public.family_members
  drop constraint if exists family_members_claimed_role_check;
alter table public.family_members
  add constraint family_members_claimed_role_check
  check (user_id is null or household_role in ('adult', 'teen', 'child'));

alter table public.family_members
  drop constraint if exists family_members_minor_permission_check;
alter table public.family_members
  add constraint family_members_minor_permission_check
  check (household_role not in ('teen', 'child') or permission_role = 'member');

alter table public.family_members
  drop constraint if exists family_members_minor_birth_date_check;
alter table public.family_members
  add constraint family_members_minor_birth_date_check
  check (household_role not in ('teen', 'child') or birth_date is null);

create table if not exists private.minor_profiles (
  member_id uuid primary key references public.family_members(id) on delete cascade,
  family_id uuid not null references public.families(id) on delete cascade,
  declared_band text not null,
  nicknames text[] not null default '{}',
  alerts_enabled boolean not null default true,
  quiet_start smallint not null default 1260,
  quiet_end smallint not null default 420,
  daily_limit_minutes smallint default 30,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table private.minor_profiles
  drop constraint if exists minor_profiles_declared_band;
alter table private.minor_profiles
  add constraint minor_profiles_declared_band
  check (declared_band in ('under_12', '12_15', '16_17'));

alter table private.minor_profiles
  drop constraint if exists minor_profiles_quiet_hours;
alter table private.minor_profiles
  add constraint minor_profiles_quiet_hours
  check (quiet_start between 0 and 1439 and quiet_end between 0 and 1439);

alter table private.minor_profiles
  drop constraint if exists minor_profiles_daily_limit;
alter table private.minor_profiles
  add constraint minor_profiles_daily_limit
  check (daily_limit_minutes is null or daily_limit_minutes in (15, 30, 60));

alter table private.minor_profiles
  drop constraint if exists minor_profiles_nicknames;
alter table private.minor_profiles
  add constraint minor_profiles_nicknames
  check (cardinality(nicknames) <= 8 and array_position(nicknames, null) is null);

alter table private.minor_profiles enable row level security;
revoke all on table private.minor_profiles
  from public, anon, authenticated, service_role;

create table if not exists private.minor_guardianships (
  id uuid primary key default gen_random_uuid(),
  family_id uuid references public.families(id) on delete set null,
  member_id uuid references public.family_members(id) on delete set null,
  guardian_user_id uuid references auth.users(id) on delete set null,
  guardian_user_hash text not null,
  relationship text not null,
  consent_text_version text not null,
  guardian_assurance text not null,
  created_at timestamptz not null default now(),
  ended_at timestamptz,
  end_reason text
);

alter table private.minor_guardianships
  drop constraint if exists minor_guardianships_relationship;
alter table private.minor_guardianships
  add constraint minor_guardianships_relationship
  check (relationship in ('mae', 'pai', 'responsavel_legal'));

alter table private.minor_guardianships
  drop constraint if exists minor_guardianships_end_reason;
alter table private.minor_guardianships
  add constraint minor_guardianships_end_reason
  check (
    (ended_at is null and end_reason is null)
    or (
      ended_at is not null
      and end_reason in (
        'reached_majority',
        'guardian_left',
        'guardian_withdrew',
        'member_removed',
        'account_deleted'
      )
    )
  );

create unique index if not exists minor_guardianships_one_live_per_guardian
  on private.minor_guardianships (member_id, guardian_user_id)
  where ended_at is null;

create index if not exists minor_guardianships_guardian_idx
  on private.minor_guardianships (guardian_user_id)
  where ended_at is null;

alter table private.minor_guardianships enable row level security;
revoke all on table private.minor_guardianships
  from public, anon, authenticated, service_role;

create table if not exists private.minor_data_consents (
  id uuid primary key default gen_random_uuid(),
  family_id uuid references public.families(id) on delete set null,
  member_id uuid references public.family_members(id) on delete set null,
  guardian_user_hash text not null,
  purpose text not null,
  text_version text not null,
  granted_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  withdrawn_by_hash text
);

alter table private.minor_data_consents
  drop constraint if exists minor_data_consents_purpose;
alter table private.minor_data_consents
  add constraint minor_data_consents_purpose
  check (purpose in ('account', 'profile', 'health'));

create index if not exists minor_data_consents_member_live_idx
  on private.minor_data_consents (member_id, purpose)
  where withdrawn_at is null;

alter table private.minor_data_consents enable row level security;
revoke all on table private.minor_data_consents
  from public, anon, authenticated, service_role;

create table if not exists private.account_terms_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  user_hash text not null,
  terms_version text not null,
  policy_version text not null,
  accepted_by text not null,
  guardian_user_hash text,
  accepted_at timestamptz not null default now()
);

alter table private.account_terms_acceptances
  drop constraint if exists account_terms_acceptances_accepted_by;
alter table private.account_terms_acceptances
  add constraint account_terms_acceptances_accepted_by
  check (accepted_by in ('self', 'guardian', 'self_with_guardian'));

create index if not exists account_terms_acceptances_user_idx
  on private.account_terms_acceptances (user_id, terms_version);

alter table private.account_terms_acceptances enable row level security;
revoke all on table private.account_terms_acceptances
  from public, anon, authenticated, service_role;

create table if not exists private.minor_acknowledgements (
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  text_version text not null,
  acknowledged_at timestamptz not null default now(),
  primary key (user_id, kind, text_version)
);

alter table private.minor_acknowledgements
  drop constraint if exists minor_acknowledgements_kind;
alter table private.minor_acknowledgements
  add constraint minor_acknowledgements_kind
  check (kind in ('entendi', 'aceitar'));

alter table private.minor_acknowledgements enable row level security;
revoke all on table private.minor_acknowledgements
  from public, anon, authenticated, service_role;

create table if not exists private.minor_usage_days (
  member_id uuid not null references public.family_members(id) on delete cascade,
  day date not null,
  minutes smallint not null default 0,
  primary key (member_id, day)
);

alter table private.minor_usage_days
  drop constraint if exists minor_usage_days_minutes;
alter table private.minor_usage_days
  add constraint minor_usage_days_minutes check (minutes between 0 and 1440);

alter table private.minor_usage_days enable row level security;
revoke all on table private.minor_usage_days
  from public, anon, authenticated, service_role;

create or replace function private.band_rank(band text)
returns integer
language sql
immutable
set search_path = pg_catalog
as $$
  select case band
    when 'under_12' then 0
    when '12_15' then 1
    when '16_17' then 2
  end;
$$;

create or replace function private.band_for_rank(band_rank integer)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case band_rank
    when 0 then 'under_12'
    when 1 then '12_15'
    when 2 then '16_17'
  end;
$$;

create or replace function private.role_for_band(band text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when band = 'under_12' then 'child'
    when band in ('12_15', '16_17') then 'teen'
  end;
$$;

revoke all on function private.band_rank(text)
  from public, anon, authenticated, service_role;
revoke all on function private.band_for_rank(integer)
  from public, anon, authenticated, service_role;
revoke all on function private.role_for_band(text)
  from public, anon, authenticated, service_role;

create or replace function private.normalized_nicknames(requested text[])
returns text[]
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  entry text;
  trimmed text;
  result text[] := '{}'::text[];
begin
  if requested is null then
    return '{}'::text[];
  end if;

  foreach entry in array requested loop
    trimmed := btrim(regexp_replace(coalesce(entry, ''), '[[:space:]]+', ' ', 'g'));
    if length(trimmed) < 1 or length(trimmed) > 40 then
      raise exception 'invalid_nicknames' using errcode = '22023';
    end if;
    if not exists (
      select 1
      from unnest(result) as kept(value)
      where lower(kept.value) = lower(trimmed)
    ) then
      result := array_append(result, trimmed);
    end if;
  end loop;

  if cardinality(result) > 8 then
    raise exception 'invalid_nicknames' using errcode = '22023';
  end if;

  return result;
end;
$$;

revoke all on function private.normalized_nicknames(text[])
  from public, anon, authenticated, service_role;

-- The effective age is always the most protective of the Apple record and any
-- band a guardian declared, and a claimed member with a live guardian is never
-- read as anything older than a minor.
create or replace function private.effective_age(target_user_id uuid)
returns table (
  status text,
  band text,
  band_source text,
  assurance text,
  parental_controls_active boolean,
  household_marked boolean,
  minor_since timestamptz,
  recorded_at timestamptz,
  recheck_after timestamptz,
  has_record boolean
)
language sql
stable
set search_path = pg_catalog, public, private
as $$
  with guardian as (
    select min(coalesce(private.band_rank(profiles.declared_band), 0)) as guardian_rank
    from public.family_members as members
    left join private.minor_profiles as profiles
      on profiles.member_id = members.id
    where target_user_id is not null
      and members.user_id = target_user_id
      and (
        profiles.member_id is not null
        or exists (
          select 1
          from private.minor_guardianships as links
          where links.member_id = members.id
            and links.ended_at is null
        )
      )
  ),
  merged as (
    select
      guardian.guardian_rank,
      stored.status as stored_status,
      stored.minor_band as stored_band,
      stored.assurance as stored_assurance,
      stored.parental_controls_active as stored_parental_controls,
      stored.household_marked as stored_marked,
      stored.minor_since as stored_minor_since,
      stored.recorded_at as stored_recorded_at,
      stored.recheck_after as stored_recheck_after,
      case
        when stored.status = 'minor' then private.band_rank(stored.minor_band)
      end as stored_rank
    from guardian
    left join private.account_age_status as stored
      on stored.user_id = target_user_id
  )
  select
    case
      when merged.guardian_rank is not null then 'minor'
      else coalesce(merged.stored_status, 'unknown')
    end,
    private.band_for_rank(
      case
        when merged.guardian_rank is not null
          then least(merged.guardian_rank, coalesce(merged.stored_rank, merged.guardian_rank))
        else merged.stored_rank
      end
    ),
    case
      when merged.guardian_rank is not null
        and (
          merged.stored_rank is null
          or merged.guardian_rank < merged.stored_rank
          or (merged.stored_marked and merged.stored_assurance = 'guardian_declared')
        ) then 'guardian'
      when merged.guardian_rank is not null or merged.stored_status = 'minor' then 'apple'
    end,
    coalesce(merged.stored_assurance, 'none'),
    coalesce(merged.stored_parental_controls, false),
    coalesce(merged.stored_marked, false),
    merged.stored_minor_since,
    merged.stored_recorded_at,
    merged.stored_recheck_after,
    merged.stored_status is not null
  from merged;
$$;

revoke all on function private.effective_age(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.is_adult(target_user_id uuid)
returns boolean
language sql
stable
set search_path = pg_catalog, private
as $$
  select coalesce(
    (select ages.status = 'adult' from private.effective_age(target_user_id) as ages),
    false
  );
$$;

-- Acting for a minor is never widened by the policy row: only Apple-confirmed
-- or operator-set adults without active parental controls are trusted.
create or replace function private.is_trusted_adult(target_user_id uuid)
returns boolean
language sql
stable
set search_path = pg_catalog, private
as $$
  select coalesce(
    (
      select ages.status = 'adult'
        and not ages.parental_controls_active
        and ages.assurance in ('confirmed', 'operator')
      from private.effective_age(target_user_id) as ages
    ),
    false
  );
$$;

create or replace function private.may_use_ai(target_user_id uuid)
returns boolean
language sql
stable
set search_path = pg_catalog, private
as $$
  select coalesce(
    (
      select ages.status = 'adult'
        and not ages.parental_controls_active
        and ages.assurance = any(policy.trusted_assurances)
      from private.effective_age(target_user_id) as ages
      cross join private.age_policy as policy
      where policy.singleton
    ),
    false
  );
$$;

create or replace function private.ai_blocked(target_user_id uuid)
returns boolean
language sql
stable
set search_path = pg_catalog, private
as $$
  select exists (
    select 1
    from private.nina_ai_blocks as blocks
    where blocks.user_id = target_user_id
      and blocks.lifted_at is null
  );
$$;

-- A guardian acts for a ward only while both live in the same house as
-- members: membership is the authorization boundary, never the link alone.
create or replace function private.is_live_guardian(
  target_member_id uuid,
  target_user_id uuid
)
returns boolean
language sql
stable
set search_path = pg_catalog, public, private
as $$
  select target_member_id is not null
    and target_user_id is not null
    and exists (
      select 1
      from private.minor_guardianships as links
      where links.member_id = target_member_id
        and links.guardian_user_id = target_user_id
        and links.ended_at is null
    )
    and exists (
      select 1
      from public.family_members as wards
      join public.family_members as guardians
        on guardians.family_id = wards.family_id
      where wards.id = target_member_id
        and guardians.user_id = target_user_id
        and guardians.household_role = 'adult'
    );
$$;

create or replace function private.guardian_names(target_member_id uuid)
returns jsonb
language sql
stable
set search_path = pg_catalog, public, private
as $$
  select coalesce(
    jsonb_agg(guardian_name order by created_at),
    '[]'::jsonb
  )
  from (
    select
      coalesce(
        nullif(trim(guardian_profiles.display_name), ''),
        nullif(trim(guardian_members.name), ''),
        'Responsável'
      ) as guardian_name,
      min(links.created_at) as created_at
    from private.minor_guardianships as links
    join public.family_members as wards on wards.id = links.member_id
    left join public.family_members as guardian_members
      on guardian_members.family_id = wards.family_id
     and guardian_members.user_id = links.guardian_user_id
    left join public.profiles as guardian_profiles
      on guardian_profiles.id = links.guardian_user_id
    where links.member_id = target_member_id
      and links.ended_at is null
      and links.guardian_user_id is not null
    group by 1
  ) as named;
$$;

create or replace function private.has_live_minor_consent(
  target_member_id uuid,
  consent_purpose text
)
returns boolean
language sql
stable
set search_path = pg_catalog, private
as $$
  select exists (
    select 1
    from private.minor_data_consents as consents
    where consents.member_id = target_member_id
      and consents.purpose = consent_purpose
      and consents.withdrawn_at is null
  );
$$;

revoke all on function private.is_adult(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.is_trusted_adult(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.may_use_ai(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.ai_blocked(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.is_live_guardian(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.guardian_names(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.has_live_minor_consent(uuid, text)
  from public, anon, authenticated, service_role;

create or replace function private.age_status_json(target_user_id uuid)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog, public, private
as $$
declare
  ages record;
  policy private.age_policy%rowtype;
  names jsonb;
  former_names jsonb;
  accepted_current boolean;
  reached_majority boolean;
begin
  select * into ages from private.effective_age(target_user_id);
  select * into policy from private.age_policy where singleton;

  select coalesce(jsonb_agg(distinct guardian.name), '[]'::jsonb)
  into names
  from public.family_members as wards
  cross join lateral jsonb_array_elements_text(private.guardian_names(wards.id)) as guardian(name)
  where wards.user_id = target_user_id;

  select coalesce(jsonb_agg(distinct former.guardian_name), '[]'::jsonb)
  into former_names
  from (
    select coalesce(
      nullif(trim(guardian_profiles.display_name), ''),
      nullif(trim(guardian_members.name), ''),
      'Responsável'
    ) as guardian_name
    from private.minor_guardianships as links
    join public.family_members as wards on wards.id = links.member_id
    left join public.family_members as guardian_members
      on guardian_members.family_id = wards.family_id
     and guardian_members.user_id = links.guardian_user_id
    left join public.profiles as guardian_profiles
      on guardian_profiles.id = links.guardian_user_id
    where wards.user_id = target_user_id
      and links.end_reason = 'reached_majority'
      and links.guardian_user_id is not null
  ) as former;

  select exists (
    select 1
    from private.account_terms_acceptances as acceptances
    where acceptances.user_id = target_user_id
      and acceptances.terms_version = policy.current_terms_version
  )
  into accepted_current;

  select ages.status = 'adult'
    and exists (
      select 1
      from private.minor_guardianships as links
      join public.family_members as wards on wards.id = links.member_id
      where wards.user_id = target_user_id
        and links.end_reason = 'reached_majority'
    )
    and not exists (
      select 1
      from private.account_terms_acceptances as acceptances
      where acceptances.user_id = target_user_id
        and acceptances.accepted_by = 'self'
        and acceptances.terms_version = policy.current_terms_version
    )
  into reached_majority;

  return jsonb_build_object(
    'status', ages.status,
    'band', case when ages.status = 'minor' then ages.band end,
    'band_source', case when ages.status = 'minor' then ages.band_source end,
    'assurance', ages.assurance,
    'parental_controls_active', ages.parental_controls_active,
    'household_marked', ages.household_marked,
    'trusted_adult', private.is_trusted_adult(target_user_id),
    'may_use_ai', private.may_use_ai(target_user_id),
    'may_buy_premium', private.may_use_ai(target_user_id),
    'ai_blocked', private.ai_blocked(target_user_id),
    'recorded_at', case
      when not ages.has_record
        or (ages.household_marked and ages.assurance = 'guardian_declared') then null
      else ages.recorded_at
    end,
    'recheck_after', ages.recheck_after,
    'guardian_names', names,
    'needs_name', ages.status <> 'adult'
      and coalesce(
        (
          select profiles.display_name_source = 'auth'
          from public.profiles
          where profiles.id = target_user_id
        ),
        true
      ),
    'terms', jsonb_build_object(
      'current_terms_version', policy.current_terms_version,
      'current_policy_version', policy.current_policy_version,
      'current_minor_consent_version', policy.current_minor_consent_version,
      'accepted_current', accepted_current,
      'reached_majority', coalesce(reached_majority, false),
      'former_guardian_names', case
        when coalesce(reached_majority, false) then former_names
        else '[]'::jsonb
      end
    )
  );
end;
$$;

revoke all on function private.age_status_json(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.current_user_is_adult()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth, private
as $$
  select auth.uid() is not null and private.is_adult(auth.uid());
$$;

revoke all on function public.current_user_is_adult()
  from public, anon, authenticated, service_role;
grant execute on function public.current_user_is_adult() to authenticated;

create or replace function public.is_adult_family_member(target_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth, private
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.family_members as members
      where members.family_id = target_family_id
        and members.user_id = auth.uid()
        and members.household_role = 'adult'
    )
    and private.is_adult(auth.uid());
$$;

revoke all on function public.is_adult_family_member(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.is_adult_family_member(uuid) to authenticated;

comment on function public.is_adult_family_member(uuid) is
  'Row level security predicate for every household table. It takes no user id, so it can only ever answer about the caller.';

-- get_my_age_status never takes a parameter: an argument would turn it into an
-- oracle for anyone else's age.
create or replace function public.get_my_age_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, private
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  return private.age_status_json(auth.uid());
end;
$$;

revoke all on function public.get_my_age_status()
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_age_status() to authenticated;

create or replace function public.record_terms_acceptance()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  ages record;
  policy private.age_policy%rowtype;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into ages from private.effective_age(current_user_id);
  if not ages.has_record then
    raise exception 'age_signal_required' using errcode = 'P0001';
  end if;
  if ages.status <> 'adult' then
    raise exception 'adult_account_required' using errcode = '42501';
  end if;

  select * into policy from private.age_policy where singleton;

  if not exists (
    select 1
    from private.account_terms_acceptances as acceptances
    where acceptances.user_id = current_user_id
      and acceptances.accepted_by = 'self'
      and acceptances.terms_version = policy.current_terms_version
      and acceptances.policy_version = policy.current_policy_version
  ) then
    insert into private.account_terms_acceptances (
      user_id,
      user_hash,
      terms_version,
      policy_version,
      accepted_by
    )
    values (
      current_user_id,
      private.user_hash(current_user_id),
      policy.current_terms_version,
      policy.current_policy_version,
      'self'
    );
  end if;

  return private.age_status_json(current_user_id);
end;
$$;

revoke all on function public.record_terms_acceptance()
  from public, anon, authenticated, service_role;
grant execute on function public.record_terms_acceptance() to authenticated;

create or replace function private.minimize_minor_profile(target_user_id uuid)
returns void
language sql
set search_path = pg_catalog, public
as $$
  update public.profiles
  set
    email = null,
    phone = '',
    birthday_label = '',
    availability_note = '',
    memory_note = '',
    communication_preference = 'gentle',
    sex = 'notDetermined',
    avatar = '{}'::jsonb
  where profiles.id = target_user_id;
$$;

revoke all on function private.minimize_minor_profile(uuid)
  from public, anon, authenticated, service_role;

-- A move toward protection takes effect at once and everywhere the person is
-- a member: no live AI consent, no administrator seat, no optional profile data.
create or replace function private.apply_protective_age_effects(target_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog, public, private
as $$
declare
  membership record;
begin
  update public.nina_ai_consents as consents
  set
    revoked_at = now(),
    revoke_reason = 'age_status'
  where consents.user_id = target_user_id
    and consents.revoked_at is null;

  update public.nina_proposals as proposals
  set
    state = 'rejected',
    resolved_at = now(),
    resolved_payload = jsonb_build_object('reason', 'age_status')
  where proposals.owner_user_id = target_user_id
    and proposals.state = 'pending';

  for membership in
    select distinct members.family_id
    from public.family_members as members
    where members.user_id = target_user_id
    order by members.family_id
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(membership.family_id::text, 0)
    );

    update public.family_members as members
    set
      permission_role = case
        when members.permission_role = 'admin' then 'member'
        else members.permission_role
      end,
      household_role = members.household_role
    where members.family_id = membership.family_id
      and members.user_id = target_user_id;
  end loop;

  perform private.minimize_minor_profile(target_user_id);
end;
$$;

revoke all on function private.apply_protective_age_effects(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.release_minor_account(
  target_user_id uuid,
  release_reason text
)
returns void
language plpgsql
set search_path = pg_catalog, public, private
as $$
declare
  membership record;
begin
  for membership in
    select members.id, members.family_id
    from public.family_members as members
    where members.user_id = target_user_id
    order by members.family_id, members.id
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(membership.family_id::text, 0)
    );

    update private.minor_guardianships as links
    set
      ended_at = now(),
      end_reason = release_reason
    where links.member_id = membership.id
      and links.ended_at is null;

    update private.minor_data_consents as consents
    set withdrawn_at = now()
    where consents.member_id = membership.id
      and consents.withdrawn_at is null;

    delete from private.minor_profiles as profiles
    where profiles.member_id = membership.id;

    update public.family_members as members
    set household_role = members.household_role
    where members.id = membership.id;
  end loop;
end;
$$;

revoke all on function private.release_minor_account(uuid, text)
  from public, anon, authenticated, service_role;

create or replace function private.store_age_status(
  target_user_id uuid,
  next_status text,
  next_band text,
  next_assurance text,
  next_parental_controls boolean,
  enforce_ratchet boolean
)
returns jsonb
language plpgsql
set search_path = pg_catalog, public, auth, private
as $$
declare
  stored private.account_age_status%rowtype;
  previous_status text;
  previous_rank integer;
  previous_minor boolean;
  protective boolean;
  changed boolean;
  normalized_band text := case when next_status = 'minor' then next_band end;
  next_recheck timestamptz := case
    when next_status = 'adult' then now() + interval '180 days'
    else now() + interval '30 days'
  end;
  ages record;
  membership record;
begin
  if target_user_id is null
     or not exists (select 1 from auth.users where users.id = target_user_id)
     or next_status is null
     or next_status not in ('adult', 'minor', 'unknown')
     or (next_status = 'minor') <> (next_band is not null)
     or (next_band is not null and next_band not in ('under_12', '12_15', '16_17'))
     or next_assurance is null
     or next_assurance not in ('confirmed', 'self_declared', 'guardian_declared', 'operator', 'none')
     or next_parental_controls is null then
    raise exception 'age_signal_invalid' using errcode = '22023';
  end if;

  for membership in
    select distinct members.family_id
    from public.family_members as members
    where members.user_id = target_user_id
    order by members.family_id
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(membership.family_id::text, 0)
    );
  end loop;

  select *
  into stored
  from private.account_age_status as ages_row
  where ages_row.user_id = target_user_id
  for update;

  select * into ages from private.effective_age(target_user_id);
  previous_status := ages.status;
  previous_rank := private.band_rank(ages.band);
  -- Declining to share is not a minor record: only a minor status, a band a
  -- guardian set, or a household marking keeps an account from self-declaring.
  previous_minor := previous_status = 'minor'
    or stored.minor_since is not null
    or coalesce(stored.household_marked, false);

  if enforce_ratchet and next_status = 'adult' and previous_status <> 'adult' then
    if previous_minor and next_assurance <> 'confirmed' then
      raise exception 'age_signal_rejected' using errcode = '22023';
    end if;
  end if;

  protective := case
    when next_status = 'adult' then false
    when next_status = 'minor' then
      previous_status <> 'minor'
      or private.band_rank(normalized_band) < coalesce(previous_rank, 3)
    else previous_status <> 'unknown'
  end;

  if stored.user_id is null then
    insert into private.account_age_status (
      user_id,
      status,
      minor_band,
      assurance,
      parental_controls_active,
      household_marked,
      minor_since,
      recorded_at,
      recheck_after
    )
    values (
      target_user_id,
      next_status,
      normalized_band,
      next_assurance,
      next_parental_controls,
      false,
      case when next_status = 'minor' then now() end,
      now(),
      next_recheck
    );
    changed := true;
  else
    changed := stored.status is distinct from next_status
      or stored.minor_band is distinct from normalized_band
      or stored.assurance is distinct from next_assurance
      or stored.parental_controls_active is distinct from next_parental_controls;

    update private.account_age_status as ages_row
    set
      status = next_status,
      minor_band = normalized_band,
      assurance = next_assurance,
      parental_controls_active = next_parental_controls,
      household_marked = case
        when next_status = 'adult' then false
        else ages_row.household_marked
      end,
      minor_since = case
        when next_status = 'minor' then coalesce(ages_row.minor_since, now())
        else ages_row.minor_since
      end,
      recorded_at = now(),
      recheck_after = next_recheck
    where ages_row.user_id = target_user_id;
  end if;

  if next_status = 'adult' and previous_status <> 'adult' then
    perform private.release_minor_account(target_user_id, 'reached_majority');
  elsif protective then
    perform private.apply_protective_age_effects(target_user_id);
  elsif changed then
    update public.family_members as members
    set household_role = members.household_role
    where members.user_id = target_user_id;
  end if;

  select * into ages from private.effective_age(target_user_id);

  return jsonb_build_object(
    'status', ages.status,
    'band', case when ages.status = 'minor' then ages.band end,
    'changed', changed,
    'photo_cleanup_required', protective
  );
end;
$$;

revoke all on function private.store_age_status(uuid, text, text, text, boolean, boolean)
  from public, anon, authenticated, service_role;

-- The ratchet lives here rather than in the Edge Function, so a compromised
-- function still cannot move an account away from protection.
create or replace function public.record_age_signal(
  target_user_id uuid,
  signal_status text,
  signal_band text,
  signal_assurance text,
  signal_parental_controls boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
begin
  if signal_assurance = 'operator' then
    raise exception 'age_signal_invalid' using errcode = '22023';
  end if;

  return private.store_age_status(
    target_user_id,
    signal_status,
    signal_band,
    signal_assurance,
    signal_parental_controls,
    true
  );
end;
$$;

revoke all on function public.record_age_signal(uuid, text, text, text, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.record_age_signal(uuid, text, text, text, boolean)
  to service_role;

create or replace function private.operator_set_age_status(
  target_user_id uuid,
  new_status text,
  new_band text,
  trusted boolean,
  reason_code text
)
returns jsonb
language plpgsql
set search_path = pg_catalog, public, auth, private
as $$
begin
  if coalesce(reason_code, '') !~ '^[a-z0-9_]{3,40}$' or trusted is null then
    raise exception 'invalid_reason_code' using errcode = '22023';
  end if;

  return private.store_age_status(
    target_user_id,
    new_status,
    new_band,
    case
      when new_status = 'unknown' then 'none'
      when trusted then 'operator'
      else 'self_declared'
    end,
    false,
    false
  );
end;
$$;

revoke all on function private.operator_set_age_status(uuid, text, text, boolean, text)
  from public, anon, authenticated, service_role;

-- A claimed member's household role follows the account's age and is never a
-- client's choice; an owner who becomes a minor keeps the row as it was and
-- loses every power through the age checks instead.
create or replace function public.enforce_family_member_age()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  ages record;
  derived_role text;
begin
  if new.user_id is not null then
    select * into ages from private.effective_age(new.user_id);

    derived_role := case
      when ages.status = 'adult' then 'adult'
      when ages.status = 'minor' then private.role_for_band(ages.band)
    end;

    if derived_role is not null
       and new.household_role is distinct from derived_role
       and not (derived_role <> 'adult' and new.permission_role = 'owner') then
      new.household_role := derived_role;
    end if;
  end if;

  if new.household_role in ('child', 'teen') then
    new.birth_date := null;
    if new.permission_role = 'admin' then
      new.permission_role := 'member';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_family_member_age()
  from public, anon, authenticated, service_role;

drop trigger if exists family_members_enforce_age on public.family_members;
create trigger family_members_enforce_age
  before insert or update of user_id, household_role, permission_role, birth_date
  on public.family_members
  for each row execute function public.enforce_family_member_age();

create or replace function public.guard_minor_profile_fields()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if exists (
    select 1
    from private.effective_age(new.id) as ages
    where ages.status = 'minor'
  ) then
    new.email := null;
    new.phone := '';
    new.birthday_label := '';
    new.availability_note := '';
    new.memory_note := '';
    new.communication_preference := 'gentle';
    new.sex := 'notDetermined';
    new.avatar := '{}'::jsonb;
  end if;

  return new;
end;
$$;

revoke all on function public.guard_minor_profile_fields()
  from public, anon, authenticated, service_role;

drop trigger if exists profiles_minor_fields_guard on public.profiles;
create trigger profiles_minor_fields_guard
  before insert or update on public.profiles
  for each row execute function public.guard_minor_profile_fields();

-- It runs after the owner label has been resolved to a member, so a health
-- task named for a child cannot slip past by arriving with only a label.
create or replace function public.guard_minor_health_task()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if new.category_id is distinct from 'health' or new.owner_member_id is null then
    return null;
  end if;

  if tg_op = 'UPDATE'
     and old.category_id is not distinct from new.category_id
     and old.owner_member_id is not distinct from new.owner_member_id then
    return null;
  end if;

  if exists (
    select 1
    from public.family_members as members
    where members.id = new.owner_member_id
      and members.household_role in ('child', 'teen')
  )
  and not private.has_live_minor_consent(new.owner_member_id, 'health') then
    raise exception 'minor_health_consent_required' using errcode = 'P0001';
  end if;

  return null;
end;
$$;

revoke all on function public.guard_minor_health_task()
  from public, anon, authenticated, service_role;

drop trigger if exists tasks_minor_health_guard on public.tasks;
create trigger tasks_minor_health_guard
  after insert or update on public.tasks
  for each row execute function public.guard_minor_health_task();

commit;
