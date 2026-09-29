begin;

alter table public.gym_equipment_reports drop constraint gym_equipment_reports_kind_check;
alter table public.gym_equipment_reports add constraint gym_equipment_reports_kind_check
  check (kind in ('not_present', 'removed', 'added', 'wrong_name', 'other',
    'quantity_changed', 'temporarily_unavailable', 'available_again'));
alter table public.gym_equipment_reports
  add column reported_quantity integer check (reported_quantity between 1 and 100),
  add column reported_unavailable_quantity integer
    check (reported_unavailable_quantity between 1 and 100),
  add column unavailable_scope text check (unavailable_scope in ('all', 'partial'));
alter table public.gym_equipment_reports add constraint gym_state_report_values check (
  (kind <> 'quantity_changed' or (equipment_id is not null and reported_quantity is not null))
  and (kind <> 'temporarily_unavailable' or
    (equipment_id is not null and unavailable_scope is not null
      and (unavailable_scope = 'all' or reported_unavailable_quantity is not null)))
  and (kind <> 'available_again' or equipment_id is not null)
  and (kind = 'temporarily_unavailable' or
    (reported_unavailable_quantity is null and unavailable_scope is null))
  and (kind = 'quantity_changed' or reported_quantity is null)
  and (unavailable_scope is distinct from 'all' or reported_unavailable_quantity is null)
);
grant insert(reported_quantity, reported_unavailable_quantity, unavailable_scope)
  on public.gym_equipment_reports to authenticated;

alter table public.gym_auto_applications
  drop constraint gym_auto_applications_change_type_check;
alter table public.gym_auto_applications
  add constraint gym_auto_applications_change_type_check
  check (change_type in ('added', 'removed', 'quantity_changed',
    'temporarily_unavailable', 'available_again'));

-- Different reported values must not be swallowed by the old duplicate check.
create or replace function public.limit_gym_equipment_reports() returns trigger
language plpgsql set search_path = '' as $$
declare master public.gym_store_equipment%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 0));
  if new.equipment_id is not null then
    select * into master from public.gym_store_equipment
    where store_id = new.store_id and equipment_id = new.equipment_id;
    if not found then raise exception 'Equipment does not belong to this store'; end if;
  end if;
  if new.kind = 'temporarily_unavailable' and new.unavailable_scope = 'partial'
    and (master.quantity is null or
      new.reported_unavailable_quantity >= master.quantity) then
    raise exception 'Partial unavailability requires a known larger total quantity';
  end if;
  if exists(select 1 from public.gym_equipment_reports r
    where r.user_id = new.user_id and r.store_id = new.store_id
      and r.equipment_id is not distinct from new.equipment_id
      and r.kind = new.kind
      and coalesce(trim(r.equipment_name), '') = coalesce(trim(new.equipment_name), '')
      and trim(r.comment) = trim(new.comment)
      and r.reported_quantity is not distinct from new.reported_quantity
      and r.reported_unavailable_quantity is not distinct from new.reported_unavailable_quantity
      and r.unavailable_scope is not distinct from new.unavailable_scope
      and r.status in ('pending', 'reviewing'))
  then return null; end if;
  if (select count(*) from public.gym_equipment_reports
      where user_id = new.user_id and created_at > now() - interval '5 minutes') >= 5
  then raise exception 'Please wait before reporting again'; end if;
  return new;
end $$;

-- These types were review-only in phase 1. Activate only after defining the
-- guarded application path in this same migration transaction.
update public.gym_auto_rule_config set auto_apply_enabled = true,
  source_protection_days = case change_type when 'quantity_changed' then 14 else 1 end,
  cooldown_days = 7, updated_at = now()
where change_type in ('quantity_changed', 'temporarily_unavailable', 'available_again');

