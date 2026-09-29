begin;

alter table public.chat_messages
  add column if not exists held_for_review_until timestamptz;

create table if not exists private.nina_reply_reports (
  id uuid primary key default gen_random_uuid(),
  family_id uuid references public.families(id) on delete set null,
  reporter_user_id uuid references auth.users(id) on delete set null,
  message_id uuid references public.chat_messages(id) on delete set null,
  run_id uuid references public.nina_ai_runs(id) on delete set null,
  reason text not null,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  outcome text
);

alter table private.nina_reply_reports
  drop constraint if exists nina_reply_reports_reason;
alter table private.nina_reply_reports
  add constraint nina_reply_reports_reason
  check (reason in ('inappropriate', 'risk_to_someone', 'health_or_medicine', 'other'));

alter table private.nina_reply_reports
  drop constraint if exists nina_reply_reports_outcome;
alter table private.nina_reply_reports
  add constraint nina_reply_reports_outcome
  check (
    outcome is null
    or outcome in ('no_action', 'prompt_changed', 'account_blocked', 'reported_to_authority')
  );

alter table private.nina_reply_reports enable row level security;
revoke all on table private.nina_reply_reports
  from public, anon, authenticated, service_role;

-- The one place household content is kept for reporting to the authorities:
-- no API role can read it, and it is emptied once receipt is confirmed. Its
-- account and house identifiers carry no foreign key, so deleting the account
-- or the house never cuts the hold loose from who wrote it.
create table if not exists private.child_safety_holds (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  family_id uuid,
  run_id uuid,
  content text not null,
  created_at timestamptz not null default now(),
  reported_at timestamptz,
  authority_receipt_at timestamptz,
  deleted_at timestamptz
);

alter table private.child_safety_holds
  drop constraint if exists child_safety_holds_user_id_fkey;
alter table private.child_safety_holds
  drop constraint if exists child_safety_holds_family_id_fkey;

alter table private.child_safety_holds
  drop constraint if exists child_safety_holds_deleted_content;
alter table private.child_safety_holds
  add constraint child_safety_holds_deleted_content
  check (deleted_at is null or content = '');

alter table private.child_safety_holds enable row level security;
revoke all on table private.child_safety_holds
  from public, anon, authenticated, service_role;

-- An account tied to a hold still inside its preservation period outlives
-- its own deletion here (Decreto 12.880 art. 39 §§1-2): the identifiers, the
-- memberships and what the account wrote, sealed from every API role.
create table if not exists private.child_safety_preserved_accounts (
  hold_id uuid primary key references private.child_safety_holds(id) on delete cascade,
  user_id uuid not null,
  apple_subject text,
  email text,
  account_created_at timestamptz,
  last_sign_in_at timestamptz,
  memberships jsonb not null default '[]'::jsonb,
  messages jsonb not null default '[]'::jsonb,
  memories jsonb not null default '[]'::jsonb,
  preserved_at timestamptz not null default now()
);

create index if not exists child_safety_preserved_accounts_subject_idx
  on private.child_safety_preserved_accounts (apple_subject);

alter table private.child_safety_preserved_accounts enable row level security;
revoke all on table private.child_safety_preserved_accounts
  from public, anon, authenticated, service_role;

create or replace function private.child_safety_hold_is_preserved(
  hold private.child_safety_holds
)
returns boolean
language sql
stable
set search_path = pg_catalog, private
as $$
  select hold.deleted_at is null
    or coalesce(hold.authority_receipt_at > now() - interval '6 months', false);
$$;

revoke all on function private.child_safety_hold_is_preserved(private.child_safety_holds)
  from public, anon, authenticated, service_role;

