-- Keep trainer attribution/audit records while making owner deletions durable.
create or replace function public.owner_mutate_recorded_workout(
  p_record uuid, p_action text, p_sets jsonb default null
) returns void language plpgsql security definer set search_path='' as $$
declare w public.workouts;
begin
  select * into w from public.workouts
    where id=p_record and user_id=auth.uid() and record_source='trainer'
    for update;
  if not found then raise exception 'Workout not found'; end if;
  if p_action='delete' then
    if w.canceled_at is null then
      update public.workouts set canceled_at=now(), canceled_by=auth.uid() where id=w.id;
    end if;
  elsif p_action='restore' then
    if w.canceled_at is not null and w.canceled_by is distinct from auth.uid() then
      raise exception 'Only your own deletion can be restored';
    end if;
    update public.workouts set canceled_at=null,canceled_by=null where id=w.id;
  elsif p_action='update' then
    if p_sets is null or jsonb_typeof(p_sets)<>'array' then raise exception 'Invalid sets'; end if;
    if jsonb_array_length(p_sets)>1000 or exists(select 1 from jsonb_array_elements(p_sets) s where jsonb_typeof(s)<>'object') then raise exception 'Invalid sets'; end if;
    if w.canceled_at is not null and w.canceled_by is distinct from auth.uid() then
      raise exception 'Canceled workout cannot be edited';
    end if;
    update public.workouts set sets=p_sets,
      canceled_at=case when jsonb_array_length(p_sets)=0 then now() end,
      canceled_by=case when jsonb_array_length(p_sets)=0 then auth.uid() end
      where id=w.id;
  else raise exception 'Invalid action'; end if;
end $$;
revoke all on function public.owner_mutate_recorded_workout(uuid,text,jsonb) from public,anon;
grant execute on function public.owner_mutate_recorded_workout(uuid,text,jsonb) to authenticated;
