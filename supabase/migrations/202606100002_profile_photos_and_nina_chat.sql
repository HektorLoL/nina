insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'profile-photos',
  'profile-photos',
  false,
  5242880,
  array['image/jpeg']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Users can read their own profile photos"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

create policy "Users can upload their own profile photos"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

create policy "Users can update their own profile photos"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  )
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

create policy "Users can delete their own profile photos"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

create table public.nina_chat_rate_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now()
);

alter table public.nina_chat_rate_limits enable row level security;

create trigger nina_chat_rate_limits_set_updated_at
  before update on public.nina_chat_rate_limits
  for each row execute function public.set_updated_at();

create or replace function public.claim_nina_chat_request(
  max_requests integer default 30,
  window_seconds integer default 3600
)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  current_count integer;
begin
  if current_user_id is null or max_requests < 1 or window_seconds < 1 then
    return false;
  end if;

  insert into public.nina_chat_rate_limits (
    user_id,
    window_started_at,
    request_count
  )
  values (
    current_user_id,
    now(),
    1
  )
  on conflict (user_id) do update
  set
    window_started_at = case
      when now() >= nina_chat_rate_limits.window_started_at + make_interval(secs => window_seconds)
        then now()
      else nina_chat_rate_limits.window_started_at
    end,
    request_count = case
      when now() >= nina_chat_rate_limits.window_started_at + make_interval(secs => window_seconds)
        then 1
      else least(nina_chat_rate_limits.request_count + 1, max_requests + 1)
    end
  returning request_count into current_count;

  return current_count <= max_requests;
end;
$$;

revoke all on function public.claim_nina_chat_request(integer, integer) from public;
grant execute on function public.claim_nina_chat_request(integer, integer) to authenticated;
