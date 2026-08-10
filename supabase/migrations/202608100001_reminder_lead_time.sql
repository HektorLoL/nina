begin;

alter table public.tasks
  add column if not exists remind_offset_minutes integer not null default 0;

alter table public.tasks
  drop constraint if exists tasks_remind_offset_minutes_check;

alter table public.tasks
  add constraint tasks_remind_offset_minutes_check
  check (remind_offset_minutes in (0, 5, 10, 15, 30, 60, 120, 1440));

comment on column public.tasks.remind_offset_minutes is
  'How many minutes before due_at the reminder fires. Zero means at the due moment, which is the behaviour every existing task keeps. The set is closed so every stored value has a pt-BR label and a notification the client can schedule, and it lives on the row rather than on the device so a lead time survives a new phone and reaches the other adult carrying the same task.';

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
as $$
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
     or not public.is_family_member(target_proposal.family_id) then
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

  case target_proposal.kind
    when 'task', 'reminder' then
      insert into public.tasks (
        family_id,
        title,
        subtitle,
        owner_label,
        due_label,
        due_at,
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
$$;

revoke all on function public.resolve_nina_proposal(uuid, text, jsonb, text)
  from public, anon, authenticated, service_role;

grant execute on function public.resolve_nina_proposal(uuid, text, jsonb, text)
  to authenticated;

commit;
