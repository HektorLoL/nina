begin;

create table public.waitlist_signups (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  first_name text,
  consent_version text not null,
  consented_at timestamptz not null default now(),
  source text not null default 'landing',
  locale text not null default 'pt-BR',
  status text not null default 'subscribed'
    check (status in ('subscribed', 'unsubscribed')),
  last_submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint waitlist_signups_email_is_normalized
    check (email = lower(trim(email)) and length(email) between 3 and 254),
  constraint waitlist_signups_first_name_is_valid
    check (first_name is null or length(first_name) between 1 and 80),
  constraint waitlist_signups_consent_version_is_valid
    check (
      length(consent_version) between 1 and 40
      and consent_version ~ '^[A-Za-z0-9._-]+$'
    ),
  constraint waitlist_signups_source_is_valid
    check (length(source) between 1 and 40 and source ~ '^[a-z0-9_-]+$'),
  constraint waitlist_signups_locale_is_valid
    check (
      length(locale) between 2 and 20
      and locale ~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$'
    )
);

create index waitlist_signups_status_created_idx
  on public.waitlist_signups(status, created_at desc);

create trigger waitlist_signups_set_updated_at
  before update on public.waitlist_signups
  for each row execute function public.set_updated_at();

create table public.waitlist_submission_limits (
  fingerprint text primary key
    check (fingerprint ~ '^[0-9a-f]{64}$'),
  attempts integer not null default 1
    check (attempts > 0),
  window_started_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '1 day')
);

create index waitlist_submission_limits_expiry_idx
  on public.waitlist_submission_limits(expires_at);

alter table public.waitlist_signups enable row level security;
alter table public.waitlist_submission_limits enable row level security;

revoke all on table public.waitlist_signups from public, anon, authenticated;
revoke all on table public.waitlist_submission_limits from public, anon, authenticated;

comment on table public.waitlist_signups is
  'Consent-backed launch notifications. Trusted web backends submit through register_waitlist_signup.';
comment on table public.waitlist_submission_limits is
  'Short-lived salted request fingerprints used only to limit anonymous waitlist abuse.';

create or replace function public.register_waitlist_signup(
  p_email text,
  p_first_name text default null,
  p_consent boolean default false,
  p_consent_version text default '',
  p_source text default 'landing',
  p_locale text default 'pt-BR',
  p_request_fingerprint text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_email text := lower(trim(coalesce(p_email, '')));
  normalized_name text := nullif(
    regexp_replace(trim(coalesce(p_first_name, '')), '[[:space:]]+', ' ', 'g'),
    ''
  );
  normalized_consent_version text := trim(coalesce(p_consent_version, ''));
  normalized_source text := lower(trim(coalesce(p_source, 'landing')));
  normalized_locale text := trim(coalesce(p_locale, 'pt-BR'));
  normalized_fingerprint text := lower(trim(coalesce(p_request_fingerprint, '')));
  limit_attempts integer;
begin
  if not coalesce(p_consent, false) then
    raise exception 'waitlist_consent_required' using errcode = '22023';
  end if;

  if length(normalized_email) > 254
     or normalized_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'waitlist_email_invalid' using errcode = '22023';
  end if;

  if normalized_name is not null and length(normalized_name) > 80 then
    raise exception 'waitlist_name_invalid' using errcode = '22023';
  end if;

  if length(normalized_consent_version) not between 1 and 40
     or normalized_consent_version !~ '^[A-Za-z0-9._-]+$' then
    raise exception 'waitlist_consent_version_invalid' using errcode = '22023';
  end if;

  if length(normalized_source) not between 1 and 40
     or normalized_source !~ '^[a-z0-9_-]+$' then
    raise exception 'waitlist_source_invalid' using errcode = '22023';
  end if;

  if length(normalized_locale) not between 2 and 20
     or normalized_locale !~ '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    normalized_locale := 'pt-BR';
  end if;

  if normalized_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'waitlist_fingerprint_invalid' using errcode = '22023';
  end if;

  delete from public.waitlist_submission_limits
  where expires_at <= now();

  insert into public.waitlist_submission_limits (
    fingerprint,
    attempts,
    window_started_at,
    expires_at
  )
  values (
    normalized_fingerprint,
    1,
    now(),
    now() + interval '1 day'
  )
  on conflict (fingerprint) do update
  set
    attempts = case
      when waitlist_submission_limits.window_started_at <= now() - interval '1 hour'
        then 1
      else waitlist_submission_limits.attempts + 1
    end,
    window_started_at = case
      when waitlist_submission_limits.window_started_at <= now() - interval '1 hour'
        then now()
      else waitlist_submission_limits.window_started_at
    end,
    expires_at = now() + interval '1 day'
  returning attempts into limit_attempts;

  if limit_attempts > 5 then
    return jsonb_build_object(
      'accepted', false,
      'reason', 'rate_limited'
    );
  end if;

  insert into public.waitlist_signups (
    email,
    first_name,
    consent_version,
    consented_at,
    source,
    locale,
    status,
    last_submitted_at
  )
  values (
    normalized_email,
    normalized_name,
    normalized_consent_version,
    now(),
    normalized_source,
    normalized_locale,
    'subscribed',
    now()
  )
  on conflict (email) do update
  set
    first_name = coalesce(excluded.first_name, waitlist_signups.first_name),
    consent_version = excluded.consent_version,
    consented_at = excluded.consented_at,
    source = excluded.source,
    locale = excluded.locale,
    status = 'subscribed',
    last_submitted_at = excluded.last_submitted_at;

  return jsonb_build_object('accepted', true);
end;
$$;

revoke all on function public.register_waitlist_signup(
  text,
  text,
  boolean,
  text,
  text,
  text,
  text
) from public;

grant execute on function public.register_waitlist_signup(
  text,
  text,
  boolean,
  text,
  text,
  text,
  text
) to service_role;

comment on function public.register_waitlist_signup(
  text,
  text,
  boolean,
  text,
  text,
  text,
  text
) is
  'Registers a consent-backed waitlist signup for trusted server components only.';

create or replace function public.run_waitlist_retention()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  deleted_signups integer;
  deleted_limits integer;
begin
  delete from public.waitlist_signups
  where status = 'unsubscribed'
     or last_submitted_at < now() - interval '24 months';
  get diagnostics deleted_signups = row_count;

  delete from public.waitlist_submission_limits
  where expires_at <= now();
  get diagnostics deleted_limits = row_count;

  return jsonb_build_object(
    'signups', deleted_signups,
    'limits', deleted_limits
  );
end;
$$;

revoke all on function public.run_waitlist_retention() from public, anon, authenticated;
grant execute on function public.run_waitlist_retention() to service_role;

commit;
