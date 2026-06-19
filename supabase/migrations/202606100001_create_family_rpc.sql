create or replace function public.create_family(
  family_name text,
  invite_code text,
  display_name text default null
)
returns public.families
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_name text := trim(family_name);
  normalized_invite_code text := lower(trim(invite_code));
  target_family public.families%rowtype;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if normalized_name = '' then
    raise exception 'family_name_required' using errcode = '22023';
  end if;

  if length(normalized_invite_code) < 4 then
    raise exception 'invalid_invite_code' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.families
    where families.invite_code = normalized_invite_code
  ) then
    normalized_invite_code := normalized_invite_code
      || '-'
      || substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
  end if;

  insert into public.families (name, invite_code, created_by)
  values (normalized_name, normalized_invite_code, current_user_id)
  returning * into target_family;

  insert into public.family_members (
    family_id,
    user_id,
    name,
    relationship,
    household_role,
    permission_role,
    tone,
    memory_note
  )
  values (
    target_family.id,
    current_user_id,
    coalesce(nullif(trim(display_name), ''), 'Você'),
    'Criador',
    'adult',
    'owner',
    'sky',
    'Participante principal desta casa.'
  );

  insert into public.family_members (
    family_id,
    user_id,
    name,
    relationship,
    household_role,
    permission_role,
    tone,
    memory_note
  )
  values (
    target_family.id,
    null,
    'Nina',
    'IA da casa',
    'assistant',
    'member',
    'mint',
    'Aprende a dinâmica familiar e transforma lembranças soltas em organização.'
  );

  return target_family;
end;
$$;

revoke all on function public.create_family(text, text, text) from public;
grant execute on function public.create_family(text, text, text) to authenticated;

revoke all on function public.join_family_by_invite(text, text) from public;
grant execute on function public.join_family_by_invite(text, text) to authenticated;
