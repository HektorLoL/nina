begin;

create table public.invites (
  token text primary key
    check (
      token = lower(trim(token))
      and token ~ '^casa-[0-9a-f]{20,64}$'
    ),
  family_id uuid not null references public.families(id) on delete cascade,
  expires_at timestamptz not null,
  max_uses integer not null check (max_uses between 1 and 100),
  accepted_by uuid[] not null default array[]::uuid[],
  revoked_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint invites_accepted_by_has_no_nulls
    check (array_position(accepted_by, null::uuid) is null),
  constraint invites_accepted_by_within_max_uses
    check (cardinality(accepted_by) <= max_uses)
);

create unique index invites_one_current_per_family
  on public.invites(family_id)
  where revoked_at is null;

create index invites_family_created_at_idx
  on public.invites(family_id, created_at desc);

create index invites_expires_at_idx
  on public.invites(expires_at)
  where revoked_at is null;

create trigger invites_set_updated_at
  before update on public.invites
  for each row execute function public.set_updated_at();

alter table public.invites enable row level security;
revoke all on table public.invites from public, anon, authenticated;

comment on table public.invites is
  'Server-managed family invitation links. Clients access invitations only through RPCs.';
comment on column public.invites.accepted_by is
  'Auth user IDs that consumed this invitation. Reuse by the same user is idempotent.';

-- Preserve existing links while moving their lifecycle into the invites table.
insert into public.invites (
  token,
  family_id,
  expires_at,
  max_uses,
  accepted_by,
  created_by,
  created_at,
  updated_at
)
select
  lower(trim(families.invite_code)),
  families.id,
  now() + interval '7 days',
  7,
  array[]::uuid[],
  families.created_by,
  families.created_at,
  now()
from public.families;

create or replace function public.generate_family_invite_code()
returns text
language sql
volatile
set search_path = public, extensions
as $$
  select 'casa-' || encode(gen_random_bytes(16), 'hex');
$$;

create or replace function public.create_family(family_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  invite_token text := public.generate_family_invite_code();
  context jsonb;
  target_family_id uuid;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  context := public.create_family(family_name, invite_token);
  target_family_id := (context #>> '{family,id}')::uuid;

  insert into public.invites (
    token,
    family_id,
    expires_at,
    max_uses,
    created_by
  )
  values (
    invite_token,
    target_family_id,
    now() + interval '7 days',
    7,
    current_user_id
  );

  return context;
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
  target_expires_at timestamptz;
  uses_remaining integer;
begin
  if length(normalized_code) < 12 or length(normalized_code) > 96 then
    return jsonb_build_object('valid', false);
  end if;

  select
    families.name,
    invites.expires_at,
    invites.max_uses - cardinality(invites.accepted_by)
  into
    target_name,
    target_expires_at,
    uses_remaining
  from public.invites
  join public.families on families.id = invites.family_id
  where invites.token = normalized_code
    and invites.revoked_at is null
    and invites.expires_at > now()
    and cardinality(invites.accepted_by) < invites.max_uses;

  if not found then
    return jsonb_build_object('valid', false);
  end if;

  return jsonb_build_object(
    'valid', true,
    'family_name', target_name,
    'expires_at', target_expires_at,
    'uses_remaining', uses_remaining
  );
end;
$$;

create or replace function public.join_family_by_invite(invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized_code text := lower(trim(invite_code));
  target_invite public.invites%rowtype;
  target_family public.families%rowtype;
  current_user_id uuid := auth.uid();
  current_profile public.profiles%rowtype;
  already_accepted boolean;
  already_member boolean;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select *
  into target_invite
  from public.invites
  where token = normalized_code
  for update;

  if not found
     or target_invite.revoked_at is not null
     or target_invite.expires_at <= now() then
    raise exception 'invalid_invite_code' using errcode = 'P0001';
  end if;

  already_accepted := current_user_id = any(target_invite.accepted_by);

  select exists (
    select 1
    from public.family_members
    where family_id = target_invite.family_id
      and user_id = current_user_id
  )
  into already_member;

  if not already_member
     and not already_accepted
     and cardinality(target_invite.accepted_by) >= target_invite.max_uses then
    raise exception 'invalid_invite_code' using errcode = 'P0001';
  end if;

  select *
  into target_family
  from public.families
  where id = target_invite.family_id;

  if not found then
    raise exception 'invalid_invite_code' using errcode = 'P0001';
  end if;

  current_profile := public.ensure_current_profile(null);

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
    current_profile.display_name,
    'Você',
    'adult',
    'member',
    'sky',
    'Participante desta casa.'
  )
  on conflict (family_id, user_id) where user_id is not null
  do update set updated_at = now();

  if not already_member and not already_accepted then
    update public.invites
    set accepted_by = array_append(accepted_by, current_user_id)
    where token = target_invite.token;
  end if;

  update public.profiles
  set active_family_id = target_family.id
  where id = current_user_id;

  return public.get_current_home_context();
end;
$$;

create or replace function public.rotate_family_invite_code(target_family_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  invite_token text := public.generate_family_invite_code();
begin
  if not public.can_manage_family(target_family_id) then
    raise exception 'family_management_denied' using errcode = '42501';
  end if;

  update public.invites
  set revoked_at = coalesce(revoked_at, now())
  where family_id = target_family_id
    and revoked_at is null;

  insert into public.invites (
    token,
    family_id,
    expires_at,
    max_uses,
    created_by
  )
  values (
    invite_token,
    target_family_id,
    now() + interval '7 days',
    7,
    current_user_id
  );

  update public.families
  set
    invite_code = invite_token,
    updated_at = now()
  where id = target_family_id;

  if not found then
    raise exception 'family_not_found' using errcode = 'P0002';
  end if;

  return public.get_current_home_context();
end;
$$;

revoke all on function public.generate_family_invite_code() from public;
revoke all on function public.create_family(text) from public;
revoke all on function public.get_family_invite_preview(text) from public;
revoke all on function public.join_family_by_invite(text) from public;
revoke all on function public.rotate_family_invite_code(uuid) from public;

grant execute on function public.create_family(text) to authenticated;
grant execute on function public.get_family_invite_preview(text) to anon, authenticated;
grant execute on function public.join_family_by_invite(text) to authenticated;
grant execute on function public.rotate_family_invite_code(uuid) to authenticated;

commit;
