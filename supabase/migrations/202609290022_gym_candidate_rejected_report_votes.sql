begin;
-- A rejected report remains in Evidence for audit, but no longer carries a vote.
-- Report status is still separate from Candidate status and never changes masters.
create or replace function public.reevaluate_gym_change_candidate(target_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  candidate public.gym_change_candidates%rowtype;
  rule public.gym_auto_rule_config%rowtype;
  support numeric(12,3) := 0;
  oppose numeric(12,3) := 0;
  reporters integer := 0;
  matching_equipment text;
  matching_count integer := 0;
  next_status text;
  reason text;
  protected_source boolean := false;
  in_cooldown boolean := false;
begin
  select * into candidate from public.gym_change_candidates where id = target_id for update;
  if not found or candidate.status not in ('collecting', 'needs_review', 'auto_ready') then
    return;
  end if;
  select * into strict rule from public.gym_auto_rule_config
    where change_type = candidate.change_type;

  -- Only the latest observation by each user contributes a vote. Independent
  -- trusted sources retain separate evidence; they never count as users.
  with ranked as (
    select e.*,
      row_number() over (
        partition by coalesce('user:' || e.user_id::text, 'source:' || e.id::text)
        order by e.observed_at desc, e.created_at desc, e.id desc
      ) as vote_rank
    from public.gym_change_evidence e
    left join public.gym_equipment_reports report
      on e.source_type = 'user_report' and report.id::text = e.source_ref
    where e.candidate_id = target_id
      and (e.source_type <> 'user_report' or
        (report.id is not null and report.status <> 'rejected'))
      and e.observed_at >= now() - make_interval(days => rule.evidence_window_days)
      and e.observed_at <= now()
  )
  select coalesce(sum(weight) filter (where direction = 'support'), 0),
         coalesce(sum(weight) filter (where direction = 'oppose'), 0),
         count(distinct user_id) filter (
           where direction = 'support' and source_type = 'user_report'
         )
    into support, oppose, reporters
  from ranked where vote_rank = 1;

  if candidate.change_type = 'added' then
    -- An exact, unique, already-reviewed master name is required. Fuzzy names,
    -- aliases and multiple equipment with the same name are not safe matches.
    select min(e.id), count(*) into matching_equipment, matching_count
    from public.equipment e
    where not e.needs_review and public.gym_search_text(e.name) = candidate.candidate_key;
    if matching_count <> 1 then matching_equipment := null; end if;
  end if;

  if rule.source_protection_days > 0 and candidate.equipment_id is not null then
    select exists (
      select 1 from public.gym_store_equipment g
      where g.store_id = candidate.store_id and g.equipment_id = candidate.equipment_id
        and g.source_kind in ('official', 'admin')
        and coalesce(g.checked_at, g.updated_at) >=
          now() - make_interval(days => rule.source_protection_days)
    ) into protected_source;
  end if;
  if rule.cooldown_days > 0 then
    select exists (
      select 1 from public.gym_change_candidates prior
      where prior.id <> candidate.id and prior.store_id = candidate.store_id
        and prior.change_type = candidate.change_type
        and prior.candidate_key = candidate.candidate_key
        and prior.resolved_at >= now() - make_interval(days => rule.cooldown_days)
    ) into in_cooldown;
  end if;

  if not rule.auto_apply_enabled then
    next_status := 'needs_review'; reason := 'manual_rule';
  elsif oppose > rule.max_oppose_score then
    next_status := 'needs_review'; reason := 'conflicting_evidence';
  elsif candidate.change_type = 'added' and matching_equipment is null then
    next_status := 'needs_review'; reason := 'equipment_not_identified';
  elsif reporters < rule.min_unique_reporters or support < rule.min_support_score then
    next_status := 'collecting'; reason := 'insufficient_support';
  elsif protected_source then
    next_status := 'needs_review'; reason := 'protected_source';
  elsif in_cooldown then
    next_status := 'needs_review'; reason := 'cooldown';
  else
    next_status := 'auto_ready'; reason := 'threshold_met';
  end if;

  update public.gym_change_candidates set
    equipment_id = case when candidate.change_type = 'added'
      then matching_equipment else candidate.equipment_id end,
    proposed_value = case when candidate.change_type = 'added'
      then candidate.proposed_value || jsonb_build_object('matched_equipment_id', matching_equipment)
      else candidate.proposed_value end,
    status = next_status, support_score = support, oppose_score = oppose,
    unique_reporters = reporters, algorithm_version = 'v1', updated_at = now()
  where id = target_id;
  insert into public.gym_auto_decisions
    (candidate_id, decision, reason_code, score_snapshot, rule_snapshot, algorithm_version)
  values (
    target_id, next_status, reason,
    jsonb_build_object('support_score', support, 'oppose_score', oppose,
      'unique_reporters', reporters, 'matched_equipment_id', matching_equipment,
      'protected_source', protected_source, 'in_cooldown', in_cooldown),
    to_jsonb(rule), 'v1'
  );
end $$;
create function public.reconsider_gym_equipment_report_evidence()
returns trigger language plpgsql security definer set search_path = '' as $$
declare affected record;
begin
  if new.status is distinct from old.status then
    for affected in
      select distinct candidate_id from public.gym_change_evidence
      where source_type = 'user_report' and source_ref = new.id::text
    loop
      perform public.reevaluate_gym_change_candidate(affected.candidate_id);
    end loop;
  end if;
  return new;
end $$;
revoke all on function public.reconsider_gym_equipment_report_evidence()
  from public, anon, authenticated;
create trigger gym_report_status_candidate_review
  after update of status on public.gym_equipment_reports
  for each row execute function public.reconsider_gym_equipment_report_evidence();
commit;
