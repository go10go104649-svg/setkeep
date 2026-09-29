begin;
create table public.gym_official_sources (
 id uuid primary key default gen_random_uuid(),
 entity_type text not null check(entity_type in ('store','store_equipment')),
 chain_id text not null references public.gym_chains(id),store_id text references public.gym_stores(id),
 source_type text not null check(source_type in ('store_page','facility_page','store_list','status_page')),
 url text not null unique check(url ~ '^https://www[.]anytimefitness[.]co[.]jp/[a-z0-9/-]+/$'),
 parser_type text not null default 'anytime' check(parser_type='anytime'),
 enabled boolean not null default false,fetch_interval_hours int not null default 24 check(fetch_interval_hours>=24),
 policy_status text not null default 'needs_review' check(policy_status in ('needs_review','approved','denied')),
 policy_note text not null default '',policy_checked_at timestamptz,
 last_checked_at timestamptz,last_success_at timestamptz,last_changed_at timestamptz,
 last_http_status int,last_error text,etag text,last_modified text,
 status text not null default 'manual_review' check(status in ('pending','ok','fetch_error','manual_review','source_broken')),
 failure_count int not null default 0,next_fetch_at timestamptz not null default now(),
 current_data jsonb,current_parsed_hash text,current_parser_version text,current_snapshot_id uuid,parser_review_required boolean not null default false,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(not enabled or (policy_status='approved' and length(trim(policy_note))>0 and policy_checked_at is not null))
);
create index gym_official_due on public.gym_official_sources(next_fetch_at) where enabled;
create table public.gym_official_source_snapshots (
 id uuid primary key default gen_random_uuid(),source_id uuid not null references public.gym_official_sources(id),
 fetched_at timestamptz not null,http_status int,content_hash text,parsed_hash text,parsed_data jsonb,
 fetch_metadata jsonb not null default '{}',parser_version text not null,is_changed boolean not null,
 error text,requires_review boolean not null default false,
 check(octet_length(coalesce(parsed_data::text,''))<=200000),check(octet_length(fetch_metadata::text)<=20000)
);
create index gym_official_snapshot_time on public.gym_official_source_snapshots(source_id,fetched_at desc);
create table public.gym_official_snapshot_candidates (
 snapshot_id uuid references public.gym_official_source_snapshots(id),candidate_id uuid references public.gym_change_candidates(id),
 primary key(snapshot_id,candidate_id)
);
-- Invocation tokens are short lived, one-use capabilities; never exposed to clients.
create table public.gym_official_fetch_jobs (
 token uuid primary key default gen_random_uuid(),source_id uuid not null references public.gym_official_sources(id),
 created_at timestamptz not null default now(),claimed_at timestamptz,finished_at timestamptz
);
create index gym_official_job_source on public.gym_official_fetch_jobs(source_id,created_at desc);
do $$ declare t text;begin
 foreach t in array array['gym_official_sources','gym_official_source_snapshots','gym_official_snapshot_candidates','gym_official_fetch_jobs'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 if t<>'gym_official_fetch_jobs' then
 execute format('grant select on public.%I to authenticated',t);
 execute format('create policy official_admin_read on public.%I for select to authenticated using(public.is_report_admin())',t);
 end if;
 end loop;
end $$;
alter table public.gym_auto_rule_config add column official_weight numeric not null default 3 check(official_weight between 1 and 10),
 add column official_review_only boolean not null default true;
-- All pilot official observations require review. Existing USER-only thresholds remain unchanged.
create function public.official_equipment_key(value text) returns text language sql immutable set search_path='' as $$
 select regexp_replace(lower(normalize(coalesce(value,''),NFKC)),'[[:space:]]','','g');
$$;
create function public.resolve_official_equipment(target_store text,raw_name text,normalized_name text) returns text
language plpgsql stable security definer set search_path='' as $$
declare matches text[];begin
 select array_agg(distinct g.equipment_id) into matches from public.gym_store_equipment g
 where g.store_id=target_store and public.official_equipment_key(g.raw_name)=public.official_equipment_key(resolve_official_equipment.raw_name);
 if cardinality(matches)=1 then return matches[1];elsif cardinality(matches)>1 then return null;end if;
 select array_agg(e.id) into matches from public.equipment e where not e.needs_review and
 public.official_equipment_key(e.normalized_name)=public.official_equipment_key(resolve_official_equipment.normalized_name);
 if cardinality(matches)=1 then return matches[1];elsif cardinality(matches)>1 then return null;end if;
 -- Canonical names do not identify load/manufacturer variants unless one approved ID remains.
 select array_agg(distinct e.id) into matches from public.canonical_equipment c
 join public.equipment_canonical_memberships m on m.canonical_id=c.id join public.equipment e on e.id=m.equipment_id
 where not e.needs_review and public.official_equipment_key(c.name)=public.official_equipment_key(resolve_official_equipment.normalized_name);
 if cardinality(matches)=1 then return matches[1];elsif cardinality(matches)>1 then return null;end if;
 -- The Anytime importer already preserved the approved reuse map in source metadata.
 select array_agg(distinct g.equipment_id) into matches from public.gym_store_equipment g join public.equipment e on e.id=g.equipment_id
 where g.store_id like 'anytime-fitness:%' and not e.needs_review
 and public.official_equipment_key(g.source->>'normalized_name')=public.official_equipment_key(resolve_official_equipment.normalized_name);
 if cardinality(matches)=1 then return matches[1];elsif cardinality(matches)>1 then return null;end if;
 select array_agg(distinct e.id) into matches from public.equipment e,unnest(e.aliases) a
 where not e.needs_review and public.official_equipment_key(a)=public.official_equipment_key(resolve_official_equipment.normalized_name);
 if cardinality(matches)=1 then return matches[1];end if;
 return null;
end $$;

-- Intercept before any old evaluator can fire its auto_apply trigger. No Master writes here.
alter function public.reevaluate_gym_change_candidate(uuid) rename to reevaluate_gym_candidate_before_official;
create function public.reevaluate_gym_change_candidate(target_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare c public.gym_change_candidates%rowtype;r public.gym_auto_rule_config%rowtype;reason text; support numeric;oppose numeric;reporters int;begin
 select * into c from public.gym_change_candidates where id=target_id;
 if not found or c.status not in ('collecting','needs_review','auto_ready') then return;end if;
 if c.entity_type='store' then perform pg_advisory_xact_lock(hashtextextended(coalesce(c.store_id,'new-store'),429));end if;
 select * into c from public.gym_change_candidates where id=target_id for update;
 if c.status not in ('collecting','needs_review','auto_ready') then return;end if;
 select * into r from public.gym_auto_rule_config where change_type=c.change_type;
 if exists(select 1 from public.gym_change_evidence e where e.candidate_id=c.id and e.source_type='official'
 and e.observed_at>now()-make_interval(days=>r.evidence_window_days) and e.data->>'requires_review'='true') then reason:='official_parser_review';
 elsif r.official_review_only and exists(select 1 from public.gym_change_evidence e where e.candidate_id=c.id and e.source_type='official' and e.direction='support'
 and e.observed_at>now()-make_interval(days=>r.evidence_window_days)) then reason:='official_pilot_review';end if;
 -- Official pages disagree, or the proposed direction contradicts a fresh official observation.
 if exists(select 1 from public.gym_change_evidence e join public.gym_change_candidates other on other.id=e.candidate_id
 where e.source_type='official' and other.store_id=c.store_id and other.entity_type=c.entity_type
 and e.observed_at>now()-make_interval(days=>greatest(r.source_protection_days,r.evidence_window_days))
 and ((c.entity_type='store' and other.change_type in ('store_temporarily_closed','store_reopened','store_closed')
 and c.change_type in ('store_temporarily_closed','store_reopened','store_closed') and other.change_type<>c.change_type)
 or (c.entity_type='store_equipment' and c.equipment_id=other.equipment_id and
 ((c.change_type='removed' and other.change_type='added') or(c.change_type='added' and other.change_type='removed')
 or(c.change_type='quantity_changed' and other.change_type='quantity_changed' and c.candidate_key<>other.candidate_key))))) then reason:='official_conflicting_evidence';end if;
 if reason is null then perform public.reevaluate_gym_candidate_before_official(target_id);return;end if;
 with ranked as (
 select e.*,row_number() over(partition by coalesce('user:'||e.user_id::text,'source:'||e.id::text)
 order by e.observed_at desc,e.created_at desc,e.id desc) as vote_rank
 from public.gym_change_evidence e
 left join public.gym_equipment_reports er on e.source_type='user_report' and e.source_ref=er.id::text
 left join public.gym_store_reports sr on e.source_type='user_report' and e.source_ref='store-report:'||sr.id::text
 where e.candidate_id=c.id and e.observed_at between now()-make_interval(days=>r.evidence_window_days) and now()
 and(e.source_type<>'user_report' or er.status<>'rejected' or sr.status<>'rejected')
 )
 select coalesce(sum(weight) filter(where direction='support'),0),coalesce(sum(weight) filter(where direction='oppose'),0),
 count(distinct user_id) filter(where direction='support' and source_type='user_report')
 into support,oppose,reporters from ranked where vote_rank=1;
 update public.gym_change_candidates set status='needs_review',updated_at=now(),
 support_score=support,oppose_score=oppose,unique_reporters=reporters where id=c.id;
 insert into public.gym_auto_decisions(candidate_id,decision,reason_code,score_snapshot,rule_snapshot,algorithm_version)
 values(c.id,'needs_review',reason,jsonb_build_object('support_score',support,'oppose_score',oppose,'unique_reporters',reporters),to_jsonb(r),'official-v1');
end $$;

create function public.capture_official_observation(source_id uuid,snapshot_id uuid,change text,subject text,equipment_id text,proposal jsonb,review_required boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare s public.gym_official_sources%rowtype;target uuid;weight numeric;identity text;begin
 select * into strict s from public.gym_official_sources where id=source_id;
 if s.store_id is null then raise exception 'Pilot requires registered store';end if;
 if change like 'store_%' then perform pg_advisory_xact_lock(hashtextextended(s.store_id,429));
 else perform pg_advisory_xact_lock(hashtextextended(s.store_id||':'||change||':'||subject,421));end if;
 select c.id into target from public.gym_change_candidates c where c.store_id=s.store_id and c.change_type=change and c.candidate_key=subject
 and c.status in ('collecting','needs_review','auto_ready') for update;
 if target is null then insert into public.gym_change_candidates(entity_type,store_id,equipment_id,change_type,candidate_key,proposed_value)
 values(case when change like 'store_%' then 'store' else 'store_equipment' end,s.store_id,equipment_id,change,subject,proposal) returning id into target;end if;
 identity:='official:'||source_id||':'||target;
 select official_weight into strict weight from public.gym_auto_rule_config where change_type=change;
 insert into public.gym_change_evidence(candidate_id,source_type,source_ref,direction,weight,observed_at,source_url,data)
 values(target,'official',identity,'support',weight,(select fetched_at from public.gym_official_source_snapshots where id=snapshot_id),s.url,jsonb_build_object('source_id',source_id,'snapshot_id',snapshot_id,'requires_review',review_required,'parser_version',s.current_parser_version)||proposal)
 on conflict(source_type,source_ref) where source_ref is not null do update set observed_at=excluded.observed_at,weight=excluded.weight,data=excluded.data;
 insert into public.gym_official_snapshot_candidates values(snapshot_id,target) on conflict do nothing;
 update public.gym_change_candidates set last_seen_at=now() where id=target;
 perform public.reevaluate_gym_change_candidate(target);
 -- Reevaluate opposite open candidates as protection, never only the new side.
 perform public.reevaluate_gym_change_candidate(c.id) from public.gym_change_candidates c where c.store_id=s.store_id and c.id<>target
 and c.status in ('collecting','needs_review','auto_ready') and ((change like 'store_%' and c.entity_type='store') or c.equipment_id=capture_official_observation.equipment_id);
 return target;
end $$;

create function public.record_official_snapshot(target_id uuid,result jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.gym_official_sources%rowtype;snapshot uuid:=gen_random_uuid();parsed jsonb;changed boolean;version_changed boolean;
 item jsonb;eq text;change text;subject text;target uuid;unmatched int:=0;ids uuid[]:='{}';status text;g public.gym_store_equipment%rowtype;fetched timestamptz;
begin
 select * into strict s from public.gym_official_sources where id=target_id for update;
 if octet_length(result::text)>240000 then raise exception 'Result too large';end if;
 fetched:=(result->>'fetched_at')::timestamptz;
 if fetched is null or fetched>clock_timestamp()+interval '1 minute' then raise exception 'Invalid fetched_at';end if;
 if s.last_checked_at is not null and fetched<s.last_checked_at then raise exception 'Stale fetch result';end if;
 parsed:=result->'parsed_data';
 if result->>'error' is null and result->>'not_modified' is distinct from 'true' and
 (parsed is null or jsonb_typeof(parsed)<>'object' or parsed->'store'->>'name' is null or jsonb_typeof(parsed->'equipment')<>'array') then raise exception 'Invalid normalized data';end if;
 if result->>'error' is null and s.policy_status<>'approved' then raise exception 'Policy approval required';end if;
 version_changed:=s.current_parser_version is not null and s.current_parser_version<>result->>'parser_version';
 changed:=result->>'error' is null and result->>'not_modified' is distinct from 'true' and (s.current_parsed_hash is distinct from result->>'parsed_hash' or version_changed);
 insert into public.gym_official_source_snapshots(id,source_id,fetched_at,http_status,content_hash,parsed_hash,parsed_data,fetch_metadata,parser_version,is_changed,error,requires_review)
 values(snapshot,s.id,fetched,(result->>'http_status')::int,result->>'content_hash',result->>'parsed_hash',parsed,coalesce(result->'fetch_metadata','{}'),result->>'parser_version',changed,result->>'error',version_changed);
 update public.gym_official_sources set last_checked_at=fetched,last_http_status=(result->>'http_status')::int,last_error=result->>'error',
 failure_count=case when result->>'error' is null then 0 else failure_count+1 end,
 status=case when result->>'error' is null then case when version_changed or s.parser_review_required then 'manual_review' else 'ok' end
 when result->>'error' like 'manual_review:%' then 'manual_review' when result->>'http_status'='404' and failure_count>=2 then 'source_broken' else 'fetch_error' end,
 last_success_at=case when result->>'error' is null then fetched else last_success_at end,
 next_fetch_at=greatest(now()+make_interval(hours=>fetch_interval_hours),coalesce((result->'fetch_metadata'->>'retry_after')::timestamptz,now())),updated_at=now()
 where id=s.id;
 if result->>'error' is not null then return jsonb_build_object('snapshot_id',snapshot,'candidates',0,'error',result->>'error');end if;
 if not changed then
 -- Reconfirmation of the SAME observation, not another vote or a bulk reevaluation.
 update public.gym_change_evidence set observed_at=fetched where source_type='official' and data->>'source_id'=s.id::text
 and data->>'snapshot_id'=s.current_snapshot_id::text;
 return jsonb_build_object('snapshot_id',snapshot,'candidates',0,'changed',false);end if;
 update public.gym_official_sources set last_changed_at=fetched,current_data=parsed,current_parsed_hash=result->>'parsed_hash',current_parser_version=result->>'parser_version',current_snapshot_id=snapshot,parser_review_required=parser_review_required or version_changed,
 etag=result->'fetch_metadata'->>'etag',last_modified=result->'fetch_metadata'->>'last_modified' where id=s.id;
 status:=parsed->'store'->>'status';
 if status in ('active','temporarily_closed','closed','preopening','conflict') then
 change:=case status when 'active' then 'store_reopened' when 'temporarily_closed' then 'store_temporarily_closed' when 'closed' then 'store_closed' else 'store_other' end;
 target:=public.capture_official_observation(s.id,snapshot,change,s.store_id,null,jsonb_build_object('operational_status',status,'basis',parsed->'store'->>'status_basis'),s.parser_review_required or version_changed or status in ('preopening','conflict'));
 ids:=array_append(ids,target);end if;
 for item in select * from jsonb_array_elements(parsed->'equipment') loop
 eq:=public.resolve_official_equipment(s.store_id,item->>'raw_name',item->>'normalized_name');
 select * into g from public.gym_store_equipment where store_id=s.store_id and equipment_id=eq;
 change:=case when eq is null then 'other' when item->>'explicit_removed'='true' then 'removed'
 when item->>'quantity' is not null and g.presence_status='present' and g.quantity is distinct from (item->>'quantity')::int then 'quantity_changed' else 'added' end;
 if eq is null then unmatched:=unmatched+1;end if;
 subject:=case change when 'added' then (select public.gym_search_text(name) from public.equipment where id=eq)
 when 'quantity_changed' then eq||':quantity:'||(item->>'quantity') when 'removed' then eq else 'official:'||left(md5(item->>'normalized_name'),24) end;
 target:=public.capture_official_observation(s.id,snapshot,change,subject,eq,item||jsonb_build_object('equipment_name',coalesce((select name from public.equipment where id=eq),item->>'raw_name'),'reported_quantity',item->'quantity'),s.parser_review_required or version_changed or eq is null);
 ids:=array_append(ids,target);
 end loop;
 return jsonb_build_object('snapshot_id',snapshot,'candidates',cardinality(ids),'candidate_ids',to_jsonb(ids),'unmatched',unmatched,'changed',true,'parser_review',version_changed);
end $$;

create function public.mark_official_source_for_review(target_id uuid) returns void language plpgsql security definer set search_path='' as $$ begin
 if not public.is_report_admin() then raise exception 'Administrator required' using errcode='42501';end if;
 -- Mark only; never take a URL from the client or bypass rate/policy controls.
 update public.gym_official_sources set status='manual_review',updated_at=now() where id=target_id;
end $$;
create function public.claim_official_fetch(job_token uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare j public.gym_official_fetch_jobs%rowtype;s public.gym_official_sources%rowtype;begin
 select * into j from public.gym_official_fetch_jobs where token=job_token and claimed_at is null and created_at>now()-interval '5 minutes' for update;
 if not found then return null;end if;
 update public.gym_official_fetch_jobs set claimed_at=now() where token=job_token;
 select * into s from public.gym_official_sources where id=j.source_id and enabled and policy_status='approved';
 if not found then return null;end if;
 return to_jsonb(s)||jsonb_build_object('store_name',(select name from public.gym_stores where id=s.store_id));
end $$;
create function public.finish_official_fetch(job_token uuid,result jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare j public.gym_official_fetch_jobs%rowtype;response jsonb;begin
 select * into strict j from public.gym_official_fetch_jobs where token=job_token and claimed_at is not null and finished_at is null and created_at>now()-interval '10 minutes' for update;
 response:=public.record_official_snapshot(j.source_id,result);
 update public.gym_official_fetch_jobs set finished_at=now() where token=job_token;
 return response;
end $$;
revoke all on function public.official_equipment_key(text),public.resolve_official_equipment(text,text,text),public.reevaluate_gym_change_candidate(uuid),
 public.capture_official_observation(uuid,uuid,text,text,text,jsonb,boolean),public.record_official_snapshot(uuid,jsonb),public.mark_official_source_for_review(uuid),public.claim_official_fetch(uuid),public.finish_official_fetch(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.claim_official_fetch(uuid),public.finish_official_fetch(uuid,jsonb),public.record_official_snapshot(uuid,jsonb) to service_role;
grant execute on function public.mark_official_source_for_review(uuid) to authenticated;

-- Only four pilot stores. Facility URLs must be explicit links observed on store pages.
insert into public.gym_official_sources(entity_type,chain_id,store_id,source_type,url,policy_note,next_fetch_at)
select 'store',chain_id,id,'store_page',official_url,'利用条件未確認のため定期取得は無効',now()+make_interval(mins=>row_number() over(order by id)::int*7)
from public.gym_stores where id in ('anytime-fitness:anytime_jp_1d4bdbb1432e','anytime-fitness:anytime_jp_a7a127d59c49','anytime-fitness:anytime_jp_f6e363e5f25f','anytime-fitness:anytime_jp_95ec9f1350fd');
insert into public.gym_official_sources(entity_type,chain_id,store_id,source_type,url,policy_note)
select 'store_equipment',chain_id,id,'facility_page',official_url||'facility/','利用条件未確認のため定期取得は無効'
from public.gym_stores where id='anytime-fitness:anytime_jp_1d4bdbb1432e';
notify pgrst,'reload schema';
commit;
