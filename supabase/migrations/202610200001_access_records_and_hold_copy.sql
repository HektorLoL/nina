begin;

-- No foreign key: a deleted account's access records stay for their six months (Marco Civil art. 15).
create table if not exists private.app_access_records (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  ip_address inet not null,
  source_port integer,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  kept_until timestamptz
);

alter table private.app_access_records
  drop constraint if exists app_access_records_source_port;
alter table private.app_access_records
  add constraint app_access_records_source_port
  check (source_port is null or source_port between 0 and 65535);

alter table private.app_access_records
  drop constraint if exists app_access_records_window;
alter table private.app_access_records
  add constraint app_access_records_window check (last_seen_at >= first_seen_at);

create index if not exists app_access_records_user_idx
  on private.app_access_records (user_id, last_seen_at desc);
create index if not exists app_access_records_address_idx
  on private.app_access_records (ip_address, first_seen_at);
create index if not exists app_access_records_last_seen_idx
  on private.app_access_records (last_seen_at);

alter table private.app_access_records enable row level security;
revoke all on table private.app_access_records
  from public, anon, authenticated, service_role;

-- Cloudflare refuses a client's own cf-connecting-ip, so it is the one address trusted; x-forwarded-for is the client's claim.
create or replace function private.request_client_address(
  out ip_address inet,
  out source_port integer
)
language plpgsql
stable
set search_path = pg_catalog
as $$
declare
  headers jsonb;
  connecting inet;
begin
  headers := nullif(current_setting('request.headers', true), '')::jsonb;
  connecting := nullif(btrim(headers ->> 'cf-connecting-ip'), '')::inet;
  -- A Class E address is Cloudflare's Pseudo IPv4 stand-in, which no client has; only then is the IPv6 header read.
  if connecting << '240.0.0.0/4'::inet then
    ip_address := nullif(btrim(headers ->> 'cf-connecting-ipv6'), '')::inet;
  else
    ip_address := connecting;
  end if;
exception
  when others then
    ip_address := null;
    source_port := null;
end;
$$;

revoke all on function private.request_client_address()
  from public, anon, authenticated, service_role;

