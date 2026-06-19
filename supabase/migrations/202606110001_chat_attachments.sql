alter table public.chat_messages
  add column if not exists attachments jsonb not null default '[]'::jsonb;

alter table public.chat_messages
  drop constraint if exists chat_messages_attachments_is_array;

alter table public.chat_messages
  add constraint chat_messages_attachments_is_array
  check (jsonb_typeof(attachments) = 'array');
