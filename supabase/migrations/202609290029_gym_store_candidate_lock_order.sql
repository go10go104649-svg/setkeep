begin;
-- Store ingestion, reevaluation and admin review must acquire the same advisory
-- lock BEFORE locking a candidate row. All unregistered stores share this lock,
-- since equivalent URL/name reports can resolve to different initial keys.
-- This prevents report ingestion and admin review taking these locks in reverse.
create or replace function public.reevaluate_gym_change_candidate(target_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare c public.gym_change_candidates%rowtype; result jsonb;
begin
 select * into c from public.gym_change_candidates where id=target_id;
 if c.entity_type='store_equipment' then perform public.reevaluate_gym_equipment_candidate(target_id);return; end if;
 if c.entity_type is distinct from 'store' then return; end if;
 perform pg_advisory_xact_lock(hashtextextended(coalesce(c.store_id,'new-store'),429));
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

create or replace function public.review_gym_store_candidate(target_id uuid,action text,note text) returns void
language plpgsql security definer set search_path='' as $$
declare c public.gym_change_candidates%rowtype;
begin
 if not public.is_report_admin() then raise exception 'Administrator required' using errcode='42501';end if;
 if action not in ('reviewing','apply','reject') then raise exception 'Invalid action';end if;
 if action in ('apply','reject') and nullif(trim(note),'') is null then raise exception 'Note required';end if;
 select * into c from public.gym_change_candidates where id=target_id and entity_type='store';
 if not found then raise exception 'Store candidate required';end if;
 perform pg_advisory_xact_lock(hashtextextended(coalesce(c.store_id,'new-store'),429));
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
commit;
