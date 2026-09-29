-- Every QA row and every Master update in this test is rolled back.
begin;
insert into auth.users(id) values
 ('00000000-0000-4000-9002-000000000001'),
 ('00000000-0000-4000-9002-000000000002'),
 ('00000000-0000-4000-9002-000000000003'),
 ('00000000-0000-4000-9002-000000000004'),
 ('00000000-0000-4000-9002-000000000005'),
 ('00000000-0000-4000-9002-000000000006'),
 ('00000000-0000-4000-9002-000000000007'),
 ('00000000-0000-4000-9002-000000000008'),
 ('00000000-0000-4000-9002-000000000009');
insert into public.app_admins(user_id)
values ('00000000-0000-4000-9002-000000000009');
insert into public.gym_chains(id, name) values ('qa-auto-chain', 'QA自動反映');
insert into public.gym_stores(id, chain_id, source_id, name) values
 ('qa-auto-added', 'qa-auto-chain', 'added', '追加店'),
 ('qa-auto-removed', 'qa-auto-chain', 'removed', '撤去店'),
 ('qa-auto-protected', 'qa-auto-chain', 'protected', '保護店'),
 ('qa-auto-old', 'qa-auto-chain', 'old', '旧確認店'),
 ('qa-auto-present', 'qa-auto-chain', 'present', '設置済店'),
 ('qa-auto-already-removed', 'qa-auto-chain', 'already-removed', '撤去済店');
insert into public.equipment(id, name, normalized_name, category) values
 ('qa-auto-rack', 'QA自動ラック', 'qa自動ラック', 'フリーウェイト'),
 ('qa-auto-machine', 'QA自動マシン', 'qa自動マシン', 'マシン');
insert into public.equipment_exercise_mapping(equipment_id, exercise_id, rationale)
values ('qa-auto-machine', 'qa-auto-exercise', 'QA direct mapping');
insert into public.gym_store_equipment
 (store_id, equipment_id, raw_name, source_kind, quantity, unavailable_quantity,
  checked_at, source) values
 ('qa-auto-removed', 'qa-auto-machine', 'QA自動マシン', 'confirmed_report',
  2, 1, now() - interval '45 days', '{"review":"original"}'),
 ('qa-auto-protected', 'qa-auto-machine', 'QA自動マシン', 'official',
  1, null, now() - interval '1 day', '{"review":"official"}'),
 ('qa-auto-old', 'qa-auto-machine', 'QA自動マシン', 'official',
  1, null, now() - interval '30 days', '{"review":"old official"}'),
 ('qa-auto-present', 'qa-auto-rack', 'QA自動ラック', 'confirmed_report',
  1, null, now(), '{}'),
 ('qa-auto-already-removed', 'qa-auto-machine', 'QA自動マシン', 'confirmed_report',
  1, null, now(), '{}');
update public.gym_store_equipment set presence_status = 'removed', available = false
where store_id = 'qa-auto-already-removed';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000001';
insert into public.gym_equipment_reports(store_id, kind, equipment_name)
values ('qa-auto-added', 'added', 'ＱＡ 自動ラック');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000002';
insert into public.gym_equipment_reports(store_id, kind, equipment_name)
values ('qa-auto-added', 'added', 'QA自動ラック');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000003';
insert into public.gym_equipment_reports(store_id, kind, equipment_name)
values ('qa-auto-added', 'added', 'QA自動ラック');