create or replace function public.ingest_gym_equipment_report(report_id uuid)
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
  elsif report.kind = 'quantity_changed' then
    subject_key := report.equipment_id || ':quantity:' || report.reported_quantity;
    proposal := jsonb_build_object('equipment_id', report.equipment_id,
      'reported_quantity', report.reported_quantity);
  elsif report.kind = 'temporarily_unavailable' then
    subject_key := report.equipment_id || ':unavailable:' || report.unavailable_scope || ':' ||
      coalesce(report.reported_unavailable_quantity::text, 'all');
    proposal := jsonb_build_object('equipment_id', report.equipment_id,
      'unavailable_scope', report.unavailable_scope,
      'reported_unavailable_quantity', report.reported_unavailable_quantity);
  elsif report.kind = 'available_again' then
    subject_key := report.equipment_id || ':available:all';
    proposal := jsonb_build_object('equipment_id', report.equipment_id,
      'recovery_scope', 'all');
  elsif report.equipment_id is not null then
    subject_key := report.equipment_id;
    proposal := jsonb_build_object('equipment_id', report.equipment_id);
    if report.kind = 'wrong_name' and coalesce(trim(report.equipment_name), '') <> '' then
      subject_key := subject_key || ':' || public.gym_search_text(report.equipment_name);
      proposal := proposal || jsonb_build_object('equipment_name', trim(report.equipment_name));
    end if;
  else
    subject_key := 'report:' || report.id::text;
    proposal := jsonb_build_object('equipment_name', report.equipment_name,
      'comment', report.comment);
  end if;
  if report.kind = 'other' then subject_key := 'report:' || report.id::text; end if;

  perform pg_advisory_xact_lock(hashtextextended(
    report.store_id || ':' || report.kind || ':' || subject_key, 421));
  select id into target_id from public.gym_change_candidates
    where store_id = report.store_id and change_type = report.kind
      and candidate_key = subject_key
      and status in ('collecting', 'needs_review', 'auto_ready') for update;
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
      'equipment_name', report.equipment_name, 'comment', report.comment,
      'reported_quantity', report.reported_quantity,
      'reported_unavailable_quantity', report.reported_unavailable_quantity,
      'unavailable_scope', report.unavailable_scope))
  on conflict (source_type, source_ref) where source_ref is not null do nothing;
  get diagnostics inserted = row_count;
  if inserted = 0 then return; end if;
  update public.gym_change_candidates set
    first_seen_at = least(first_seen_at, report.created_at),
    last_seen_at = greatest(last_seen_at, report.created_at),
    updated_at = now() where id = target_id;
  perform public.reevaluate_gym_change_candidate(target_id);
end $$;

-- Keep the phase-2 presence logic intact and route only the new change types
-- through the additional state-change path. Existing rollback snapshots are
-- complete Master rows, so the rollback RPC already handles these types.
alter function public.apply_gym_change_candidate(uuid)
  rename to apply_gym_presence_candidate;

