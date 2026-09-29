begin;

-- Presence is distinct from temporary availability. Existing inventory is present.
alter table public.gym_store_equipment
  add column presence_status text not null default 'present'
  check (presence_status in ('present', 'removed'));
alter table public.gym_store_equipment
  add constraint gym_removed_not_available
  check (presence_status <> 'removed' or not available);
create index gym_current_store_equipment on public.gym_store_equipment(store_id)
  where presence_status = 'present';

create table public.gym_auto_applications (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null unique references public.gym_change_candidates(id),
  store_id text not null references public.gym_stores(id),
  equipment_id text not null references public.equipment(id),
  change_type text not null check (change_type in ('added', 'removed')),
  before_data jsonb,
  after_data jsonb not null,
  application_type text not null check (application_type in ('auto', 'admin')),
  applied_at timestamptz not null default now(),
  rolled_back_at timestamptz,
  rollback_reason text check (rollback_reason is null or length(trim(rollback_reason)) > 0),
  rolled_back_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index gym_applications_equipment_time
  on public.gym_auto_applications(store_id, equipment_id, applied_at desc);
alter table public.gym_auto_applications enable row level security;
revoke all on public.gym_auto_applications from anon, authenticated;
grant select on public.gym_auto_applications to authenticated;
create policy gym_applications_admin_read on public.gym_auto_applications
  for select to authenticated using (public.is_report_admin());

-- Keep the original audit log, and identify the exact Candidate/application.
alter table public.gym_equipment_changes
  add column candidate_id uuid references public.gym_change_candidates(id),
  add column application_id uuid;
create or replace function public.record_gym_equipment_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and to_jsonb(old) = to_jsonb(new) then return new; end if;
  insert into public.gym_equipment_changes
    (store_id, equipment_id, operation, before_data, after_data,
     candidate_id, application_id)
  values (
    coalesce(new.store_id, old.store_id),
    coalesce(new.equipment_id, old.equipment_id),
    tg_op,
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end,
    nullif(current_setting('setkeep.gym_candidate_id', true), '')::uuid,
    nullif(current_setting('setkeep.gym_application_id', true), '')::uuid
  );
  return coalesce(new, old);
end $$;

-- An ordinary lower-confidence update remains blocked. Only the locked,
-- SECURITY DEFINER auto-apply/rollback path sets this transaction-local marker.
create or replace function public.protect_gym_equipment_source() returns trigger
language plpgsql set search_path = '' as $$
declare
  ranks text[] := array['unconfirmed_report','confirmed_report','official','admin'];
  marked_id uuid := nullif(current_setting('setkeep.gym_candidate_id', true), '')::uuid;
begin
  if array_position(ranks, new.source_kind) < array_position(ranks, old.source_kind) then
    if current_user = 'postgres' and marked_id is not null and exists (
      select 1 from public.gym_change_candidates c
      where c.id = marked_id and c.store_id = new.store_id
        and c.equipment_id = new.equipment_id
        and c.status in ('auto_ready', 'auto_applied')
    ) then return new; end if;
    return old;
  end if;
  return new;
end $$;

-- A report may be marked applied by the internal Candidate transaction.
-- Client-side transitions retain the existing admin-only guard.
create or replace function public.review_report_guard() returns trigger
language plpgsql set search_path = '' as $$
declare marked_id uuid := nullif(current_setting('setkeep.gym_candidate_id', true), '')::uuid;
begin
  if tg_table_name = 'gym_equipment_reports'
    and current_user = 'postgres' and marked_id is not null
    and old.status in ('pending', 'reviewing') and new.status = 'applied'
    and exists (
      select 1 from public.gym_change_candidates c
      join public.gym_change_evidence e on e.candidate_id = c.id
      where c.id = marked_id and c.status = 'auto_applied'
        and e.source_type = 'user_report' and e.source_ref = old.id::text
    )
  then
    new.reviewed_by = null;
    new.reviewed_at = now();
    return new;
  end if;
  if not public.is_report_admin() then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  if new.status <> old.status and not (
    (old.status = 'pending' and new.status in ('reviewing', 'rejected'))
    or (old.status = 'reviewing' and new.status in ('applied', 'rejected'))
  ) then raise exception 'Invalid report transition'; end if;
  if new.status = 'rejected' and length(trim(new.admin_note)) = 0 then
    raise exception 'Rejection note required';
  end if;
  new.reviewed_by = auth.uid();
  new.reviewed_at = now();
  return new;
end $$;

-- Both direct mappings and combinations must ignore removed inventory.
create or replace function public.gym_store_exercise_evidence(target_store_id text)
returns table(exercise_id text, equipment_ids text[], equipment_names text[], rule_id text)
language sql stable security invoker set search_path = '' as $$
  select * from public.equipment_exercise_evidence(array(
    select g.equipment_id from public.gym_store_equipment g
    where g.store_id = target_store_id and g.presence_status = 'present'
      and g.available
      and (g.quantity is null or g.quantity - coalesce(g.unavailable_quantity, 0) > 0)
  ));
$$;
create or replace function public.gym_store_detail(target_store_id text) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'store', (select to_jsonb(s) || jsonb_build_object('chain_name', c.name)
      from public.gym_stores s join public.gym_chains c on c.id = s.chain_id
      where s.id = target_store_id),
    'equipment', coalesce((select jsonb_agg(to_jsonb(g) || jsonb_build_object(
      'equipment', to_jsonb(e) || jsonb_build_object(
        'equipment_exercise_mapping', coalesce((select jsonb_agg(jsonb_build_object('exercise_id', m.exercise_id))
          from public.equipment_exercise_mapping m where m.equipment_id = e.id), '[]'::jsonb),
        'exercise_equipment_rule_items', coalesce((select jsonb_agg(jsonb_build_object('rule_id', i.rule_id))
          from public.exercise_equipment_rule_items i where i.equipment_id = e.id), '[]'::jsonb)
      )) order by e.category, e.name, e.id)
      from public.gym_store_equipment g join public.equipment e on e.id = g.equipment_id
      where g.store_id = target_store_id and g.presence_status = 'present'), '[]'::jsonb),
    'evidence', coalesce((select jsonb_agg(to_jsonb(x))
      from public.gym_store_exercise_evidence(target_store_id) x), '[]'::jsonb)
  );
