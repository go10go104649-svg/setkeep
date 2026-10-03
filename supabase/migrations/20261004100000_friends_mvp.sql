-- Social snapshots are independent of Premium backup and trainer records.
create table public.friend_profiles (
 user_id uuid primary key references auth.users on delete cascade,
 display_name text not null check(char_length(btrim(display_name)) between 1 and 40),
 invite_code uuid not null unique default gen_random_uuid(),
 visibility text not null default 'private' check(visibility in ('private','friends'))
);
create table public.friend_connections (
 id uuid primary key default gen_random_uuid(),
 requester uuid not null references public.friend_profiles(user_id) on delete cascade,
 recipient uuid not null references public.friend_profiles(user_id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','accepted')),
 created_at timestamptz not null default now(),
 check(requester <> recipient)
);
create unique index friend_pair on public.friend_connections(least(requester,recipient),greatest(requester,recipient));
create table public.friend_workouts (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.friend_profiles(user_id) on delete cascade,
 client_id text not null,
 performed_at timestamptz not null,
 duration_seconds integer not null check(duration_seconds >= 0),
 sets jsonb not null check(jsonb_typeof(sets)='array'),
 unique(user_id,client_id)
);
create table public.friend_likes (
 workout_id uuid not null references public.friend_workouts on delete cascade,
 user_id uuid not null references auth.users on delete cascade,
 primary key(workout_id,user_id)
);
create table public.friend_comments (
 id uuid primary key default gen_random_uuid(),
 workout_id uuid not null references public.friend_workouts on delete cascade,
 user_id uuid not null references auth.users on delete cascade,
 body text not null check(char_length(btrim(body)) between 1 and 140),
 created_at timestamptz not null default now()
);
create index friend_workouts_feed on public.friend_workouts(performed_at desc);
create index friend_comments_workout on public.friend_comments(workout_id,created_at);
create function public.are_friends(a uuid,b uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select auth.uid() in (a,b) and exists(select 1 from friend_connections where status='accepted' and
 ((requester=a and recipient=b) or (requester=b and recipient=a)))
$$;
create function public.can_read_friend_workout(w uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from friend_workouts f join friend_profiles p on p.user_id=f.user_id
 where f.id=w and (f.user_id=auth.uid() or (p.visibility='friends' and are_friends(auth.uid(),f.user_id))))
$$;
alter table public.friend_profiles enable row level security;
alter table public.friend_connections enable row level security;
alter table public.friend_workouts enable row level security;
alter table public.friend_likes enable row level security;
alter table public.friend_comments enable row level security;
revoke all on public.friend_profiles,public.friend_connections,public.friend_workouts,public.friend_likes,public.friend_comments from anon,authenticated;
grant select,insert,update on public.friend_profiles to authenticated;
grant select,delete on public.friend_connections to authenticated;
grant select on public.friend_workouts to authenticated;
grant select,insert,delete on public.friend_likes,public.friend_comments to authenticated;
create policy profile_read on public.friend_profiles for select to authenticated using(user_id=auth.uid() or public.are_friends(auth.uid(),user_id));
create policy profile_insert on public.friend_profiles for insert to authenticated with check(user_id=auth.uid());
create policy profile_update on public.friend_profiles for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy connection_read on public.friend_connections for select to authenticated using(auth.uid() in (requester,recipient));
create policy connection_delete on public.friend_connections for delete to authenticated using(auth.uid() in (requester,recipient));
create policy workout_read on public.friend_workouts for select to authenticated using(public.can_read_friend_workout(id));
create policy like_read on public.friend_likes for select to authenticated using(public.can_read_friend_workout(workout_id));
create policy like_insert on public.friend_likes for insert to authenticated with check(user_id=auth.uid() and public.can_read_friend_workout(workout_id));
create policy like_delete on public.friend_likes for delete to authenticated using(user_id=auth.uid() and public.can_read_friend_workout(workout_id));
create policy comment_read on public.friend_comments for select to authenticated using(public.can_read_friend_workout(workout_id));
create policy comment_insert on public.friend_comments for insert to authenticated with check(user_id=auth.uid() and public.can_read_friend_workout(workout_id));
create policy comment_delete on public.friend_comments for delete to authenticated using(user_id=auth.uid() and public.can_read_friend_workout(workout_id));
create function public.request_friend(code uuid) returns void
language plpgsql security definer set search_path=public as $$
declare target uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select user_id into target from friend_profiles where invite_code=code;
 if target is null or target=auth.uid() then raise exception 'Invalid invite code'; end if;
 insert into friend_connections(requester,recipient) values(auth.uid(),target);
end $$;
create function public.accept_friend(connection_id uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
 update friend_connections set status='accepted' where id=connection_id and recipient=auth.uid() and status='pending';
 if not found then raise exception 'Request not available'; end if;
end $$;
-- Replace the owner's complete social snapshot atomically. Never touch workouts.
create function public.publish_friend_workouts(records jsonb) returns void
language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not exists(select 1 from friend_profiles where user_id=auth.uid() and visibility='friends') then return; end if;
 if jsonb_typeof(records)<>'array' then raise exception 'Array required'; end if;
 insert into friend_workouts(user_id,client_id,performed_at,duration_seconds,sets)
 select auth.uid(),r->>'date',(r->>'date')::timestamptz,coalesce((r->>'durationSeconds')::integer,0),r->'sets'
 from jsonb_array_elements(records) r
 on conflict(user_id,client_id) do update set performed_at=excluded.performed_at,duration_seconds=excluded.duration_seconds,sets=excluded.sets;
 delete from friend_workouts where user_id=auth.uid() and client_id not in(select r->>'date' from jsonb_array_elements(records) r);
end $$;
revoke all on function public.are_friends(uuid,uuid),public.can_read_friend_workout(uuid),public.request_friend(uuid),public.accept_friend(uuid),public.publish_friend_workouts(jsonb) from public,anon;
grant execute on function public.are_friends(uuid,uuid),public.can_read_friend_workout(uuid),public.request_friend(uuid),public.accept_friend(uuid),public.publish_friend_workouts(jsonb) to authenticated;
create function public.list_friend_connections() returns table(id uuid,requester uuid,recipient uuid,status text,friend_name text)
language sql stable security definer set search_path=public as $$
 select c.id,c.requester,c.recipient,c.status,p.display_name
 from friend_connections c join friend_profiles p on p.user_id=case when c.requester=auth.uid() then c.recipient else c.requester end
 where auth.uid() in (c.requester,c.recipient) order by c.created_at
$$;
revoke all on function public.list_friend_connections() from public,anon;
grant execute on function public.list_friend_connections() to authenticated;
