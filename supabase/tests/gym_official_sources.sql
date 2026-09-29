begin;
create function pg_temp.assert_true(ok boolean,msg text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception '%',msg;end if;end$$;
insert into auth.users(id) values('00000000-0000-4000-9030-000000000001'),('00000000-0000-4000-9030-000000000002');
insert into public.app_admins(user_id) values('00000000-0000-4000-9030-000000000002');
insert into public.gym_chains(id,name) values('qa-official','QA');
insert into public.gym_stores(id,chain_id,source_id,name) values('qa-official','qa-official','qa','QA店');
insert into public.equipment(id,name,normalized_name,category) values('qa-official','QAラック','qaラック','マシン');
insert into public.gym_official_sources(id,entity_type,chain_id,store_id,source_type,url,policy_status,policy_note,policy_checked_at)
values('00000000-0000-4000-9030-000000000010','store_equipment','qa-official','qa-official','facility_page','https://www.anytimefitness.co.jp/qa/facility/','approved','Synthetic QA only',now()),
('00000000-0000-4000-9030-000000000011','store','qa-official','qa-official','store_page','https://www.anytimefitness.co.jp/qa/','approved','Synthetic QA only',now());
create function pg_temp.record(hash text,equipment jsonb default '[]',status text default 'unknown',version text default 'anytime-1',error text default null,http int default 200,source_id uuid default '00000000-0000-4000-9030-000000000010') returns jsonb language sql as $$
 select public.record_official_snapshot(source_id,jsonb_build_object('parsed_hash',hash,'content_hash','raw-'||hash,
 'fetched_at',clock_timestamp()-interval '1 second','parser_version',version,'error',error,'http_status',http,
 'parsed_data',jsonb_build_object('store',jsonb_build_object('name','QA店','status',status),'equipment',equipment)));
$$;
select pg_temp.record('a','[{"raw_name":"QAラック","normalized_name":"qaラック","quantity":null,"explicit_removed":false}]');
select pg_temp.assert_true(exists(select 1 from public.gym_change_candidates where store_id='qa-official' and change_type='added' and status='needs_review'),'Known new equipment not routed to review');
select pg_temp.assert_true(not exists(select 1 from public.gym_store_equipment where store_id='qa-official'),'Pilot changed master');
create temp table before_repeat as select count(*) votes,sum(weight) weight,(select count(*) from public.gym_auto_decisions) decisions from public.gym_change_evidence where source_type='official';
select pg_temp.record('a','[{"raw_name":"QAラック","normalized_name":"qaラック"}]');
select pg_temp.assert_true((select count(*)=b.votes and sum(gym_change_evidence.weight)=b.weight from public.gym_change_evidence,before_repeat b where source_type='official' group by b.votes,b.weight),'Repeated content inflated votes');
select pg_temp.assert_true((select count(*)=(select decisions from before_repeat) from public.gym_auto_decisions),'Duplicate caused reevaluation');
select pg_temp.assert_true((select e.observed_at=s.last_checked_at from public.gym_change_evidence e join public.gym_official_sources s on e.data->>'source_id'=s.id::text where s.id='00000000-0000-4000-9030-000000000010'),'Actual fetched timestamp not retained');
select pg_temp.record('b','[]');
select pg_temp.assert_true(not exists(select 1 from public.gym_change_candidates where store_id='qa-official' and change_type='removed'),'Missing listing interpreted as removal');
select pg_temp.record('c','[{"raw_name":"QAラック","normalized_name":"qaラック","explicit_removed":true}]');
select pg_temp.assert_true(exists(select 1 from public.gym_change_candidates where store_id='qa-official' and change_type='removed' and status='needs_review'),'Explicit removal not recorded');
select pg_temp.record('temp','[]','temporarily_closed','anytime-1',null,200,'00000000-0000-4000-9030-000000000011');
select pg_temp.assert_true(exists(select 1 from public.gym_change_candidates where store_id='qa-official' and change_type='store_temporarily_closed'),'Temporary closure evidence absent');
select pg_temp.record('closed','[]','closed','anytime-1',null,200,'00000000-0000-4000-9030-000000000011');
select pg_temp.assert_true(exists(select 1 from public.gym_change_candidates where store_id='qa-official' and change_type='store_closed' and status='needs_review'),'Permanent closure must require review');
select pg_temp.assert_true((select operational_status='active' from public.gym_stores where id='qa-official'),'Official changed store master');
select pg_temp.record('reopen','[]','active');
select pg_temp.assert_true(exists(select 1 from public.gym_auto_decisions d join public.gym_change_candidates c on c.id=d.candidate_id where c.store_id='qa-official' and d.reason_code='official_conflicting_evidence'),'Conflicting official statuses not protected');
create temp table before_errors as select count(*) n from public.gym_change_evidence;
select pg_temp.record(null,'[]','unknown','anytime-1','fetch_error: HTTP 404',404);
select pg_temp.record(null,'[]','unknown','anytime-1','fetch_error: HTTP 404',404);
select pg_temp.record(null,'[]','unknown','anytime-1','fetch_error: HTTP 404',404);
select pg_temp.assert_true((select status='source_broken' from public.gym_official_sources where id='00000000-0000-4000-9030-000000000010'),'Repeated 404 not flagged');
select pg_temp.record(null,'[]','unknown','anytime-1','parse_error: layout changed',200);
select pg_temp.record(null,'[]','unknown','anytime-1','manual_review: HTTP 403',403);
select pg_temp.assert_true((select count(*)=(select n from before_errors) from public.gym_change_evidence),'Failures generated evidence');
-- Even if an operator opts into automatic rules, parser upgrades persistently gate application.
update public.gym_auto_rule_config set official_review_only=false;
insert into public.equipment(id,name,normalized_name,category) values('qa-official-new','QA別ラック','qa別ラック','マシン');
select pg_temp.record('upgrade-known','[{"raw_name":"QA別ラック","normalized_name":"qa別ラック"}]','unknown','anytime-2');
select pg_temp.assert_true(exists(select 1 from public.gym_change_evidence e join public.gym_change_candidates c on c.id=e.candidate_id
 where c.equipment_id='qa-official-new' and e.data->>'requires_review'='true' and c.status='needs_review'),'Known equipment bypassed version review');
select pg_temp.assert_true(exists(select 1 from public.gym_auto_decisions d join public.gym_change_candidates c on c.id=d.candidate_id
 where c.equipment_id='qa-official-new' and d.reason_code='official_parser_review'),'Upgrade safeguard not evaluated');

select pg_temp.record('v2','[{"raw_name":"Unmatched","normalized_name":"unmatched"}]','unknown','anytime-2');
select pg_temp.record('v2next','[{"raw_name":"Another","normalized_name":"another"}]','unknown','anytime-2');
select pg_temp.assert_true((select parser_review_required and status='manual_review' from public.gym_official_sources where id='00000000-0000-4000-9030-000000000010'),'Parser review hold lost');
select pg_temp.assert_true(not exists(select 1 from public.equipment where name in ('Unmatched','Another')),'Unknown equipment auto-created');
select pg_temp.assert_true((select bool_and((e.data->>'requires_review')::boolean) from public.gym_change_evidence e where e.data->>'parser_version'='anytime-2'),'Upgrade evidence not gated');
-- HTTPS allowlist constraints, policy gates and one-use jobs.
do $$begin
 begin insert into public.gym_official_sources(entity_type,chain_id,source_type,url) values('store','qa-official','store_page','http://169.254.169.254/latest/');raise exception 'Unsafe URL accepted';
 exception when check_violation then null;end;
 begin update public.gym_official_sources set enabled=true,policy_status='needs_review' where id='00000000-0000-4000-9030-000000000010';raise exception 'Unapproved source enabled';
 exception when check_violation then null;end;
end$$;
insert into public.gym_official_fetch_jobs(token,source_id) values('00000000-0000-4000-9030-000000000020','00000000-0000-4000-9030-000000000010');
select pg_temp.assert_true(public.claim_official_fetch('00000000-0000-4000-9030-000000000020') is null,'Disabled source fetched');
update public.gym_official_sources set enabled=true where id='00000000-0000-4000-9030-000000000010';
insert into public.gym_official_fetch_jobs(token,source_id) values('00000000-0000-4000-9030-000000000021','00000000-0000-4000-9030-000000000010');
select pg_temp.assert_true(public.claim_official_fetch('00000000-0000-4000-9030-000000000021')->>'store_name'='QA店','Registered source not claimed');
select pg_temp.assert_true(public.claim_official_fetch('00000000-0000-4000-9030-000000000021') is null,'Job replay accepted');
select public.finish_official_fetch('00000000-0000-4000-9030-000000000021',
 jsonb_build_object('fetched_at',clock_timestamp(),'parser_version','anytime-2','http_status',500,'error','fetch_error: HTTP 500'));
do $$begin
 begin perform public.finish_official_fetch('00000000-0000-4000-9030-000000000021','{}');raise exception 'Finished job replayed';
 exception when no_data_found then null;end;
end$$;
insert into public.gym_official_fetch_jobs(token,source_id,created_at)
 values('00000000-0000-4000-9030-000000000022','00000000-0000-4000-9030-000000000010',now()-interval '6 minutes');
select pg_temp.assert_true(public.claim_official_fetch('00000000-0000-4000-9030-000000000022') is null,'Expired job accepted');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-9030-000000000001',true);
select pg_temp.assert_true(not exists(select 1 from public.gym_official_sources),'Source RLS leak');
select pg_temp.assert_true(not exists(select 1 from public.gym_official_source_snapshots),'Snapshot RLS leak');
do $$begin
 begin perform public.claim_official_fetch('00000000-0000-4000-9030-000000000021');raise exception 'Client worker invocation';exception when insufficient_privilege then null;end;
 begin perform public.mark_official_source_for_review('00000000-0000-4000-9030-000000000010');raise exception 'Nonadmin review';exception when insufficient_privilege then null;end;
 begin update public.gym_official_sources set enabled=true;raise exception 'Client source mutation';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-9030-000000000002',true);
select pg_temp.assert_true(exists(select 1 from public.gym_official_sources),'Admin cannot read sources');
select pg_temp.assert_true(exists(select 1 from public.gym_official_source_snapshots),'Admin cannot read snapshots');
select public.mark_official_source_for_review('00000000-0000-4000-9030-000000000010');
reset role;
select pg_temp.assert_true(not exists(select 1 from public.gym_store_equipment where store_id='qa-official'),'Master modified');
select 'official source assertions passed' as result;
rollback;