create function public.apply_gym_state_candidate(target_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  c public.gym_change_candidates%rowtype;
  g public.gym_store_equipment%rowtype;
  after_row public.gym_store_equipment%rowtype;
  rule public.gym_auto_rule_config%rowtype;
  application_id uuid := gen_random_uuid();
  reason text;
  target_quantity integer;
  target_unavailable integer;
  target_available boolean;
begin
  select * into c from public.gym_change_candidates where id = target_id for update;
  if not found or c.status <> 'auto_ready' or c.change_type not in
    ('quantity_changed', 'temporarily_unavailable', 'available_again') then return; end if;
  if exists(select 1 from public.gym_auto_applications where candidate_id = c.id) then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(c.store_id || ':' || c.equipment_id, 422));
  perform public.reevaluate_gym_change_candidate(c.id);
  select * into c from public.gym_change_candidates where id = target_id for update;
  if c.status <> 'auto_ready' then return; end if;
  select * into rule from public.gym_auto_rule_config where change_type = c.change_type;
  select * into g from public.gym_store_equipment
    where store_id = c.store_id and equipment_id = c.equipment_id for update;
  if not found or g.presence_status <> 'present' then reason := 'equipment_not_present'; end if;
  if reason is null and not exists (
    select 1 from public.gym_stores where id = c.store_id and active
  ) then reason := 'store_not_active'; end if;
  if reason is null and not exists (
    select 1 from public.equipment where id = c.equipment_id and not needs_review
  ) then reason := 'equipment_not_identified'; end if;
  if reason is null and g.source_kind in ('official', 'admin') and
    coalesce(g.checked_at, g.updated_at) >=
      now() - make_interval(days => rule.source_protection_days)
  then reason := 'protected_source'; end if;
  if reason is null and exists (
    select 1 from public.gym_change_candidates other
    where other.id <> c.id and other.store_id = c.store_id
      and other.equipment_id = c.equipment_id
      and other.status in ('collecting', 'needs_review', 'auto_ready')
      and other.unique_reporters > 0 and (
        (c.change_type = 'quantity_changed' and
          other.change_type = 'quantity_changed' and other.candidate_key <> c.candidate_key)
        or (c.change_type in ('temporarily_unavailable', 'available_again')
          and other.change_type in ('temporarily_unavailable', 'available_again')
          and other.candidate_key <> c.candidate_key)
        or other.change_type in ('added', 'removed')
      )
  ) then reason := 'conflicting_candidate'; end if;
  if reason is null and exists (
    select 1 from public.gym_auto_applications a
    where a.store_id = c.store_id and a.equipment_id = c.equipment_id
      and a.applied_at >= now() - make_interval(days => rule.cooldown_days)
      and (a.change_type = c.change_type or
        (c.change_type in ('temporarily_unavailable', 'available_again') and
          a.change_type in ('temporarily_unavailable', 'available_again')))
  ) then reason := 'state_change_cooldown'; end if;

  if reason is null and c.change_type = 'quantity_changed' then
    target_quantity := (c.proposed_value->>'reported_quantity')::integer;
    if target_quantity not between 1 and 100 then reason := 'invalid_quantity';
    elsif g.unavailable_quantity is not null and g.unavailable_quantity > target_quantity
    then reason := 'unavailable_count_exceeds_new_quantity';
    elsif g.quantity = target_quantity then reason := 'already_current'; end if;
  elsif reason is null and c.change_type = 'temporarily_unavailable' then
    if c.proposed_value->>'unavailable_scope' = 'all' then
      target_unavailable := g.quantity;
      target_available := false;
    elsif c.proposed_value->>'unavailable_scope' = 'partial' then
      target_unavailable := (c.proposed_value->>'reported_unavailable_quantity')::integer;
      if g.quantity is null or target_unavailable is null or
        target_unavailable < 1 or target_unavailable >= g.quantity
      then reason := 'invalid_partial_quantity'; end if;
      target_available := true;
    else reason := 'invalid_unavailable_scope'; end if;
    if reason is null and g.available = target_available and
      g.unavailable_quantity is not distinct from target_unavailable
    then reason := 'already_current'; end if;
  elsif reason is null then
    -- v1 recovery reports mean all units are available again.
    target_available := true;
    target_unavailable := case when g.quantity is null then null else 0 end;
    if g.available and (g.unavailable_quantity is null or g.unavailable_quantity = 0)
    then reason := 'already_current'; end if;
  end if;
  if reason is not null then
    update public.gym_change_candidates set
      status = case when reason = 'already_current' then 'superseded' else 'needs_review' end,
      resolved_at = case when reason = 'already_current' then now() else resolved_at end,
      updated_at = now() where id = c.id;
    insert into public.gym_auto_decisions
      (candidate_id, decision, reason_code, score_snapshot, rule_snapshot, algorithm_version)
    values (c.id, case when reason = 'already_current' then 'superseded' else 'needs_review' end,
      reason, jsonb_build_object('support_score', c.support_score,
        'oppose_score', c.oppose_score, 'unique_reporters', c.unique_reporters),
      to_jsonb(rule), c.algorithm_version);
    return;
  end if;

  perform set_config('setkeep.gym_candidate_id', c.id::text, true);
  perform set_config('setkeep.gym_application_id', application_id::text, true);
  if c.change_type = 'quantity_changed' then
    update public.gym_store_equipment set quantity = target_quantity,
      source_kind = 'confirmed_report', checked_at = now(), updated_at = now(),
      source = source || jsonb_build_object('auto_applied', true,
        'candidate_id', c.id, 'algorithm_version', c.algorithm_version)
    where store_id = c.store_id and equipment_id = c.equipment_id;
  else
    update public.gym_store_equipment set
      available = target_available, unavailable_quantity = target_unavailable,
      source_kind = 'confirmed_report', checked_at = now(), updated_at = now(),
      source = source || jsonb_build_object('auto_applied', true,
        'candidate_id', c.id, 'algorithm_version', c.algorithm_version)
    where store_id = c.store_id and equipment_id = c.equipment_id;
  end if;
  select * into after_row from public.gym_store_equipment
    where store_id = c.store_id and equipment_id = c.equipment_id;
  if not found or after_row.presence_status <> 'present' then
    raise exception 'Master update was blocked'; end if;
  insert into public.gym_auto_applications
    (id, candidate_id, store_id, equipment_id, change_type,
     before_data, after_data, application_type)
  values (application_id, c.id, c.store_id, c.equipment_id, c.change_type,
    to_jsonb(g), to_jsonb(after_row), 'auto');
  update public.gym_change_candidates set
    status = 'auto_applied', resolved_at = now(), updated_at = now() where id = c.id;
  insert into public.gym_auto_decisions
    (candidate_id, decision, reason_code, score_snapshot, rule_snapshot, algorithm_version)
  values (c.id, 'auto_applied', 'applied_to_master',
    jsonb_build_object('support_score', c.support_score,
      'oppose_score', c.oppose_score, 'unique_reporters', c.unique_reporters,
      'application_id', application_id), to_jsonb(rule), c.algorithm_version);
  update public.gym_equipment_reports r set status = 'applied',
    admin_note = '設備情報へ自動反映済み'
  from public.gym_change_evidence e
  where e.candidate_id = c.id and e.source_type = 'user_report'
    and e.source_ref = r.id::text and r.status in ('pending', 'reviewing');
  perform set_config('setkeep.gym_candidate_id', '', true);
  perform set_config('setkeep.gym_application_id', '', true);
