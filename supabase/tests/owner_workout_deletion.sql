begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if;
raise notice 'PASS: %',label; end $$;
create function pg_temp.denied(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return true; end $$;
insert into auth.users(id) values('41000000-0000-0000-0000-000000000001'),('41000000-0000-0000-0000-000000000002');
insert into public.workouts(id,user_id,client_id,performed_at,sets,record_source,recorded_by)
values('42000000-0000-0000-0000-000000000001','41000000-0000-0000-0000-000000000001','delete-test',now(),'[{"exerciseName":"A","weight":20,"reps":8},{"exerciseName":"B","weight":30,"reps":10}]','trainer','41000000-0000-0000-0000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000002',true);
select pg_temp.ok(pg_temp.denied($q$select public.owner_mutate_recorded_workout('42000000-0000-0000-0000-000000000001','delete')$q$),'other user cannot delete');
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000001',true);
select public.owner_mutate_recorded_workout('42000000-0000-0000-0000-000000000001','delete');
select pg_temp.ok((select canceled_at is not null and canceled_by=auth.uid() from public.workouts where client_id='delete-test'),'delete immediately persisted');
select public.owner_mutate_recorded_workout('42000000-0000-0000-0000-000000000001','restore');
select pg_temp.ok((select canceled_at is null and jsonb_array_length(sets)=2 and sets->0->>'exerciseName'='A' and sets->1->>'exerciseName'='B' from public.workouts where client_id='delete-test'),'undo retains sets and order');
select public.owner_mutate_recorded_workout('42000000-0000-0000-0000-000000000001','update','[]');
select pg_temp.ok((select canceled_at is not null from public.workouts where client_id='delete-test'),'deleting last set cancels server record');
select public.owner_mutate_recorded_workout('42000000-0000-0000-0000-000000000001','update','[{"exerciseName":"B","weight":30,"reps":10}]');
select pg_temp.ok((select canceled_at is null and jsonb_array_length(sets)=1 and record_source='trainer' and recorded_by='41000000-0000-0000-0000-000000000002' from public.workouts where client_id='delete-test'),'edit restores set without changing attribution');
reset role;
update public.workouts set canceled_at=now(),canceled_by='41000000-0000-0000-0000-000000000002' where client_id='delete-test';
set local role authenticated;
select pg_temp.ok(pg_temp.denied($q$select public.owner_mutate_recorded_workout('42000000-0000-0000-0000-000000000001','restore')$q$),'cannot undo trainer cancellation');
set local role anon;
select pg_temp.ok(pg_temp.denied($q$select public.owner_mutate_recorded_workout('42000000-0000-0000-0000-000000000001','delete')$q$),'anonymous denied');
rollback;
