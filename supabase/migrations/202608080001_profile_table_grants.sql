begin;

-- Every other policy-bearing table grants explicitly; profiles relied on the
-- project's default privileges, so a freshly provisioned database had none.
revoke all on table public.profiles from public, anon;

grant select, insert, update on table public.profiles to authenticated;

commit;
