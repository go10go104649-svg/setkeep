-- Run against the linked schema. All fixtures / changes roll back.
begin;
create function pg_temp.assert_true(ok boolean, message text) returns void
language plpgsql as $$ begin
  if ok is distinct from true then raise exception '%', message; end if;
end $$;
create temporary table canonical_baseline as
select (select md5(jsonb_agg(to_jsonb(e) order by id)::text) from public.equipment e) equipment,
       (select md5(jsonb_agg(to_jsonb(m) order by equipment_id,exercise_id)::text) from public.equipment_exercise_mapping m) direct;
insert into public.gym_chains(id,name) values ('qa-canonical','QA canonical');
insert into public.gym_stores(id,chain_id,source_id,name) values
 ('qa-canonical-a','qa-canonical','a','QA A'),('qa-canonical-b','qa-canonical','b','QA B');
-- Reuse reviewed metadata, NOT the original direct mappings.
insert into public.equipment(id,name,normalized_name,category,load_type,manufacturer,model)
select 'qa-canonical-'||x.id,e.name,e.normalized_name,e.category,e.load_type,e.manufacturer,e.model
from (values ('dumbbell'),('flat_bench'),('incline_bench'),('barbell'),('rack')) x(id)
cross join lateral (
 select e.* from public.equipment_canonical_memberships m join public.equipment e on e.id=m.equipment_id
 where m.canonical_id=x.id
 -- A pure flat bench must not imply incline / decline.
 and (x.id<>'flat_bench' or e.name='フラットベンチ')
 order by e.id limit 1
) e;
select pg_temp.assert_true((select count(*)=5 from public.equipment where id like 'qa-canonical-%'), 'Fixture capabilities missing');
select pg_temp.assert_true(not exists(select 1 from public.equipment_canonical_memberships where equipment_id like 'qa-canonical-%'), 'New imports must NOT auto-approve');
select pg_temp.assert_true(exists(select 1 from public.equipment_canonical_candidates where equipment_id='qa-canonical-dumbbell'), 'Reviewed exact candidate not generated');
insert into public.equipment_canonical_mapping(equipment_id,canonical_id,matcher_id,review_basis)
select equipment_id,canonical_id,matcher_id,'QA approval' from public.equipment_canonical_candidates
where equipment_id like 'qa-canonical-%';
insert into public.gym_store_equipment(store_id,equipment_id,raw_name,quantity)
values ('qa-canonical-a','qa-canonical-dumbbell','ダンベル1～40kg',1),
 ('qa-canonical-b','qa-canonical-dumbbell','ダンベル1～50kg',2);
select pg_temp.assert_true(
 (select array_agg(exercise_id order by exercise_id) from public.gym_store_exercise_ids('qa-canonical-a')) =
 (select array_agg(exercise_id order by exercise_id) from public.gym_store_exercise_ids('qa-canonical-b')), 'Chain/store affects dumbbell knowledge');
select pg_temp.assert_true((select count(*)=15 from public.gym_store_exercise_ids('qa-canonical-a')), 'Dumbbell basics missing or bench exercises leaked');
select pg_temp.assert_true(not exists(select 1 from public.gym_store_exercise_ids('qa-canonical-a') where exercise_id in ('flat_dumbbell_press','incline_dumbbell_press','dumbbell_shoulder_press')), 'Bench-free false positive');
insert into public.gym_store_equipment(store_id,equipment_id,raw_name)
values ('qa-canonical-a','qa-canonical-flat_bench','フラットベンチ');
select pg_temp.assert_true(exists(select 1 from public.gym_store_exercise_ids('qa-canonical-a') where exercise_id='flat_dumbbell_press'), 'Flat combination not resolved');
select pg_temp.assert_true(not exists(select 1 from public.gym_store_exercise_ids('qa-canonical-a') where exercise_id in ('incline_dumbbell_press','decline_dumbbell_press')), 'Bench angle incorrectly inferred');
select pg_temp.assert_true(exists(select 1 from public.equipment_exercise_evidence(array['qa-canonical-dumbbell','qa-canonical-incline_bench']) where exercise_id='incline_dumbbell_press'), 'Private place evaluator differs');
select pg_temp.assert_true(not exists(select 1 from public.equipment_exercise_evidence(array['qa-canonical-rack','qa-canonical-flat_bench']) where exercise_id='bench_press'), 'Rack implied barbell');
select pg_temp.assert_true(exists(select 1 from public.equipment_exercise_evidence(array['qa-canonical-barbell','qa-canonical-rack','qa-canonical-flat_bench']) where exercise_id='bench_press'), 'Barbell/rack/bench not resolved');
select pg_temp.assert_true(not exists(
 select 1 from public.gym_store_exercise_evidence('qa-canonical-a') v,
 unnest(v.equipment_ids,v.equipment_names) x(id,name)
 join public.equipment e on e.id=x.id where x.name<>coalesce(e.display_name,e.name)
), 'Evidence names do not correspond to original equipment IDs');
insert into public.equipment_exercise_mapping(equipment_id,exercise_id,rationale)
values ('qa-canonical-dumbbell','dumbbell_curl','QA duplicate source'),
 ('qa-canonical-dumbbell','dumbbell_shoulder_press','Legacy broad direct mapping');
