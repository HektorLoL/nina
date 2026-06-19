revoke insert, update, delete on public.family_members from public, anon, authenticated;
revoke insert, update, delete on public.families from public, anon, authenticated;

revoke all on function public.auth_user_display_name(auth.users) from public, anon, authenticated;
revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
revoke all on function public.enforce_family_member_limit() from public, anon, authenticated;
