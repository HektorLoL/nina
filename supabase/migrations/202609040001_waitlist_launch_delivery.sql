-- The launch email is built from the subscribed rows at send time and recorded per
-- address, so a rerun after a crash never sends the same campaign twice.

create table public.waitlist_deliveries (
  email text not null
    references public.waitlist_signups(email) on delete cascade,
  campaign text not null,
  provider_message_id text,
  delivered_at timestamptz not null default now(),
  primary key (email, campaign),
  constraint waitlist_deliveries_campaign_is_valid
    check (length(campaign) between 1 and 40 and campaign ~ '^[a-z0-9._-]+$'),
  constraint waitlist_deliveries_provider_message_id_is_valid
    check (
      provider_message_id is null
      or length(provider_message_id) between 1 and 200
    )
);

comment on table public.waitlist_deliveries is
  'Which waitlist address already received which campaign. The sender reads it immediately before sending; a rerun never repeats a message.';

alter table public.waitlist_deliveries enable row level security;

revoke all on table public.waitlist_deliveries
  from public, anon, authenticated, service_role;

create or replace function public.list_waitlist_recipients(p_campaign text)
returns table (
  email text,
  first_name text,
  unsubscribe_token text,
  locale text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_campaign text := lower(trim(coalesce(p_campaign, '')));
begin
  if length(normalized_campaign) not between 1 and 40
     or normalized_campaign !~ '^[a-z0-9._-]+$' then
    raise exception 'waitlist_campaign_invalid' using errcode = '22023';
  end if;

  return query
    select s.email, s.first_name, s.unsubscribe_token, s.locale
    from public.waitlist_signups s
    where s.status = 'subscribed'
      and not exists (
        select 1
        from public.waitlist_deliveries d
        where d.email = s.email
          and d.campaign = normalized_campaign
      )
    order by s.created_at, s.email;
end;
$$;

revoke all on function public.list_waitlist_recipients(text)
  from public, anon, authenticated, service_role;
grant execute on function public.list_waitlist_recipients(text) to service_role;

create or replace function public.record_waitlist_delivery(
  p_email text,
  p_campaign text,
  p_provider_message_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  normalized_email text := lower(trim(coalesce(p_email, '')));
  normalized_campaign text := lower(trim(coalesce(p_campaign, '')));
  normalized_message_id text := nullif(trim(coalesce(p_provider_message_id, '')), '');
  inserted integer;
begin
  if length(normalized_campaign) not between 1 and 40
     or normalized_campaign !~ '^[a-z0-9._-]+$' then
    raise exception 'waitlist_campaign_invalid' using errcode = '22023';
  end if;

  if normalized_message_id is not null and length(normalized_message_id) > 200 then
    raise exception 'waitlist_message_id_invalid' using errcode = '22023';
  end if;

  insert into public.waitlist_deliveries (email, campaign, provider_message_id)
  select s.email, normalized_campaign, normalized_message_id
  from public.waitlist_signups s
  where s.email = normalized_email
  on conflict (email, campaign) do nothing;

  get diagnostics inserted = row_count;

  return jsonb_build_object('recorded', inserted = 1);
end;
$$;

revoke all on function public.record_waitlist_delivery(text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_waitlist_delivery(text, text, text)
  to service_role;
