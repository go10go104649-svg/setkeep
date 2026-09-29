begin;
-- Preserve active/search compatibility. Imported inactivity is not proof of closure.
alter table public.gym_stores
 add column operational_status text not null default 'unknown'
 check (operational_status in ('active','preopening','temporarily_closed','closed','unknown')),
 add column status_source_kind text not null default 'import'
 check (status_source_kind in ('import','confirmed_report','official','admin','gym_staff')),
 add column status_checked_at timestamptz,
 add column status_source_url text,
 add column status_source_data jsonb not null default '{}';
update public.gym_stores set operational_status=case
 when source->>'page_status'='preopening_text' then 'preopening'
 when active then 'active' else 'unknown' end,
 status_source_url=official_url,
 status_source_data=jsonb_build_object('migration','202609290028','original_active',active,'page_status',source->>'page_status');
create function public.sync_gym_operational_status() returns trigger
language plpgsql set search_path='' as $$ begin
 if tg_op='INSERT' and new.operational_status='unknown' then
  new.operational_status:=case when new.source->>'page_status'='preopening_text' then 'preopening'
    when new.active then 'active' else 'unknown' end;
 end if;
 if tg_op='UPDATE' and new.active is distinct from old.active and new.operational_status=old.operational_status then
  new.operational_status:=case when new.active then 'active' else 'unknown' end;
 end if;
 if new.operational_status='closed' then new.active:=false;
 elsif new.operational_status in ('active','preopening','temporarily_closed') then new.active:=true; end if;
 return new;
end $$;
create trigger gym_store_operational_compat before insert or update on public.gym_stores
 for each row execute function public.sync_gym_operational_status();

create function public.guard_new_gym_registration() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if not exists(select 1 from public.user_gym_stores where user_id=new.user_id and store_id=new.store_id)
 and not exists(select 1 from public.gym_stores where id=new.store_id and active and operational_status='active')
 then raise exception 'This store is not currently selectable';end if;
 return new;
end $$;
revoke all on function public.guard_new_gym_registration() from public,anon,authenticated;
create trigger gym_registration_state before insert on public.user_gym_stores for each row execute function public.guard_new_gym_registration();

-- Namespace store rules to keep existing equipment wrong_name/other semantics.
alter table public.gym_auto_rule_config drop constraint gym_auto_rule_config_change_type_check;
alter table public.gym_auto_rule_config add constraint gym_auto_rule_config_change_type_check check (
 change_type in ('added','removed','not_present','wrong_name','other','quantity_changed','temporarily_unavailable','available_again',
 'store_temporarily_closed','store_reopened','store_closed','store_new_store','store_relocated','store_wrong_name','store_wrong_address','store_other'));
insert into public.gym_auto_rule_config(change_type,auto_apply_enabled,min_unique_reporters,min_support_score,max_oppose_score,evidence_window_days,source_protection_days,cooldown_days)
select 'store_'||kind,kind in ('temporarily_closed','reopened'),
 case when kind='temporarily_closed' then 3 else 2 end,
 case when kind='temporarily_closed' then 3 else 2 end,0,7,14,7
from unnest(array['temporarily_closed','reopened','closed','new_store','relocated','wrong_name','wrong_address','other']) kind;
alter table public.gym_change_candidates drop constraint gym_change_candidates_entity_type_check;
alter table public.gym_change_candidates alter column store_id drop not null;
alter table public.gym_change_candidates add constraint gym_candidate_entity_shape check (
 (entity_type='store_equipment' and store_id is not null and change_type not like 'store_%') or
 (entity_type='store' and equipment_id is null and change_type like 'store_%'
  and (store_id is not null or change_type='store_new_store')));
create unique index gym_store_candidate_open_key on public.gym_change_candidates
 (coalesce(store_id,''),change_type,candidate_key) where entity_type='store'
 and status in ('collecting','needs_review','auto_ready');