select pg_temp.assert_true(not exists(select 1 from public.gym_store_exercise_ids('qa-canonical-a') where exercise_id='dumbbell_shoulder_press'), 'Legacy dumbbell direct bypassed bench requirement');
select pg_temp.assert_true(exists(select 1 from public.equipment_exercise_evidence(array['qa-canonical-dumbbell','qa-canonical-incline_bench']) where exercise_id='dumbbell_shoulder_press'), 'Legacy dumbbell exercise lost with required bench');
select pg_temp.assert_true(not exists(
 select 1 from public.equipment_exercise_evidence(array['fit-place24:fp_eq_e2f3c2ba7ec7'])
 where exercise_id in ('dumbbell_shoulder_press','concentration_curl','one_arm_dumbbell_row','arnold_press','french_press','triceps_kickback')
), 'FIT PLACE old mapping bypassed bench requirements');
select pg_temp.assert_true((select count(*)=1 from public.gym_store_exercise_ids('qa-canonical-a') where exercise_id='dumbbell_curl'), 'Direct/canonical duplicate');
update public.gym_store_equipment set available=false where store_id='qa-canonical-a' and equipment_id='qa-canonical-dumbbell';
select pg_temp.assert_true(not exists(select 1 from public.gym_store_exercise_ids('qa-canonical-a')), 'Unavailable equipment used');
update public.gym_store_equipment set available=false,presence_status='removed' where store_id='qa-canonical-a' and equipment_id='qa-canonical-dumbbell';
select pg_temp.assert_true(not exists(select 1 from public.gym_store_exercise_ids('qa-canonical-a')), 'Removed equipment used');
update public.gym_store_equipment set available=true,presence_status='present',unavailable_quantity=1 where store_id='qa-canonical-a' and equipment_id='qa-canonical-dumbbell';
select pg_temp.assert_true(not exists(select 1 from public.gym_store_exercise_ids('qa-canonical-a')), 'Fully unavailable quantity used');
update public.equipment set load_type='plate_loaded_explicit' where id='qa-canonical-dumbbell';
select pg_temp.assert_true(not exists(select 1 from public.equipment_canonical_memberships where equipment_id='qa-canonical-dumbbell'), 'Changed loading metadata retains approval');
select pg_temp.assert_true(not exists(select 1 from public.equipment_canonical_memberships where equipment_id in ('anytime-fitness:anytime_eq_f90fabed6c45','anytime-fitness:anytime_eq_821f39b9c595')), 'Ambiguous Mabashi equipment guessed');
select pg_temp.assert_true(exists(select 1 from public.gym_store_exercise_ids('anytime-fitness:anytime_jp_1d4bdbb1432e') where exercise_id='dumbbell_curl'), 'Mabashi dumbbell missing');
select pg_temp.assert_true(exists(select 1 from public.gym_store_exercise_ids('anytime-fitness:anytime_jp_1d4bdbb1432e') where exercise_id='incline_dumbbell_press'), 'Mabashi adjustable bench combination missing');
select pg_temp.assert_true(exists(select 1 from public.equipment_resolved_exercise_mapping where equipment_id='golds-gym:fp_eq_e2f3c2ba7ec7' and exercise_id='dumbbell_curl'), 'Cross-chain reused Golds dumbbell missing');
-- The same public reference/RPC access as a normal app client.
set local role authenticated;
select pg_temp.assert_true(exists(select 1 from public.canonical_equipment), 'RLS reference select denied');
select pg_temp.assert_true(public.gym_store_detail('anytime-fitness:anytime_jp_1d4bdbb1432e')->'equipment' is not null, 'Detail under RLS failed');
select pg_temp.assert_true(exists(select 1 from public.gym_store_equipment_page('anytime-fitness:anytime_jp_1d4bdbb1432e',0)), 'Equipment pagination under RLS failed');
do $$ begin
 begin insert into public.canonical_equipment(id,name,review_basis) values('forbidden','forbidden','QA');
 raise exception 'User can change reference data'; exception when insufficient_privilege then null; end;
 begin update public.equipment_canonical_mapping set review_basis='forbidden';
 raise exception 'User can approve mappings'; exception when insufficient_privilege then null; end;
end $$;
reset role;
-- Assert every pre-existing original definition and direct mapping is intact.
select pg_temp.assert_true((select equipment from canonical_baseline)=(select md5(jsonb_agg(to_jsonb(e) order by id)::text) from public.equipment e where id not like 'qa-canonical-%'), 'Original equipment mutated');
select pg_temp.assert_true((select direct from canonical_baseline)=(select md5(jsonb_agg(to_jsonb(m) order by equipment_id,exercise_id)::text) from public.equipment_exercise_mapping m where equipment_id not like 'qa-canonical-%'), 'Original direct mappings mutated');
select 'canonical_equipment: all assertions passed' as result;
rollback;
