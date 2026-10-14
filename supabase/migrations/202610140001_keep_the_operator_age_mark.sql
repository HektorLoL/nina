begin;

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

  -- A device signal that leaves an account adult never replaces the operator's mark.
  if enforce_ratchet
     and next_status = 'adult'
     and previous_status = 'adult'
     and stored.assurance = 'operator' then
    next_assurance := 'operator';
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

commit;