create table public.gym_store_reports (
 id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id),
 store_id text references public.gym_stores(id), chain_id text references public.gym_chains(id),
 reported_chain_name text check(length(reported_chain_name)<=200),
 kind text not null check(kind in ('temporarily_closed','reopened','closed','new_store','relocated','wrong_name','wrong_address','other')),
 reported_name text check(length(reported_name)<=200),
 reported_address text check(length(reported_address)<=1000),
 reported_official_url text check(reported_official_url is null or (length(reported_official_url)<=2000 and reported_official_url ~ '^https?://')),
 reported_source_id text check(length(reported_source_id)<=300),
 comment text not null default '' check(length(comment)<=1000),
 status text not null default 'pending' check(status in ('pending','reviewing','applied','rejected')),
 created_at timestamptz not null default now(), admin_note text not null default '',
 reviewed_at timestamptz, reviewed_by uuid references auth.users(id),
 check(kind='new_store' or store_id is not null),
 check(kind<>'new_store' or (store_id is null and (chain_id is not null or coalesce(length(trim(reported_chain_name)),0)>0)
  and coalesce(length(trim(reported_name)),0)>0 and coalesce(length(trim(reported_address)),0)>0)),
 check(kind<>'wrong_name' or coalesce(length(trim(reported_name)),0)>0),
 check(kind not in ('relocated','wrong_address') or coalesce(length(trim(reported_address)),0)>0),
 check(kind<>'other' or length(trim(comment))>0)
);
create index gym_store_reports_rate on public.gym_store_reports(user_id,store_id,kind,created_at desc);
alter table public.gym_store_reports enable row level security;
revoke all on public.gym_store_reports from public,anon,authenticated;
grant select on public.gym_store_reports to authenticated;
grant insert(store_id,chain_id,reported_chain_name,kind,reported_name,reported_address,reported_official_url,reported_source_id,comment)
 on public.gym_store_reports to authenticated;
create policy store_reports_admin_read on public.gym_store_reports for select to authenticated using(public.is_report_admin());
create policy store_reports_self_insert on public.gym_store_reports for insert to authenticated
 with check(user_id=auth.uid() and status='pending');

-- Application ledger is shared; original equipment constraints remain enforced.
alter table public.gym_auto_applications alter column equipment_id drop not null;
alter table public.gym_auto_applications drop constraint gym_auto_applications_change_type_check;
alter table public.gym_auto_applications add constraint gym_auto_applications_change_type_check check (
 (equipment_id is not null and change_type in ('added','removed','quantity_changed','temporarily_unavailable','available_again')) or
 (equipment_id is null and change_type in ('store_temporarily_closed','store_reopened','store_closed')));
create index gym_store_applications_time on public.gym_auto_applications(store_id,applied_at desc) where equipment_id is null;
create table public.gym_store_changes (
 id uuid primary key default gen_random_uuid(), store_id text not null references public.gym_stores(id),
 operation text not null, before_data jsonb, after_data jsonb,
 candidate_id uuid references public.gym_change_candidates(id), application_id uuid references public.gym_auto_applications(id),
 changed_at timestamptz not null default now(),changed_by uuid references auth.users(id)
);
alter table public.gym_store_changes enable row level security;
revoke all on public.gym_store_changes from public,anon,authenticated;
grant select on public.gym_store_changes to authenticated;
create policy store_changes_admin_read on public.gym_store_changes for select to authenticated using(public.is_report_admin());
create function public.record_gym_store_change() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if to_jsonb(old) is distinct from to_jsonb(new) then
 insert into public.gym_store_changes(store_id,operation,before_data,after_data,candidate_id,application_id,changed_by)
 values(new.id,tg_op,to_jsonb(old),to_jsonb(new),
 nullif(current_setting('setkeep.gym_candidate_id',true),'')::uuid,
 nullif(current_setting('setkeep.gym_application_id',true),'')::uuid,auth.uid()); end if;
 return new;
end $$;
create trigger gym_store_audit after update on public.gym_stores for each row execute function public.record_gym_store_change();

create function public.gym_store_identity_key(value text) returns text language sql immutable set search_path='' as $$
 select regexp_replace(lower(normalize(coalesce(value,''),NFKC)),'[[:space:]ー−‐–—-]','','g');
$$;
create function public.gym_store_url_key(value text) returns text language sql immutable set search_path='' as $$
 select regexp_replace(regexp_replace(lower(trim(coalesce(value,''))),'^https?://',''),'[/?#]+$','');
