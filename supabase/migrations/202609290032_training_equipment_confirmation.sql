begin;
-- Only explicit, reviewed reverse inferences. Forward exercise mappings are
-- NOT invertible and are never blindly expanded into store inventory.
create table public.gym_training_equipment_rules(
 exercise_id text not null,equipment_id text not null references public.equipment(id),
 canonical_id text references public.canonical_equipment(id),label text not null,
 basis text not null,primary key(exercise_id,equipment_id)
);
alter table public.gym_training_equipment_rules enable row level security;
revoke all on public.gym_training_equipment_rules from public,anon,authenticated;
grant select on public.gym_training_equipment_rules to authenticated;
create policy training_rules_read on public.gym_training_equipment_rules for select to authenticated using(true);

create table public.gym_training_equipment_confirmations(
 user_id uuid not null references auth.users(id) on delete cascade,
 store_id text not null references public.gym_stores(id),
 equipment_id text not null references public.equipment(id),
 candidate_id uuid references public.gym_change_candidates(id),
 exercise_id text not null,workout_key text not null check(length(workout_key) between 1 and 100),
 active boolean not null default true,first_seen_at timestamptz not null default now(),
 last_seen_at timestamptz not null default now(),
 primary key(user_id,store_id,equipment_id)
);
alter table public.gym_training_equipment_confirmations enable row level security;
revoke all on public.gym_training_equipment_confirmations from public,anon,authenticated;
grant select on public.gym_training_equipment_confirmations to authenticated;
create policy training_confirmation_private on public.gym_training_equipment_confirmations for select to authenticated
 using(user_id=auth.uid() or public.is_report_admin());

alter table public.gym_change_evidence drop constraint gym_change_evidence_source_type_check;
alter table public.gym_change_evidence add constraint gym_change_evidence_source_type_check check(source_type in
 ('admin','official','gym_staff','confirmed_report','user_report','import','training_confirmation'));

-- One vote per person across manual reports and training confirmations.
create function public.gym_candidate_votes(target uuid,window_days int)
returns table(support numeric,oppose numeric,reporters bigint)
language sql stable security definer set search_path='' as $$
 with ranked as (
 select e.*,row_number() over(partition by coalesce('user:'||e.user_id::text,'source:'||e.id::text)
 order by e.observed_at desc,e.created_at desc,e.id desc) vote_rank
 from public.gym_change_evidence e
 left join public.gym_equipment_reports er on e.source_type='user_report' and e.source_ref=er.id::text
 left join public.gym_store_reports sr on e.source_type='user_report' and e.source_ref='store-report:'||sr.id::text
 where e.candidate_id=target and e.observed_at between now()-make_interval(days=>window_days) and now()
 and(e.source_type<>'user_report' or er.status<>'rejected' or sr.status<>'rejected')
 and(e.source_type<>'training_confirmation' or exists(
 select 1 from public.gym_training_equipment_confirmations t where t.user_id=e.user_id and t.candidate_id=e.candidate_id and t.active))
 )
 select coalesce(sum(weight) filter(where direction='support'),0),
 coalesce(sum(weight) filter(where direction='oppose'),0),
 count(distinct user_id) filter(where direction='support' and source_type in ('user_report','training_confirmation'))
 from ranked where vote_rank=1;
$$;
revoke all on function public.gym_candidate_votes(uuid,int) from public,anon,authenticated;

create function public.training_equipment_present(target_store text,target_equipment text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.gym_store_equipment g where g.store_id=target_store and g.presence_status='present'
 and(g.equipment_id=target_equipment or exists(
 select 1 from public.equipment_canonical_memberships m join public.gym_training_equipment_rules r on r.canonical_id=m.canonical_id
 where m.equipment_id=g.equipment_id and r.equipment_id=target_equipment)));
$$;
revoke all on function public.training_equipment_present(text,text) from public,anon,authenticated;