$$;

-- Trigger-only entry point. It runs in the report transaction: any failure
-- rolls back the report, Candidate, Master and audit writes together.
create function public.apply_gym_change_candidate(target_id uuid) returns void
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
    if exact_matches <> 1 then reason := 'equipment_not_identified'; end if;
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
revoke all on function public.apply_gym_change_candidate(uuid) from public, anon, authenticated;

create function public.auto_apply_ready_gym_candidate() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.apply_gym_change_candidate(new.id);
  return new;
end $$;
revoke all on function public.auto_apply_ready_gym_candidate() from public, anon, authenticated;
create trigger gym_candidate_auto_apply after update of status on public.gym_change_candidates
  for each row when (new.status = 'auto_ready' and old.status is distinct from new.status)
  execute function public.auto_apply_ready_gym_candidate();

create function public.rollback_gym_change_candidate(target_id uuid, reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  c public.gym_change_candidates%rowtype;
  a public.gym_auto_applications%rowtype;
  current_row public.gym_store_equipment%rowtype;
  original public.gym_store_equipment%rowtype;
begin
  if not public.is_report_admin() then
    raise exception 'Administrator required' using errcode = '42501';
  end if;
  if nullif(trim(reason), '') is null then raise exception 'Rollback reason required'; end if;
  select * into c from public.gym_change_candidates where id = target_id for update;
  if not found or c.status <> 'auto_applied' then
    raise exception 'Candidate is not auto-applied';
  end if;
  select * into a from public.gym_auto_applications
    where candidate_id = target_id for update;
  if not found or a.rolled_back_at is not null then
    raise exception 'Application is already rolled back';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(a.store_id || ':' || a.equipment_id, 422));
  select * into current_row from public.gym_store_equipment
    where store_id = a.store_id and equipment_id = a.equipment_id for update;
  if not found or to_jsonb(current_row) <> a.after_data then
    raise exception 'Master changed since application; review manually';
  end if;
  perform set_config('setkeep.gym_candidate_id', c.id::text, true);
  perform set_config('setkeep.gym_application_id', a.id::text, true);
  if a.before_data is null then
    delete from public.gym_store_equipment
      where store_id = a.store_id and equipment_id = a.equipment_id;
  else
    select * into original from jsonb_populate_record(
      null::public.gym_store_equipment, a.before_data);
    update public.gym_store_equipment set
      quantity = original.quantity, available = original.available,
      raw_name = original.raw_name, source_url = original.source_url,
      checked_at = original.checked_at, source = original.source,
      updated_at = original.updated_at,
      unavailable_quantity = original.unavailable_quantity,
      source_kind = original.source_kind,
      presence_status = original.presence_status
    where store_id = a.store_id and equipment_id = a.equipment_id;
    select * into current_row from public.gym_store_equipment
      where store_id = a.store_id and equipment_id = a.equipment_id;
    if to_jsonb(current_row) <> a.before_data then
      raise exception 'Rollback did not restore the original Master row';
    end if;
  end if;
  update public.gym_auto_applications set
    rolled_back_at = now(), rollback_reason = trim(reason),
    rolled_back_by = auth.uid() where id = a.id;
  update public.gym_change_candidates set
    status = 'rolled_back', resolved_at = coalesce(resolved_at, now()),
    updated_at = now() where id = c.id;
  insert into public.gym_auto_decisions
    (candidate_id, decision, reason_code, score_snapshot, rule_snapshot, algorithm_version)
  values (c.id, 'rolled_back', 'admin_rollback',
    jsonb_build_object('application_id', a.id, 'rollback_reason', trim(reason)),
    (select to_jsonb(r) from public.gym_auto_rule_config r where r.change_type = c.change_type),
    c.algorithm_version);
  perform set_config('setkeep.gym_candidate_id', '', true);
  perform set_config('setkeep.gym_application_id', '', true);
end $$;
revoke all on function public.rollback_gym_change_candidate(uuid, text) from public, anon;
grant execute on function public.rollback_gym_change_candidate(uuid, text) to authenticated;

-- Preserve the existing admin view's column order; append application data.
create or replace view public.admin_gym_change_candidates
with (security_invoker = true) as
  select c.*, concat_ws(' ', chain.name, store.name) as store_name,
    coalesce(e.display_name, e.name) as equipment_name,
    a.id as application_id, a.applied_at, a.before_data, a.after_data,
    a.rolled_back_at, a.rollback_reason
  from public.gym_change_candidates c
  join public.gym_stores store on store.id = c.store_id
  join public.gym_chains chain on chain.id = store.chain_id
  left join public.equipment e on e.id = c.equipment_id
  left join public.gym_auto_applications a on a.candidate_id = c.id;

notify pgrst, 'reload schema';
commit;