end $$;
revoke all on function public.apply_gym_state_candidate(uuid) from public, anon, authenticated;

create function public.apply_gym_change_candidate(target_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare kind text;
begin
  select change_type into kind from public.gym_change_candidates where id = target_id;
  if kind in ('added', 'removed') then
    perform public.apply_gym_presence_candidate(target_id);
  elsif kind in ('quantity_changed', 'temporarily_unavailable', 'available_again') then
    perform public.apply_gym_state_candidate(target_id);
  end if;
end $$;
revoke all on function public.apply_gym_change_candidate(uuid) from public, anon, authenticated;
create or replace function public.auto_apply_ready_gym_candidate() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.apply_gym_change_candidate(new.id);
  return new;
end $$;

-- Keep current state visible in the admin Candidate list even before apply.
create or replace view public.admin_gym_change_candidates
with (security_invoker = true) as
  select c.*, concat_ws(' ', chain.name, store.name) as store_name,
    coalesce(e.display_name, e.name) as equipment_name,
    a.id as application_id, a.applied_at, a.before_data, a.after_data,
    a.rolled_back_at, a.rollback_reason,
    to_jsonb(g) as current_data
  from public.gym_change_candidates c
  join public.gym_stores store on store.id = c.store_id
  join public.gym_chains chain on chain.id = store.chain_id
  left join public.equipment e on e.id = c.equipment_id
  left join public.gym_auto_applications a on a.candidate_id = c.id
  left join public.gym_store_equipment g on g.store_id = c.store_id
    and g.equipment_id = c.equipment_id;

notify pgrst, 'reload schema';
commit;
