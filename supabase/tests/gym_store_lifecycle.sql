begin;
create function pg_temp.assert_true(ok boolean,msg text) returns void language plpgsql as $$ begin
 if ok is distinct from true then raise exception '%',msg;end if;end $$;
insert into auth.users(id) select ('00000000-0000-4000-9028-'||lpad(n::text,12,'0'))::uuid from generate_series(1,32)n;
insert into public.app_admins(user_id) values('00000000-0000-4000-9028-000000000012');
insert into public.gym_chains(id,name) values('qa-store-chain','QA店舗チェーン');
insert into public.gym_stores(id,chain_id,source_id,name,address,official_url)
select 'qa-store-'||n,'qa-store-chain',n,n,'QA住所'||n,'https://example.com/'||n
from unnest(array['close','reopen','permanent','official','relocation','expired','conflict','rollback-conflict','duplicate','active-reopen'])n;
insert into public.gym_stores(id,chain_id,source_id,name,source)
values('qa-store-pre','qa-store-chain','pre','開業前','{"page_status":"preopening_text"}');
update public.gym_stores set operational_status='temporarily_closed',status_checked_at=now()-interval '30 days' where id='qa-store-reopen';
update public.gym_stores set status_source_kind='official',status_checked_at=now(),status_source_url='https://example.com/verified' where id='qa-store-official';
insert into public.user_gym_stores(user_id,store_id) values('00000000-0000-4000-9028-000000000001','qa-store-permanent');
insert into public.equipment(id,name,normalized_name,category) values('qa-store-equipment','QA設備','QA設備','マシン');
insert into public.gym_store_equipment(store_id,equipment_id,raw_name) values('qa-store-permanent','qa-store-equipment','QA設備');
create function pg_temp.report(user_number int,store text,kind text,proposal_name text default null,proposal_address text default null) returns void
language plpgsql as $$ begin
 perform set_config('request.jwt.claim.sub',('00000000-0000-4000-9028-'||lpad(user_number::text,12,'0')),true);
 insert into public.gym_store_reports(store_id,chain_id,kind,reported_name,reported_address,comment)
 values(store,'qa-store-chain',kind,proposal_name,proposal_address,'QA報告');
end $$;
set local role authenticated;
select pg_temp.report(1,'qa-store-close','temporarily_closed');
select pg_temp.report(2,'qa-store-close','temporarily_closed');
select pg_temp.assert_true((select operational_status='active' from public.gym_stores where id='qa-store-close'),'Two reports must not close');
select pg_temp.report(3,'qa-store-close','temporarily_closed');
select pg_temp.assert_true((select operational_status='temporarily_closed' and active from public.gym_stores where id='qa-store-close'),'Three reports did not temporarily close');
select pg_temp.assert_true(exists(select 1 from public.search_gym_stores_v2('close',0,'qa-store-chain') x where x->>'id'='qa-store-close'),'Temporary closure hidden from search');
select pg_temp.report(4,'qa-store-close','reopened');select pg_temp.report(5,'qa-store-close','reopened');
select pg_temp.assert_true((select operational_status='temporarily_closed' from public.gym_stores where id='qa-store-close'),'Cooldown failed');
select pg_temp.report(6,'qa-store-reopen','reopened');select pg_temp.report(7,'qa-store-reopen','reopened');
select pg_temp.assert_true((select operational_status='active' from public.gym_stores where id='qa-store-reopen'),'Reopening failed');
select pg_temp.report(1,'qa-store-active-reopen','reopened');
select pg_temp.report(1,'qa-store-permanent','closed');select pg_temp.report(2,'qa-store-permanent','closed');
select pg_temp.report(3,'qa-store-permanent','closed');select pg_temp.report(4,'qa-store-permanent','closed');
select pg_temp.assert_true((select operational_status='active' from public.gym_stores where id='qa-store-permanent'),'Users permanently closed a store');
select pg_temp.report(6,'qa-store-official','temporarily_closed');select pg_temp.report(7,'qa-store-official','temporarily_closed');select pg_temp.report(8,'qa-store-official','temporarily_closed');
select pg_temp.assert_true((select operational_status='active' from public.gym_stores where id='qa-store-official'),'Official source protection failed');
select pg_temp.report(6,'qa-store-relocation','relocated',null,'別住所');
select pg_temp.assert_true((select address='QA住所relocation' from public.gym_stores where id='qa-store-relocation'),'Relocation changed master');
select pg_temp.report(8,null,'new_store',' New  Store ','新住所１－２');
select pg_temp.report(9,null,'new_store','newstore','新住所1-2');
select pg_temp.report(10,null,'new_store','duplicate','QA住所duplicate');
select pg_temp.assert_true(not exists(select 1 from public.gym_stores where name='newstore'),'new_store automatically inserted');
select pg_temp.report(9,'qa-store-duplicate','temporarily_closed');
do $$ begin
 for i in 1..10 loop
 begin perform pg_temp.report(9,'qa-store-duplicate','temporarily_closed');raise exception 'Duplicate accepted';
 exception when raise_exception then if sqlerrm='Duplicate accepted' then raise;end if;end;
 end loop;
