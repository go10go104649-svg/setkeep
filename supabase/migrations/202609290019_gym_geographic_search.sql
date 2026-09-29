begin;
-- The same paged search supports the existing store and chain queries plus
-- prefecture/city lookups. Keep literal substring matching (including % and _).
create or replace function public.search_gym_stores_v2(
  search_query text default '', page_offset integer default 0,
  selected_chain text default null
)
returns setof jsonb language sql stable security invoker set search_path='' as $$
 with candidates as (
 select s.*,c.name as chain_name,
 public.gym_search_text(s.name) as sn,
 public.gym_search_text(c.name) as cn,
 public.gym_search_text(c.name||s.name) as full_name,
 public.gym_search_text(s.prefecture) as pn,
 public.gym_search_text(s.city) as cityn,
 array(select public.gym_search_text(a||s.name) from unnest(c.search_aliases) a) as aliases,
 public.gym_search_text(search_query) as q
 from public.gym_stores s join public.gym_chains c on c.id=s.chain_id
 where s.active and (selected_chain is null or s.chain_id=selected_chain)
 )
 select to_jsonb(x)-'sn'-'cn'-'full_name'-'pn'-'cityn'-'aliases'-'q'
 from candidates x
 where q='' or strpos(full_name,q)>0 or strpos(pn,q)>0 or
  strpos(cityn,q)>0 or exists(select 1 from unnest(aliases) a where strpos(a,q)>0)
 order by case when q=sn or q=cn or q=full_name then 0
  when starts_with(sn,q) or starts_with(cn,q) or starts_with(full_name,q) then 1
  when q=pn or q=cityn then 2 else 3 end,
 name,id limit 30 offset greatest(0,least(page_offset,100000))
$$;
notify pgrst,'reload schema';
commit;