create function public.training_equipment_options(target_store text,exercise_ids text[]) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required' using errcode='42501';end if;
 if cardinality(exercise_ids)>100 then raise exception 'Too many exercises';end if;
 if not exists(select 1 from public.gym_stores where id=target_store and active and operational_status='active') then return '[]';end if;
 return coalesce((select jsonb_agg(x) from(
 select r.exercise_id,jsonb_agg(jsonb_build_object('equipment_id',r.equipment_id,'label',r.label,
 'known',public.training_equipment_present(target_store,r.equipment_id) or exists(
 select 1 from public.gym_training_equipment_confirmations t where t.user_id=auth.uid() and t.store_id=target_store
 and t.equipment_id=r.equipment_id and t.active and t.last_seen_at>=now()-make_interval(days=>(select evidence_window_days from public.gym_auto_rule_config where change_type='added'))
 )) order by r.label) options
 from public.gym_training_equipment_rules r join public.equipment e on e.id=r.equipment_id and not e.needs_review
 where r.exercise_id=any(exercise_ids) group by r.exercise_id)x),'[]');
end$$;
revoke all on function public.training_equipment_options(text,text[]) from public,anon;
grant execute on function public.training_equipment_options(text,text[]) to authenticated;

-- Local history is not cloud backup. The RPC receives only a user's explicit
-- completed-workout attestation, stable local key and reviewed exercise/equipment
-- IDs. No name, weight, repetitions, sets or history copy is stored.
create function public.confirm_training_equipment(target_store text,target_equipment text,
 target_exercise text,record_key text,performed boolean,expected_user uuid default auth.uid()) returns void
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();prior public.gym_training_equipment_confirmations%rowtype;
 c uuid;subject text:='training:'||target_equipment;eq public.equipment%rowtype;identity text;
begin
 if uid is null or uid is distinct from expected_user then raise exception 'Sign in required' using errcode='42501';end if;
 if performed is null or length(record_key) not between 1 and 100 then raise exception 'Invalid confirmation';end if;
 perform pg_advisory_xact_lock(hashtextextended(target_store||':added:'||subject,421));
 select * into prior from public.gym_training_equipment_confirmations
 where user_id=uid and store_id=target_store and equipment_id=target_equipment for update;
 if not performed then
  -- A stale device/delete must not withdraw a newer independent confirmation.
  if prior.workout_key=record_key and prior.active then
   update public.gym_training_equipment_confirmations set active=false where user_id=uid and store_id=target_store and equipment_id=target_equipment;
   perform public.reevaluate_gym_change_candidate(prior.candidate_id);
  end if;
  return;
 end if;
 if not exists(select 1 from public.gym_stores where id=target_store and active and operational_status='active') then raise exception 'Store unavailable';end if;
 if not exists(select 1 from public.gym_training_equipment_rules where exercise_id=target_exercise and equipment_id=target_equipment) then raise exception 'Unreviewed inference';end if;
 select * into strict eq from public.equipment where id=target_equipment and not needs_review;
 if public.training_equipment_present(target_store,target_equipment) then return;end if;
 if prior.active and prior.workout_key=record_key and prior.exercise_id=target_exercise then return;end if;
 select id into c from public.gym_change_candidates where store_id=target_store and change_type='added'
 and candidate_key=subject order by created_at desc limit 1 for update;
 if c is not null and (select status in ('rejected','rolled_back') from public.gym_change_candidates where id=c) then return;end if;
 if c is null then
 insert into public.gym_change_candidates(store_id,equipment_id,change_type,candidate_key,proposed_value)
 values(target_store,target_equipment,'added',subject,jsonb_build_object('origin','training_confirmation','equipment_name',eq.name)) returning id into c;
 end if;
 insert into public.gym_training_equipment_confirmations(user_id,store_id,equipment_id,candidate_id,exercise_id,workout_key)
 values(uid,target_store,target_equipment,c,target_exercise,record_key)
 on conflict(user_id,store_id,equipment_id) do update set candidate_id=c,exercise_id=excluded.exercise_id,
 workout_key=excluded.workout_key,active=true,last_seen_at=now();
 identity:=uid||':'||target_store||':'||target_equipment;
 insert into public.gym_change_evidence(candidate_id,source_type,source_ref,user_id,direction,weight,observed_at,data)
 values(c,'training_confirmation',identity,uid,'support',1,now(),jsonb_build_object('origin','completed_workout_user_confirmation'))
 on conflict(source_type,source_ref) where source_ref is not null do update set candidate_id=c,observed_at=now();
 update public.gym_change_candidates set last_seen_at=now() where id=c;
 perform public.reevaluate_gym_change_candidate(c);
