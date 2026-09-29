-- Phase 3 integration test. Fixtures and Master changes are rolled back.
begin;
insert into auth.users(id)
select ('00000000-0000-4000-9003-' || lpad(n::text, 12, '0'))::uuid
from generate_series(1, 9) n;
insert into public.app_admins(user_id)
values ('00000000-0000-4000-9003-000000000009');
insert into public.gym_chains(id, name) values ('qa-state-chain', 'QA状態管理');
insert into public.gym_stores(id, chain_id, source_id, name)
select 'qa-state-' || name, 'qa-state-chain', name, 'QA' || name
from unnest(array['quantity', 'quantity-conflict', 'quantity-unsafe',
 'full', 'partial', 'recovery', 'removed', 'state-conflict', 'cooldown',
 'official']) name;
insert into public.equipment(id, name, normalized_name, category)
values ('qa-state-machine', 'QA状態マシン', 'qa状態マシン', 'マシン');
insert into public.equipment_exercise_mapping(equipment_id, exercise_id, rationale)
values ('qa-state-machine', 'qa-state-exercise', 'QA state evidence');
insert into public.gym_store_equipment
 (store_id, equipment_id, raw_name, quantity, unavailable_quantity,
  available, source_kind, checked_at)
select 'qa-state-' || name, 'qa-state-machine', 'QA状態マシン',
 case name when 'full' then 3 when 'partial' then 4 else 2 end,
 case name when 'quantity-unsafe' then 2 when 'recovery' then 2 else null end,
 name <> 'recovery',
 case name when 'official' then 'official' else 'confirmed_report' end,
 now() - case name when 'official' then interval '1 day' else interval '60 days' end
from unnest(array['quantity', 'quantity-conflict', 'quantity-unsafe',
 'full', 'partial', 'recovery', 'removed', 'state-conflict', 'cooldown',
 'official']) name;
update public.gym_store_equipment set presence_status = 'removed', available = false
where store_id = 'qa-state-removed';

set local role authenticated;
do $$ declare n integer; begin
  for n in 1..3 loop
    perform set_config('request.jwt.claim.sub',
      '00000000-0000-4000-9003-' || lpad(n::text, 12, '0'), true);
    insert into public.gym_equipment_reports
      (store_id, equipment_id, kind, reported_quantity)
    values ('qa-state-quantity', 'qa-state-machine', 'quantity_changed', 3);
  end loop;
end $$;
reset role;
do $$ declare c record; begin
  select * into c from public.gym_change_candidates
  where store_id = 'qa-state-quantity' and change_type = 'quantity_changed';
  if c.status <> 'auto_applied' or c.unique_reporters <> 3
    or (select quantity from public.gym_store_equipment
      where store_id = 'qa-state-quantity') <> 3 then
    raise exception 'Three quantity reports did not apply the new total'; end if;
  if (select count(*) from public.gym_equipment_reports
    where store_id = 'qa-state-quantity' and status = 'applied') <> 3 then
    raise exception 'Quantity supporting reports were not settled'; end if;
  perform public.apply_gym_change_candidate(c.id);
  if (select count(*) from public.gym_auto_applications where candidate_id = c.id) <> 1
    or (select count(*) from public.gym_equipment_changes where candidate_id = c.id) <> 1
  then raise exception 'Quantity application was duplicated'; end if;
end $$;

-- Different proposed totals must not merge or race to change the Master.
set local role authenticated;
do $$ declare n integer; begin
  for n in 4..5 loop
    perform set_config('request.jwt.claim.sub',
      '00000000-0000-4000-9003-' || lpad(n::text, 12, '0'), true);
    insert into public.gym_equipment_reports
      (store_id, equipment_id, kind, reported_quantity)
    values ('qa-state-quantity-conflict', 'qa-state-machine', 'quantity_changed', 4);
  end loop;
  for n in 1..3 loop
    perform set_config('request.jwt.claim.sub',
      '00000000-0000-4000-9003-' || lpad(n::text, 12, '0'), true);
    insert into public.gym_equipment_reports
      (store_id, equipment_id, kind, reported_quantity)
    values ('qa-state-quantity-conflict', 'qa-state-machine', 'quantity_changed', 3);
  end loop;
end $$;
reset role;
do $$ begin
  if (select quantity from public.gym_store_equipment
    where store_id = 'qa-state-quantity-conflict') <> 2 or
    (select count(*) from public.gym_change_candidates
      where store_id = 'qa-state-quantity-conflict') <> 2 or
    not exists(select 1 from public.gym_change_candidates
      where store_id = 'qa-state-quantity-conflict' and status = 'needs_review') then
    raise exception 'Conflicting quantities changed the Master'; end if;