reset role;
do $$ declare c record; a record; begin
 select * into c from public.gym_change_candidates
 where store_id = 'qa-auto-added' and change_type = 'added';
 if c.status <> 'auto_applied' or c.unique_reporters <> 3 then
   raise exception 'Three independent added votes were not auto-applied'; end if;
 if not exists(select 1 from public.gym_store_equipment
   where store_id = 'qa-auto-added' and equipment_id = 'qa-auto-rack'
     and presence_status = 'present' and available
     and source_kind = 'confirmed_report') then
   raise exception 'Added Master row is missing'; end if;
 select * into a from public.gym_auto_applications where candidate_id = c.id;
 if a.before_data is not null or a.after_data->>'presence_status' <> 'present'
   or a.application_type <> 'auto' then
   raise exception 'Added application snapshot is wrong'; end if;
 if (select count(*) from public.gym_equipment_changes
   where candidate_id = c.id and application_id = a.id and operation = 'INSERT') <> 1 then
   raise exception 'Added Master audit is not linked'; end if;
 if (select count(*) from public.gym_equipment_reports
   where store_id = 'qa-auto-added' and status = 'applied') <> 3 then
   raise exception 'Supporting reports were not marked applied'; end if;
 perform public.apply_gym_change_candidate(c.id);
 if (select count(*) from public.gym_auto_applications where candidate_id = c.id) <> 1
   or (select count(*) from public.gym_equipment_changes where candidate_id = c.id) <> 1
 then raise exception 'Retry applied the same Candidate twice'; end if;
end $$;

-- Already-current Master state resolves a Candidate without a write/application.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000005';
insert into public.gym_equipment_reports(store_id, kind, equipment_name)
values ('qa-auto-present', 'added', 'QA自動ラック');
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-already-removed', 'qa-auto-machine', 'removed');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000006';
insert into public.gym_equipment_reports(store_id, kind, equipment_name)
values ('qa-auto-present', 'added', 'QA自動ラック');
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-already-removed', 'qa-auto-machine', 'removed');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000007';
insert into public.gym_equipment_reports(store_id, kind, equipment_name)
values ('qa-auto-present', 'added', 'QA自動ラック');
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-already-removed', 'qa-auto-machine', 'removed');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000008';
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-already-removed', 'qa-auto-machine', 'removed');
reset role;
do $$ begin
 if (select count(*) from public.gym_change_candidates
   where store_id in ('qa-auto-present', 'qa-auto-already-removed')
     and status = 'superseded') <> 2 then
   raise exception 'Already-current Candidates were not superseded'; end if;
 if exists(select 1 from public.gym_auto_applications
   where store_id in ('qa-auto-present', 'qa-auto-already-removed')) then
   raise exception 'Already-current Master generated an application'; end if;
end $$;

-- A reverse removal inside the cooldown window must not flip the Master.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000001';
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-added', 'qa-auto-rack', 'removed');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000002';
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-added', 'qa-auto-rack', 'removed');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000003';
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-added', 'qa-auto-rack', 'removed');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000004';
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-added', 'qa-auto-rack', 'removed');
reset role;
do $$ begin
 if not exists(select 1 from public.gym_change_candidates
   where store_id = 'qa-auto-added' and change_type = 'removed'
     and status = 'needs_review') then
   raise exception 'Reverse cooldown did not block removal'; end if;
 if not exists(select 1 from public.gym_store_equipment
   where store_id = 'qa-auto-added' and equipment_id = 'qa-auto-rack'
     and presence_status = 'present') then
   raise exception 'Reverse cooldown changed the Master'; end if;
end $$;

-- Four distinct reports remove a row from public views, not from the Master.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000001';
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-removed', 'qa-auto-machine', 'removed');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000002';
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-removed', 'qa-auto-machine', 'removed');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000003';
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-removed', 'qa-auto-machine', 'removed');
reset role;
do $$ begin
 if not exists(select 1 from public.gym_change_candidates
   where store_id = 'qa-auto-removed' and change_type = 'removed'
     and status = 'collecting' and unique_reporters = 3) then
   raise exception 'Three removed votes should remain collecting'; end if;
