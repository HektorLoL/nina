begin;

-- Every household table is read and written by adults of the house only. A
-- minor reaches the house through get_minor_home_view and set_minor_task_done,
-- so realtime stays silent for them by design.
drop policy if exists "Family members can view families" on public.families;
create policy "Family members can view families"
  on public.families
  for select
  to authenticated
  using (public.is_adult_family_member(id));

drop policy if exists "Family members can view memberships" on public.family_members;
create policy "Family members can view memberships"
  on public.family_members
  for select
  to authenticated
  using (public.is_adult_family_member(family_id));

drop policy if exists "Family snapshots are family scoped" on public.family_snapshots;
create policy "Family snapshots are family scoped"
  on public.family_snapshots
  for all
  to authenticated
  using (public.is_adult_family_member(family_id))
  with check (public.is_adult_family_member(family_id));

drop policy if exists "Household insights are family readable" on public.household_insights;
create policy "Household insights are family readable"
  on public.household_insights
  for select
  to authenticated
  using (public.is_adult_family_member(family_id));

drop policy if exists "Confirmed Nina memories respect visibility" on public.memory_items;
create policy "Confirmed Nina memories respect visibility"
  on public.memory_items
  for select
  to authenticated
  using (
    status = 'confirmed'
    and public.is_adult_family_member(family_id)
    and (visibility = 'shared' or owner_user_id = (select auth.uid()))
  );

drop policy if exists "Memory owners can delete confirmed memories" on public.memory_items;
create policy "Memory owners can delete confirmed memories"
  on public.memory_items
  for delete
  to authenticated
  using (
    owner_user_id = (select auth.uid())
    and public.is_adult_family_member(family_id)
  );

drop policy if exists "Memory owners can update confirmed memories" on public.memory_items;
create policy "Memory owners can update confirmed memories"
  on public.memory_items
  for update
  to authenticated
  using (
    owner_user_id = (select auth.uid())
    and public.is_adult_family_member(family_id)
  )
  with check (
    owner_user_id = (select auth.uid())
    and public.is_adult_family_member(family_id)
    and status = 'confirmed'
  );

drop policy if exists "Nina proposals are owner readable" on public.nina_proposals;
create policy "Nina proposals are owner readable"
  on public.nina_proposals
  for select
  to authenticated
  using (
    owner_user_id = (select auth.uid())
    and public.is_adult_family_member(family_id)
  );

drop policy if exists "Nina threads are owner scoped" on public.nina_threads;
create policy "Nina threads are owner scoped"
  on public.nina_threads
  for select
  to authenticated
  using (
    owner_user_id = (select auth.uid())
    and public.is_adult_family_member(family_id)
  );

drop policy if exists "Private Nina messages are owner scoped" on public.chat_messages;
create policy "Private Nina messages are owner scoped"
  on public.chat_messages
  for select
  to authenticated
  using (
    (thread_id is null and public.is_adult_family_member(family_id))
    or exists (
      select 1
      from public.nina_threads
      where nina_threads.id = chat_messages.thread_id
        and nina_threads.owner_user_id = (select auth.uid())
        and public.is_adult_family_member(nina_threads.family_id)
    )
  );

-- Every signed-in person keeps their own profile row at any age, so a minor
-- can still set the name the house calls them; only adults read co-members.
drop policy if exists "Profiles are visible to self and family" on public.profiles;
create policy "Profiles are visible to self and family"
  on public.profiles
  for select
  to authenticated
  using (
    id = (select auth.uid())
    or (public.current_user_is_adult() and public.shares_family_with(id))
  );

drop policy if exists "Shopping items are family scoped" on public.shopping_items;
create policy "Shopping items are family scoped"
  on public.shopping_items
  for all
  to authenticated
  using (public.is_adult_family_member(family_id))
  with check (public.is_adult_family_member(family_id));

drop policy if exists "Task categories are family scoped" on public.task_categories;
create policy "Task categories are family scoped"
  on public.task_categories
  for all
  to authenticated
  using (public.is_adult_family_member(family_id))
  with check (public.is_adult_family_member(family_id));

drop policy if exists "Task sections are family scoped" on public.task_sections;
create policy "Task sections are family scoped"
  on public.task_sections
  for all
  to authenticated
  using (public.is_adult_family_member(family_id))
  with check (public.is_adult_family_member(family_id));

