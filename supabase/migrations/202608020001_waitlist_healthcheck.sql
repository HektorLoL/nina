begin;

create or replace function public.waitlist_healthcheck()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'ready', true,
    'schema_version', '2026-08-02'
  )
  from (
    select
      count(unsubscribe_token) as unsubscribe_capability_count,
      count(unsubscribed_at) as withdrawal_timestamp_count
    from public.waitlist_signups
    where false
  ) as schema_probe;
$$;

revoke all on function public.waitlist_healthcheck()
  from public, anon, authenticated;
grant execute on function public.waitlist_healthcheck()
  to service_role;

comment on function public.waitlist_healthcheck() is
  'Read-only service probe that proves the current waitlist schema is reachable without exposing or scanning signup rows.';

commit;
