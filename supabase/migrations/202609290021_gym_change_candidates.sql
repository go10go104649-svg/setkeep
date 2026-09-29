begin;

-- Phase 1 records and evaluates proposed changes. Nothing here writes a gym master.
create table public.gym_auto_rule_config (
  change_type text primary key check (change_type in (
    'added', 'removed', 'not_present', 'wrong_name', 'other',
    'quantity_changed', 'temporarily_unavailable', 'available_again'
  )),
  auto_apply_enabled boolean not null default false,
  min_unique_reporters integer not null check (min_unique_reporters >= 0),
  min_support_score numeric(12,3) not null check (min_support_score >= 0),
  max_oppose_score numeric(12,3) not null check (max_oppose_score >= 0),
  evidence_window_days integer not null check (evidence_window_days > 0),
  source_protection_days integer not null default 0 check (source_protection_days >= 0),
  cooldown_days integer not null default 0 check (cooldown_days >= 0),
  updated_at timestamptz not null default now()
);

-- auto_apply_enabled means eligible for auto_ready in this phase, not permission
-- to change gym_store_equipment. Other change types remain review-only.
insert into public.gym_auto_rule_config
  (change_type, auto_apply_enabled, min_unique_reporters, min_support_score,
   max_oppose_score, evidence_window_days, source_protection_days, cooldown_days)
values
  ('added', true, 3, 3, 0, 30, 0, 7),
  ('removed', true, 4, 4, 0, 30, 14, 7),
  ('not_present', false, 4, 4, 0, 30, 0, 0),
  ('wrong_name', false, 1, 1, 0, 30, 0, 0),
  ('other', false, 1, 1, 0, 30, 0, 0),
  ('quantity_changed', false, 3, 3, 0, 30, 0, 7),
  ('temporarily_unavailable', false, 2, 2, 0, 14, 0, 0),
  ('available_again', false, 2, 2, 0, 14, 0, 0);