drop policy if exists "Tasks are family scoped" on public.tasks;
create policy "Tasks are family scoped"
  on public.tasks
  for all
  to authenticated
  using (public.is_adult_family_member(family_id))
  with check (public.is_adult_family_member(family_id));

drop policy if exists "Users can read own premium subscriptions" on public.premium_subscriptions;
create policy "Users can read own premium subscriptions"
  on public.premium_subscriptions
  for select
  to authenticated
  using (user_id = (select auth.uid()) and public.current_user_is_adult());

drop policy if exists "Users can read own premium transactions" on public.premium_subscription_transactions;
create policy "Users can read own premium transactions"
  on public.premium_subscription_transactions
  for select
  to authenticated
  using (user_id = (select auth.uid()) and public.current_user_is_adult());

drop policy if exists "Users can upload their own profile photos" on storage.objects;
create policy "Users can upload their own profile photos"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and (select public.current_user_is_adult())
  );

drop policy if exists "Users can update their own profile photos" on storage.objects;
create policy "Users can update their own profile photos"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and (select public.current_user_is_adult())
  )
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and (select public.current_user_is_adult())
  );

create or replace function public.get_current_nina_state(target_family_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  target_thread_id uuid;
begin
  if current_user_id is null
     or not public.is_adult_family_member(target_family_id) then
    raise exception 'family_access_denied' using errcode = '42501';
  end if;

  select id
  into target_thread_id
  from public.nina_threads
  where family_id = target_family_id
    and owner_user_id = current_user_id
    and visibility = 'private';

  return jsonb_build_object(
    'thread', case
      when target_thread_id is null then null
      else jsonb_build_object(
        'id', target_thread_id,
        'family_id', target_family_id,
        'owner_user_id', current_user_id
      )
    end,
    'messages', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', messages.id,
            'sender', messages.sender,
            'text', messages.text,
            'suggestion', messages.suggestion,
            'attachments', messages.attachments,
            'created_at', messages.created_at,
            'proposals', coalesce(
              (
                select jsonb_agg(
                  jsonb_build_object(
                    'id', proposals.id,
                    'kind', proposals.kind,
                    'state', proposals.state,
                    'title', proposals.title,
                    'detail', proposals.detail,
                    'action_title', proposals.action_title,
                    'payload', proposals.payload,
                    'allowed_memory_visibilities', proposals.allowed_memory_visibilities,
                    'resolved_payload', proposals.resolved_payload
                  )
                  order by proposals.created_at
                )
                from public.nina_proposals as proposals
                where proposals.assistant_message_id = messages.id
              ),
              '[]'::jsonb
            )
          )
          order by messages.created_at
        )
        from public.chat_messages as messages
        where messages.thread_id = target_thread_id
      ),
      '[]'::jsonb
    ),
    'memories', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', memories.id,
            'family_id', memories.family_id,
            'owner_user_id', memories.owner_user_id,
            'title', memories.title,
            'body', memories.body,
            'visibility', memories.visibility,
            'confidence', memories.confidence,
            'created_at', memories.created_at,
            'updated_at', memories.updated_at
          )
          order by memories.updated_at desc
        )
        from public.memory_items as memories
        where memories.family_id = target_family_id
          and memories.status = 'confirmed'
          and (
            memories.visibility = 'shared'
            or memories.owner_user_id = current_user_id
          )
      ),
      '[]'::jsonb
    )
  );
end;
$$;

