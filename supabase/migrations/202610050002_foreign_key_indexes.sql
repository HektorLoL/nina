begin;

-- A foreign key without an index makes every delete of its parent scan the child table; a
-- house or account deletion cascades through all of these.
create index if not exists minor_data_consents_family_id_fkey_idx on private.minor_data_consents (family_id);
create index if not exists minor_guardianships_family_id_fkey_idx on private.minor_guardianships (family_id);
create index if not exists minor_profiles_family_id_fkey_idx on private.minor_profiles (family_id);
create index if not exists nina_reply_reports_family_id_fkey_idx on private.nina_reply_reports (family_id);
create index if not exists nina_reply_reports_message_id_fkey_idx on private.nina_reply_reports (message_id);
create index if not exists nina_reply_reports_reporter_user_id_fkey_idx on private.nina_reply_reports (reporter_user_id);
create index if not exists nina_reply_reports_run_id_fkey_idx on private.nina_reply_reports (run_id);
create index if not exists chat_messages_created_by_fkey_idx on public.chat_messages (created_by);
create index if not exists chat_messages_family_id_fkey_idx on public.chat_messages (family_id);
create index if not exists chat_messages_run_id_fkey_idx on public.chat_messages (run_id);
create index if not exists families_created_by_fkey_idx on public.families (created_by);
create index if not exists family_access_decisions_family_id_fkey_idx on public.family_access_decisions (family_id);
create index if not exists family_join_requests_invite_token_fkey_idx on public.family_join_requests (invite_token);
create index if not exists family_join_requests_reviewed_by_fkey_idx on public.family_join_requests (reviewed_by);
create index if not exists family_members_user_id_fkey_idx on public.family_members (user_id);
create index if not exists family_snapshots_updated_by_fkey_idx on public.family_snapshots (updated_by);
create index if not exists household_insights_source_run_id_fkey_idx on public.household_insights (source_run_id);
create index if not exists invites_created_by_fkey_idx on public.invites (created_by);
create index if not exists memory_items_confirmed_by_fkey_idx on public.memory_items (confirmed_by);
create index if not exists memory_items_created_by_fkey_idx on public.memory_items (created_by);
create index if not exists memory_items_owner_user_id_fkey_idx on public.memory_items (owner_user_id);
create index if not exists memory_items_source_run_id_fkey_idx on public.memory_items (source_run_id);
create index if not exists memory_items_subject_member_id_fkey_idx on public.memory_items (subject_member_id);
create index if not exists nina_ai_runs_thread_id_fkey_idx on public.nina_ai_runs (thread_id);
create index if not exists nina_ai_runs_user_id_fkey_idx on public.nina_ai_runs (user_id);
create index if not exists nina_proposals_assistant_message_id_fkey_idx on public.nina_proposals (assistant_message_id);
create index if not exists nina_proposals_family_id_fkey_idx on public.nina_proposals (family_id);
create index if not exists nina_proposals_resolved_by_fkey_idx on public.nina_proposals (resolved_by);
create index if not exists nina_proposals_run_id_fkey_idx on public.nina_proposals (run_id);
create index if not exists nina_proposals_thread_id_fkey_idx on public.nina_proposals (thread_id);
create index if not exists nina_threads_owner_user_id_fkey_idx on public.nina_threads (owner_user_id);
create index if not exists shopping_items_created_by_fkey_idx on public.shopping_items (created_by);
create index if not exists tasks_created_by_fkey_idx on public.tasks (created_by);

alter function public.set_updated_at() set search_path = pg_catalog, public;

commit;
