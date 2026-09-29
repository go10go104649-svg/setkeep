begin;
create function pg_temp.assert_true(ok boolean,msg text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception '%',msg;end if;end$$;
select pg_temp.assert_true((select not enabled from public.gym_official_monitor_config where id),'Scheduler must remain disabled pending policy');
select pg_temp.assert_true(not exists(select 1 from public.gym_official_sources where enabled),'Sources enabled before policy review');
select pg_temp.assert_true((select not active from cron.job where jobname='setkeep-official-pilot'),'Cron must remain inactive');
create temp table before_dispatch as select count(*) n from public.gym_official_fetch_jobs;
select public.dispatch_gym_official_fetch();
select pg_temp.assert_true((select count(*)=(select n from before_dispatch) from public.gym_official_fetch_jobs),'Disabled scheduler created job');
set local role authenticated;
do $$begin
 begin perform public.dispatch_gym_official_fetch();raise exception 'User dispatched jobs';exception when insufficient_privilege then null;end;
 begin update public.gym_official_monitor_config set enabled=true;raise exception 'User enabled monitor';exception when insufficient_privilege then null;end;
 begin select count(*) from public.gym_official_fetch_jobs;raise exception 'User read capability tokens';exception when insufficient_privilege then null;end;
end$$;
reset role;
select 'disabled scheduler and privilege assertions passed' as result;
rollback;