create or replace function public.delete_nina_memory(target_memory_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  delete from public.memory_items
  where id = target_memory_id
    and owner_user_id = auth.uid()
    and public.is_adult_family_member(family_id);

  if not found then
    raise exception 'nina_memory_not_found' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.update_nina_memory(
  target_memory_id uuid,
  memory_title text,
  memory_body text,
  memory_visibility text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  updated_memory public.memory_items%rowtype;
begin
  if memory_visibility not in ('private', 'shared') then
    raise exception 'invalid_memory_visibility' using errcode = '22023';
  end if;

  update public.memory_items
  set
    title = coalesce(nullif(trim(memory_title), ''), title),
    body = trim(memory_body),
    visibility = memory_visibility,
    deduplication_key = null
  where id = target_memory_id
    and owner_user_id = current_user_id
    and status = 'confirmed'
    and public.is_adult_family_member(family_id)
  returning * into updated_memory;

  if not found then
    raise exception 'nina_memory_not_found' using errcode = 'P0002';
  end if;

  return to_jsonb(updated_memory);
end;
$$;

create or replace function public.delete_task_section(
  target_family_id uuid,
  target_section_id text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if target_section_id = 'house-tasks' then
    raise exception 'default_task_section_cannot_be_deleted'
      using errcode = '22023';
  end if;

  if not public.is_adult_family_member(target_family_id) then
    raise exception 'family_access_denied'
      using errcode = '42501';
  end if;

  update public.tasks
  set section_id = 'house-tasks'
  where family_id = target_family_id
    and section_id = target_section_id;

  delete from public.task_sections
  where family_id = target_family_id
    and id = target_section_id;

  if not found then
    raise exception 'task_section_not_found'
      using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.resolve_nina_proposal(
  target_proposal_id uuid,
  decision text,
  edited_payload jsonb default '{}'::jsonb,
  memory_visibility text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $_$
declare
  current_user_id uuid := auth.uid();
  target_proposal public.nina_proposals%rowtype;
  final_payload jsonb;
  final_title text;
  final_detail text;
  final_owner text;
  final_due_label text;
  final_due_at timestamptz;
  final_category text;
  final_symbol text;
  final_recurrence text;
  final_task_kind text;
  final_remind_offset_text text;
  final_remind_offset integer;
  final_visibility text;
  created_id uuid;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if decision not in ('accept', 'reject') then
    raise exception 'invalid_proposal_decision' using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(edited_payload, '{}'::jsonb)) <> 'object' then
    raise exception 'invalid_proposal_payload' using errcode = '22023';
  end if;

  select *
  into target_proposal
  from public.nina_proposals
  where id = target_proposal_id
  for update;

  if not found then
    raise exception 'nina_proposal_not_found' using errcode = 'P0002';
  end if;

  if target_proposal.owner_user_id <> current_user_id
     or not public.is_adult_family_member(target_proposal.family_id) then
    raise exception 'nina_proposal_access_denied' using errcode = '42501';
  end if;

  if target_proposal.state <> 'pending' then
    return jsonb_build_object(
      'id', target_proposal.id,
      'state', target_proposal.state,
      'resolved_payload', target_proposal.resolved_payload
    );
  end if;

  if decision = 'reject' then
    update public.nina_proposals
    set
      state = 'rejected',
      resolved_at = now(),
      resolved_by = current_user_id,
      resolved_payload = '{}'::jsonb
    where id = target_proposal.id;

    return jsonb_build_object(
      'id', target_proposal.id,
      'state', 'rejected',
      'resolved_payload', '{}'::jsonb
    );
  end if;

  final_payload := target_proposal.payload || coalesce(edited_payload, '{}'::jsonb);
  final_title := coalesce(
    nullif(trim(final_payload ->> 'title'), ''),
    target_proposal.title
  );
  final_detail := coalesce(final_payload ->> 'detail', target_proposal.detail, '');
  final_owner := coalesce(nullif(trim(final_payload ->> 'owner'), ''), 'Casa');
  final_due_label := coalesce(nullif(trim(final_payload ->> 'due_label'), ''), 'Sem data');
  final_category := coalesce(nullif(trim(final_payload ->> 'category'), ''), 'home');
  final_symbol := coalesce(nullif(trim(final_payload ->> 'symbol_name'), ''), 'bell.fill');
  final_recurrence := coalesce(nullif(trim(final_payload ->> 'recurrence_rule'), ''), 'none');
  final_remind_offset_text := nullif(trim(final_payload ->> 'remind_offset_minutes'), '');
  final_due_at := case
    when nullif(final_payload ->> 'due_at', '') is null then null
    else (final_payload ->> 'due_at')::timestamptz
  end;

  if final_recurrence not in ('none', 'daily', 'weekly', 'monthly', 'yearly') then
    raise exception 'invalid_recurrence_rule' using errcode = '22023';
  end if;

  if final_remind_offset_text is not null
     and final_remind_offset_text !~ '^[0-9]+$' then
    raise exception 'invalid_remind_offset_minutes' using errcode = '22023';
  end if;

  final_remind_offset := coalesce(final_remind_offset_text::integer, 0);

  if final_remind_offset not in (0, 5, 10, 15, 30, 60, 120, 1440) then
    raise exception 'invalid_remind_offset_minutes' using errcode = '22023';
  end if;

  final_task_kind := case
    when target_proposal.kind = 'seed' then 'seed'
    else 'task'
  end;

  -- A semente is an intention nobody owes a date, so the date, the repetition
  -- and the lead time counted back from it are dropped rather than carried.
  if final_task_kind = 'seed' then
    final_due_at := null;
    final_due_label := 'Sem data';
    final_recurrence := 'none';
    final_remind_offset := 0;
  end if;

  case target_proposal.kind
    when 'task', 'reminder', 'seed' then
      insert into public.tasks (
        family_id,
        title,
        subtitle,
        owner_label,
        due_label,
        due_at,
        task_kind,
        category_id,
        category_snapshot,
        priority,
        recurrence_rule,
        remind_offset_minutes,
        created_by,
        created_by_label
      )
      values (
        target_proposal.family_id,
        final_title,
        final_detail,
        final_owner,
        final_due_label,
        final_due_at,
        final_task_kind,
        final_category,
        case
          when target_proposal.kind = 'reminder' then jsonb_build_object(
            'id', final_category,
            'title', 'Casa',
            'symbolName', final_symbol,
            'tone', 'amber'
          )
          else '{}'::jsonb
        end,
        coalesce(nullif(final_payload ->> 'priority', ''), 'normal'),
        final_recurrence,
        final_remind_offset,
        current_user_id,
        'Nina'
      )
      returning id into created_id;
    when 'shopping' then
      insert into public.shopping_items (
        family_id,
        title,
        amount,
        owner_label,
        created_by
      )
      values (
        target_proposal.family_id,
        final_title,
        coalesce(final_payload ->> 'amount', ''),
        final_owner,
        current_user_id
      )
      returning id into created_id;
    when 'memory' then
      final_visibility := coalesce(memory_visibility, final_payload ->> 'visibility', 'private');
      if final_visibility not in ('private', 'shared') then
        raise exception 'invalid_memory_visibility' using errcode = '22023';
      end if;

      insert into public.memory_items (
        family_id,
        title,
        body,
        source,
        created_by,
        owner_user_id,
        visibility,
        status,
        confidence,
        source_run_id,
        deduplication_key,
        confirmed_at,
        confirmed_by
      )
      values (
        target_proposal.family_id,
        final_title,
        final_detail,
        'nina',
        current_user_id,
        current_user_id,
        final_visibility,
        'confirmed',
        coalesce((final_payload ->> 'confidence')::numeric, 0.7),
        target_proposal.run_id,
        nullif(final_payload ->> 'deduplication_key', ''),
        now(),
        current_user_id
      )
      on conflict (
        family_id,
        owner_user_id,
        visibility,
        deduplication_key
      )
      where status = 'confirmed' and deduplication_key is not null
      do update set
        title = excluded.title,
        body = excluded.body,
        confidence = greatest(memory_items.confidence, excluded.confidence),
        source_run_id = excluded.source_run_id,
        confirmed_at = now(),
        confirmed_by = excluded.confirmed_by
      returning id into created_id;
  end case;

  final_payload := final_payload || jsonb_build_object(
    'created_id', created_id,
    'memory_visibility', final_visibility
  );

  update public.nina_proposals
  set
    state = 'accepted',
    resolved_at = now(),
    resolved_by = current_user_id,
    resolved_payload = final_payload
  where id = target_proposal.id;

  return jsonb_build_object(
    'id', target_proposal.id,
    'state', 'accepted',
    'resolved_payload', final_payload
  );
end;
$_$;

revoke all on function public.get_current_nina_state(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_current_nina_state(uuid) to authenticated;

revoke all on function public.delete_nina_memory(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.delete_nina_memory(uuid) to authenticated;

revoke all on function public.update_nina_memory(uuid, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.update_nina_memory(uuid, text, text, text)
  to authenticated;

revoke all on function public.delete_task_section(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.delete_task_section(uuid, text) to authenticated;

revoke all on function public.resolve_nina_proposal(uuid, text, jsonb, text)
  from public, anon, authenticated, service_role;
grant execute on function public.resolve_nina_proposal(uuid, text, jsonb, text)
  to authenticated;

commit;
