begin;

-- Age is a band the server holds, written only by the service role after an
-- App Attest-verified signal, and never a birth date or a range bound.
create table if not exists private.account_age_status (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null,
  minor_band text,
  assurance text not null default 'none',
  parental_controls_active boolean not null default false,
  household_marked boolean not null default false,
  minor_since timestamptz,
  recorded_at timestamptz not null default now(),
  recheck_after timestamptz not null
);

alter table private.account_age_status
  drop constraint if exists account_age_status_status;
alter table private.account_age_status
  add constraint account_age_status_status
  check (status in ('adult', 'minor', 'unknown'));

alter table private.account_age_status
  drop constraint if exists account_age_status_band;
alter table private.account_age_status
  add constraint account_age_status_band
  check (minor_band is null or minor_band in ('under_12', '12_15', '16_17'));

alter table private.account_age_status
  drop constraint if exists account_age_status_assurance;
alter table private.account_age_status
  add constraint account_age_status_assurance
  check (
    assurance in (
      'confirmed',
      'self_declared',
      'guardian_declared',
      'operator',
      'none'
    )
  );

alter table private.account_age_status
  drop constraint if exists account_age_status_band_matches;
alter table private.account_age_status
  add constraint account_age_status_band_matches
  check ((status = 'minor') = (minor_band is not null));

alter table private.account_age_status enable row level security;
revoke all on table private.account_age_status
  from public, anon, authenticated, service_role;

create table if not exists private.age_policy (
  singleton boolean primary key default true,
  trusted_assurances text[] not null default '{confirmed,operator}',
  current_policy_version text not null,
  current_terms_version text not null,
  current_minor_consent_version text not null,
  legacy_profile_deadline timestamptz,
  updated_at timestamptz not null default now()
);

alter table private.age_policy
  drop constraint if exists age_policy_singleton;
alter table private.age_policy
  add constraint age_policy_singleton check (singleton);

-- Self-declared adults may be let into chat and Premium by the operator, but
-- the two proven assurances can never be switched off.
alter table private.age_policy
  drop constraint if exists age_policy_trusted_assurances;
alter table private.age_policy
  add constraint age_policy_trusted_assurances
  check (
    trusted_assurances <@ array['confirmed', 'operator', 'self_declared']::text[]
    and trusted_assurances @> array['confirmed', 'operator']::text[]
  );

alter table private.age_policy enable row level security;
revoke all on table private.age_policy
  from public, anon, authenticated, service_role;

insert into private.age_policy (
  singleton,
  current_policy_version,
  current_terms_version,
  current_minor_consent_version
)
values (true, '2026-09-29', '2026-09-29', '2026-09-29')
on conflict (singleton) do update
set
  current_policy_version = excluded.current_policy_version,
  current_terms_version = excluded.current_terms_version,
  current_minor_consent_version = excluded.current_minor_consent_version,
  updated_at = now();

create table if not exists private.age_signal_challenges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  challenge_hash text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz
);

alter table private.age_signal_challenges
  drop constraint if exists age_signal_challenges_hash_shape;
alter table private.age_signal_challenges
  add constraint age_signal_challenges_hash_shape
  check (challenge_hash ~ '^[0-9a-f]{64}$');

create index if not exists age_signal_challenges_user_created_idx
  on private.age_signal_challenges (user_id, created_at desc);

alter table private.age_signal_challenges enable row level security;
revoke all on table private.age_signal_challenges
  from public, anon, authenticated, service_role;

create table if not exists private.app_attest_keys (
  key_id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  public_key_spki text not null,
  counter bigint not null default 0,
  environment text not null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);

alter table private.app_attest_keys
  drop constraint if exists app_attest_keys_environment;
alter table private.app_attest_keys
  add constraint app_attest_keys_environment
  check (environment in ('production', 'development'));

alter table private.app_attest_keys
  drop constraint if exists app_attest_keys_shape;
alter table private.app_attest_keys
  add constraint app_attest_keys_shape
  check (
    length(key_id) between 1 and 200
    and length(public_key_spki) between 1 and 400
    and counter >= 0
  );

