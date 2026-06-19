begin;

revoke all on function public.claim_nina_chat_request(integer, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date)
  from public, anon, authenticated, service_role;
revoke all on function public.complete_nina_chat_run(uuid, uuid, text, jsonb, integer, integer, integer, integer, bigint, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.fail_nina_ai_run(uuid, text, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.get_nina_chat_result(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_current_nina_state(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.resolve_nina_proposal(uuid, text, jsonb, text)
  from public, anon, authenticated, service_role;
revoke all on function public.update_nina_memory(uuid, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.delete_nina_memory(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.delete_current_nina_chat_history(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_nina_weekly_candidates()
  from public, anon, authenticated, service_role;
revoke all on function public.reserve_nina_insight_run(uuid, text, bigint, date)
  from public, anon, authenticated, service_role;
revoke all on function public.complete_nina_insight_run(uuid, jsonb, integer, integer, integer, integer, bigint, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.run_nina_retention()
  from public, anon, authenticated, service_role;
revoke all on function public.verify_nina_maintenance_secret(text)
  from public, anon, authenticated, service_role;

grant execute on function public.begin_nina_chat_run(uuid, uuid, text, jsonb, text, bigint, date)
  to authenticated;
grant execute on function public.get_nina_chat_result(uuid)
  to authenticated;
grant execute on function public.get_current_nina_state(uuid)
  to authenticated;
grant execute on function public.resolve_nina_proposal(uuid, text, jsonb, text)
  to authenticated;
grant execute on function public.update_nina_memory(uuid, text, text, text)
  to authenticated;
grant execute on function public.delete_nina_memory(uuid)
  to authenticated;
grant execute on function public.delete_current_nina_chat_history(uuid)
  to authenticated;

grant execute on function public.complete_nina_chat_run(uuid, uuid, text, jsonb, integer, integer, integer, integer, bigint, integer)
  to service_role;
grant execute on function public.fail_nina_ai_run(uuid, text, integer)
  to service_role;
grant execute on function public.get_nina_weekly_candidates()
  to service_role;
grant execute on function public.reserve_nina_insight_run(uuid, text, bigint, date)
  to service_role;
grant execute on function public.complete_nina_insight_run(uuid, jsonb, integer, integer, integer, integer, bigint, integer)
  to service_role;
grant execute on function public.run_nina_retention()
  to service_role;
grant execute on function public.verify_nina_maintenance_secret(text)
  to service_role;

commit;