end $$;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000004';
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-removed', 'qa-auto-machine', 'removed');
reset role;
do $$ declare c record; a record; begin
 select * into c from public.gym_change_candidates
 where store_id = 'qa-auto-removed' and change_type = 'removed';
 if c.status <> 'auto_applied' then raise exception 'Removal was not applied'; end if;
 if not exists(select 1 from public.gym_store_equipment
   where store_id = 'qa-auto-removed' and equipment_id = 'qa-auto-machine'
     and presence_status = 'removed' and not available and quantity = 2) then
   raise exception 'Removal lost history or availability state'; end if;
 if exists(select 1 from public.gym_store_exercise_ids('qa-auto-removed')
   where exercise_id = 'qa-auto-exercise') then
   raise exception 'Removed equipment still grants an exercise'; end if;
 if jsonb_array_length(public.gym_store_detail('qa-auto-removed')->'equipment') <> 0 then
   raise exception 'Removed equipment remains in store details'; end if;
 select * into a from public.gym_auto_applications where candidate_id = c.id;
 if a.before_data->>'presence_status' <> 'present'
   or a.after_data->>'presence_status' <> 'removed' then
   raise exception 'Removal snapshots are wrong'; end if;
end $$;

-- Recent official information protects a row; stale official information can
-- be superseded only by the verified auto-apply path.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000001';
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-protected', 'qa-auto-machine', 'removed');
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-old', 'qa-auto-machine', 'removed');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000002';
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-protected', 'qa-auto-machine', 'removed');
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-old', 'qa-auto-machine', 'removed');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000003';
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-protected', 'qa-auto-machine', 'removed');
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-old', 'qa-auto-machine', 'removed');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000004';
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-protected', 'qa-auto-machine', 'removed');
insert into public.gym_equipment_reports(store_id, equipment_id, kind)
values ('qa-auto-old', 'qa-auto-machine', 'removed');
reset role;
do $$ begin
 if not exists(select 1 from public.gym_change_candidates
   where store_id = 'qa-auto-protected' and status = 'needs_review') or
   not exists(select 1 from public.gym_store_equipment
     where store_id = 'qa-auto-protected' and presence_status = 'present') then
   raise exception 'Recent official protection failed'; end if;
 if not exists(select 1 from public.gym_change_candidates
   where store_id = 'qa-auto-old' and status = 'auto_applied') or
   not exists(select 1 from public.gym_store_equipment
     where store_id = 'qa-auto-old' and presence_status = 'removed'
       and source_kind = 'confirmed_report') then
   raise exception 'Stale official information was never corrected'; end if;
 update public.gym_store_equipment set source_kind = 'confirmed_report',
   raw_name = 'unreviewed overwrite'
 where store_id = 'qa-auto-protected' and equipment_id = 'qa-auto-machine';
 if not exists(select 1 from public.gym_store_equipment
   where store_id = 'qa-auto-protected' and source_kind = 'official'
     and raw_name = 'QA自動マシン') then
   raise exception 'Ordinary lower-confidence source overwrote official data'; end if;
end $$;

-- After the opposite-direction cooldown expires, an added Candidate revives
-- the same removed row. Rolling it back restores the removed snapshot.
update public.gym_auto_applications set applied_at = now() - interval '8 days'
where store_id = 'qa-auto-old';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000005';
insert into public.gym_equipment_reports(store_id, kind, equipment_name)
values ('qa-auto-old', 'added', 'QA自動マシン');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000006';
insert into public.gym_equipment_reports(store_id, kind, equipment_name)
values ('qa-auto-old', 'added', 'QA自動マシン');
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000007';
insert into public.gym_equipment_reports(store_id, kind, equipment_name)
values ('qa-auto-old', 'added', 'QA自動マシン');
reset role;
do $$ declare c record; a record; begin
 select * into c from public.gym_change_candidates
 where store_id = 'qa-auto-old' and change_type = 'added';
 select * into a from public.gym_auto_applications where candidate_id = c.id;
 if c.status <> 'auto_applied' or a.before_data->>'presence_status' <> 'removed'
   or a.after_data->>'presence_status' <> 'present' or
   (select count(*) from public.gym_store_equipment where store_id = 'qa-auto-old') <> 1
 then raise exception 'Added report did not revive existing removed row'; end if;
end $$;