create or replace function private.preserve_child_safety_account(target_user_id uuid)
returns void
language plpgsql
set search_path = pg_catalog, public, auth, private
as $$
begin
  insert into private.child_safety_preserved_accounts (
    hold_id,
    user_id,
    apple_subject,
    email,
    account_created_at,
    last_sign_in_at,
    memberships,
    messages,
    memories
  )
  select
    holds.id,
    users.id,
    (
      select identities.provider_id
      from auth.identities
      where identities.user_id = users.id
        and identities.provider = 'apple'
      order by identities.created_at
      limit 1
    ),
    users.email,
    users.created_at,
    users.last_sign_in_at,
    coalesce(
      (
        select jsonb_agg(to_jsonb(members) order by members.created_at, members.id)
        from public.family_members as members
        where members.user_id = users.id
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(to_jsonb(messages) order by messages.created_at, messages.id)
        from public.chat_messages as messages
        where messages.created_by = users.id
           or messages.thread_id in (
             select threads.id
             from public.nina_threads as threads
             where threads.owner_user_id = users.id
           )
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(to_jsonb(memories) order by memories.created_at, memories.id)
        from public.memory_items as memories
        where memories.owner_user_id = users.id
           or memories.created_by = users.id
      ),
      '[]'::jsonb
    )
  from private.child_safety_holds as holds
  join auth.users on users.id = holds.user_id
  where holds.user_id = target_user_id
    and private.child_safety_hold_is_preserved(holds)
  on conflict (hold_id) do nothing;
end;
$$;

revoke all on function private.preserve_child_safety_account(uuid)
  from public, anon, authenticated, service_role;

-- A block tied to a preserved account also holds for a new account signed in
-- with the same Apple ID, so deleting and signing in again never clears it.
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
      and (holds.deleted_at is null or holds.authority_receipt_at is not null)
  );
$$;

