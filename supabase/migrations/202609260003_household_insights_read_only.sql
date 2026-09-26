begin;

-- An insight speaks in Nina's voice about who carries the house, so only
-- complete_nina_insight_run writes one; a member who could would put blame in her mouth.
revoke all on table public.household_insights from public, anon, authenticated;
grant select on table public.household_insights to authenticated;

drop policy if exists "Household insights are family scoped" on public.household_insights;
drop policy if exists "Household insights are family readable" on public.household_insights;

create policy "Household insights are family readable"
  on public.household_insights for select
  to authenticated
  using (public.is_family_member(family_id));

commit;