end $$;

-- Never infer that two broken units became one broken unit after total shrinks.
set local role authenticated;
do $$ declare n integer; begin
  for n in 1..3 loop
    perform set_config('request.jwt.claim.sub',
      '00000000-0000-4000-9003-' || lpad(n::text, 12, '0'), true);
    insert into public.gym_equipment_reports
      (store_id, equipment_id, kind, reported_quantity)
    values ('qa-state-quantity-unsafe', 'qa-state-machine', 'quantity_changed', 1);
  end loop;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.gym_change_candidates
    where store_id = 'qa-state-quantity-unsafe' and status = 'needs_review')
    or not exists(select 1 from public.gym_store_equipment
      where store_id = 'qa-state-quantity-unsafe' and quantity = 2
        and unavailable_quantity = 2) then
    raise exception 'Unsafe quantity reduction was applied'; end if;
end $$;

set local role authenticated;
do $$ declare n integer; begin
  for n in 1..2 loop
    perform set_config('request.jwt.claim.sub',
      '00000000-0000-4000-9003-' || lpad(n::text, 12, '0'), true);
    insert into public.gym_equipment_reports
      (store_id, equipment_id, kind, unavailable_scope)
    values ('qa-state-full', 'qa-state-machine', 'temporarily_unavailable', 'all');
  end loop;
  for n in 3..4 loop
    perform set_config('request.jwt.claim.sub',
      '00000000-0000-4000-9003-' || lpad(n::text, 12, '0'), true);
    insert into public.gym_equipment_reports
      (store_id, equipment_id, kind, unavailable_scope, reported_unavailable_quantity)
    values ('qa-state-partial', 'qa-state-machine', 'temporarily_unavailable', 'partial', 1);
  end loop;
  for n in 1..2 loop
    perform set_config('request.jwt.claim.sub',
      '00000000-0000-4000-9003-' || lpad(n::text, 12, '0'), true);
    insert into public.gym_equipment_reports
      (store_id, equipment_id, kind)
    values ('qa-state-recovery', 'qa-state-machine', 'available_again');
  end loop;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.gym_store_equipment
    where store_id = 'qa-state-full' and presence_status = 'present'
      and not available and unavailable_quantity = 3) then
    raise exception 'Full temporary unavailability was not applied'; end if;
  if exists(select 1 from public.gym_store_exercise_ids('qa-state-full')
    where exercise_id = 'qa-state-exercise') then
    raise exception 'Unavailable equipment still grants an exercise'; end if;
  if not exists(select 1 from public.gym_store_equipment
    where store_id = 'qa-state-partial' and presence_status = 'present'
      and available and quantity = 4 and unavailable_quantity = 1) then
    raise exception 'Partial temporary unavailability was not applied'; end if;
  if not exists(select 1 from public.gym_store_exercise_ids('qa-state-partial')
    where exercise_id = 'qa-state-exercise') then
    raise exception 'Remaining available units no longer grant exercise'; end if;
  if not exists(select 1 from public.gym_store_equipment
    where store_id = 'qa-state-recovery' and presence_status = 'present'
      and available and unavailable_quantity = 0) then
    raise exception 'Full recovery was not applied'; end if;
end $$;

set local role authenticated;
do $$ declare n integer; begin
  for n in 3..4 loop
    perform set_config('request.jwt.claim.sub',
      '00000000-0000-4000-9003-' || lpad(n::text, 12, '0'), true);
    insert into public.gym_equipment_reports
      (store_id, equipment_id, kind)
    values ('qa-state-removed', 'qa-state-machine', 'available_again');
  end loop;
  perform set_config('request.jwt.claim.sub',
    '00000000-0000-4000-9003-000000000005', true);
  insert into public.gym_equipment_reports
    (store_id, equipment_id, kind)
  values ('qa-state-state-conflict', 'qa-state-machine', 'available_again');
  for n in 4..5 loop
    perform set_config('request.jwt.claim.sub',
      '00000000-0000-4000-9003-' || lpad(n::text, 12, '0'), true);
    insert into public.gym_equipment_reports
      (store_id, equipment_id, kind, unavailable_scope)
    values ('qa-state-state-conflict', 'qa-state-machine', 'temporarily_unavailable', 'all');
  end loop;
  perform set_config('request.jwt.claim.sub',
    '00000000-0000-4000-9003-000000000006', true);
  insert into public.gym_equipment_reports
    (store_id, equipment_id, kind)
  values ('qa-state-state-conflict', 'qa-state-machine', 'available_again');
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.gym_change_candidates
    where store_id = 'qa-state-removed' and status = 'needs_review') or
    not exists(select 1 from public.gym_store_equipment
      where store_id = 'qa-state-removed' and presence_status = 'removed'
        and not available) then
    raise exception 'Removed equipment was incorrectly recovered'; end if;
  if (select count(*) from public.gym_change_candidates
    where store_id = 'qa-state-state-conflict' and status = 'needs_review') <> 2
    or not exists(select 1 from public.gym_store_equipment
      where store_id = 'qa-state-state-conflict' and available) then
    raise exception 'Opposing availability reports auto-applied'; end if;