revoke all on function private.ai_blocked(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.report_nina_reply(
  target_message_id uuid,
  report_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  target_message public.chat_messages%rowtype;
  run_request_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if not private.is_adult(current_user_id) then
    raise exception 'adult_account_required' using errcode = '42501';
  end if;

  if coalesce(report_reason, '') not in (
    'inappropriate',
    'risk_to_someone',
    'health_or_medicine',
    'other'
  ) then
    raise exception 'invalid_report_reason' using errcode = '22023';
  end if;

  select messages.*
  into target_message
  from public.chat_messages as messages
  join public.nina_threads as threads on threads.id = messages.thread_id
  where messages.id = target_message_id
    and messages.sender = 'nina'
    and threads.owner_user_id = current_user_id
  for update of messages;

  if target_message.id is null then
    raise exception 'nina_message_not_found' using errcode = 'P0002';
  end if;

  insert into private.nina_reply_reports (
    family_id,
    reporter_user_id,
    message_id,
    run_id,
    reason
  )
  values (
    target_message.family_id,
    current_user_id,
    target_message.id,
    target_message.run_id,
    report_reason
  );

  select runs.request_message_id
  into run_request_message_id
  from public.nina_ai_runs as runs
  where runs.id = target_message.run_id;

  update public.chat_messages as messages
  set held_for_review_until = now() + interval '90 days'
  where messages.id in (target_message.id, run_request_message_id);

  return jsonb_build_object('reported', true);
end;
$$;

revoke all on function public.report_nina_reply(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.report_nina_reply(uuid, text) to authenticated;

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

    update public.chat_messages as messages
    set
      text = 'Mensagem não enviada.',
      attachments = '[]'::jsonb
    where messages.id = held_message.id;
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

-- A message moderation refused keeps only the neutral marker, so no refresh
-- can bring the original words back to the phone.
create or replace function public.redact_refused_nina_message(target_run_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  target_run public.nina_ai_runs%rowtype;
begin
  select *
  into target_run
  from public.nina_ai_runs as runs
  where runs.id = target_run_id
    and runs.purpose = 'interactive';

  if target_run.id is null then
    raise exception 'nina_run_not_found' using errcode = 'P0002';
  end if;

  update public.chat_messages as messages
  set
    text = 'Mensagem não enviada.',
    attachments = '[]'::jsonb
  where messages.id = target_run.request_message_id
    and messages.sender = 'user'
    and (messages.text <> 'Mensagem não enviada.' or messages.attachments <> '[]'::jsonb);
end;
$$;

revoke all on function public.redact_refused_nina_message(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.redact_refused_nina_message(uuid)
  to service_role;

-- An export carries only the caller's own data: never another member's birth
-- date, memory note or age, and never a task's detail line for a minor.
create or replace function public.export_account_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  ages record;
  minor_view boolean;
  own_member_ids uuid[];
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into ages from private.effective_age(current_user_id);
  minor_view := ages.status <> 'adult';

  select coalesce(array_agg(members.id), '{}'::uuid[])
  into own_member_ids
  from public.family_members as members
  where members.user_id = current_user_id;

  return jsonb_build_object(
    'schema_version', 1,
    'exported_at', now(),
    'account', (
      select jsonb_build_object(
        'id', users.id,
        'email', case when minor_view then null else users.email end,
        'created_at', users.created_at
      )
      from auth.users
      where users.id = current_user_id
    ),
    'profile', (
      select case
        when minor_view then jsonb_build_object('display_name', profiles.display_name)
        else to_jsonb(profiles) - 'active_family_id'
      end
      from public.profiles
      where profiles.id = current_user_id
    ),
    'age', jsonb_build_object(
      'status', ages.status,
      'band', case when ages.status = 'minor' then ages.band end,
      'assurance', ages.assurance,
      'recorded_at', ages.recorded_at
    ),
    'memberships', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'family_id', members.family_id,
            'family_name', families.name,
            'member_id', members.id,
            'name', members.name,
            'relationship', members.relationship,
            'household_role', members.household_role,
            'permission_role', members.permission_role,
            'memory_note', case when minor_view then null else members.memory_note end,
            'birth_date', case when minor_view then null else members.birth_date end,
            'joined_at', members.created_at
          )
          order by members.created_at
        )
        from public.family_members as members
        join public.families on families.id = members.family_id
        where members.user_id = current_user_id
      ),
      '[]'::jsonb
    ),
    'tasks', coalesce(
      (
        select jsonb_agg(
          case
            when minor_view then jsonb_build_object(
              'id', tasks.id,
              'title', tasks.title,
              'due_at', tasks.due_at,
              'due_label', tasks.due_label,
              'category_id', tasks.category_id,
              'is_done', tasks.is_done,
              'completed_at', tasks.completed_at
            )
            else jsonb_build_object(
              'id', tasks.id,
              'family_id', tasks.family_id,
              'task_kind', tasks.task_kind,
              'title', tasks.title,
              'subtitle', tasks.subtitle,
              'owner_label', tasks.owner_label,
              'due_at', tasks.due_at,
              'due_label', tasks.due_label,
              'category_id', tasks.category_id,
              'priority', tasks.priority,
              'recurrence_rule', tasks.recurrence_rule,
              'is_done', tasks.is_done,
              'completed_at', tasks.completed_at,
              'created_at', tasks.created_at
            )
          end
          order by tasks.created_at
        )
        from public.tasks
        where tasks.owner_member_id = any(own_member_ids)
          or (not minor_view and tasks.created_by = current_user_id)
      ),
      '[]'::jsonb
    ),
    'shopping', case
      when minor_view then '[]'::jsonb
      else coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', items.id,
              'family_id', items.family_id,
              'title', items.title,
              'amount', items.amount,
              'owner_label', items.owner_label,
              'is_checked', items.is_checked,
              'created_at', items.created_at
            )
            order by items.created_at
          )
          from public.shopping_items as items
          where items.created_by = current_user_id
            or items.owner_member_id = any(own_member_ids)
        ),
        '[]'::jsonb
      )
    end,
    'nina', jsonb_build_object(
      'messages', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'sender', messages.sender,
              'text', messages.text,
              'created_at', messages.created_at
            )
            order by messages.created_at
          )
          from public.chat_messages as messages
          join public.nina_threads as threads on threads.id = messages.thread_id
          where threads.owner_user_id = current_user_id
        ),
        '[]'::jsonb
      ),
      'memories', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'title', memories.title,
              'body', memories.body,
              'visibility', memories.visibility,
              'created_at', memories.created_at
            )
            order by memories.created_at
          )
          from public.memory_items as memories
          where memories.owner_user_id = current_user_id
        ),
        '[]'::jsonb
      ),
      'proposals', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'kind', proposals.kind,
              'state', proposals.state,
              'title', proposals.title,
              'detail', proposals.detail,
              'created_at', proposals.created_at,
              'resolved_at', proposals.resolved_at
            )
            order by proposals.created_at
          )
          from public.nina_proposals as proposals
          where proposals.owner_user_id = current_user_id
        ),
        '[]'::jsonb
      )
    ),
    'ai_consents', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'family_id', consents.family_id,
            'policy_version', consents.policy_version,
            'accepted_at', consents.accepted_at,
            'transfer_consented_at', consents.transfer_consented_at,
            'revoked_at', consents.revoked_at,
            'revoke_reason', consents.revoke_reason
          )
          order by consents.accepted_at
        )
        from public.nina_ai_consents as consents
        where consents.user_id = current_user_id
      ),
      '[]'::jsonb
    ),
    'terms_acceptances', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'terms_version', acceptances.terms_version,
            'policy_version', acceptances.policy_version,
            'accepted_by', acceptances.accepted_by,
            'accepted_at', acceptances.accepted_at
          )
          order by acceptances.accepted_at
        )
        from private.account_terms_acceptances as acceptances
        where acceptances.user_id = current_user_id
      ),
      '[]'::jsonb
    ),
    'acknowledgements', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'kind', acknowledgements.kind,
            'text_version', acknowledgements.text_version,
            'acknowledged_at', acknowledgements.acknowledged_at
          )
          order by acknowledgements.acknowledged_at
        )
        from private.minor_acknowledgements as acknowledgements
        where acknowledgements.user_id = current_user_id
      ),
      '[]'::jsonb
    ),
    'usage', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object('day', usage.day, 'minutes', usage.minutes)
          order by usage.day
        )
        from private.minor_usage_days as usage
        where usage.member_id = any(own_member_ids)
      ),
      '[]'::jsonb
    ),
    'guardianships_held', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'ward_name', wards.name,
            'relationship', links.relationship,
            'created_at', links.created_at,
            'ended_at', links.ended_at,
            'end_reason', links.end_reason
          )
          order by links.created_at
        )
        from private.minor_guardianships as links
        left join public.family_members as wards on wards.id = links.member_id
        where links.guardian_user_id = current_user_id
      ),
      '[]'::jsonb
    ),
    'premium', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'product_id', subscriptions.product_id,
            'status', subscriptions.status,
            'is_active', subscriptions.is_active,
            'environment', subscriptions.environment,
            'purchased_at', subscriptions.purchased_at,
            'original_purchase_at', subscriptions.original_purchase_at,
            'expires_at', subscriptions.expires_at,
            'will_renew', subscriptions.will_renew
          )
          order by subscriptions.created_at
        )
        from public.premium_subscriptions as subscriptions
        where subscriptions.user_id = current_user_id
      ),
      '[]'::jsonb
    )
  );