end $$;
-- Conflicting recent observations must block an otherwise sufficient vote.
select pg_temp.report(13,'qa-store-conflict','closed');
select pg_temp.report(14,'qa-store-conflict','temporarily_closed');
select pg_temp.report(15,'qa-store-conflict','temporarily_closed');
select pg_temp.report(16,'qa-store-conflict','temporarily_closed');
select pg_temp.assert_true((select operational_status='active' from public.gym_stores where id='qa-store-conflict'),'Conflicting evidence ignored');
-- No new registrations at an unavailable store; existing registrations survive.
do $$ begin
 begin insert into public.user_gym_stores(user_id,store_id) values(auth.uid(),'qa-store-close');raise exception 'Unavailable store registered';
 exception when raise_exception then if sqlerrm='Unavailable store registered' then raise;end if;end;
 begin insert into public.gym_store_reports(kind,reported_name,reported_address) values('new_store','No chain','Address');raise exception 'Invalid new store accepted';exception when check_violation then null;end;
end $$;
-- Ordinary users have no candidate/evidence/master mutation or other reports access.
select pg_temp.assert_true(not exists(select 1 from public.gym_change_candidates),'Candidate RLS leak');
select pg_temp.assert_true(not exists(select 1 from public.gym_store_reports),'Reports RLS leak');
do $$ begin
 begin update public.gym_stores set operational_status='closed' where id='qa-store-close';raise exception 'Master writable';exception when insufficient_privilege then null;end;
 begin insert into public.gym_change_evidence(candidate_id,source_type,direction,weight,observed_at) values(gen_random_uuid(),'admin','support',100,now());raise exception 'Evidence writable';exception when insufficient_privilege then null;end;
 begin perform public.review_gym_store_candidate(gen_random_uuid(),'apply','hack');raise exception 'Admin RPC unguarded';exception when insufficient_privilege then null;end;
 begin insert into public.gym_store_reports(user_id,store_id,kind) values('00000000-0000-4000-9028-000000000001','qa-store-close','closed');raise exception 'Spoof user';exception when insufficient_privilege then null;end;
end $$;
reset role;
select pg_temp.assert_true((select status='auto_applied' from public.gym_change_candidates where store_id='qa-store-close' and change_type='store_temporarily_closed'),'Not auto applied');
select pg_temp.assert_true((select status='superseded' from public.gym_change_candidates where store_id='qa-store-active-reopen'),'Active reopening not superseded');
select pg_temp.assert_true((select unique_reporters=1 from public.gym_change_candidates where store_id='qa-store-duplicate'),'Vote inflation');
select pg_temp.assert_true((select count(*)=1 from public.gym_change_candidates where entity_type='store' and change_type='store_new_store' and proposed_value->>'address'='新住所１－２'),'Normalized new store reports split');
select pg_temp.assert_true((select unique_reporters=2 and status='needs_review' from public.gym_change_candidates where entity_type='store' and change_type='store_new_store' and proposed_value->>'address'='新住所１－２'),'New store aggregation failed');
select pg_temp.assert_true(exists(select 1 from public.gym_change_candidates where change_type='store_new_store' and proposed_value->'possible_existing_store_ids' @> '["qa-store-duplicate"]'),'Existing-store suggestion missing');
select pg_temp.assert_true((select operational_status='preopening' and active from public.gym_stores where id='qa-store-pre'),'Preopening regression');
select pg_temp.assert_true(exists(select 1 from public.search_gym_stores_v2('',0,'qa-store-chain') x where x->>'id'='qa-store-pre'),'Preopening not searchable');
select pg_temp.assert_true(exists(select 1 from public.gym_auto_decisions d join public.gym_change_candidates c on c.id=d.candidate_id where c.store_id='qa-store-close' and reason_code='cooldown'),'Cooldown not recorded');
select pg_temp.assert_true(exists(select 1 from public.gym_auto_decisions d join public.gym_change_candidates c on c.id=d.candidate_id where c.store_id='qa-store-official' and reason_code='protected_source'),'Protection not recorded');
select pg_temp.assert_true(exists(select 1 from public.gym_auto_decisions d join public.gym_change_candidates c on c.id=d.candidate_id where c.store_id='qa-store-conflict' and reason_code='conflicting_evidence'),'Conflict not recorded');
-- Old votes expire, remain in evidence, and do not combine with a fresh vote.
select pg_temp.report(17,'qa-store-expired','temporarily_closed');
select pg_temp.report(18,'qa-store-expired','temporarily_closed');
update public.gym_change_evidence set observed_at=now()-interval '20 days' where candidate_id in(select id from public.gym_change_candidates where store_id='qa-store-expired');
select pg_temp.report(19,'qa-store-expired','temporarily_closed');
select pg_temp.assert_true((select unique_reporters=1 and support_score=1 from public.gym_change_candidates where store_id='qa-store-expired'),'Stale votes counted');
select pg_temp.assert_true((select count(*)=3 from public.gym_change_evidence e join public.gym_change_candidates c on c.id=e.candidate_id where c.store_id='qa-store-expired'),'Evidence was deleted');
-- Expired evidence never restores a closed/temporarily closed store.
update public.gym_change_evidence set observed_at=now()-interval '20 days' where candidate_id in(select id from public.gym_change_candidates where store_id='qa-store-close');
select public.reevaluate_gym_change_candidate(id) from public.gym_change_candidates where store_id='qa-store-close';
select pg_temp.assert_true((select operational_status='temporarily_closed' from public.gym_stores where id='qa-store-close'),'Expiry reopened master');
-- Admin manual permanent closure and exact rollback, without losing registrations/inventory.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-9028-000000000012',true);
select pg_temp.assert_true(exists(select 1 from public.admin_gym_change_candidates where store_id is null and store_name like '%New  Store%'),'Admin new-store name/join missing');
do $$ declare target uuid;begin
 select id into target from public.gym_change_candidates where store_id='qa-store-permanent';
 begin perform public.review_gym_store_candidate(target,'reject','');raise exception 'Empty rejection reason accepted';
 exception when raise_exception then if sqlerrm='Empty rejection reason accepted' then raise;end if;end;
