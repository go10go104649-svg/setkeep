begin;
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create table public.gym_official_monitor_config (
 id boolean primary key default true check(id),
 endpoint text check(endpoint ~ '^https://[a-z0-9]+[.]supabase[.]co/functions/v1/gym-official-monitor$'),
 enabled boolean not null default false
);
alter table public.gym_official_monitor_config enable row level security;
revoke all on public.gym_official_monitor_config from public,anon,authenticated;
insert into public.gym_official_monitor_config(id) values(true);
create function public.dispatch_gym_official_fetch() returns void language plpgsql security definer set search_path='' as $$
declare conf public.gym_official_monitor_config%rowtype;s public.gym_official_sources%rowtype;token uuid;begin
 -- At most one source per minute; no simultaneous nationwide fan-out.
 if not pg_try_advisory_xact_lock(762430) then return;end if;
 select * into conf from public.gym_official_monitor_config where id and enabled and endpoint is not null;
 if not found then return;end if;
 select * into s from public.gym_official_sources where enabled and policy_status='approved' and next_fetch_at<=now()
 order by next_fetch_at,id limit 1 for update skip locked;
 if not found then return;end if;
 insert into public.gym_official_fetch_jobs(source_id) values(s.id) returning gym_official_fetch_jobs.token into token;
 update public.gym_official_sources set next_fetch_at=now()+make_interval(hours=>fetch_interval_hours) where id=s.id;
 perform net.http_post(url:=conf.endpoint,headers:='{"Content-Type":"application/json"}'::jsonb,body:=jsonb_build_object('token',token),timeout_milliseconds:=60000);
end $$;
revoke all on function public.dispatch_gym_official_fetch() from public,anon,authenticated;
-- Prepared but DISABLED: source policy review and operator enablement are required.
select cron.schedule('setkeep-official-pilot','* * * * *','select public.dispatch_gym_official_fetch()');
select cron.alter_job(job_id:=jobid,active:=false) from cron.job where jobname='setkeep-official-pilot';
commit;