create index if not exists app_attest_keys_user_idx
  on private.app_attest_keys (user_id);

alter table private.app_attest_keys enable row level security;
revoke all on table private.app_attest_keys
  from public, anon, authenticated, service_role;

create table if not exists private.pseudonym_salt (
  singleton boolean primary key default true,
  salt bytea not null default extensions.gen_random_bytes(32),
  created_at timestamptz not null default now()
);

alter table private.pseudonym_salt
  drop constraint if exists pseudonym_salt_singleton;
alter table private.pseudonym_salt
  add constraint pseudonym_salt_singleton check (singleton);

alter table private.pseudonym_salt enable row level security;
revoke all on table private.pseudonym_salt
  from public, anon, authenticated, service_role;

insert into private.pseudonym_salt (singleton)
values (true)
on conflict (singleton) do nothing;

create table if not exists private.nina_ai_blocks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reason_code text not null,
  created_at timestamptz not null default now(),
  lifted_at timestamptz,
  lift_reason_code text
);

alter table private.nina_ai_blocks
  drop constraint if exists nina_ai_blocks_reason_code;
alter table private.nina_ai_blocks
  add constraint nina_ai_blocks_reason_code
  check (reason_code in ('child_safety_hold', 'operator'));

alter table private.nina_ai_blocks
  drop constraint if exists nina_ai_blocks_lift_reason_shape;
alter table private.nina_ai_blocks
  add constraint nina_ai_blocks_lift_reason_shape
  check (
    lift_reason_code is null
    or lift_reason_code ~ '^[a-z0-9_]{3,40}$'
  );

alter table private.nina_ai_blocks enable row level security;
revoke all on table private.nina_ai_blocks
  from public, anon, authenticated, service_role;

create or replace function private.user_hash(target_user_id uuid)
returns text
language sql
stable
set search_path = pg_catalog, private, extensions
as $$
  select encode(
    extensions.digest(salts.salt || uuid_send(target_user_id), 'sha256'),
    'hex'
  )
  from private.pseudonym_salt as salts
  where salts.singleton;
$$;