end;
$$;

revoke all on function public.export_account_data()
  from public, anon, authenticated, service_role;
grant execute on function public.export_account_data() to authenticated;

create or replace function public.export_minor_data(target_member_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid := auth.uid();
  ward public.family_members%rowtype;
  settings private.minor_profiles%rowtype;
  ward_age record;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into ward from public.family_members as members where members.id = target_member_id;
  if ward.id is null or not private.is_live_guardian(ward.id, current_user_id) then
    raise exception 'guardian_access_denied' using errcode = '42501';
  end if;

  select * into settings from private.minor_profiles as profiles where profiles.member_id = ward.id;
  select * into ward_age from private.effective_age(ward.user_id);

  return jsonb_build_object(
    'schema_version', 1,
    'exported_at', now(),
    'member', jsonb_build_object(
      'id', ward.id,
      'name', ward.name,
      'relationship', ward.relationship,
      'household_role', ward.household_role,
      'is_claimed', ward.user_id is not null,
      'created_at', ward.created_at
    ),
    'band', coalesce(ward_age.band, settings.declared_band),
    'declared_band', settings.declared_band,
    'nicknames', to_jsonb(coalesce(settings.nicknames, '{}'::text[])),
    'supervision', jsonb_build_object(
      'alerts_enabled', settings.alerts_enabled,
      'quiet_start', settings.quiet_start,
      'quiet_end', settings.quiet_end,
      'daily_limit_minutes', settings.daily_limit_minutes
    ),
    'guardianships', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'relationship', links.relationship,
            'consent_text_version', links.consent_text_version,
            'created_at', links.created_at,
            'ended_at', links.ended_at,
            'end_reason', links.end_reason
          )
          order by links.created_at
        )
        from private.minor_guardianships as links
        where links.member_id = ward.id
      ),
      '[]'::jsonb
    ),
    'consents', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'purpose', consents.purpose,
            'text_version', consents.text_version,
            'granted_at', consents.granted_at,
            'withdrawn_at', consents.withdrawn_at
          )
          order by consents.granted_at
        )
        from private.minor_data_consents as consents
        where consents.member_id = ward.id
      ),
      '[]'::jsonb
    ),
    'tasks', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'title', tasks.title,
            'subtitle', tasks.subtitle,
            'due_at', tasks.due_at,
            'due_label', tasks.due_label,
            'category_id', tasks.category_id,
            'recurrence_rule', tasks.recurrence_rule,
            'is_done', tasks.is_done,
            'completed_at', tasks.completed_at,
            'created_at', tasks.created_at
          )
          order by tasks.created_at
        )
        from public.tasks
        where tasks.owner_member_id = ward.id
      ),
      '[]'::jsonb
    ),
    'usage', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object('day', usage.day, 'minutes', usage.minutes)
          order by usage.day
        )
        from private.minor_usage_days as usage
        where usage.member_id = ward.id
      ),
      '[]'::jsonb
    ),
    'account', case
      when ward.user_id is null then null
      else jsonb_build_object(
        'acknowledgements', coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'kind', acknowledgements.kind,
                'text_version', acknowledgements.text_version,
                'acknowledged_at', acknowledgements.acknowledged_at
              )
              order by acknowledgements.acknowledged_at
            )
            from private.minor_acknowledgements as acknowledgements
            where acknowledgements.user_id = ward.user_id
          ),
          '[]'::jsonb
        ),
        'terms_acceptances', coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'terms_version', acceptances.terms_version,
                'accepted_by', acceptances.accepted_by,
                'accepted_at', acceptances.accepted_at
              )
              order by acceptances.accepted_at
            )
            from private.account_terms_acceptances as acceptances
            where acceptances.user_id = ward.user_id
          ),
          '[]'::jsonb
        )
      )
    end
  );