$$;
create function public.limit_gym_store_reports() returns trigger language plpgsql security definer set search_path='' as $$ begin
 perform pg_advisory_xact_lock(hashtextextended(new.user_id::text,428));
 if (select count(*) from public.gym_store_reports where user_id=new.user_id and created_at>now()-interval '5 minutes')>=5
 or exists(select 1 from public.gym_store_reports r where r.user_id=new.user_id and r.kind=new.kind
  and r.store_id is not distinct from new.store_id
  and (new.store_id is not null or (public.gym_store_identity_key(r.reported_name)=public.gym_store_identity_key(new.reported_name)
   and r.chain_id is not distinct from new.chain_id))
  and (r.created_at>now()-interval '5 minutes' or r.status in ('pending','reviewing')))
 then raise exception 'Please wait before reporting again'; end if;
 return new;
end $$;
create trigger store_report_rate before insert on public.gym_store_reports for each row execute function public.limit_gym_store_reports();

-- Assess on every apply as well as every report; never trust a stale auto_ready.
create function public.assess_gym_store_candidate(target_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.gym_change_candidates%rowtype; r public.gym_auto_rule_config%rowtype;
 s public.gym_stores%rowtype; support numeric:=0; oppose numeric:=0; reporters int:=0;
 protected boolean:=false; cooling boolean:=false; result_status text; reason text;
begin
 select * into strict c from public.gym_change_candidates where id=target_id and entity_type='store';
 select * into strict r from public.gym_auto_rule_config where change_type=c.change_type;
 select * into s from public.gym_stores where id=c.store_id;
 with ranked as (
 select e.*, row_number() over(partition by coalesce(e.user_id::text,e.id::text)
 order by e.observed_at desc,e.created_at desc,e.id desc) rank
 from public.gym_change_evidence e left join public.gym_store_reports p on e.source_ref='store-report:'||p.id::text
 where e.candidate_id=c.id and e.observed_at between now()-make_interval(days=>r.evidence_window_days) and now()
 and (e.source_type<>'user_report' or (p.id is not null and p.status<>'rejected')))
 select coalesce(sum(weight) filter(where direction='support'),0),coalesce(sum(weight) filter(where direction='oppose'),0),
 count(distinct user_id) filter(where direction='support' and source_type='user_report')
 into support,oppose,reporters from ranked where rank=1;
 -- Opposite recent store state observations block automatic oscillation.
 if c.change_type in ('store_temporarily_closed','store_reopened') and exists(
 select 1 from public.gym_change_candidates other join public.gym_change_evidence e on e.candidate_id=other.id
 left join public.gym_store_reports p on e.source_ref='store-report:'||p.id::text
 where other.entity_type='store' and other.store_id=c.store_id and other.id<>c.id
 and other.change_type in ('store_temporarily_closed','store_reopened','store_closed') and other.change_type<>c.change_type
 and other.status not in ('rejected','rolled_back') and e.direction='support'
 and e.observed_at between now()-make_interval(days=>r.evidence_window_days) and now()
 and (e.source_type<>'user_report' or (p.id is not null and p.status<>'rejected')))
 then oppose:=greatest(oppose,1); end if;
 protected:=s.status_source_kind in ('official','admin','gym_staff') and s.status_checked_at>=now()-make_interval(days=>r.source_protection_days);
 protected:=coalesce(protected,false) or exists(select 1 from public.gym_change_evidence e where e.candidate_id=c.id
  and e.source_type in ('official','admin','gym_staff') and e.direction='oppose' and e.observed_at>=now()-make_interval(days=>r.source_protection_days));
 cooling:=exists(select 1 from public.gym_auto_applications a where a.store_id=c.store_id and a.equipment_id is null
 and greatest(a.applied_at,a.rolled_back_at)>=now()-make_interval(days=>r.cooldown_days));
 if c.change_type='store_reopened' and s.operational_status='active' then result_status:='superseded';reason:='already_active';
 elsif not r.auto_apply_enabled or c.change_type not in ('store_temporarily_closed','store_reopened') then result_status:='needs_review';reason:='manual_rule';
 elsif (c.change_type='store_reopened' and s.operational_status<>'temporarily_closed')
    or (c.change_type='store_temporarily_closed' and s.operational_status<>'active') then result_status:='needs_review';reason:='ineligible_store_state';
 elsif protected then result_status:='needs_review';reason:='protected_source';
 elsif cooling then result_status:='needs_review';reason:='cooldown';
 elsif oppose>r.max_oppose_score then result_status:='needs_review';reason:='conflicting_evidence';
 elsif reporters<r.min_unique_reporters or support<r.min_support_score then
   result_status:=case when c.last_seen_at<now()-make_interval(days=>r.evidence_window_days) then 'expired' else 'collecting' end;reason:='insufficient_support';
 else result_status:='auto_ready';reason:='threshold_met'; end if;
 return jsonb_build_object('status',result_status,'reason',reason,'support_score',support,'oppose_score',oppose,
 'unique_reporters',reporters,'protected_source',protected,'in_cooldown',cooling,'rule',to_jsonb(r));
end $$;

alter function public.reevaluate_gym_change_candidate(uuid) rename to reevaluate_gym_equipment_candidate;
create function public.reevaluate_gym_change_candidate(target_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare c public.gym_change_candidates%rowtype; result jsonb;
begin
 select * into c from public.gym_change_candidates where id=target_id;
 if c.entity_type='store_equipment' then perform public.reevaluate_gym_equipment_candidate(target_id);return; end if;
 if c.entity_type is distinct from 'store' then return; end if;
 perform pg_advisory_xact_lock(hashtextextended(coalesce(c.store_id,c.candidate_key),429));
 select * into c from public.gym_change_candidates where id=target_id for update;
 if c.status not in ('collecting','needs_review','auto_ready') then return; end if;
 result:=public.assess_gym_store_candidate(c.id);
 insert into public.gym_auto_decisions(candidate_id,decision,reason_code,score_snapshot,rule_snapshot,algorithm_version)
 values(c.id,result->>'status',result->>'reason',result-'rule',result->'rule','store-v1');
 update public.gym_change_candidates set status=result->>'status',support_score=(result->>'support_score')::numeric,
 oppose_score=(result->>'oppose_score')::numeric,unique_reporters=(result->>'unique_reporters')::int,
 algorithm_version='store-v1',resolved_at=case when result->>'status' in ('superseded','expired') then now() else null end,
 updated_at=now() where id=c.id;
 if result->>'status'='superseded' then
 update public.gym_store_reports p set status='applied',reviewed_at=now()
 from public.gym_change_evidence e where e.candidate_id=c.id and e.source_ref='store-report:'||p.id::text and p.status in ('pending','reviewing'); end if;
end $$;

create function public.ingest_gym_store_report() returns trigger language plpgsql security definer set search_path='' as $$
declare target uuid; subject text; proposal jsonb; duplicate_ids jsonb;
begin
 subject:=coalesce(new.store_id,md5(coalesce(new.chain_id,public.gym_store_identity_key(new.reported_chain_name))||':'||public.gym_store_identity_key(new.reported_name)||':'||public.gym_store_identity_key(new.reported_address)));
 perform pg_advisory_xact_lock(hashtextextended(coalesce(new.store_id,'new-store'),429));
 proposal:=jsonb_build_object('chain_id',new.chain_id,'chain_name',new.reported_chain_name,'name',new.reported_name,
 'address',new.reported_address,'official_url',new.reported_official_url,'comment',new.comment,
 'operational_status',case new.kind when 'reopened' then 'active' when 'temporarily_closed' then 'temporarily_closed' when 'closed' then 'closed' end);
 if new.kind='new_store' then
 select coalesce(jsonb_agg(id),'[]') into duplicate_ids from (
 select id from public.gym_stores s where
 (new.reported_source_id is not null and s.chain_id=new.chain_id and s.source_id=new.reported_source_id) or
 (coalesce(new.reported_official_url,'')<>'' and public.gym_store_url_key(s.official_url)=public.gym_store_url_key(new.reported_official_url)) or
 (public.gym_store_identity_key(s.address)<>'' and public.gym_store_identity_key(s.address)=public.gym_store_identity_key(new.reported_address)) or
 (s.chain_id=new.chain_id and extensions.similarity(public.gym_store_identity_key(s.name),public.gym_store_identity_key(new.reported_name))>=0.8)
 order by id limit 20) duplicates;
 proposal:=proposal||jsonb_build_object('possible_existing_store_ids',duplicate_ids);
 end if;
 select id into target from public.gym_change_candidates c where entity_type='store'
 and c.store_id is not distinct from new.store_id and change_type='store_'||new.kind
 and (candidate_key=subject or (new.kind='new_store' and coalesce(new.reported_official_url,'')<>''
  and proposed_value->>'chain_id' is not distinct from new.chain_id
  and public.gym_store_url_key(proposed_value->>'official_url')=public.gym_store_url_key(new.reported_official_url)))
 and status in ('collecting','needs_review','auto_ready') order by created_at limit 1 for update;
 if target is null then
 insert into public.gym_change_candidates(entity_type,store_id,change_type,candidate_key,proposed_value)
 values('store',new.store_id,'store_'||new.kind,subject,proposal) returning id into target;
 end if;
 insert into public.gym_change_evidence(candidate_id,source_type,source_ref,user_id,direction,weight,observed_at,source_url,data)
 values(target,'user_report','store-report:'||new.id,new.user_id,'support',1,new.created_at,new.reported_official_url,to_jsonb(new));
 update public.gym_change_candidates set last_seen_at=new.created_at,updated_at=now() where id=target;
 perform public.reevaluate_gym_change_candidate(target);
 return new;
end $$;
create trigger store_report_evidence after insert on public.gym_store_reports for each row execute function public.ingest_gym_store_report();

create function public.apply_gym_store_candidate(target_id uuid, manual boolean default false, note text default '') returns void
language plpgsql security definer set search_path='' as $$
declare c public.gym_change_candidates%rowtype; s public.gym_stores%rowtype; before_row jsonb; after_row jsonb;
 result jsonb; app_id uuid:=gen_random_uuid(); desired text;
begin
 if manual and not public.is_report_admin() then raise exception 'Administrator required' using errcode='42501';end if;
 if manual and nullif(trim(note),'') is null then raise exception 'Review evidence/note required';end if;
 select * into c from public.gym_change_candidates where id=target_id and entity_type='store';
 if not found or c.store_id is null then raise exception 'Store status candidate required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(c.store_id,429));
 select * into c from public.gym_change_candidates where id=target_id for update;
 if c.status not in ('collecting','needs_review','auto_ready') then return;end if;
 if exists(select 1 from public.gym_auto_applications where candidate_id=c.id) then return;end if;
 if c.change_type not in ('store_temporarily_closed','store_reopened','store_closed') then raise exception 'This change requires separate master review';end if;
 select * into strict s from public.gym_stores where id=c.store_id for update;
 if not manual then
 result:=public.assess_gym_store_candidate(c.id);
 if c.status<>'auto_ready' or result->>'status'<>'auto_ready' then return;end if;
 end if;
 desired:=case c.change_type when 'store_reopened' then 'active' when 'store_closed' then 'closed' else 'temporarily_closed' end;
 before_row:=to_jsonb(s);
 insert into public.gym_auto_applications(id,candidate_id,store_id,equipment_id,change_type,before_data,after_data,application_type)
 values(app_id,c.id,c.store_id,null,c.change_type,before_row,'{}',case when manual then 'admin' else 'auto' end);
 perform set_config('setkeep.gym_candidate_id',c.id::text,true);
 perform set_config('setkeep.gym_application_id',app_id::text,true);
 update public.gym_stores set operational_status=desired,status_source_kind=case when manual then 'admin' else 'confirmed_report' end,
 status_checked_at=now(),status_source_url=null,status_source_data=jsonb_build_object('candidate_id',c.id,'application_id',app_id,'note',trim(note)),updated_at=now()
 where id=c.store_id returning to_jsonb(gym_stores.*) into after_row;
 update public.gym_auto_applications set after_data=after_row where id=app_id;
 update public.gym_change_candidates set status=case when manual then 'admin_applied' else 'auto_applied' end,resolved_at=now(),updated_at=now() where id=c.id;
 if manual then insert into public.gym_change_evidence(candidate_id,source_type,user_id,direction,weight,observed_at,data)
 values(c.id,'admin',auth.uid(),'support',5,now(),jsonb_build_object('note',trim(note),'application_id',app_id));end if;
 insert into public.gym_auto_decisions(candidate_id,decision,reason_code,score_snapshot,rule_snapshot,algorithm_version)
 values(c.id,case when manual then 'admin_applied' else 'auto_applied' end,case when manual then 'admin_confirmed' else 'threshold_met' end,
 jsonb_build_object('application_id',app_id),(select to_jsonb(r) from public.gym_auto_rule_config r where change_type=c.change_type),'store-v1');
 update public.gym_store_reports p set status='applied',admin_note=case when manual then trim(note) else '' end,reviewed_at=now(),reviewed_by=case when manual then auth.uid() else null end
 from public.gym_change_evidence e where e.candidate_id=c.id and e.source_ref='store-report:'||p.id::text and p.status in ('pending','reviewing');
 perform set_config('setkeep.gym_candidate_id','',true);perform set_config('setkeep.gym_application_id','',true);
end $$;

alter function public.apply_gym_change_candidate(uuid) rename to apply_gym_equipment_candidate;
create function public.apply_gym_change_candidate(target_id uuid) returns void language plpgsql security definer set search_path='' as $$ begin
 if exists(select 1 from public.gym_change_candidates where id=target_id and entity_type='store') then
 perform public.apply_gym_store_candidate(target_id);
 else perform public.apply_gym_equipment_candidate(target_id);end if;
end $$;

alter function public.rollback_gym_change_candidate(uuid,text) rename to rollback_gym_equipment_candidate;
create function public.rollback_gym_change_candidate(target_id uuid,reason text) returns void
language plpgsql security definer set search_path='' as $$
declare c public.gym_change_candidates%rowtype; a public.gym_auto_applications%rowtype; s public.gym_stores%rowtype; original public.gym_stores%rowtype;
begin
 if not public.is_report_admin() then raise exception 'Administrator required' using errcode='42501';end if;
 if nullif(trim(reason),'') is null then raise exception 'Rollback reason required';end if;
 select * into c from public.gym_change_candidates where id=target_id;
 if c.entity_type='store_equipment' then perform public.rollback_gym_equipment_candidate(target_id,reason);return;end if;
 perform pg_advisory_xact_lock(hashtextextended(c.store_id,429));
 select * into c from public.gym_change_candidates where id=target_id for update;
 if c.status not in ('auto_applied','admin_applied') then raise exception 'Not applied';end if;
 select * into strict a from public.gym_auto_applications where candidate_id=c.id for update;
 select * into strict s from public.gym_stores where id=c.store_id for update;
 if a.rolled_back_at is not null or to_jsonb(s)<>a.after_data then raise exception 'Master changed since application';end if;
 select * into original from jsonb_populate_record(null::public.gym_stores,a.before_data);
 perform set_config('setkeep.gym_candidate_id',c.id::text,true);perform set_config('setkeep.gym_application_id',a.id::text,true);
 update public.gym_stores set operational_status=original.operational_status,active=original.active,
 status_source_kind=original.status_source_kind,status_checked_at=original.status_checked_at,status_source_url=original.status_source_url,
 status_source_data=original.status_source_data,updated_at=original.updated_at where id=c.store_id;
 if (select to_jsonb(x) from public.gym_stores x where id=c.store_id)<>a.before_data then raise exception 'Rollback mismatch';end if;
 update public.gym_auto_applications set rolled_back_at=now(),rollback_reason=trim(reason),rolled_back_by=auth.uid() where id=a.id;
 update public.gym_change_candidates set status='rolled_back',updated_at=now() where id=c.id;
 insert into public.gym_auto_decisions(candidate_id,decision,reason_code,score_snapshot,rule_snapshot,algorithm_version)
 values(c.id,'rolled_back','admin_rollback',jsonb_build_object('reason',trim(reason),'application_id',a.id),'{}','store-v1');
 perform set_config('setkeep.gym_candidate_id','',true);perform set_config('setkeep.gym_application_id','',true);
end $$;

-- Admin confirmation is explicit; new/relocated/name/address never auto-change.
create function public.review_gym_store_candidate(target_id uuid,action text,note text) returns void
language plpgsql security definer set search_path='' as $$
declare c public.gym_change_candidates%rowtype;
begin
 if not public.is_report_admin() then raise exception 'Administrator required' using errcode='42501';end if;
 if action not in ('reviewing','apply','reject') then raise exception 'Invalid action';end if;
 if action in ('apply','reject') and nullif(trim(note),'') is null then raise exception 'Note required';end if;
 select * into c from public.gym_change_candidates where id=target_id and entity_type='store';
 if not found then raise exception 'Store candidate required';end if;
 perform pg_advisory_xact_lock(hashtextextended(coalesce(c.store_id,c.candidate_key),429));
 select * into c from public.gym_change_candidates where id=target_id for update;
 if c.status not in ('collecting','needs_review','auto_ready') then raise exception 'Candidate already resolved';end if;
 if action='apply' then perform public.apply_gym_store_candidate(target_id,true,note);return;end if;
 update public.gym_store_reports p set status=case when action='reject' then 'rejected' else 'reviewing' end,
 admin_note=trim(note),reviewed_by=auth.uid(),reviewed_at=now()
 from public.gym_change_evidence e where e.candidate_id=c.id and e.source_ref='store-report:'||p.id::text and p.status in ('pending','reviewing');
 update public.gym_change_candidates set status=case when action='reject' then 'rejected' else 'needs_review' end,
 resolved_at=case when action='reject' then now() else null end,updated_at=now() where id=c.id;
 insert into public.gym_auto_decisions(candidate_id,decision,reason_code,score_snapshot,rule_snapshot,algorithm_version)
 values(c.id,case when action='reject' then 'rejected' else 'needs_review' end,'admin_'||action,jsonb_build_object('note',trim(note)),'{}','store-v1');
end $$;

create or replace view public.admin_gym_change_candidates with (security_invoker=true) as
select c.*,case when s.id is not null then concat_ws(' ',chain.name,s.name)
 else concat_ws(' ',coalesce(chain.name,c.proposed_value->>'chain_name'),c.proposed_value->>'name') end store_name,
 coalesce(e.display_name,e.name) equipment_name,a.id application_id,a.applied_at,a.before_data,a.after_data,a.rolled_back_at,a.rollback_reason,
 case when c.entity_type='store' then to_jsonb(s) else to_jsonb(g) end current_data,
 (select count(*) from public.gym_change_evidence ev where ev.candidate_id=c.id) evidence_count,
 (select reason_code from public.gym_auto_decisions d where d.candidate_id=c.id order by decided_at desc,id desc limit 1) decision_reason
from public.gym_change_candidates c left join public.gym_stores s on s.id=c.store_id
left join public.gym_chains chain on chain.id=coalesce(s.chain_id,c.proposed_value->>'chain_id')
left join public.equipment e on e.id=c.equipment_id
left join public.gym_auto_applications a on a.candidate_id=c.id
left join public.gym_store_equipment g on g.store_id=c.store_id and g.equipment_id=c.equipment_id;

-- All mutation/assessment helpers are private. Only reviewed admin RPCs exposed.
revoke all on function public.sync_gym_operational_status(),public.record_gym_store_change(),public.gym_store_identity_key(text),public.gym_store_url_key(text),
 public.limit_gym_store_reports(),public.assess_gym_store_candidate(uuid),public.ingest_gym_store_report(),
 public.reevaluate_gym_change_candidate(uuid),public.apply_gym_store_candidate(uuid,boolean,text),public.apply_gym_change_candidate(uuid)
 from public,anon,authenticated;
revoke all on function public.rollback_gym_change_candidate(uuid,text),public.review_gym_store_candidate(uuid,text,text) from public,anon;
grant execute on function public.rollback_gym_change_candidate(uuid,text),public.review_gym_store_candidate(uuid,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