end$$;
revoke all on function public.confirm_training_equipment(text,text,text,text,boolean,uuid) from public,anon;
grant execute on function public.confirm_training_equipment(text,text,text,text,boolean,uuid) to authenticated;

create view public.gym_training_equipment_summary with(security_invoker=true) as
 select t.store_id,t.equipment_id,count(distinct t.user_id) filter(where t.active and t.last_seen_at>=now()-make_interval(days=>(select evidence_window_days from public.gym_auto_rule_config where change_type='added'))) unique_user_count,
 count(*) filter(where t.active and t.last_seen_at>=now()-make_interval(days=>(select evidence_window_days from public.gym_auto_rule_config where change_type='added'))) evidence_count,min(t.first_seen_at) first_seen_at,max(t.last_seen_at) last_seen_at,
 max(c.status) status
 from public.gym_training_equipment_confirmations t left join public.gym_change_candidates c on c.id=t.candidate_id
 where public.is_report_admin() group by t.store_id,t.equipment_id;
grant select on public.gym_training_equipment_summary to authenticated;
create or replace function public.reevaluate_gym_equipment_candidate(target_id uuid)
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
  select v.support,v.oppose,v.reporters into support,oppose,reporters
  from public.gym_candidate_votes(target_id,rule.evidence_window_days) v;

  if candidate.change_type = 'added' then
    -- An exact, unique, already-reviewed master name is required. Fuzzy names,
    -- aliases and multiple equipment with the same name are not safe matches.
    select min(e.id), count(*) into matching_equipment, matching_count
    from public.equipment e
    where not e.needs_review and public.gym_search_text(e.name) = candidate.candidate_key;
    if matching_count <> 1 then matching_equipment := null; end if;
    if candidate.candidate_key='training:'||candidate.equipment_id
     and candidate.proposed_value->>'origin'='training_confirmation'
     and exists(select 1 from public.gym_training_equipment_rules r join public.equipment e on e.id=r.equipment_id and not e.needs_review
       where r.equipment_id=candidate.equipment_id) then matching_equipment:=candidate.equipment_id;end if;

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
create or replace function public.apply_gym_presence_candidate(target_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  c public.gym_change_candidates%rowtype;
  g public.gym_store_equipment%rowtype;
  after_row public.gym_store_equipment%rowtype;
  rule public.gym_auto_rule_config%rowtype;
  application_id uuid := gen_random_uuid();
  reason text;
  exact_matches integer;
  has_row boolean;
begin
  select * into c from public.gym_change_candidates where id = target_id for update;
  if not found or c.status <> 'auto_ready' then return; end if;
  if c.change_type not in ('added', 'removed') then return; end if;
  if exists(select 1 from public.gym_auto_applications where candidate_id = target_id) then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(
    c.store_id || ':' || coalesce(c.equipment_id, c.candidate_key), 422));
  -- Recompute votes, window, source protection and configured thresholds now.
  perform public.reevaluate_gym_change_candidate(target_id);
  select * into c from public.gym_change_candidates where id = target_id for update;
  if c.status <> 'auto_ready' then return; end if;
  select * into rule from public.gym_auto_rule_config where change_type = c.change_type;

  if c.equipment_id is null or not exists (
    select 1 from public.equipment where id = c.equipment_id and not needs_review
  ) then reason := 'equipment_not_identified'; end if;
  if reason is null and not exists (
    select 1 from public.gym_stores where id = c.store_id and active
  ) then reason := 'store_not_active'; end if;
  if reason is null and c.change_type = 'added' then
    select count(*) into exact_matches from public.equipment
    where not needs_review and public.gym_search_text(name) = c.candidate_key;
    if exact_matches <> 1 and not (
     c.candidate_key='training:'||c.equipment_id and c.proposed_value->>'origin'='training_confirmation'
     and exists(select 1 from public.gym_training_equipment_rules where equipment_id=c.equipment_id)
    ) then reason := 'equipment_not_identified'; end if;
  end if;
  if reason is null and exists (
    select 1 from public.gym_change_candidates other
    where other.id <> c.id and other.store_id = c.store_id
      and other.equipment_id = c.equipment_id
      and other.change_type in ('added', 'removed')
      and other.change_type <> c.change_type
      and other.status in ('collecting', 'needs_review', 'auto_ready')
      and other.unique_reporters > 0
  ) then reason := 'conflicting_candidate'; end if;
  if reason is null and exists (
    select 1 from public.gym_auto_applications a
    where a.store_id = c.store_id and a.equipment_id = c.equipment_id
      and a.change_type <> c.change_type
      and a.applied_at >= now() - make_interval(days => rule.cooldown_days)
  ) then reason := 'opposite_change_cooldown'; end if;
  if reason is not null then
    update public.gym_change_candidates set status = 'needs_review', updated_at = now()
    where id = c.id;
    insert into public.gym_auto_decisions
      (candidate_id, decision, reason_code, score_snapshot, rule_snapshot, algorithm_version)
    values (c.id, 'needs_review', reason,
      jsonb_build_object('support_score', c.support_score,
        'oppose_score', c.oppose_score, 'unique_reporters', c.unique_reporters),
      to_jsonb(rule), 'v1');
    return;
  end if;

  select * into g from public.gym_store_equipment
    where store_id = c.store_id and equipment_id = c.equipment_id for update;
  has_row := found;
  if c.change_type = 'removed' and has_row and
    g.source_kind in ('official', 'admin') and
    coalesce(g.checked_at, g.updated_at) >=
      now() - make_interval(days => rule.source_protection_days)
  then
    update public.gym_change_candidates set status = 'needs_review', updated_at = now()
      where id = c.id;
    insert into public.gym_auto_decisions
      (candidate_id, decision, reason_code, score_snapshot, rule_snapshot, algorithm_version)
    values (c.id, 'needs_review', 'protected_source',
      jsonb_build_object('support_score', c.support_score,
        'oppose_score', c.oppose_score, 'unique_reporters', c.unique_reporters),
      to_jsonb(rule), 'v1');
    return;
  end if;
  if (c.change_type = 'added' and has_row and g.presence_status = 'present')
    or (c.change_type = 'removed' and (not has_row or g.presence_status = 'removed'))
  then
    update public.gym_change_candidates
      set status = 'superseded', resolved_at = now(), updated_at = now()
      where id = c.id;
    insert into public.gym_auto_decisions
      (candidate_id, decision, reason_code, score_snapshot, rule_snapshot, algorithm_version)
    values (c.id, 'superseded', 'already_current',
      jsonb_build_object('support_score', c.support_score,
        'oppose_score', c.oppose_score, 'unique_reporters', c.unique_reporters),
      to_jsonb(rule), 'v1');
    return;
  end if;

  perform set_config('setkeep.gym_candidate_id', c.id::text, true);
  perform set_config('setkeep.gym_application_id', application_id::text, true);
  if c.change_type = 'added' and not has_row then
    insert into public.gym_store_equipment
      (store_id, equipment_id, raw_name, available, presence_status,
       source_kind, checked_at, source)
    values (c.store_id, c.equipment_id,
      coalesce(nullif(c.proposed_value->>'equipment_name', ''),
        (select name from public.equipment where id = c.equipment_id)),
      true, 'present', 'confirmed_report', now(),
      jsonb_build_object('auto_applied', true, 'candidate_id', c.id,
        'algorithm_version', c.algorithm_version));
  elsif c.change_type = 'added' then
    update public.gym_store_equipment set
      presence_status = 'present', available = true,
      unavailable_quantity = case when quantity is null then null else 0 end,
      source_kind = 'confirmed_report', checked_at = now(), updated_at = now(),
      source = source || jsonb_build_object('auto_applied', true,
        'candidate_id', c.id, 'algorithm_version', c.algorithm_version)
    where store_id = c.store_id and equipment_id = c.equipment_id;
  else
    update public.gym_store_equipment set
      presence_status = 'removed', available = false,
      source_kind = 'confirmed_report', checked_at = now(), updated_at = now(),
      source = source || jsonb_build_object('auto_applied', true,
        'candidate_id', c.id, 'algorithm_version', c.algorithm_version)
    where store_id = c.store_id and equipment_id = c.equipment_id;
  end if;
  select * into after_row from public.gym_store_equipment
    where store_id = c.store_id and equipment_id = c.equipment_id;
  if not found or (c.change_type = 'removed' and after_row.presence_status <> 'removed')
    or (c.change_type = 'added' and after_row.presence_status <> 'present') then
    raise exception 'Master update was blocked';
  end if;
  insert into public.gym_auto_applications
    (id, candidate_id, store_id, equipment_id, change_type,
     before_data, after_data, application_type)
  values (application_id, c.id, c.store_id, c.equipment_id, c.change_type,
    case when g.store_id is not null then to_jsonb(g) end,
    to_jsonb(after_row), 'auto');
  update public.gym_change_candidates
    set status = 'auto_applied', resolved_at = now(), updated_at = now()
    where id = c.id;
  insert into public.gym_auto_decisions
    (candidate_id, decision, reason_code, score_snapshot, rule_snapshot, algorithm_version)
  values (c.id, 'auto_applied', 'applied_to_master',
    jsonb_build_object('support_score', c.support_score,
      'oppose_score', c.oppose_score, 'unique_reporters', c.unique_reporters,
      'application_id', application_id), to_jsonb(rule), 'v1');
  update public.gym_equipment_reports r set
    status = 'applied', admin_note = '設備情報へ自動反映済み'
  from public.gym_change_evidence e
  where e.candidate_id = c.id and e.source_type = 'user_report'
    and e.source_ref = r.id::text and r.status in ('pending', 'reviewing');
  perform set_config('setkeep.gym_candidate_id', '', true);
  perform set_config('setkeep.gym_application_id', '', true);