end;
$$;

revoke all on function public.export_minor_data(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.export_minor_data(uuid) to authenticated;

create or replace function public.authorize_guardian_account_deletion(
  guardian_user_id uuid,
  target_member_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  ward public.family_members%rowtype;
  ward_age record;
begin
  select * into ward from public.family_members as members where members.id = target_member_id;
  select * into ward_age from private.effective_age(ward.user_id);

  if ward.id is null
     or ward.user_id is null
     or ward.user_id = guardian_user_id
     or ward_age.status is distinct from 'minor'
     or not private.is_acting_guardian(ward.id, guardian_user_id) then
    raise exception 'guardian_access_denied' using errcode = '42501';
  end if;

  return ward.user_id;
end;
$$;

revoke all on function public.authorize_guardian_account_deletion(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.authorize_guardian_account_deletion(uuid, uuid)
  to service_role;

-- A minor's account does not outlive its house: thirty days after the last
-- house, request or decision, nina-maintenance deletes it in the same order a
-- person's own deletion follows.
create or replace function public.list_minor_accounts_due_for_deletion(max_accounts integer)
returns setof uuid
language sql
stable
security definer
set search_path = pg_catalog, public, auth, private
as $$
  select ages.user_id
  from private.account_age_status as ages
  join auth.users on users.id = ages.user_id
  where ages.status = 'minor'
    and not exists (
      select 1
      from public.family_members as members
      where members.user_id = ages.user_id
    )
    and not exists (
      select 1
      from public.family_join_requests as requests
      where requests.requester_user_id = ages.user_id
        and requests.status = 'pending'
    )
    and greatest(
      users.created_at,
      coalesce(ages.minor_since, users.created_at),
      coalesce(
        (
          select max(decisions.decided_at)
          from public.family_access_decisions as decisions
          where decisions.subject_user_id = ages.user_id
        ),
        users.created_at
      ),
      coalesce(
        (
          select max(requests.updated_at)
          from public.family_join_requests as requests
          where requests.requester_user_id = ages.user_id
        ),
        users.created_at
      )
    ) < now() - interval '30 days'
  order by ages.user_id
  limit greatest(least(coalesce(max_accounts, 25), 100), 0);
$$;

revoke all on function public.list_minor_accounts_due_for_deletion(integer)
  from public, anon, authenticated, service_role;
grant execute on function public.list_minor_accounts_due_for_deletion(integer)
  to service_role;

create or replace function public.run_nina_retention()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
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
  deleted_consent_proofs integer := 0;
  deleted_legacy_profiles integer := 0;
  proof_rows integer;
  legacy_deadline timestamptz;
begin
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

  -- Thirty days sits well clear of the seven the weekly insight reads back, so
  -- bounding the list can never starve the metric it is measured from.
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
    'consent_proofs', deleted_consent_proofs,
    'legacy_minor_profiles', deleted_legacy_profiles
  );
end;
$$;

revoke all on function public.run_nina_retention()
  from public, anon, authenticated, service_role;
grant execute on function public.run_nina_retention() to service_role;

commit;
