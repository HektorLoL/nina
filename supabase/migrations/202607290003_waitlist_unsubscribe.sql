begin;

alter table public.waitlist_signups
  add column unsubscribe_token text,
  add column unsubscribed_at timestamptz;

update public.waitlist_signups
set
  unsubscribe_token = encode(extensions.gen_random_bytes(32), 'hex'),
  unsubscribed_at = case
    when status = 'unsubscribed' then updated_at
    else null
  end;

alter table public.waitlist_signups
  alter column unsubscribe_token
    set default encode(extensions.gen_random_bytes(32), 'hex'),
  alter column unsubscribe_token set not null,
  add constraint waitlist_signups_unsubscribe_token_is_valid
    check (unsubscribe_token ~ '^[0-9a-f]{64}$'),
  add constraint waitlist_signups_unsubscribe_token_key
    unique (unsubscribe_token),
  add constraint waitlist_signups_unsubscribed_at_matches_status
    check (
      (status = 'subscribed' and unsubscribed_at is null)
      or
      (status = 'unsubscribed' and unsubscribed_at is not null)
    );

comment on column public.waitlist_signups.unsubscribe_token is
  'Opaque single-purpose capability included in email URL fragments. Rotated whenever consent is renewed.';
comment on column public.waitlist_signups.unsubscribed_at is
  'Time the launch-email consent was withdrawn. Unsubscribed rows are removed by retention.';

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
    last_submitted_at = excluded.last_submitted_at,
    unsubscribe_token = encode(extensions.gen_random_bytes(32), 'hex'),
    unsubscribed_at = null;

  return jsonb_build_object('accepted', true);
end;
$$;

create or replace function public.unsubscribe_waitlist_signup(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_token text := lower(trim(coalesce(p_token, '')));
begin
  if normalized_token ~ '^[0-9a-f]{64}$' then
    update public.waitlist_signups
    set
      status = 'unsubscribed',
      unsubscribed_at = now()
    where unsubscribe_token = normalized_token
      and status = 'subscribed';
  end if;

  return jsonb_build_object('accepted', true);
end;
$$;

revoke all on function public.unsubscribe_waitlist_signup(text)
  from public, anon, authenticated;
grant execute on function public.unsubscribe_waitlist_signup(text)
  to service_role;

comment on function public.unsubscribe_waitlist_signup(text) is
  'Withdraws launch-email consent through an opaque capability. Always returns a non-enumerating response.';

commit;