end $$;
select public.review_gym_store_candidate(id,'reviewing','調査中') from public.gym_change_candidates where store_id='qa-store-permanent';
select public.review_gym_store_candidate(id,'apply','公式閉店案内を確認') from public.gym_change_candidates where store_id='qa-store-permanent';
select pg_temp.assert_true((select operational_status='closed' and not active from public.gym_stores where id='qa-store-permanent'),'Admin closure failed');
select pg_temp.assert_true(not exists(select 1 from public.search_gym_stores_v2('permanent',0,'qa-store-chain')),'Closed store in search');
select pg_temp.report(11,'qa-store-permanent','reopened');
select pg_temp.assert_true((select operational_status='closed' from public.gym_stores where id='qa-store-permanent'),'Closed store auto-reopened');
select set_config('request.jwt.claim.sub','00000000-0000-4000-9028-000000000012',true);
select public.rollback_gym_change_candidate(id,'閉店情報を再確認して訂正') from public.gym_change_candidates where store_id='qa-store-permanent' and status='admin_applied';
select pg_temp.assert_true((select operational_status='active' and active from public.gym_stores where id='qa-store-permanent'),'Closure rollback failed');
select public.rollback_gym_change_candidate(id,'休業報告の誤り') from public.gym_change_candidates where store_id='qa-store-close' and status='auto_applied';
select pg_temp.assert_true((select operational_status='active' from public.gym_stores where id='qa-store-close'),'Temporary rollback failed');
select public.review_gym_store_candidate(id,'reject','所在地を確認できない') from public.gym_change_candidates where change_type='store_new_store';
reset role;
select pg_temp.assert_true(exists(select 1 from public.user_gym_stores where store_id='qa-store-permanent'),'Registration deleted');
select pg_temp.assert_true(exists(select 1 from public.gym_store_equipment where store_id='qa-store-permanent'),'Equipment deleted');
select pg_temp.assert_true((select count(*)>=5 from public.gym_store_changes where candidate_id is not null and application_id is not null),'Audit missing');
select pg_temp.assert_true(not exists(select 1 from public.gym_store_reports where kind='new_store' and status<>'rejected'),'Report rejection not synchronized');
-- A newer master edit must not be overwritten by rollback.
select pg_temp.report(20,'qa-store-rollback-conflict','temporarily_closed');
select pg_temp.report(21,'qa-store-rollback-conflict','temporarily_closed');
select pg_temp.report(22,'qa-store-rollback-conflict','temporarily_closed');
update public.gym_stores set address='New official address' where id='qa-store-rollback-conflict';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-9028-000000000012',true);
do $$ declare target uuid;begin
 select id into target from public.gym_change_candidates where store_id='qa-store-rollback-conflict';
 begin perform public.rollback_gym_change_candidate(target,'old rollback');raise exception 'Stale rollback accepted';
 exception when raise_exception then if sqlerrm='Stale rollback accepted' then raise;end if;end;
end $$;
select pg_temp.assert_true((select address='New official address' and operational_status='temporarily_closed' from public.gym_stores where id='qa-store-rollback-conflict'),'Rollback overwrote newer data');
reset role;
select 'gym_store_lifecycle assertions passed' as result;
rollback;
