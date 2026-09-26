begin;

-- The server key reaches a table directly only where an Edge Function names it; the rest is RPCs.
revoke all
  on public.chat_messages,
     public.families,
     public.family_access_decisions,
     public.family_join_requests,
     public.family_members,
     public.family_snapshots,
     public.household_insights,
     public.invites,
     public.memory_items,
     public.nina_ai_budget_months,
     public.nina_ai_consents,
     public.nina_ai_family_rate_limits,
     public.nina_chat_rate_limits,
     public.nina_proposals,
     public.nina_threads,
     public.profiles,
     public.shopping_items,
     public.task_categories,
     public.task_sections,
     public.tasks,
     public.waitlist_signups,
     public.waitlist_submission_limits
  from service_role;

revoke all
  on public.premium_subscriptions,
     public.premium_subscription_transactions,
     public.app_store_server_notifications,
     public.nina_ai_runs
  from service_role;

grant select, insert, update, delete on table public.premium_subscriptions to service_role;
grant select, insert, update, delete on table public.premium_subscription_transactions to service_role;
grant select, insert, update, delete on table public.app_store_server_notifications to service_role;
grant select, update on table public.nina_ai_runs to service_role;

commit;
