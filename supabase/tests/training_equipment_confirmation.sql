begin;
create function pg_temp.assert_true(ok boolean,msg text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception '%',msg;end if;end$$;
insert into auth.users(id) select ('00000000-0000-4000-9032-'||lpad(n::text,12,'0'))::uuid from generate_series(1,5)n;
insert into public.gym_chains(id,name) values('qa-training','QA');
insert into public.gym_stores(id,chain_id,source_id,name) values('qa-training','qa-training','qa','QA'),('qa-training-other','qa-training','qa-other','QA他店');
create function pg_temp.confirm(n int,k text default 'record-1',performed boolean default true) returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',('00000000-0000-4000-9032-'||lpad(n::text,12,'0')),true);
 perform public.confirm_training_equipment('qa-training','fit-place24:fp_eq_74ae16617af0','smith_bench_press',k,performed,auth.uid());
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-9032-000000000001',true);
select pg_temp.assert_true(public.training_equipment_options(null,array['smith_bench_press'])='[]','No-store options');
select pg_temp.assert_true(public.training_equipment_options('qa-training',array['custom:smith'])='[]','Unknown/custom name inferred');
select pg_temp.assert_true(jsonb_array_length(public.training_equipment_options('qa-training',array['preacher_curl']))=1,'Ambiguous group missing');
do $$begin
 begin perform public.confirm_training_equipment('qa-training','fit-place24:fp_eq_74ae16617af0','lateral_raise','record',true);raise exception 'Wrong equipment accepted';exception when raise_exception then if sqlerrm='Wrong equipment accepted' then raise;end if;end;
end$$;
select pg_temp.confirm(1);
select pg_temp.confirm(1);
select pg_temp.confirm(1,'record-2');
select pg_temp.assert_true(not exists(select 1 from public.gym_store_equipment where store_id='qa-training'),'One user confirmed equipment');
select pg_temp.assert_true((select count(*)=1 from public.gym_training_equipment_confirmations),'Duplicate receipt rows');
select pg_temp.confirm(1,'record-1',false);
select pg_temp.assert_true((select active from public.gym_training_equipment_confirmations),'Stale deletion withdrew new confirmation');
select pg_temp.confirm(1,'record-2',false);
select pg_temp.assert_true((select not active from public.gym_training_equipment_confirmations),'Edit/delete did not withdraw');
reset role;
select pg_temp.assert_true((select unique_reporters=0 and support_score=0 from public.gym_change_candidates where store_id='qa-training'),'Withdrawn confirmation counted');
set local role authenticated;
select pg_temp.confirm(1,'record-2',true);
select pg_temp.confirm(2);
select pg_temp.assert_true(not exists(select 1 from public.gym_store_equipment where store_id='qa-training'),'Two users prematurely applied');
select pg_temp.confirm(3);
select pg_temp.assert_true((select count(*)=1 from public.gym_store_equipment where store_id='qa-training'),'Three users did not apply exactly once');
select pg_temp.assert_true((select source_kind='confirmed_report' from public.gym_store_equipment where store_id='qa-training'),'Source provenance wrong');
select pg_temp.assert_true((public.training_equipment_options('qa-training',array['smith_bench_press'])->0->'options'->0->>'known')='true','Existing equipment still prompted');
select pg_temp.confirm(3,'record-2');
select pg_temp.confirm(3,'record-1',false);
select pg_temp.assert_true((select count(*)=1 from public.gym_store_equipment where store_id='qa-training'),'Deletion removed confirmed master');
select pg_temp.assert_true(not exists(select 1 from public.gym_store_equipment where store_id='qa-training-other'),'Other store mutated');
-- RLS: personal evidence is not a public store fact.
select pg_temp.assert_true((select count(*)=1 from public.gym_training_equipment_confirmations),'Other user receipts exposed');
do $$begin
 begin update public.gym_training_equipment_confirmations set active=true;raise exception 'Direct receipt write';exception when insufficient_privilege then null;end;
 begin perform public.confirm_training_equipment('qa-training','fit-place24:fp_eq_74ae16617af0','smith_bench_press','fake',true,'00000000-0000-4000-9032-000000000001');raise exception 'Account mismatch';exception when insufficient_privilege then null;end;
end$$;
reset role;
select pg_temp.assert_true((select count(*)=3 from public.gym_training_equipment_confirmations where store_id='qa-training'),'Receipts grew by history');
select pg_temp.assert_true((select count(*)=1 from public.gym_change_candidates where store_id='qa-training'),'Duplicate candidates');
select pg_temp.assert_true((select count(*)=3 from public.gym_change_evidence e join public.gym_change_candidates c on c.id=e.candidate_id where c.store_id='qa-training'),'Duplicate evidence votes');
select pg_temp.assert_true((select unique_reporters=3 and status='auto_applied' from public.gym_change_candidates where store_id='qa-training'),'Count or status wrong');
-- Expired support is ignored; expiry does not remove a confirmed inventory row.
update public.gym_change_evidence set observed_at=now()-interval '31 days' where candidate_id in(select id from public.gym_change_candidates where store_id='qa-training');
select pg_temp.assert_true((select v.reporters=0 from public.gym_change_candidates c cross join lateral public.gym_candidate_votes(c.id,30) v where c.store_id='qa-training'),'Expired evidence counted');
select pg_temp.assert_true((select count(*)=1 from public.gym_store_equipment where store_id='qa-training'),'Expiry removed inventory');
-- Reviewed canonical equivalence suppresses another chain's matching equipment.
insert into public.gym_store_equipment(store_id,equipment_id,raw_name) select 'qa-training-other',m.equipment_id,'既存スミス' from public.equipment_canonical_memberships m where m.canonical_id='smith' and m.equipment_id<>'fit-place24:fp_eq_74ae16617af0' limit 1;
select pg_temp.assert_true(public.training_equipment_present('qa-training-other','fit-place24:fp_eq_74ae16617af0'),'Canonical existing equipment was not recognized');
select pg_temp.assert_true(not exists(select 1 from public.gym_official_sources where enabled),'Official crawler enabled');
set local role anon;
do $$begin
 begin perform public.training_equipment_options('qa-training',array['smith_bench_press']);raise exception 'Anonymous options allowed';exception when insufficient_privilege then null;end;
 begin perform public.confirm_training_equipment('qa-training','fit-place24:fp_eq_74ae16617af0','smith_bench_press','fake',true);raise exception 'Anonymous confirmation allowed';exception when insufficient_privilege then null;end;
 begin perform count(*) from public.gym_training_equipment_confirmations;raise exception 'Anonymous receipts exposed';exception when insufficient_privilege then null;end;
end$$;
reset role;
select 'training confirmation aggregation, thresholds, privacy and withdrawal passed' result;
rollback;