-- A failure here never stops the app from loading.
create or replace function private.record_app_access(target_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog, private
as $$
declare
  address record;
  open_record bigint;
begin
  select * into address from private.request_client_address();

  if target_user_id is null or address.ip_address is null then
    return;
  end if;

  select records.id
  into open_record
  from private.app_access_records as records
  where records.user_id = target_user_id
    and records.ip_address = address.ip_address
    and records.source_port is not distinct from address.source_port
    and records.last_seen_at > now() - interval '30 minutes'
  order by records.last_seen_at desc
  limit 1
  for update;

  if open_record is not null then
    -- now() is the transaction's start, so a slow request only widens a record, never moves it back.
    update private.app_access_records
    set
      first_seen_at = least(first_seen_at, now()),
      last_seen_at = greatest(last_seen_at, now())
    where id = open_record;
  elsif (
    select count(*)
    from private.app_access_records as records
    where records.user_id = target_user_id
      and records.first_seen_at > now() - interval '1 day'
  ) < 500 then
    insert into private.app_access_records (user_id, ip_address, source_port)
    values (target_user_id, address.ip_address, address.source_port);
  else
    raise warning 'app_access_record_cap_reached';
  end if;
exception
  when others then
    raise warning 'app_access_record_failed' using detail = sqlstate;
end;
$$;

revoke all on function private.record_app_access(uuid)
  from public, anon, authenticated, service_role;

-- Decreto 8.771 art. 13 III: each read through the operator function leaves a line here.
create table if not exists private.app_access_record_reads (
  id bigint generated always as identity primary key,
  read_at timestamptz not null default now(),
  finished_at timestamptz not null default clock_timestamp(),
  read_by text not null,
  database_role text not null default session_user,
  case_reference text not null,
  target_user_id uuid,
  target_ip_address inet,
  from_at timestamptz not null,
  to_at timestamptz not null,
  rows_returned integer not null
);

alter table private.app_access_record_reads
  drop constraint if exists app_access_record_reads_target;
alter table private.app_access_record_reads
  add constraint app_access_record_reads_target
  check (target_user_id is not null or target_ip_address is not null);

alter table private.app_access_record_reads enable row level security;
revoke all on table private.app_access_record_reads
  from public, anon, authenticated, service_role;

create or replace function private.operator_read_access_records(
  reader_name text,
  case_reference text,
  target_user_id uuid,
  target_ip_address inet,
  from_at timestamptz,
  to_at timestamptz
)
returns table (
  user_id uuid,
  ip_address inet,
  source_port integer,
  first_seen_at timestamptz,
  last_seen_at timestamptz
)
language plpgsql
set search_path = pg_catalog, private
as $$
declare
  found_rows integer;
begin
  if nullif(btrim(reader_name), '') is null then
    raise exception 'reader_name_required' using errcode = '22023';
  end if;
  if nullif(btrim(case_reference), '') is null then
    raise exception 'case_reference_required' using errcode = '22023';
  end if;
  if target_user_id is null and target_ip_address is null then
    raise exception 'access_record_target_required' using errcode = '22023';
  end if;
  if from_at is null or to_at is null or to_at < from_at then
    raise exception 'access_record_period_invalid' using errcode = '22023';
  end if;

  return query
  select records.user_id, records.ip_address, records.source_port,
    records.first_seen_at, records.last_seen_at
  from private.app_access_records as records
  where (target_user_id is null or records.user_id = target_user_id)
    and (target_ip_address is null or records.ip_address = target_ip_address)
    and records.last_seen_at >= from_at
    and records.first_seen_at <= to_at
  order by records.first_seen_at, records.id;

  get diagnostics found_rows = row_count;

  insert into private.app_access_record_reads (
    read_by, case_reference, target_user_id, target_ip_address, from_at, to_at, rows_returned
  )
  values (
    btrim(reader_name), btrim(case_reference), target_user_id, target_ip_address,
    from_at, to_at, found_rows
  );
end;
$$;

revoke all on function private.operator_read_access_records(text, text, uuid, inet, timestamptz, timestamptz)
  from public, anon, authenticated, service_role;

create or replace function public.ensure_current_profile(display_name_hint text default null)
returns public.profiles
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  auth_user_record auth.users%rowtype;
  target_profile public.profiles%rowtype;
  normalized_hint text := nullif(trim(display_name_hint), '');
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select *
  into auth_user_record
  from auth.users
  where id = auth.uid();

  if not found then
    raise exception 'auth_user_not_found' using errcode = 'P0002';
  end if;

  insert into public.profiles (
    id,
    display_name,
    display_name_source,
    email
  )
  values (
    auth_user_record.id,
    coalesce(normalized_hint, public.auth_user_display_name(auth_user_record)),
    'auth',
    auth_user_record.email
  )
  on conflict (id) do update
  set
    email = excluded.email,
    display_name = case
      when profiles.display_name_source = 'user' then profiles.display_name
      else coalesce(normalized_hint, excluded.display_name)
    end,
    updated_at = now()
  returning * into target_profile;

  perform private.record_app_access(auth_user_record.id);

  return target_profile;
end;
$$;

revoke all on function public.ensure_current_profile(text)
  from public, anon, authenticated, service_role;
grant execute on function public.ensure_current_profile(text) to authenticated;

create or replace function public.hold_nina_chat_run_for_child_safety(target_run_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  target_run public.nina_ai_runs%rowtype;
  held_message public.chat_messages%rowtype;
begin
  select *
  into target_run
  from public.nina_ai_runs as runs
  where runs.id = target_run_id
    and runs.purpose = 'interactive';

  if target_run.id is null or target_run.user_id is null then
    raise exception 'nina_run_not_found' using errcode = 'P0002';
  end if;

  select *
  into held_message
  from public.chat_messages as messages
  where messages.id = target_run.request_message_id
  for update;

  if held_message.id is not null and held_message.text <> 'Mensagem não enviada.' then
    insert into private.child_safety_holds (
      user_id,
      family_id,
      run_id,
      content
    )
    values (
      target_run.user_id,
      target_run.family_id,
      target_run.id,
      held_message.text
    );

    -- The same words sent again after a failed turn are sealed too, so the copy below never repeats them.
    update public.chat_messages as messages
    set
      text = 'Mensagem não enviada.',
      attachments = '[]'::jsonb
    where messages.id = held_message.id
      or (
        messages.created_by = target_run.user_id
        and messages.sender = 'user'
        and messages.text = held_message.text
      );

    -- A failed copy never undoes the hold; the next deletion, or the operator, takes it again.
    begin
      perform private.preserve_child_safety_account(target_run.user_id);
    exception
      when others then
        raise warning 'child_safety_copy_failed' using detail = sqlstate;
    end;
  end if;

  insert into private.nina_ai_blocks (user_id, reason_code)
  values (target_run.user_id, 'child_safety_hold')
  on conflict (user_id) do update
  set
    reason_code = 'child_safety_hold',
    created_at = now(),
    lifted_at = null,
    lift_reason_code = null;
end;
$$;

revoke all on function public.hold_nina_chat_run_for_child_safety(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.hold_nina_chat_run_for_child_safety(uuid)
  to service_role;

-- The held account answers to its own block alone; its copy blocks only another account with the same Apple ID.
create or replace function private.ai_blocked(target_user_id uuid)
returns boolean
language sql
stable
set search_path = pg_catalog, auth, private
as $$
  select exists (
    select 1
    from private.nina_ai_blocks as blocks
    where blocks.user_id = target_user_id
      and blocks.lifted_at is null
  )
  or exists (
    select 1
    from auth.identities
    join private.child_safety_preserved_accounts as preserved
      on preserved.apple_subject = identities.provider_id
    join private.child_safety_holds as holds
      on holds.id = preserved.hold_id
    where identities.user_id = target_user_id
      and identities.provider = 'apple'
      and preserved.user_id <> target_user_id
      and (holds.deleted_at is null or holds.authority_receipt_at is not null)
  );
$$;

revoke all on function private.ai_blocked(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.run_nina_retention()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  abandoned_runs integer;
  deleted_messages integer;
  deleted_proposals integer;
  deleted_runs integer;
  deleted_insights integer;
  archived_tasks integer;
  deleted_challenges integer;
  deleted_attest_keys integer;
  deleted_minor_requests integer;
  deleted_usage_days integer;
  deleted_reports integer;
  deleted_blocks integer;
  deleted_preserved_accounts integer;
  deleted_access_records integer;
  deleted_consent_proofs integer := 0;
  deleted_legacy_profiles integer := 0;
  proof_rows integer;
  legacy_deadline timestamptz;
begin
  -- Abandoned runs are settled before old runs are deleted, so no reservation
  -- is ever deleted with the run that held it.
  abandoned_runs := private.settle_abandoned_ai_runs();

  update public.nina_proposals
  set
    state = 'rejected',
    resolved_at = now(),
    resolved_payload = jsonb_build_object('reason', 'expired')
  where state = 'pending'
    and created_at < now() - interval '30 days';

  -- A reported reply is held for review, and never for more than ninety days.
  delete from public.chat_messages
  where coalesce(retained_until, created_at + interval '30 days') < now()
    and (
      held_for_review_until is null
      or held_for_review_until < now()
      or held_for_review_until > now() + interval '90 days'
    );
  get diagnostics deleted_messages = row_count;

  -- Words a deleted house left on a report are kept no longer than the reply itself could be.
  update private.nina_reply_reports
  set
    reply_text = null,
    request_text = null
  where created_at < now() - interval '90 days'
    and (reply_text is not null or request_text is not null);

  delete from public.nina_proposals
  where state <> 'pending'
    and resolved_at < now() - interval '30 days';
  get diagnostics deleted_proposals = row_count;

  delete from public.nina_ai_runs
  where created_at < now() - interval '90 days';
  get diagnostics deleted_runs = row_count;

  delete from public.household_insights
  where coalesce(expires_at, created_at + interval '90 days') < now();
  get diagnostics deleted_insights = row_count;

  -- Thirty days sits well clear of the fortnight the weekly insight can read
  -- back, so bounding the list can never starve the metric it is measured from.
  update public.tasks
  set archived_at = now()
  where archived_at is null
    and is_done
    and completed_at < now() - interval '30 days';
  get diagnostics archived_tasks = row_count;

  delete from private.age_signal_challenges
  where created_at < now() - interval '1 day';
  get diagnostics deleted_challenges = row_count;

  delete from private.app_attest_keys
  where coalesce(last_used_at, created_at) < now() - interval '400 days';
  get diagnostics deleted_attest_keys = row_count;

  delete from public.family_join_requests as requests
  where requests.status = 'pending'
    and requests.created_at < now() - interval '7 days'
    and not private.is_adult(requests.requester_user_id);
  get diagnostics deleted_minor_requests = row_count;

  delete from private.minor_usage_days
  where day < (now() at time zone 'America/Sao_Paulo')::date - 30;
  get diagnostics deleted_usage_days = row_count;

  delete from private.nina_reply_reports
  where reviewed_at < now() - interval '6 months';
  get diagnostics deleted_reports = row_count;

  delete from private.nina_ai_blocks
  where lifted_at < now() - interval '1 year';
  get diagnostics deleted_blocks = row_count;

  delete from private.child_safety_preserved_accounts as preserved
  using private.child_safety_holds as holds
  where holds.id = preserved.hold_id
    and not private.child_safety_hold_is_preserved(holds);
  get diagnostics deleted_preserved_accounts = row_count;

  -- An access record leaves six months after its last use, unless an authority's request or a preserved hold on its account keeps it.
  delete from private.app_access_records as records
  where records.last_seen_at < now() - interval '6 months'
    and (records.kept_until is null or records.kept_until < now())
    and not exists (
      select 1
      from private.child_safety_holds as holds
      where holds.user_id = records.user_id
        and private.child_safety_hold_is_preserved(holds)
    );
  get diagnostics deleted_access_records = row_count;

  delete from private.app_access_record_reads
  where read_at < now() - interval '5 years';

  delete from private.minor_guardianships
  where ended_at < now() - interval '5 years';
  get diagnostics proof_rows = row_count;
  deleted_consent_proofs := deleted_consent_proofs + proof_rows;

  delete from private.minor_data_consents
  where withdrawn_at < now() - interval '5 years';
  get diagnostics proof_rows = row_count;
  deleted_consent_proofs := deleted_consent_proofs + proof_rows;

  delete from private.account_terms_acceptances
  where user_id is null
    and accepted_at < now() - interval '5 years';
  get diagnostics proof_rows = row_count;
  deleted_consent_proofs := deleted_consent_proofs + proof_rows;

  select policy.legacy_profile_deadline
  into legacy_deadline
  from private.age_policy as policy
  where policy.singleton;

  if legacy_deadline is not null and legacy_deadline < now() then
    delete from public.family_members as members
    where members.user_id is null
      and members.household_role in ('child', 'teen')
      and not private.has_live_minor_consent(members.id, 'profile')
      and not exists (
        select 1
        from private.minor_guardianships as links
        where links.member_id = members.id
          and links.ended_at is null
      );
    get diagnostics deleted_legacy_profiles = row_count;
  end if;

  return jsonb_build_object(
    'abandoned_runs', abandoned_runs,
    'messages', deleted_messages,
    'proposals', deleted_proposals,
    'runs', deleted_runs,
    'insights', deleted_insights,
    'archived_tasks', archived_tasks,
    'age_challenges', deleted_challenges,
    'app_attest_keys', deleted_attest_keys,
    'minor_join_requests', deleted_minor_requests,
    'minor_usage_days', deleted_usage_days,
    'reply_reports', deleted_reports,
    'ai_blocks', deleted_blocks,
    'preserved_accounts', deleted_preserved_accounts,
    'access_records', deleted_access_records,
    'consent_proofs', deleted_consent_proofs,
    'legacy_minor_profiles', deleted_legacy_profiles
  );
end;
$$;

revoke all on function public.run_nina_retention()
  from public, anon, authenticated, service_role;
grant execute on function public.run_nina_retention() to service_role;

commit;