end $$;

set local role authenticated;
do $$ declare n integer; begin
  for n in 7..8 loop
    perform set_config('request.jwt.claim.sub',
      '00000000-0000-4000-9003-' || lpad(n::text, 12, '0'), true);
    insert into public.gym_equipment_reports
      (store_id, equipment_id, kind, unavailable_scope)
    values ('qa-state-cooldown', 'qa-state-machine', 'temporarily_unavailable', 'all');
  end loop;
  for n in 6..7 loop
    perform set_config('request.jwt.claim.sub',
      '00000000-0000-4000-9003-' || lpad(n::text, 12, '0'), true);
    insert into public.gym_equipment_reports
      (store_id, equipment_id, kind)
    values ('qa-state-cooldown', 'qa-state-machine', 'available_again');
  end loop;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.gym_change_candidates
    where store_id = 'qa-state-cooldown' and change_type = 'available_again'
      and status = 'needs_review') or
    not exists(select 1 from public.gym_store_equipment
      where store_id = 'qa-state-cooldown' and not available
        and presence_status = 'present') then
    raise exception 'State-change cooldown failed'; end if;
end $$;

set local role authenticated;
do $$ declare n integer; begin
  for n in 5..7 loop
    perform set_config('request.jwt.claim.sub',
      '00000000-0000-4000-9003-' || lpad(n::text, 12, '0'), true);
    insert into public.gym_equipment_reports
      (store_id, equipment_id, kind, reported_quantity)
    values ('qa-state-official', 'qa-state-machine', 'quantity_changed', 3);
  end loop;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.gym_change_candidates
    where store_id = 'qa-state-official' and status = 'needs_review') or
    not exists(select 1 from public.gym_store_equipment
      where store_id = 'qa-state-official' and quantity = 2
        and source_kind = 'official') then
    raise exception 'Recent official quantity was overwritten'; end if;
end $$;

-- Rollback all three kinds using the existing admin RPC and complete snapshots.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-9003-000000000001';
do $$ declare target_id uuid; begin
  select id into target_id from public.gym_change_candidates
  where store_id = 'qa-state-quantity' and change_type = 'quantity_changed';
  begin
    perform public.rollback_gym_change_candidate(target_id, 'unauthorized');
    raise exception 'Ordinary user rolled back quantity';
  exception when insufficient_privilege then null; end;
  begin
    update public.gym_auto_rule_config set min_unique_reporters = 1
    where change_type = 'quantity_changed';
    raise exception 'Ordinary user changed rule';
  exception when insufficient_privilege then null; end;
end $$;
set local request.jwt.claim.sub = '00000000-0000-4000-9003-000000000009';
do $$ declare target_id uuid; begin
  for target_id in select id from public.gym_change_candidates
    where store_id in ('qa-state-quantity', 'qa-state-full', 'qa-state-recovery')
      and status = 'auto_applied'
  loop
    perform public.rollback_gym_change_candidate(target_id, 'QAで元に戻す');
  end loop;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.gym_store_equipment
    where store_id = 'qa-state-quantity' and quantity = 2) or
    not exists(select 1 from public.gym_store_equipment
      where store_id = 'qa-state-full' and available and unavailable_quantity is null) or
    not exists(select 1 from public.gym_store_equipment
      where store_id = 'qa-state-recovery' and not available and unavailable_quantity = 2)
  then raise exception 'State-change rollback did not restore Master snapshots'; end if;
  if (select count(*) from public.gym_auto_applications
    where rolled_back_at is not null and rollback_reason = 'QAで元に戻す') <> 3
  then raise exception 'State-change rollback audit missing'; end if;
end $$;
rollback;
select 'equipment state reports, conflict, cooldown, rollback and RLS passed' as result;