revoke all on function private.user_hash(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.issue_age_signal_challenge(
  target_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  raw_challenge bytea := extensions.gen_random_bytes(32);
  challenge_expires_at timestamptz := now() + interval '5 minutes';
  recent_challenges integer;
begin
  if target_user_id is null
     or not exists (select 1 from auth.users where users.id = target_user_id) then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  delete from private.age_signal_challenges as challenges
  where challenges.created_at < now() - interval '1 hour'
    and (challenges.used_at is not null or challenges.expires_at <= now());

  select count(*)::integer
  into recent_challenges
  from private.age_signal_challenges as challenges
  where challenges.user_id = target_user_id
    and challenges.created_at > now() - interval '1 hour';

  if recent_challenges >= 20 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  insert into private.age_signal_challenges (
    user_id,
    challenge_hash,
    expires_at
  )
  values (
    target_user_id,
    encode(extensions.digest(raw_challenge, 'sha256'), 'hex'),
    challenge_expires_at
  );

  return jsonb_build_object(
    'challenge', rtrim(
      translate(replace(encode(raw_challenge, 'base64'), E'\n', ''), '+/', '-_'),
      '='
    ),
    'expires_at', challenge_expires_at
  );
end;
$$;

revoke all on function public.issue_age_signal_challenge(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.issue_age_signal_challenge(uuid) to service_role;

create or replace function public.consume_age_signal_challenge(
  target_user_id uuid,
  challenge text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  normalized text := translate(coalesce(challenge, ''), '-_', '+/');
  raw_challenge bytea;
begin
  if target_user_id is null
     or normalized !~ '^[A-Za-z0-9+/]{43}$' then
    return false;
  end if;

  begin
    raw_challenge := decode(normalized || '=', 'base64');
  exception when others then
    return false;
  end;

  if octet_length(raw_challenge) <> 32 then
    return false;
  end if;

  update private.age_signal_challenges as challenges
  set used_at = now()
  where challenges.user_id = target_user_id
    and challenges.challenge_hash = encode(
      extensions.digest(raw_challenge, 'sha256'),
      'hex'
    )
    and challenges.used_at is null
    and challenges.expires_at > now();

  return found;
end;
$$;

revoke all on function public.consume_age_signal_challenge(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.consume_age_signal_challenge(uuid, text)
  to service_role;

create or replace function public.register_app_attest_key(
  target_user_id uuid,
  attest_key_id text,
  public_key_spki text,
  attest_environment text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  existing_owner uuid;
begin
  if target_user_id is null
     or coalesce(attest_key_id, '') = ''
     or coalesce(public_key_spki, '') = ''
     or attest_environment not in ('production', 'development') then
    raise exception 'app_attest_invalid' using errcode = '22023';
  end if;

  select keys.user_id
  into existing_owner
  from private.app_attest_keys as keys
  where keys.key_id = attest_key_id
  for update;

  -- A device key belongs to the account that attested it and is never moved.
  if existing_owner is not null and existing_owner <> target_user_id then
    raise exception 'app_attest_invalid' using errcode = '22023';
  end if;

  insert into private.app_attest_keys (
    key_id,
    user_id,
    public_key_spki,
    counter,
    environment
  )
  values (
    attest_key_id,
    target_user_id,
    register_app_attest_key.public_key_spki,
    0,
    attest_environment
  )
  on conflict (key_id) do update
  set
    public_key_spki = excluded.public_key_spki,
    environment = excluded.environment,
    counter = 0,
    last_used_at = null;
end;
$$;

revoke all on function public.register_app_attest_key(uuid, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.register_app_attest_key(uuid, text, text, text)
  to service_role;

create or replace function public.get_app_attest_key(
  target_user_id uuid,
  attest_key_id text
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select jsonb_build_object(
    'public_key_spki', keys.public_key_spki,
    'counter', keys.counter,
    'environment', keys.environment
  )
  from private.app_attest_keys as keys
  where keys.key_id = attest_key_id
    and keys.user_id = target_user_id;
$$;

revoke all on function public.get_app_attest_key(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_app_attest_key(uuid, text) to service_role;

create or replace function public.advance_app_attest_counter(
  attest_key_id text,
  new_counter bigint
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  update private.app_attest_keys as keys
  set
    counter = new_counter,
    last_used_at = now()
  where keys.key_id = attest_key_id
    and new_counter > keys.counter;

  return found;
end;
$$;

revoke all on function public.advance_app_attest_counter(text, bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.advance_app_attest_counter(text, bigint)
  to service_role;

-- The TestFlight measurement for D3 counts stored records and never reads a
-- birth date or a range bound, because none is ever stored.
create or replace function private.age_assurance_distribution()
returns table (
  status text,
  band text,
  assurance text,
  parental_controls_active boolean,
  accounts bigint
)
language sql
stable
set search_path = pg_catalog, private
as $$
  select
    ages.status,
    ages.minor_band,
    ages.assurance,
    ages.parental_controls_active,
    count(*)::bigint
  from private.account_age_status as ages
  group by ages.status, ages.minor_band, ages.assurance, ages.parental_controls_active
  order by ages.status, ages.minor_band nulls first, ages.assurance, ages.parental_controls_active;
$$;

revoke all on function private.age_assurance_distribution()
  from public, anon, authenticated, service_role;

create or replace function private.operator_lift_ai_block(
  target_user_id uuid,
  reason_code text
)
returns void
language plpgsql
set search_path = pg_catalog, private
as $$
begin
  if coalesce(reason_code, '') !~ '^[a-z0-9_]{3,40}$' then
    raise exception 'invalid_reason_code' using errcode = '22023';
  end if;

  update private.nina_ai_blocks as blocks
  set
    lifted_at = now(),
    lift_reason_code = operator_lift_ai_block.reason_code
  where blocks.user_id = target_user_id
    and blocks.lifted_at is null;

  if not found then
    raise exception 'nina_ai_block_not_found' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function private.operator_lift_ai_block(uuid, text)
  from public, anon, authenticated, service_role;

commit;
