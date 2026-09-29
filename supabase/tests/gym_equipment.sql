-- Transactional QA fixtures are rolled back; no real user data is changed.
begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002');
insert into gym_chains(id,name) values ('qa-only','QA');
insert into gym_stores(id,chain_id,source_id,name,city,station) values ('qa-store','qa-only','one','店舗テスト','市区町村テスト','駅テスト');
insert into equipment(id,name,normalized_name,category) values ('qa-e','設備','設備','その他');
insert into gym_store_equipment(store_id,equipment_id,raw_name) values ('qa-store','qa-e','設備');
set local role anon;
do $$ begin
  if (select count(*) from public.search_gym_stores('店舗テスト'))<>1 or
     (select count(*) from public.search_gym_stores('市区町村テスト'))<>1 or
     (select count(*) from public.search_gym_stores('駅テスト'))<>0 then raise exception 'Search failed'; end if;
  begin insert into public.gym_chains(id,name) values ('bad','bad'); raise exception 'Anon wrote master'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
set local role authenticated;
insert into public.user_gym_stores(store_id) values ('qa-store');
insert into public.gym_equipment_reports(store_id,equipment_id,kind) values ('qa-store','qa-e','removed');
do $$ begin
  if not exists(select 1 from public.user_gym_stores where store_id='qa-store') then raise exception 'Owner read failed'; end if;
  if not exists(select 1 from public.gym_store_equipment where store_id='qa-store') then raise exception 'Report changed master'; end if;
  insert into public.gym_equipment_reports(store_id,equipment_id,kind) values ('qa-store','qa-e','removed');
  if (select count(*) from public.gym_equipment_reports where store_id='qa-store')<>1 then raise exception 'Duplicate report inserted'; end if;
  begin insert into public.gym_equipment_reports(store_id,kind) values ('qa-store','added'); raise exception 'Null name accepted'; exception when check_violation then null; end;
  begin insert into public.gym_equipment_reports(store_id,kind,status) values ('qa-store','other','approved'); raise exception 'Self approval allowed'; exception when insufficient_privilege then null; end;
end $$;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000002';
do $$ begin
  if exists(select 1 from public.user_gym_stores where store_id='qa-store') or exists(select 1 from public.gym_equipment_reports where store_id='qa-store') then raise exception 'Private data leaked'; end if;
  delete from public.user_gym_stores where store_id='qa-store';
end $$;
set local request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
do $$ begin if not exists(select 1 from public.user_gym_stores where store_id='qa-store') then raise exception 'Other user deleted registration'; end if; end $$;
rollback;
select 'gym RLS/search/report assertions passed' as result;