-- RLS and RPC authorization are distinct from a hidden Flutter button.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000001';
do $$ declare id_to_rollback uuid; begin
 select id into id_to_rollback from public.gym_change_candidates
 where store_id = 'qa-auto-removed' and change_type = 'removed';
 begin
   perform public.rollback_gym_change_candidate(id_to_rollback, 'unauthorized');
   raise exception 'Ordinary user rolled back a Candidate';
 exception when insufficient_privilege then null; end;
 begin
   perform public.apply_gym_change_candidate(id_to_rollback);
   raise exception 'Ordinary user executed internal apply function';
 exception when insufficient_privilege then null; end;
 begin
   update public.gym_store_equipment set available = true
   where store_id = 'qa-auto-removed';
   raise exception 'Ordinary user changed Master directly';
 exception when insufficient_privilege then null; end;
 begin
   insert into public.gym_auto_applications
     (candidate_id, store_id, equipment_id, change_type,
      after_data, application_type)
   values (gen_random_uuid(), 'qa-auto-removed', 'qa-auto-machine',
     'removed', '{}'::jsonb, 'auto');
   raise exception 'Ordinary user created application';
 exception when insufficient_privilege then null; end;
 if exists(select 1 from public.gym_auto_applications) then
   raise exception 'Ordinary user can read applications'; end if;
end $$;

set local request.jwt.claim.sub = '00000000-0000-4000-9002-000000000009';
do $$ declare added_id uuid; removed_id uuid; revived_id uuid; begin
 if not exists(select 1 from public.admin_gym_change_candidates
   where store_id = 'qa-auto-removed' and status = 'auto_applied'
     and applied_at is not null and before_data is not null
     and after_data->>'presence_status' = 'removed') then
   raise exception 'Admin view lacks application snapshots'; end if;
 select id into added_id from public.gym_change_candidates
 where store_id = 'qa-auto-added' and change_type = 'added';
 select id into removed_id from public.gym_change_candidates
 where store_id = 'qa-auto-removed' and change_type = 'removed';
 select id into revived_id from public.gym_change_candidates
 where store_id = 'qa-auto-old' and change_type = 'added';
 begin
   perform public.rollback_gym_change_candidate(added_id, '  ');
   raise exception 'Blank rollback reason was accepted';
 exception when raise_exception then
   if sqlerrm = 'Blank rollback reason was accepted' then raise; end if;
 end;
 perform public.rollback_gym_change_candidate(added_id, '誤登録を確認');
 perform public.rollback_gym_change_candidate(removed_id, '撤去報告を訂正');
 perform public.rollback_gym_change_candidate(revived_id, '再導入報告を訂正');
end $$;
reset role;
do $$ begin
 if exists(select 1 from public.gym_store_equipment
   where store_id = 'qa-auto-added' and equipment_id = 'qa-auto-rack') then
   raise exception 'Added rollback did not remove newly created row'; end if;
 if not exists(select 1 from public.gym_store_equipment
   where store_id = 'qa-auto-removed' and equipment_id = 'qa-auto-machine'
     and presence_status = 'present' and available and quantity = 2
     and unavailable_quantity = 1 and source_kind = 'confirmed_report'
     and source = '{"review":"original"}'::jsonb) then
   raise exception 'Removed rollback failed to restore original row'; end if;
 if (select count(*) from public.gym_auto_applications
   where rolled_back_at is not null and rollback_reason <> '') <> 3 then
   raise exception 'Rollback audit missing'; end if;
 if (select count(*) from public.gym_change_candidates
   where status = 'rolled_back') <> 3 then
   raise exception 'Rollback did not close Candidates'; end if;
 if not exists(select 1 from public.gym_store_equipment
   where store_id = 'qa-auto-old' and presence_status = 'removed'
     and not available and source_kind = 'confirmed_report') then
   raise exception 'Revival rollback did not restore removed row'; end if;
 if (select count(*) from public.gym_equipment_changes
   where candidate_id is not null and operation = 'DELETE') <> 1 then
   raise exception 'Rollback audit did not link the deletion'; end if;
end $$;
rollback;
select 'auto apply, protection, cooldown, rollback, RLS and public views passed' as result;
