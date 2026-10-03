begin;
create function pg_temp.ok(v boolean,label text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %',label; end if; raise notice 'PASS: %',label; end $$;
create function pg_temp.denied(q text) returns boolean language plpgsql as $$
begin execute q; return false; exception when others then return true; end $$;
insert into auth.users(id) values('51000000-0000-0000-0000-000000000001'),('51000000-0000-0000-0000-000000000002'),('51000000-0000-0000-0000-000000000003');
insert into public.friend_profiles(user_id,display_name,invite_code,visibility) values
('51000000-0000-0000-0000-000000000001','A','52000000-0000-0000-0000-000000000001','friends'),
('51000000-0000-0000-0000-000000000002','B','52000000-0000-0000-0000-000000000002','private'),
('51000000-0000-0000-0000-000000000003','C','52000000-0000-0000-0000-000000000003','friends');
insert into public.friend_workouts(id,user_id,client_id,performed_at,duration_seconds,sets) values
('53000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000001','fixture',now(),0,'[]');
set local role authenticated;
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000001',true);
select public.request_friend('52000000-0000-0000-0000-000000000002');
select pg_temp.ok(pg_temp.denied($q$select public.accept_friend((select id from public.friend_connections limit 1))$q$),'requester cannot self-approve');
select pg_temp.ok(pg_temp.denied($q$select public.request_friend('52000000-0000-0000-0000-000000000001')$q$),'self request denied');
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000002',true);
select pg_temp.ok((select count(*)=0 from public.friend_workouts),'pending friend cannot read');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_likes values('53000000-0000-0000-0000-000000000001',auth.uid())$q$),'pending friend cannot like');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_comments(workout_id,user_id,body) values('53000000-0000-0000-0000-000000000001',auth.uid(),'hello')$q$),'pending friend cannot comment');
select public.accept_friend((select id from public.friend_connections limit 1));
select pg_temp.ok((select count(*)=1 from public.friend_workouts),'approved friend reads');
select pg_temp.ok((select friend_name='A' from public.list_friend_connections()),'participant sees name');
insert into public.friend_likes values('53000000-0000-0000-0000-000000000001',auth.uid());
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_likes values('53000000-0000-0000-0000-000000000001',auth.uid())$q$),'one like per user');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_likes values('53000000-0000-0000-0000-000000000001','51000000-0000-0000-0000-000000000001')$q$),'cannot impersonate like');
insert into public.friend_comments(id,workout_id,user_id,body) values('54000000-0000-0000-0000-000000000001','53000000-0000-0000-0000-000000000001',auth.uid(),'hello');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_comments(workout_id,user_id,body) values('53000000-0000-0000-0000-000000000001',auth.uid(),repeat('x',141))$q$),'long comments rejected');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_comments(workout_id,user_id,body) values('53000000-0000-0000-0000-000000000001',auth.uid(),'   ')$q$),'blank comments rejected');
select pg_temp.ok(pg_temp.denied($q$update public.friend_workouts set sets='[]'$q$),'friend cannot edit workout');
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000003',true);
select pg_temp.ok((select count(*)=0 from public.friend_connections),'stranger cannot read connections');
select pg_temp.ok((select count(*)=0 from public.list_friend_connections()),'stranger cannot list names');
select pg_temp.ok((select count(*)=0 from public.friend_workouts),'stranger cannot read workout');
select pg_temp.ok((select count(*)=0 from public.friend_likes),'stranger cannot read likes');
select pg_temp.ok((select count(*)=0 from public.friend_comments),'stranger cannot read comments');
select pg_temp.ok(pg_temp.denied($q$select public.accept_friend('00000000-0000-0000-0000-000000000000')$q$),'stranger cannot approve');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_comments(workout_id,user_id,body) values('53000000-0000-0000-0000-000000000001',auth.uid(),'hello')$q$),'stranger cannot comment');
delete from public.friend_comments where id='54000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000001',true);
select pg_temp.ok((select count(*)=1 from public.friend_comments),'other user cannot delete comment');
update public.friend_profiles set visibility='private' where user_id=auth.uid();
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000002',true);
select pg_temp.ok((select count(*)=0 from public.friend_workouts),'private hides from approved friend');
select pg_temp.ok((select count(*)=0 from public.friend_comments),'private hides comments');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_comments(workout_id,user_id,body) values('53000000-0000-0000-0000-000000000001',auth.uid(),'hello')$q$),'private rejects comments');
select pg_temp.ok(pg_temp.denied($q$insert into public.friend_likes values('53000000-0000-0000-0000-000000000001',auth.uid())$q$),'private rejects likes');
update public.friend_profiles set visibility='friends' where user_id='51000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000001',true);
select pg_temp.ok((select visibility='private' from public.friend_profiles where user_id=auth.uid()),'other user cannot change privacy');
update public.friend_profiles set visibility='friends' where user_id=auth.uid();
select public.publish_friend_workouts('[{"date":"2026-10-03T12:00:00Z","durationSeconds":60,"sets":[]}]');
select pg_temp.ok((select count(*)=1 and min(client_id)='2026-10-03T12:00:00Z' from public.friend_workouts),'atomic snapshot deletes removed record');
select pg_temp.ok((select count(*)=0 from public.friend_likes),'deleted workout cascades likes');
select pg_temp.ok((select count(*)=0 from public.friend_comments),'deleted workout cascades comments');
insert into public.friend_likes select id,auth.uid() from public.friend_workouts;
select public.publish_friend_workouts('[{"date":"2026-10-03T12:00:00Z","durationSeconds":120,"sets":[{"exerciseName":"Updated","weight":30,"reps":10}]}]');
select pg_temp.ok((select duration_seconds=120 and sets->0->>'exerciseName'='Updated' from public.friend_workouts),'source edit updates social detail');
select pg_temp.ok((select count(*)=1 from public.friend_likes),'edit preserves workout identity and reactions');

select set_config('request.jwt.claim.sub','51000000-0000-0000-0000-000000000002',true);
delete from public.friend_connections;
select pg_temp.ok((select count(*)=0 from public.friend_workouts),'unfriend revokes immediately');
set local role anon;
select pg_temp.ok(pg_temp.denied($q$select * from public.friend_workouts$q$),'anonymous read denied');
select pg_temp.ok(pg_temp.denied($q$select public.publish_friend_workouts('[]')$q$),'anonymous publish denied');
select pg_temp.ok(pg_temp.denied($q$select public.request_friend('52000000-0000-0000-0000-000000000001')$q$),'anonymous request denied');
rollback;