create table public.gym_change_candidates (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null default 'store_equipment' check (entity_type = 'store_equipment'),
  store_id text not null references public.gym_stores(id),
  equipment_id text references public.equipment(id) on delete set null,
  change_type text not null references public.gym_auto_rule_config(change_type),
  candidate_key text not null check (length(candidate_key) between 1 and 300),
  proposed_value jsonb not null default '{}'::jsonb,
  status text not null default 'collecting' check (status in (
    'collecting', 'needs_review', 'auto_ready', 'auto_applied', 'admin_applied',
    'rejected', 'expired', 'superseded', 'rolled_back'
  )),
  support_score numeric(12,3) not null default 0,
  oppose_score numeric(12,3) not null default 0,
  unique_reporters integer not null default 0,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  algorithm_version text not null default 'v1',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index gym_candidate_open_key on public.gym_change_candidates
  (store_id, change_type, candidate_key)
  where status in ('collecting', 'needs_review', 'auto_ready');
create index gym_candidate_admin_queue on public.gym_change_candidates(status, last_seen_at desc);

create table public.gym_change_evidence (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.gym_change_candidates(id) on delete cascade,
  source_type text not null check (source_type in (
    'admin', 'official', 'gym_staff', 'confirmed_report', 'user_report', 'import'
  )),
  source_ref text,
  user_id uuid references auth.users(id) on delete set null,
  direction text not null check (direction in ('support', 'oppose')),
  weight numeric(12,3) not null check (weight > 0 and weight <= 100),
  observed_at timestamptz not null,
  source_url text,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create unique index gym_evidence_source_ref on public.gym_change_evidence(source_type, source_ref)
  where source_ref is not null;
create index gym_evidence_candidate_time on public.gym_change_evidence(candidate_id, observed_at desc);

create table public.gym_auto_decisions (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.gym_change_candidates(id) on delete cascade,
  decision text not null check (decision in (
    'collecting', 'needs_review', 'auto_ready', 'auto_applied', 'admin_applied',
    'rejected', 'expired', 'superseded', 'rolled_back'
  )),
  reason_code text not null,
  score_snapshot jsonb not null,
  rule_snapshot jsonb not null,
  algorithm_version text not null default 'v1',
  decided_at timestamptz not null default now()
);
create index gym_decisions_candidate_time on public.gym_auto_decisions(candidate_id, decided_at desc);

-- The app may read these tables only after its existing admin check succeeds.
-- All mutations are reserved for the database owner/service role and the
-- restricted trigger functions below; authenticated users cannot cast votes.
alter table public.gym_auto_rule_config enable row level security;
alter table public.gym_change_candidates enable row level security;
alter table public.gym_change_evidence enable row level security;
alter table public.gym_auto_decisions enable row level security;
revoke all on public.gym_auto_rule_config, public.gym_change_candidates,
  public.gym_change_evidence, public.gym_auto_decisions from anon, authenticated;
grant select on public.gym_auto_rule_config, public.gym_change_candidates,
  public.gym_change_evidence, public.gym_auto_decisions to authenticated;
create policy gym_rules_admin_read on public.gym_auto_rule_config
  for select to authenticated using (public.is_report_admin());
create policy gym_candidates_admin_read on public.gym_change_candidates
  for select to authenticated using (public.is_report_admin());
create policy gym_evidence_admin_read on public.gym_change_evidence
  for select to authenticated using (public.is_report_admin());
create policy gym_decisions_admin_read on public.gym_auto_decisions
  for select to authenticated using (public.is_report_admin());

create view public.admin_gym_change_candidates with (security_invoker = true) as
  select c.*, concat_ws(' ', chain.name, store.name) as store_name,
    coalesce(e.display_name, e.name) as equipment_name
  from public.gym_change_candidates c
  join public.gym_stores store on store.id = c.store_id
  join public.gym_chains chain on chain.id = store.chain_id
  left join public.equipment e on e.id = c.equipment_id;
grant select on public.admin_gym_change_candidates to authenticated;

create function public.reevaluate_gym_change_candidate(target_id uuid)
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
    where e.candidate_id = target_id
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
revoke all on function public.reevaluate_gym_change_candidate(uuid) from public, anon, authenticated;

create function public.ingest_gym_equipment_report(report_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  report public.gym_equipment_reports%rowtype;
  subject_key text;
  proposal jsonb;
  target_id uuid;
  inserted integer;
begin
  select * into report from public.gym_equipment_reports where id = report_id;
  if not found or report.status not in ('pending', 'reviewing') then return; end if;

  if report.kind = 'added' then
    subject_key := public.gym_search_text(report.equipment_name);
    proposal := jsonb_build_object('equipment_name', trim(report.equipment_name),
      'normalized_equipment_name', subject_key);
  elsif report.equipment_id is not null then
    subject_key := report.equipment_id;
    proposal := jsonb_build_object('equipment_id', report.equipment_id);
    if report.kind = 'wrong_name' and coalesce(trim(report.equipment_name), '') <> '' then
      subject_key := subject_key || ':' || public.gym_search_text(report.equipment_name);
      proposal := proposal || jsonb_build_object('equipment_name', trim(report.equipment_name));
    end if;
  else
    -- Unstructured reports are not merged on a guessed equipment identity.
    subject_key := 'report:' || report.id::text;
    proposal := jsonb_build_object('equipment_name', report.equipment_name,
      'comment', report.comment);
  end if;
  if report.kind = 'other' then
    subject_key := 'report:' || report.id::text;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    report.store_id || ':' || report.kind || ':' || subject_key, 421
  ));
  select id into target_id from public.gym_change_candidates
    where store_id = report.store_id and change_type = report.kind
      and candidate_key = subject_key
      and status in ('collecting', 'needs_review', 'auto_ready')
    for update;
  if target_id is null then
    insert into public.gym_change_candidates
      (store_id, equipment_id, change_type, candidate_key, proposed_value,
       first_seen_at, last_seen_at)
    values (report.store_id, report.equipment_id, report.kind, subject_key,
      proposal, report.created_at, report.created_at)
    returning id into target_id;
  end if;

  insert into public.gym_change_evidence
    (candidate_id, source_type, source_ref, user_id, direction, weight,
     observed_at, data)
  values (target_id, 'user_report', report.id::text, report.user_id,
    'support', 1, report.created_at,
    jsonb_build_object('report_id', report.id, 'kind', report.kind,
      'equipment_name', report.equipment_name, 'comment', report.comment))
  on conflict (source_type, source_ref) where source_ref is not null do nothing;
  get diagnostics inserted = row_count;
  if inserted = 0 then return; end if;

  update public.gym_change_candidates set
    first_seen_at = least(first_seen_at, report.created_at),
    last_seen_at = greatest(last_seen_at, report.created_at),
    updated_at = now()
  where id = target_id;
  perform public.reevaluate_gym_change_candidate(target_id);
end $$;
revoke all on function public.ingest_gym_equipment_report(uuid) from public, anon, authenticated;

create function public.capture_gym_equipment_report_evidence()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.ingest_gym_equipment_report(new.id);
  return new;
end $$;
revoke all on function public.capture_gym_equipment_report_evidence() from public, anon, authenticated;
create trigger gym_equipment_report_evidence after insert on public.gym_equipment_reports
  for each row execute function public.capture_gym_equipment_report_evidence();

-- Existing unresolved reports join the same pipeline. Resolved/rejected report
-- history is preserved but does not create a fresh open candidate.
do $$ declare old_report record; begin
  for old_report in
    select id from public.gym_equipment_reports
    where status in ('pending', 'reviewing') order by created_at, id
  loop
    perform public.ingest_gym_equipment_report(old_report.id);
  end loop;
end $$;

notify pgrst, 'reload schema';
commit;
