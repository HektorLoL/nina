begin;

-- A chat row speaks as a person or as Nina, so only nina-chat's RPCs write one;
-- a member who could would put words in Nina's mouth or erase another adult's turn.
revoke all on table public.chat_messages from public, anon, authenticated;
grant select on table public.chat_messages to authenticated;

drop policy if exists "Legacy chat messages remain family writable" on public.chat_messages;

commit;
