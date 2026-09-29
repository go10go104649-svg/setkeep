begin;
insert into public.gym_chains(id,name,search_aliases) values ('qa-search-chain','Sample Gym24',array['サンプルジム']);
insert into public.gym_stores(id,chain_id,source_id,name,prefecture,city,station) values ('qa-search-store','qa-search-chain','qa','東口','試験県','試験市','試験駅');
set local role anon;
do $$ declare q text; begin
 foreach q in array array['Sample','Sample Gym24 東口','ＳＡＭＰＬＥ　ＧＹＭ２４ 東口','samplegym24','サンプルジム 東口'] loop
   if not exists(select 1 from public.search_gym_stores(q) where id='qa-search-store') then raise exception 'Search missed query %',q; end if;
 end loop;
 if not exists(select 1 from public.search_gym_stores('試験県') where id='qa-search-store')
    or not exists(select 1 from public.search_gym_stores('試験市') where id='qa-search-store')
 then raise exception 'Prefecture/city search failed'; end if;
 if exists(select 1 from public.search_gym_stores('試験駅')) then raise exception 'Station scope leaked'; end if;
 if exists(select 1 from public.search_gym_stores('Sample nonexistent') where id='qa-search-store') then raise exception 'Token filter failed'; end if;
 if exists(select 1 from public.search_gym_stores('%') where id='qa-search-store') then raise exception 'Wildcard not literal'; end if;
end $$;
rollback;
select 'chain, alias, prefecture, city, width, token and literal search passed' as result;
