-- Existing official inventory is public without user votes. Acquisition stays
-- separate. No production rows are modified; isolated fixtures always roll back.
begin;
create function pg_temp.assert_true(ok boolean, message text) returns void
language plpgsql as $$ begin
  if ok is distinct from true then raise exception '%', message; end if;
end $$;
insert into public.gym_chains(id,name) values ('qa-publication','QA publication');
insert into public.gym_stores(id,chain_id,source_id,name,equipment_status)
values ('qa-publication-store','qa-publication','store','QA store','published'),
       ('qa-publication-empty','qa-publication','empty','QA not collected','not_collected');
insert into public.equipment(id,name,normalized_name,category,manufacturer,model)
values ('qa-publication-machine','QA machine','QA machine','筋トレ','QA maker','QA model'),
       ('qa-publication-bench','QA bench','QA bench','フリーウェイト',null,null),
       ('qa-publication-removed','QA removed','QA removed','筋トレ',null,null),
       ('qa-publication-unavailable','QA unavailable','QA unavailable','筋トレ',null,null),
       ('qa-publication-unmapped','QA unmapped','QA unmapped','その他',null,null);
insert into public.gym_store_equipment
 (store_id,equipment_id,raw_name,quantity,source_kind,checked_at,source_url,available,presence_status)
values
 ('qa-publication-store','qa-publication-machine','original machine',2,'official','2026-01-02Z','https://example.com/equipment',true,'present'),
 ('qa-publication-store','qa-publication-removed','original removed',null,'official',null,null,false,'removed'),
 ('qa-publication-store','qa-publication-unavailable','original unavailable',null,'official',null,null,false,'present'),
 ('qa-publication-store','qa-publication-unmapped','original unmapped',null,'official',null,null,true,'present');
insert into public.equipment_exercise_mapping(equipment_id,exercise_id,rationale)
values ('qa-publication-machine','chest_press','QA explicit mapping'),
       ('qa-publication-removed','seated_row','QA removed mapping'),
       ('qa-publication-unavailable','lat_pulldown','QA unavailable mapping');
insert into public.exercise_equipment_rules(id,exercise_id,rationale)
values ('qa-publication-rule','bench_press','QA explicit two-equipment rule');
insert into public.exercise_equipment_rule_items(rule_id,equipment_id)
values ('qa-publication-rule','qa-publication-machine'),('qa-publication-rule','qa-publication-bench');

set local role authenticated;
select pg_temp.assert_true(
 jsonb_array_length(public.gym_store_detail('qa-publication-store')->'equipment')=3,
 'Official equipment hidden without user reports, or removed row revived');
select pg_temp.assert_true(
 (select count(*)=3 from public.gym_store_equipment_page('qa-publication-store',0)),
 'Paginated inventory differs from detail');
select pg_temp.assert_true(
 (select array_agg(exercise_id order by exercise_id)=array['chest_press']
  from public.gym_store_exercise_ids('qa-publication-store')),
 'Official mapping missing, unknown inferred, removed/unavailable used, or incomplete combination used');
select pg_temp.assert_true(
 exists(select 1 from jsonb_array_elements(public.gym_store_detail('qa-publication-store')->'equipment') e
   where e->>'equipment_id'='qa-publication-machine' and e->>'source_kind'='official'
    and (e->>'checked_at')::timestamptz='2026-01-02Z'::timestamptz
    and e->>'source_url'='https://example.com/equipment' and e->>'quantity'='2'
    and e->'equipment'->>'manufacturer'='QA maker' and e->'equipment'->>'model'='QA model'),
 'Provenance, original date, quantity or equipment metadata changed');
select pg_temp.assert_true(
 public.gym_store_detail('qa-publication-empty')->'store'->>'equipment_status'='not_collected'
 and jsonb_array_length(public.gym_store_detail('qa-publication-empty')->'equipment')=0,
 'Uncollected status lost');
do $$ begin
 begin
  update public.gym_store_equipment set source_kind='confirmed_report'
   where store_id='qa-publication-store';
  raise exception 'User can rewrite inventory provenance';
 exception when insufficient_privilege then null; end;
end $$;
reset role;

insert into public.gym_store_equipment(store_id,equipment_id,raw_name,source_kind)
values ('qa-publication-store','qa-publication-bench','QA bench','official');
set local role authenticated;
select pg_temp.assert_true(exists(select 1 from public.gym_store_exercise_ids('qa-publication-store')
 where exercise_id='bench_press'), 'Complete combination not displayed');
reset role;
update public.gym_store_equipment set available=false,presence_status='removed'
 where store_id='qa-publication-store' and equipment_id='qa-publication-bench';
set local role authenticated;
select pg_temp.assert_true(not exists(select 1 from public.gym_store_exercise_ids('qa-publication-store')
 where exercise_id='bench_press'), 'Removed prerequisite still satisfies combination');
reset role;
rollback;
