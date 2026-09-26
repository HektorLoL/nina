begin;

-- The production project was created with default privileges that granted
-- anon, authenticated and service_role everything on each new public object,
-- while a fresh database grants them nothing. Every migration that revoked
-- only from PUBLIC therefore left production wider than the tests saw:
-- register_waitlist_signup was callable with the publishable key, skipping the
-- Worker's honeypot, fingerprint and rate limit. From here on no API role holds
-- a privilege on a new public object unless a migration grants it by name.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on functions from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;

drop function if exists public.update_family_settings(uuid, text, text);

revoke all on function public.register_waitlist_signup(
  text,
  text,
  boolean,
  text,
  text,
  text,
  text
) from public, anon, authenticated, service_role;
grant execute on function public.register_waitlist_signup(
  text,
  text,
  boolean,
  text,
  text,
  text,
  text
) to service_role;

revoke all on function public.get_family_invite_preview(text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_family_invite_preview(text)
  to anon, authenticated;

revoke all on function public.activate_family(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.activate_family(uuid) to authenticated;

revoke all on function public.add_unclaimed_family_member(
  uuid,
  text,
  text,
  text,
  text,
  text,
  date,
  text,
  text
) from public, anon, authenticated, service_role;
grant execute on function public.add_unclaimed_family_member(
  uuid,
  text,
  text,
  text,
  text,
  text,
  date,
  text,
  text
) to authenticated;

revoke all on function public.approve_family_join_request(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.approve_family_join_request(uuid, text)
  to authenticated;

revoke all on function public.cancel_family_join_request(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.cancel_family_join_request(uuid) to authenticated;

revoke all on function public.create_family(text)
  from public, anon, authenticated, service_role;
grant execute on function public.create_family(text) to authenticated;

revoke all on function public.delete_task_section(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.delete_task_section(uuid, text) to authenticated;

revoke all on function public.ensure_current_profile(text)
  from public, anon, authenticated, service_role;
grant execute on function public.ensure_current_profile(text) to authenticated;

revoke all on function public.get_pending_family_join_request()
  from public, anon, authenticated, service_role;
grant execute on function public.get_pending_family_join_request() to authenticated;

revoke all on function public.join_family_by_invite(text)
  from public, anon, authenticated, service_role;
grant execute on function public.join_family_by_invite(text) to authenticated;

revoke all on function public.request_family_join(text)
  from public, anon, authenticated, service_role;
grant execute on function public.request_family_join(text) to authenticated;

revoke all on function public.rotate_family_invite_code(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.rotate_family_invite_code(uuid) to authenticated;

revoke all on function public.update_family_member(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  date,
  text,
  text
) from public, anon, authenticated, service_role;
grant execute on function public.update_family_member(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  date,
  text,
  text
) to authenticated;

revoke all on function public.can_manage_family(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.can_manage_family(uuid, uuid) to authenticated;

revoke all on function public.is_family_creator(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.is_family_creator(uuid, uuid) to authenticated;

revoke all on function public.is_family_member(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.is_family_member(uuid, uuid) to authenticated;

revoke all on function public.shares_family_with(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.shares_family_with(uuid, uuid) to authenticated;

-- Reached only from create_family(text), which runs as the owner and mints the token itself.
revoke all on function public.create_family(text, text)
  from public, anon, authenticated, service_role;

revoke all on function public.generate_family_invite_code()
  from public, anon, authenticated, service_role;
revoke all on function public.auth_user_display_name(auth.users)
  from public, anon, authenticated, service_role;
revoke all on function public.bump_task_version()
  from public, anon, authenticated, service_role;
revoke all on function public.set_updated_at()
  from public, anon, authenticated, service_role;
revoke all on function public.enforce_family_people_limit()
  from public, anon, authenticated, service_role;
revoke all on function public.handle_new_auth_user()
  from public, anon, authenticated, service_role;

-- Supabase installs rls_auto_enable() on some projects for its ensure_rls event
-- trigger; an event trigger never checks EXECUTE, so no role needs it.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke all on function public.rls_auto_enable()
      from public, anon, authenticated, service_role;
  end if;
end;
$$;

revoke all on table public.family_members from public, anon, authenticated;
grant select on table public.family_members to authenticated;

revoke all on table public.family_snapshots from public, anon, authenticated;
grant select on table public.family_snapshots to authenticated;

revoke all on table public.profiles from public, anon, authenticated;
grant select, insert, update on table public.profiles to authenticated;

revoke all on table public.memory_items from public, anon, authenticated;
grant select, update, delete on table public.memory_items to authenticated;

revoke all on table public.nina_chat_rate_limits from public, anon, authenticated;

revoke all
  on public.task_sections,
     public.task_categories,
     public.tasks,
     public.shopping_items,
     public.chat_messages,
     public.household_insights
  from public, anon, authenticated;

grant select, insert, update, delete
  on public.task_sections,
     public.task_categories,
     public.tasks,
     public.shopping_items,
     public.chat_messages,
     public.household_insights
  to authenticated;

commit;