end $$;
create or replace function public.reevaluate_gym_change_candidate(target_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare c public.gym_change_candidates%rowtype;r public.gym_auto_rule_config%rowtype;reason text; support numeric;oppose numeric;reporters int;begin
 select * into c from public.gym_change_candidates where id=target_id;
 if not found or c.status not in ('collecting','needs_review','auto_ready') then return;end if;
 if c.entity_type='store' then perform pg_advisory_xact_lock(hashtextextended(coalesce(c.store_id,'new-store'),429));end if;
 select * into c from public.gym_change_candidates where id=target_id for update;
 if c.status not in ('collecting','needs_review','auto_ready') then return;end if;
 select * into r from public.gym_auto_rule_config where change_type=c.change_type;
 if exists(select 1 from public.gym_change_evidence e where e.candidate_id=c.id and e.source_type='official'
 and e.observed_at>now()-make_interval(days=>r.evidence_window_days) and e.data->>'requires_review'='true') then reason:='official_parser_review';
 elsif r.official_review_only and exists(select 1 from public.gym_change_evidence e where e.candidate_id=c.id and e.source_type='official' and e.direction='support'
 and e.observed_at>now()-make_interval(days=>r.evidence_window_days)) then reason:='official_pilot_review';end if;
 -- Official pages disagree, or the proposed direction contradicts a fresh official observation.
 if exists(select 1 from public.gym_change_evidence e join public.gym_change_candidates other on other.id=e.candidate_id
 where e.source_type='official' and other.store_id=c.store_id and other.entity_type=c.entity_type
 and e.observed_at>now()-make_interval(days=>greatest(r.source_protection_days,r.evidence_window_days))
 and ((c.entity_type='store' and other.change_type in ('store_temporarily_closed','store_reopened','store_closed')
 and c.change_type in ('store_temporarily_closed','store_reopened','store_closed') and other.change_type<>c.change_type)
 or (c.entity_type='store_equipment' and c.equipment_id=other.equipment_id and
 ((c.change_type='removed' and other.change_type='added') or(c.change_type='added' and other.change_type='removed')
 or(c.change_type='quantity_changed' and other.change_type='quantity_changed' and c.candidate_key<>other.candidate_key))))) then reason:='official_conflicting_evidence';end if;
 if reason is null then perform public.reevaluate_gym_candidate_before_official(target_id);return;end if;
 select v.support,v.oppose,v.reporters into support,oppose,reporters
 from public.gym_candidate_votes(c.id,r.evidence_window_days) v;
 update public.gym_change_candidates set status='needs_review',updated_at=now(),
 support_score=support,oppose_score=oppose,unique_reporters=reporters where id=c.id;
 insert into public.gym_auto_decisions(candidate_id,decision,reason_code,score_snapshot,rule_snapshot,algorithm_version)
 values(c.id,'needs_review',reason,jsonb_build_object('support_score',support,'oppose_score',oppose,'unique_reporters',reporters),to_jsonb(r),'official-v1');
end $$;

-- Explicit reviewed reverse inference seeds; no Master rows or forward mappings changed.
insert into public.gym_training_equipment_rules(exercise_id,equipment_id,canonical_id,label,basis) values
('bench_press','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('incline_dumbbell_press','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('incline_barbell_press','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('flat_dumbbell_press','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_fly','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_fly','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('bent_over_row','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('deadlift','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('straight_arm_pulldown','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('straight_arm_pulldown','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('dumbbell_shoulder_press','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('military_press','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('lateral_raise','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('front_raise','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('rear_raise','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('barbell_curl','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('dumbbell_curl','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('hammer_curl','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_curl','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_curl','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('barbell_squat','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('romanian_deadlift','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('dumbbell_fly','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('decline_barbell_press','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('smith_bench_press','fit-place24:fp_eq_74ae16617af0','smith','スミスマシン','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('smith_incline_press','fit-place24:fp_eq_74ae16617af0','smith','スミスマシン','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('smith_decline_press','fit-place24:fp_eq_74ae16617af0','smith','スミスマシン','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('decline_dumbbell_press','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('incline_dumbbell_fly','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('decline_dumbbell_fly','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('low_cable_fly','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('low_cable_fly','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('high_cable_fly','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('high_cable_fly','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('single_arm_cable_fly','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('single_arm_cable_fly','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('rack_pull','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('snatch_grip_deadlift','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('pendlay_row','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('chest_supported_dumbbell_row','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('seal_row','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('kneeling_lat_pulldown','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('kneeling_lat_pulldown','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('dumbbell_pullover','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_pullover','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_pullover','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('smith_shoulder_press','fit-place24:fp_eq_74ae16617af0','smith','スミスマシン','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('arnold_press','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_shoulder_press','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_shoulder_press','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('machine_lateral_raise','fit-place24:fp_eq_df0b02e63072','lateral_raise','シーテッドラテラルレイズ','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('machine_lateral_raise','fit-place24:fp_eq_1caec5a7c3b6','lateral_raise','スタンディングラテラルレイズ','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_lateral_raise','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_lateral_raise','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('single_arm_cable_lateral_raise','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('single_arm_cable_lateral_raise','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_front_raise','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_front_raise','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_rear_delt_fly','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_rear_delt_fly','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('dumbbell_shrug','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('barbell_shrug','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('incline_dumbbell_curl','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('concentration_curl','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('spider_curl','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_hammer_curl','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_hammer_curl','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('bayesian_curl','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('bayesian_curl','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('zottman_curl','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('close_grip_bench_press','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('jm_press','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('single_arm_pushdown','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('single_arm_pushdown','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('reverse_grip_pushdown','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('reverse_grip_pushdown','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('straight_bar_pushdown','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('straight_bar_pushdown','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('rope_pushdown','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('rope_pushdown','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('triceps_kickback','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('front_squat','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('goblet_squat','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('smith_squat','fit-place24:fp_eq_74ae16617af0','smith','スミスマシン','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('sumo_deadlift','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('smith_bulgarian_split_squat','fit-place24:fp_eq_74ae16617af0','smith','スミスマシン','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('step_up','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('good_morning','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('single_leg_rdl','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_pull_through','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_pull_through','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_glute_kickback','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_glute_kickback','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_woodchop','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('cable_woodchop','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('pallof_press','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('pallof_press','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('dumbbell_skull_crusher','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('v_bar_pushdown','fit-place24:fp_eq_4740a3f1901c','cable_crossover','ケーブルクロスオーバー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('v_bar_pushdown','fit-place24:fp_eq_b333827ebb7e','dual_pulley','デュアルアジャスタブルプーリー','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('gorilla_row','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','種目カタログの明示器具仕様を確認。使用した設備だけ本人確認し、ベンチ等の付帯設備は推定しない。'),
('preacher_curl','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','フリーウェイトの使用器具は本人の選択が必要。その他は判定しない。'),
('preacher_curl','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','フリーウェイトの使用器具は本人の選択が必要。その他は判定しない。'),
('upright_row','hyper-fit24:fp_eq_e2f3c2ba7ec7','dumbbell','ダンベル','フリーウェイトの使用器具は本人の選択が必要。その他は判定しない。'),
('upright_row','golds-gym:fp_eq_7b69e5784787','barbell','バーベル','フリーウェイトの使用器具は本人の選択が必要。その他は判定しない。');
notify pgrst,'reload schema';
commit;
