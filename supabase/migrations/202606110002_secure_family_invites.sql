begin;

create or replace function public.generate_family_invite_code()
returns text
language sql
volatile
set search_path = public, extensions
as $$
  select 'casa-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 20);
$$;

-- The app is still pre-launch, so rotate every predictable legacy code once.
update public.families
set
  invite_code = public.generate_family_invite_code(),
  updated_at = now();

create or replace function public.create_family(family_name text)
returns jsonb
language sql
security definer
set search_path = public, auth
as $$
  select public.create_family(
    family_name,
    public.generate_family_invite_code()
  );
$$;

create or replace function public.update_family_settings(
  target_family_id uuid,
  family_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_invite_code text;
begin
  select invite_code
  into current_invite_code
  from public.families
  where id = target_family_id;

  if current_invite_code is null then
    raise exception 'family_not_found' using errcode = 'P0002';
  end if;

  return public.update_family_settings(
    target_family_id,
    family_name,
    current_invite_code
  );
end;
$$;

create or replace function public.get_family_invite_preview(invite_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  normalized_code text := lower(trim(invite_code));
  target_name text;
begin
  if length(normalized_code) < 12 then
    return jsonb_build_object('valid', false);
  end if;

  select name
  into target_name
  from public.families
  where families.invite_code = normalized_code;

  if target_name is null then
    return jsonb_build_object('valid', false);
  end if;

  return jsonb_build_object(
    'valid', true,
    'family_name', target_name
  );
end;
$$;

create or replace function public.rotate_family_invite_code(target_family_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.can_manage_family(target_family_id) then
    raise exception 'family_management_denied' using errcode = '42501';
  end if;

  update public.families
  set
    invite_code = public.generate_family_invite_code(),
    updated_at = now()
  where id = target_family_id;

  if not found then
    raise exception 'family_not_found' using errcode = 'P0002';
  end if;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.generate_family_invite_code() from public;
revoke all on function public.create_family(text, text) from public;
revoke all on function public.create_family(text, text) from authenticated;
revoke all on function public.update_family_settings(uuid, text, text) from public;
revoke all on function public.update_family_settings(uuid, text, text) from authenticated;
revoke all on function public.create_family(text) from public;
revoke all on function public.update_family_settings(uuid, text) from public;
revoke all on function public.get_family_invite_preview(text) from public;
revoke all on function public.rotate_family_invite_code(uuid) from public;

grant execute on function public.create_family(text) to authenticated;
grant execute on function public.update_family_settings(uuid, text) to authenticated;
grant execute on function public.get_family_invite_preview(text) to anon, authenticated;
grant execute on function public.rotate_family_invite_code(uuid) to authenticated;

commit;
